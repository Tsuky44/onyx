package capacity

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

// Le planificateur : la recette d'une session.
//
// La recopie est décidée avant lui, par streaming.PlanVideo, sans changement :
// elle reste toujours le premier choix. Quand l'image doit être encodée,
// PlanPipeline énumère les recettes que le rendu sait lancer (le décodage, la
// mise à l'échelle, le tone mapping, l'encodeur et son preset), prévoit le
// coût de chacune par ressource avec le profil, et sa vitesse : sur chaque
// ressource, la part libre divisée par le coût, et le minimum sur toutes.
//
// La règle de choix généralise le « le plus rapide gagne » que fytroz
// applique au périphérique Vulkan :
//
//  1. ce qui tient moins de 1,5× est éliminé, pour qu'une session repartie de
//     zéro après un saut reprenne de l'avance ;
//  2. avec de la marge, la meilleure image : x264 à son preset le plus lent
//     d'abord, comme l'ADR-0023 l'a mesuré ;
//  3. sans marge, la recette qui épargne la ressource la plus rare.
//
// Si rien ne tient 1,5×, la recette la plus rapide est rendue quand même, avec
// son verdict : décider quoi en faire (descendre, prévenir, refuser) est la
// phase 3.

// HoldSpeed est la vitesse qu'une recette doit tenir pour être retenue.
const HoldSpeed = 1.5

// MarginFraction est la part de chaque ressource qu'une recette doit laisser
// libre, une fois son propre coût payé, pour qu'on parle de marge. Un quart :
// de quoi absorber un film plus dur que la source de synthèse du banc, ou une
// machine qui chauffe (l'i7 de fytroz à 99 °C).
const MarginFraction = 0.25

// MaxEncoderThreads plafonne les threads de libx264 par session.
//
// L'hôte de la prod est un Xeon à deux sockets : étaler une session sur les
// deux coûte plus en trafic mémoire entre nœuds NUMA que ça ne rapporte, et
// prive les sessions voisines. Seize threads saturent le parallélisme par
// images d'un socket et en laissent à une deuxième session. Sous ce plafond,
// la machine n'a pas plus de cœurs que de threads utiles.
const MaxEncoderThreads = 16

// ThreadsFor est le nombre de threads de libx264 sur cores cœurs : tous
// jusqu'au plafond, un au moins.
func ThreadsFor(cores int) int { return min(max(cores, 1), MaxEncoderThreads) }

// X264Presets sont les presets que le planificateur sait choisir, du plus
// lent (la meilleure image) au plus rapide.
var X264Presets = []string{"veryfast", "superfast", "ultrafast"}

// Verdict dit ce qu'on attend de la recette retenue.
type Verdict string

const (
	// VerdictOK : la recette tient au moins HoldSpeed.
	VerdictOK Verdict = "ok"
	// VerdictLimit : entre 1,0 et HoldSpeed ; elle tient la lecture, mais une
	// session repartie de zéro ne reprend pas d'avance.
	VerdictLimit Verdict = "limite"
	// VerdictTooHeavy : sous 1,0, la lecture attendra ses segments.
	VerdictTooHeavy Verdict = "trop_lourd"
)

// VerdictFor est le verdict d'une vitesse prévue.
func VerdictFor(speed float64) Verdict {
	switch {
	case speed >= HoldSpeed:
		return VerdictOK
	case speed >= 1:
		return VerdictLimit
	default:
		return VerdictTooHeavy
	}
}

// Source décrit l'image d'origine.
type Source struct {
	Width, Height int
	// FPS est la cadence ; 24 quand elle est inconnue ou absurde.
	FPS float64
	// Codec est le nom canonique (`h264`, `hevc`, `av1`…).
	Codec    string
	BitDepth int
	// DV5 est un Dolby Vision profil 5, que seul libplacebo tone mappe
	// (ADR-0060).
	DV5 bool
}

// Target est le barreau demandé.
type Target struct {
	// Width, Height sont la boîte du barreau : l'image y est ajustée, jamais
	// agrandie.
	Width, Height int
	// Preset est le preset de libx264 du barreau, le plus lent que le
	// planificateur prendra : `ultrafast` en 2160p, pour qu'une session
	// repartie de zéro y tienne (streaming/quality.go).
	Preset string
}

// Job est ce que la session doit faire de l'image.
type Job struct {
	Source Source
	Target Target
	// ToneMap ramène le HDR en SDR.
	ToneMap bool
	// KeepHDR encode en HEVC Main 10 et garde le HDR (ADR-0106).
	KeepHDR bool
	// SoftwareOnly impose la chaîne logicielle : un sous-titre incrusté ou le
	// désentrelacement travaillent sur des images logicielles, avant la mise
	// à l'échelle.
	SoftwareOnly bool
}

// Load est ce que les sessions en cours occupent déjà, par seconde. Zéro en
// phase 2 : le budget par ressource est la phase 3, qui la remplira.
type Load struct {
	Used Cost
}

// Pipeline est la recette retenue pour une session.
type Pipeline struct {
	// Decode vaut `cpu` ou la surface du circuit (`vaapi`).
	Decode string
	// Scale vaut `sw`, la surface du circuit, ou "" sans mise à l'échelle.
	Scale string
	// ToneMap vaut `zscale`, `libplacebo` ou "".
	ToneMap      string
	ToneMapOnGPU bool
	Encoder      string
	Hardware     bool
	// Preset est celui de l'encodeur logiciel, vide pour le circuit.
	Preset string
	// Threads est le `-threads` de libx264.
	Threads int
	// Cost est le coût prévu par seconde de film, à la vitesse de lecture.
	Cost Cost
	// Speed est la vitesse prévue, en multiple de la lecture.
	Speed   float64
	Verdict Verdict
	// Estimated dit qu'au moins une étape n'a pas été mesurée sur cette
	// machine et vient de la référence. Les autres tailles d'image que le
	// 1080p du banc s'extrapolent toujours au prorata des pixels : le coût est
	// mesuré par mégapixel·image.
	Estimated bool
	// Considered est le nombre de recettes comparées.
	Considered int
}

// String est la ligne de journal de la recette.
func (p Pipeline) String() string {
	tm := p.ToneMap
	if tm == "" {
		tm = "aucun"
	} else if p.ToneMapOnGPU {
		tm += "@gpu"
	}
	scale := p.Scale
	if scale == "" {
		scale = "aucune"
	}
	enc := p.Encoder
	if p.Preset != "" {
		enc += "/" + p.Preset
	}
	estimated := ""
	if p.Estimated {
		estimated = ", estimée"
	}
	return fmt.Sprintf("décodage=%s, échelle=%s, tone mapping=%s, encodeur=%s, coût=%.2f cœur%s, vitesse prévue %.1f× (%s%s, %d recettes)",
		p.Decode, scale, tm, enc, p.Cost.CPU, gpuCost(p.Cost), p.Speed, p.Verdict, estimated, p.Considered)
}

func gpuCost(c Cost) string {
	var parts []string
	for _, r := range Resources[1:] {
		if v := c.Of(r); v > 0 {
			parts = append(parts, fmt.Sprintf("%s %.0f %%", r, v*100))
		}
	}
	if len(parts) == 0 {
		return ""
	}
	return " + " + strings.Join(parts, ", ")
}

// recipe est une recette énumérée, avec ce qu'en dit le profil.
type recipe struct {
	Pipeline
	rank     int
	headroom float64
}

// PlanPipeline choisit la recette de job sur cette machine, sous cette charge.
// ok est faux quand aucun encodeur du profil ne sait faire ce travail :
// l'appelant garde alors le comportement d'avant le profil.
func PlanPipeline(job Job, profile *Profile, load Load) (Pipeline, bool) {
	if profile == nil {
		return Pipeline{}, false
	}
	recipes := enumerate(job, profile, false)
	if len(recipes) == 0 {
		recipes = enumerate(job, profile, true)
	}
	if len(recipes) == 0 {
		return Pipeline{}, false
	}
	capacity := Cost{CPU: float64(max(profile.Inventory.Cores, 1)), Decode: 1, Encode: 1, Compute: 1}
	for i := range recipes {
		recipes[i].Speed, recipes[i].headroom = predict(recipes[i].Cost, capacity, load.Used)
	}
	// La meilleure image d'abord ; à image égale, la plus rapide.
	sort.SliceStable(recipes, func(i, j int) bool {
		if recipes[i].rank != recipes[j].rank {
			return recipes[i].rank > recipes[j].rank
		}
		return recipes[i].Speed > recipes[j].Speed
	})
	chosen := choose(recipes)
	chosen.Verdict = VerdictFor(chosen.Speed)
	chosen.Considered = len(recipes)
	return chosen.Pipeline, true
}

// choose applique la règle, sur des recettes triées par image décroissante.
func choose(recipes []recipe) recipe {
	var holding []recipe
	for _, r := range recipes {
		if r.Speed >= HoldSpeed {
			holding = append(holding, r)
		}
	}
	if len(holding) == 0 {
		fastest := recipes[0]
		for _, r := range recipes[1:] {
			if r.Speed > fastest.Speed {
				fastest = r
			}
		}
		return fastest
	}
	for _, r := range holding {
		if r.headroom >= MarginFraction {
			return r
		}
	}
	// Sans marge : celle qui laisse le plus de sa ressource la plus tendue.
	spare := holding[0]
	for _, r := range holding[1:] {
		if r.headroom > spare.headroom {
			spare = r
		}
	}
	return spare
}

// predict rend la vitesse prévue et la marge : la part de la ressource la plus
// tendue qui reste libre une fois la recette payée à la vitesse de lecture.
func predict(cost, capacity, used Cost) (speed, headroom float64) {
	speed, headroom = math.Inf(1), math.Inf(1)
	for _, r := range Resources {
		need := cost.Of(r)
		if need <= 0 {
			continue
		}
		free := capacity.Of(r) - used.Of(r)
		speed = math.Min(speed, math.Max(free, 0)/need)
		headroom = math.Min(headroom, (free-need)/capacity.Of(r))
	}
	if math.IsInf(speed, 1) {
		// Une recette qui ne coûte rien (profil vide) : bornée, pour rester
		// comparable et lisible au journal.
		return 100, 1
	}
	return speed, headroom
}

// enumerate liste les recettes valides. Avec fallback, seuls les candidats de
// repli sont pris ; sans, seuls les autres.
func enumerate(job Job, p *Profile, fallback bool) []recipe {
	codec := "h264"
	if job.KeepHDR {
		codec = "hevc"
	}
	src := job.Source
	fps := src.FPS
	if fps < 1 || fps > 120 {
		fps = 24
	}
	outW, outH, needsScale := fit(src.Width, src.Height, job.Target.Width, job.Target.Height)
	srcRate := megapixels(src.Width, src.Height) * fps
	outRate := megapixels(outW, outH) * fps
	tm, tmGPU := toneMapOf(job, p)
	heavy := heavyDecode(src)

	var out []recipe
	for _, c := range p.Candidates(codec) {
		if c.Fallback != fallback {
			continue
		}
		// Une commande n'a qu'un périphérique de filtres : libplacebo y veut
		// Vulkan, un encodeur à envoi y veut le sien (TranscodeOptions.encoder()).
		// Le pipeline à deux périphériques est la phase 6.
		if c.Upload && tm == ToneMapLibplacebo {
			continue
		}
		base := Pipeline{
			Decode: "cpu", ToneMap: tm, ToneMapOnGPU: tmGPU, Encoder: c.Name, Hardware: c.Hardware,
			Threads: ThreadsFor(p.Inventory.Cores),
		}
		if needsScale {
			base.Scale = ScaleSoftware
		}
		if c.Hardware && c.Surface != "" && p.HardwareFilters(c.Surface) && hardwareChainApplies(job, tm, needsScale) {
			// La chaîne de fytroz : l'image reste sur le circuit, et la mise à
			// l'échelle y tourne toujours (au moins la conversion en NV12).
			base.Decode, base.Scale = c.Surface, c.Surface
		}
		for _, preset := range presetsOf(c, job.Target.Preset) {
			pipe := base
			pipe.Preset = preset
			cost, estimated, ok := recipeCost(p, pipe, heavy, needsScale, srcRate, outRate)
			if !ok {
				continue
			}
			pipe.Cost, pipe.Estimated = cost, estimated
			out = append(out, recipe{Pipeline: pipe, rank: imageRank(c, preset)})
		}
	}
	return out
}

// hardwareChainApplies reprend les conditions de usesHardwareFilters
// (streaming/hardware_filters.go) : le planificateur ne propose que ce que le
// rendu lancera.
func hardwareChainApplies(job Job, tm string, needsScale bool) bool {
	if job.SoftwareOnly || job.KeepHDR {
		return false
	}
	switch tm {
	case "":
		return true
	case ToneMapZscale:
		// Une source HDR déjà à la taille du barreau n'a rien à gagner :
		// l'aller-retour ne ferait que la ramener en mémoire.
		return needsScale
	default:
		return false
	}
}

// toneMapOf est le tone mapping que le rendu fera, comme toneMapperFor
// (streaming/tonemap_dovi.go) : libplacebo pour un profil 5 quand il tourne,
// zscale sinon, rien sans zscale.
func toneMapOf(job Job, p *Profile) (string, bool) {
	if !job.ToneMap || job.KeepHDR {
		return "", false
	}
	if job.Source.DV5 {
		if usable, gpu := p.Libplacebo(); usable {
			return ToneMapLibplacebo, gpu
		}
	}
	if p.Zscale() {
		return ToneMapZscale, false
	}
	return "", false
}

// presetsOf rend les presets à essayer pour un encodeur : libx264 de celui du
// barreau jusqu'au plus rapide, libx265 en ultrafast (encoder_hevc.go), aucun
// pour le circuit.
func presetsOf(c EncoderCandidate, tierPreset string) []string {
	switch {
	case c.Hardware:
		return []string{""}
	case c.Name == "libx264":
		for i, preset := range X264Presets {
			if preset == tierPreset {
				return X264Presets[i:]
			}
		}
		if tierPreset == "" {
			return X264Presets
		}
		return []string{tierPreset}
	case c.Name == "libx265":
		return []string{"ultrafast"}
	default:
		return []string{""}
	}
}

// imageRank classe les recettes par image, à débit égal. x264 d'abord, du
// preset le plus lent au plus rapide (ADR-0023 : ultrafast écrit 2,4 fois le
// débit de veryfast pour la même qualité, et le plafond du barreau le lui
// refuse) ; le circuit entre superfast et ultrafast.
func imageRank(c EncoderCandidate, preset string) int {
	if c.Hardware {
		return 15
	}
	switch preset {
	case "veryfast":
		return 30
	case "superfast":
		return 20
	case "ultrafast":
		if c.Name == "libx265" {
			// Le seul HEVC logiciel : il passe devant le circuit comme libx264.
			return 30
		}
		return 10
	}
	return 5
}

// recipeCost additionne les étapes. Le décodage sur le circuit ne compte que
// s'il a été mesuré : un circuit qui ne décode pas ce flux rend la main au
// processeur, et la référence ne le dirait pas.
func recipeCost(p *Profile, pipe Pipeline, heavy, needsScale bool, srcRate, outRate float64) (Cost, bool, bool) {
	var total Cost
	estimated := false
	add := func(stage Stage, variant string, hardware bool, rate float64) bool {
		c, ok := p.StageCost(stage, variant, hardware)
		if !ok {
			return false
		}
		estimated = estimated || c.Estimated
		total = total.Plus(c.Cost.Times(rate))
		return true
	}

	decodeCPU := DecodeH264CPU
	decodeHW := DecodeH264VAAPI
	if heavy {
		decodeCPU, decodeHW = DecodeHEVC10CPU, DecodeHEVC10VAAPI
	}
	decoded := false
	if pipe.Decode != "cpu" {
		if c, ok := p.StageCost(StageDecode, decodeHW, true); ok && !c.Estimated {
			total = total.Plus(c.Cost.Times(srcRate))
			decoded = true
		}
	}
	if !decoded && !add(StageDecode, decodeCPU, false, srcRate) {
		return Cost{}, false, false
	}
	switch pipe.Scale {
	case ScaleSoftware:
		if !add(StageScale, ScaleSoftware, false, srcRate) {
			return Cost{}, false, false
		}
	case "":
	default:
		if !add(StageScale, pipe.Scale, true, srcRate) {
			return Cost{}, false, false
		}
	}
	if pipe.ToneMap != "" && !add(StageToneMap, pipe.ToneMap, pipe.ToneMapOnGPU, outRate) {
		return Cost{}, false, false
	}
	if !add(StageEncode, EncodeVariant(pipe.Encoder, pipe.Preset), pipe.Hardware, outRate) {
		return Cost{}, false, false
	}
	return total.rounded(), estimated, true
}

// fit ajuste width×height dans la boîte, sans jamais agrandir, comme
// buildScaleFilter et outputResolution (streaming/ffmpeg.go).
func fit(width, height, boxW, boxH int) (int, int, bool) {
	if width <= 0 || height <= 0 {
		return boxW, boxH, true
	}
	if width <= boxW && height <= boxH {
		return width, height, false
	}
	scale := math.Min(float64(boxW)/float64(width), float64(boxH)/float64(height))
	return max(int(float64(width)*scale+0.5)&^1, 2), max(int(float64(height)*scale+0.5)&^1, 2), true
}

// heavyDecode range la source dans la classe de décodage lourde : HEVC, AV1,
// VP9, ou tout flux de plus de 8 bits.
func heavyDecode(src Source) bool {
	switch src.Codec {
	case "hevc", "av1", "vp9":
		return true
	}
	return src.BitDepth > 8
}

func megapixels(width, height int) float64 { return float64(width) * float64(height) / 1e6 }
