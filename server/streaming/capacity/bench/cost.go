package bench

import (
	"errors"
	"fmt"
	"strconv"
)

// Step est une étape du pipeline dont on veut le coût : un filtre, un
// encodeur, ou les deux. La commande qui la mesure et sa ligne de base ne
// diffèrent que par elle.
type Step struct {
	Name string
	// Filter est la valeur de `-vf` ; vide pour une étape sans filtre.
	Filter string
	// Codec sont les arguments de sortie vidéo (`-c:v libx264 -preset …`) ; vide
	// pour une étape de filtre seule, que la ligne de base écrit comme elle.
	Codec []string
	// Megapixels est la taille d'image que l'étape traite, pour rapporter son
	// coût à la surface : l'entrée d'un filtre, la sortie d'un encodeur.
	Megapixels float64
	// NeedsHDR dit que l'étape n'a de sens que sur une source marquée HDR10 :
	// zscale refuse une image dont il ne connaît pas le transfert, et la
	// commande échoue au lieu de coûter quelque chose.
	NeedsHDR bool
}

// Applies dit si l'étape se mesure sur cette source.
func (s Step) Applies(src SourceSpec) bool { return !s.NeedsHDR || src.HDR10 }

// baselineCodec écrit les images telles quelles : la sortie de la ligne de
// base, qui ne compresse rien.
var baselineCodec = []string{"-c:v", "rawvideo"}

// MeasuredArgs est la commande qui exerce l'étape : l'entrée, le filtre, le
// codec, rien écrit (`-f null`), frames images au plus.
func (s Step) MeasuredArgs(input []string, frames int) []string {
	codec := s.Codec
	if len(codec) == 0 {
		codec = baselineCodec
	}
	return commandArgs(input, s.Filter, codec, frames)
}

// BaselineArgs est la même commande sans l'étape : même entrée, mêmes images,
// ni filtre ni codec. Elle paie ce que l'étape ne doit pas se voir imputer — le
// démarrage du processus, la génération `lavfi` ou le décodage de la source —,
// et le coût de l'étape est la différence entre les deux.
func (s Step) BaselineArgs(input []string, frames int) []string {
	return commandArgs(input, "", baselineCodec, frames)
}

func commandArgs(input []string, filter string, codec []string, frames int) []string {
	args := []string{"-hide_banner", "-loglevel", "error"}
	args = append(args, input...)
	if filter != "" {
		args = append(args, "-vf", filter)
	}
	args = append(args, "-frames:v", strconv.Itoa(frames))
	args = append(args, codec...)
	return append(args, "-f", "null", "-")
}

// FileInput est l'entrée d'une source écrite par GenerateArgs, pour mesurer
// une étape qui suit un vrai décodage.
func FileInput(path string) []string { return []string{"-i", path} }

// StandardSteps sont les étapes que le plan veut chiffrer, de la plus légère à
// la plus lourde. Les filtres sont ceux du serveur ; le banc ne peut pas les
// lire dans streaming sans l'importer, donc ils sont recopiés ici et à garder
// alignés avec `buildScaleFilter` et `hdrToSDRFilter`.
func StandardSteps() []Step {
	return []Step{
		{
			Name:       "mise à l'échelle 1080p → 720p (swscale)",
			Filter:     "scale=w=1280:h=720:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=bilinear",
			Megapixels: Megapixels(1920, 1080),
		},
		{
			Name: "tone mapping zscale (Hable)",
			Filter: "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709," +
				"tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p",
			Megapixels: Megapixels(1920, 1080),
			NeedsHDR:   true,
		},
		{
			Name:       "libx264 veryfast",
			Filter:     "format=yuv420p",
			Codec:      []string{"-c:v", "libx264", "-preset", "veryfast", "-crf", "23"},
			Megapixels: Megapixels(1920, 1080),
		},
		{
			Name:       "libx264 ultrafast",
			Filter:     "format=yuv420p",
			Codec:      []string{"-c:v", "libx264", "-preset", "ultrafast", "-crf", "23"},
			Megapixels: Megapixels(1920, 1080),
		},
	}
}

// StepCost est le coût de l'étape en cœur-secondes par mégapixel·image : le
// temps processeur que mesured dépasse baseline, rapporté au nombre d'images
// et à leur taille. Le débit d'une machine s'en déduit : une étape de c
// cœur-seconde/Mpx·image sur une image de m Mpx coûte c×m cœurs à une image
// par seconde.
//
// Les deux mesures doivent avoir traité les mêmes images, sans quoi la
// soustraction ne compare pas la même chose. Un coût négatif — le bruit d'une
// étape trop légère devant la variation de la ligne de base — est ramené à 0 :
// refaire la mesure avec plus d'images ou MeasureMedian.
func StepCost(measured, baseline Result, megapixels float64) (float64, error) {
	if measured.Frames <= 0 || megapixels <= 0 {
		return 0, errors.New("bench: aucune image mesurée, ou taille d'image inconnue")
	}
	if measured.Frames != baseline.Frames {
		return 0, fmt.Errorf("bench: la mesure a %d images et la ligne de base %d : la soustraction ne compare pas la même chose",
			measured.Frames, baseline.Frames)
	}
	extra := (measured.CPU - baseline.CPU).Seconds()
	if extra < 0 {
		extra = 0
	}
	return extra / (float64(measured.Frames) * megapixels), nil
}

// CoresAt est ce que coûte l'étape, en cœurs, pour tenir fps images par seconde
// à megapixels mégapixels l'image.
func CoresAt(costPerMegapixelFrame, megapixels, fps float64) float64 {
	return costPerMegapixelFrame * megapixels * fps
}
