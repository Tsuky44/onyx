package capacity

import "math"

// Ce que coûte une étape du pipeline, et sur quelle ressource.
//
// Un transcodage ne se paie pas qu'en cœurs. Sur un serveur Intel, la chaîne
// VAAPI ne coûte presque rien au processeur, mais elle occupe le décodeur et
// l'encodeur du circuit ; libplacebo sur le circuit occupe son calcul. Le
// planificateur compare des recettes qui ne tirent pas sur la même ressource :
// il lui faut donc un coût par ressource, pas un seul chiffre.

// Cost est un coût sur chaque ressource que le planificateur compte.
//
// Dans le profil, c'est un coût par mégapixel·image (ce que coûte une image
// d'un mégapixel). Dans un Pipeline, c'est un coût par seconde de film à la
// vitesse de lecture : des cœurs pour le CPU, une part d'occupation (1 =
// plein) pour chaque moteur du circuit.
type Cost struct {
	// CPU est en cœurs (cœur-secondes par seconde).
	CPU float64 `json:"cpu"`
	// Decode est l'occupation du décodeur du circuit.
	Decode float64 `json:"decode,omitempty"`
	// Encode est l'occupation de l'encodeur du circuit.
	Encode float64 `json:"encode,omitempty"`
	// Compute est l'occupation du calcul du circuit (Vulkan, filtres VAAPI).
	Compute float64 `json:"compute,omitempty"`
}

// Resource nomme une ressource, pour le journal et la règle « épargner la
// ressource la plus rare ».
type Resource string

const (
	ResourceCPU     Resource = "cpu"
	ResourceDecode  Resource = "décodeur"
	ResourceEncode  Resource = "encodeur"
	ResourceCompute Resource = "calcul"
)

// Resources est l'ordre dans lequel les ressources sont parcourues.
var Resources = []Resource{ResourceCPU, ResourceDecode, ResourceEncode, ResourceCompute}

// Of rend la part de c sur r.
func (c Cost) Of(r Resource) float64 {
	switch r {
	case ResourceCPU:
		return c.CPU
	case ResourceDecode:
		return c.Decode
	case ResourceEncode:
		return c.Encode
	case ResourceCompute:
		return c.Compute
	}
	return 0
}

// Plus additionne deux coûts.
func (c Cost) Plus(o Cost) Cost {
	return Cost{CPU: c.CPU + o.CPU, Decode: c.Decode + o.Decode, Encode: c.Encode + o.Encode, Compute: c.Compute + o.Compute}
}

// Times multiplie chaque part par k.
func (c Cost) Times(k float64) Cost {
	return Cost{CPU: c.CPU * k, Decode: c.Decode * k, Encode: c.Encode * k, Compute: c.Compute * k}
}

// rounded arrondit chaque part, pour un cache et un journal lisibles.
func (c Cost) rounded() Cost {
	r := func(v float64) float64 { return math.Round(v*1e6) / 1e6 }
	return Cost{CPU: r(c.CPU), Decode: r(c.Decode), Encode: r(c.Encode), Compute: r(c.Compute)}
}

// Stage est une étape du pipeline.
type Stage string

const (
	StageDecode  Stage = "decode"
	StageScale   Stage = "scale"
	StageToneMap Stage = "tonemap"
	StageEncode  Stage = "encode"
)

// Les variantes nommées d'une étape. Le décodage se range en deux classes,
// selon ce qui pèse : `h264` pour les flux 8 bits légers (H.264, MPEG-2,
// VC-1), `hevc10` pour les lourds (HEVC, AV1, VP9, tout le 10 bits). Les
// autres variantes sont le nom du chemin (`sw`, `vaapi`, `zscale`,
// `libplacebo`) ou de l'encodeur et de son preset (`libx264/veryfast`,
// `h264_vaapi`).
const (
	DecodeH264CPU     = "h264/cpu"
	DecodeHEVC10CPU   = "hevc10/cpu"
	DecodeH264VAAPI   = "h264/vaapi"
	DecodeHEVC10VAAPI = "hevc10/vaapi"

	ScaleSoftware = "sw"
	ScaleVAAPI    = "vaapi"

	ToneMapZscale     = "zscale"
	ToneMapLibplacebo = "libplacebo"
)

// EncodeVariant est la variante d'encodage d'un encodeur, avec son preset
// pour un encodeur logiciel.
func EncodeVariant(encoder, preset string) string {
	if preset == "" {
		return encoder
	}
	return encoder + "/" + preset
}

// StageCost est le coût d'une variante d'étape, par mégapixel·image.
type StageCost struct {
	Stage   Stage  `json:"stage"`
	Variant string `json:"variant"`
	Cost    Cost   `json:"per_mpx_frame"`
	// Estimated dit que ce chiffre n'a pas été mesuré sur cette machine : il
	// vient de la table de référence, ramenée à la vitesse mesurée des cœurs
	// quand elle est connue.
	Estimated bool `json:"estimated,omitempty"`
}

// Les coûts de référence, par mégapixel·image, d'où vient toute valeur que le
// banc n'a pas pu mesurer. Les parts CPU sont celles de la machine de fytroz
// (4 cœurs sans circuit, FFmpeg 6.1, 4K HEVC 10 bits PQ vers 1080p à 24 i/s,
// docs/transcodage-adaptatif.md §2) ramenées au mégapixel·image :
//
//	décodage HEVC 4K   1,63 cœur / (8,29 Mpx × 24) = 0,0082
//	swscale            0,17 / (8,29 × 24)           = 0,00085
//	zscale (en 1080p)  0,76 / (2,07 × 24)           = 0,0153
//	x264 veryfast      0,88 / (2,07 × 24)           = 0,0177
//	libplacebo logiciel (9,06 − 2,68) / (2,07 × 24) = 0,128
//
// Le reste est *estimé* : superfast et ultrafast au prorata du Mac de
// l'ADR-0023 (ultrafast ≈ 0,34 × veryfast), le décodage H.264 au quart du
// HEVC 10 bits, libx265 à 2,1 × x264 veryfast (encoder_hevc.go). Les parts du
// circuit viennent du seul chiffre mesuré (videotoolbox à 2,2× en 2160p : une
// occupation de 0,45, soit 0,0023 par Mpx·image) et de la course libplacebo
// de l'i7 (419 ms pour 24 images de 720p, démarrage compris).
var referenceCosts = []StageCost{
	{Stage: StageDecode, Variant: DecodeH264CPU, Cost: Cost{CPU: 0.0025}},
	{Stage: StageDecode, Variant: DecodeHEVC10CPU, Cost: Cost{CPU: 0.0082}},
	{Stage: StageDecode, Variant: DecodeH264VAAPI, Cost: Cost{CPU: 0.0002, Decode: 0.0012}},
	{Stage: StageDecode, Variant: DecodeHEVC10VAAPI, Cost: Cost{CPU: 0.0003, Decode: 0.0018}},
	{Stage: StageScale, Variant: ScaleSoftware, Cost: Cost{CPU: 0.00085}},
	{Stage: StageScale, Variant: ScaleVAAPI, Cost: Cost{CPU: 0.0001, Compute: 0.0005}},
	{Stage: StageToneMap, Variant: ToneMapZscale, Cost: Cost{CPU: 0.0153}},
	{Stage: StageEncode, Variant: "libx264/veryfast", Cost: Cost{CPU: 0.0177}},
	{Stage: StageEncode, Variant: "libx264/superfast", Cost: Cost{CPU: 0.0106}},
	{Stage: StageEncode, Variant: "libx264/ultrafast", Cost: Cost{CPU: 0.0060}},
	{Stage: StageEncode, Variant: "libx265/ultrafast", Cost: Cost{CPU: 0.037}},
}

// referenceLibplacebo est libplacebo sur le Vulkan logiciel ou sur un circuit.
var (
	referenceLibplaceboSoftware = Cost{CPU: 0.128}
	referenceLibplaceboGPU      = Cost{CPU: 0.001, Compute: 0.019}
	// referenceHardwareEncode vaut pour tout encodeur du circuit.
	referenceHardwareEncode = Cost{CPU: 0.0009, Encode: 0.0023}
)

// anchorVariant est l'étape qui sert d'étalon : sa mesure, rapportée à sa
// référence, dit combien les cœurs de cette machine vont plus ou moins vite
// que ceux de la machine de référence.
var anchorVariant = EncodeVariant("libx264", "veryfast")

// referenceCost rend la valeur de référence d'une variante, ou faux. Un
// encodeur matériel inconnu de la table prend referenceHardwareEncode.
func referenceCost(stage Stage, variant string, hardware bool) (Cost, bool) {
	if stage == StageToneMap && variant == ToneMapLibplacebo {
		if hardware {
			return referenceLibplaceboGPU, true
		}
		return referenceLibplaceboSoftware, true
	}
	for _, c := range referenceCosts {
		if c.Stage == stage && c.Variant == variant {
			return c.Cost, true
		}
	}
	if stage == StageEncode && hardware {
		return referenceHardwareEncode, true
	}
	return Cost{}, false
}
