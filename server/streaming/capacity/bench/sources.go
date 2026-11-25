// Package bench est le banc de mesure du transcodage : il fabrique des sources
// de test avec FFmpeg, lance une commande en relevant ce qu'elle coûte, et en
// déduit le coût d'une étape par soustraction d'une ligne de base.
//
// Il n'importe pas le paquet streaming (qui importera capacity, pour le profil
// matériel de la phase 1) : le banc reçoit des arguments FFmpeg et rend des
// chiffres, rien d'autre. Voir docs/transcodage-adaptatif.md, phase 0.
//
// Les sources viennent de `lavfi testsrc2`, pas d'un film : l'image est
// synthétique et se compresse autrement qu'une vraie. Le coût mesuré ici est
// un ordre de grandeur reproductible d'une machine à l'autre, pas le coût
// d'un film donné.
package bench

import "strconv"

// SourceSpec décrit une source de mesure.
type SourceSpec struct {
	Name          string
	Width, Height int
	FPS           int
	// Codec et PixFmt sont ceux du fichier écrit.
	Codec  string
	PixFmt string
	// HDR10 marque la source BT.2020 PQ, comme un film HDR10 : sans transfert
	// connu, zscale refuse l'image.
	HDR10 bool
}

// Les trois sources du plan. 1080p : de quoi comparer les machines sans
// attendre, et la taille que prennent les barreaux les plus lus.
var (
	// SDRH264 est un 1080p H.264 SDR 8 bits, le cas ordinaire.
	SDRH264 = SourceSpec{Name: "1080p-h264-sdr", Width: 1920, Height: 1080, FPS: 24, Codec: "libx264", PixFmt: "yuv420p"}
	// HEVC10 est un 1080p HEVC Main 10, sans marque HDR.
	HEVC10 = SourceSpec{Name: "1080p-hevc-10bit", Width: 1920, Height: 1080, FPS: 24, Codec: "libx265", PixFmt: "yuv420p10le"}
	// HDR10 est le même HEVC 10 bits, marqué BT.2020 PQ.
	HDR10 = SourceSpec{Name: "1080p-hevc-hdr10", Width: 1920, Height: 1080, FPS: 24, Codec: "libx265", PixFmt: "yuv420p10le", HDR10: true}
)

// Sources liste les sources de mesure, de la plus simple à la plus lourde.
func Sources() []SourceSpec { return []SourceSpec{SDRH264, HEVC10, HDR10} }

// Megapixels est la taille d'une image, en mégapixels.
func (s SourceSpec) Megapixels() float64 { return Megapixels(s.Width, s.Height) }

// Megapixels est la taille d'une image width×height, en mégapixels.
func Megapixels(width, height int) float64 { return float64(width) * float64(height) / 1e6 }

// hdr10Marks pose BT.2020 PQ sur les images. Les marques sont posées deux
// fois, sur les images (`setparams`) et dans le flux par x265, et pas par
// `-color_trc` en sortie : le FFmpeg de certains runners ignore cette option
// et écrit une source sans transfert (voir hardwareProbeSampleArgs).
const hdr10Marks = "setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc"

// LavfiInput est l'entrée synthétique de cette source : des images générées
// à la volée, sans fichier, pour mesurer une étape sans le décodage.
func (s SourceSpec) LavfiInput() []string {
	graph := "testsrc2=size=" + strconv.Itoa(s.Width) + "x" + strconv.Itoa(s.Height) +
		":rate=" + strconv.Itoa(s.FPS)
	if s.HDR10 {
		graph += "," + hdr10Marks
	}
	return []string{"-f", "lavfi", "-i", graph}
}

// GenerateArgs est la commande qui écrit la source dans path : seconds
// secondes d'images, encodées au plus vite (la source n'est pas ce qu'on mesure).
func (s SourceSpec) GenerateArgs(path string, seconds int) []string {
	args := []string{"-hide_banner", "-loglevel", "error", "-y"}
	args = append(args, s.LavfiInput()...)
	args = append(args,
		"-frames:v", strconv.Itoa(seconds*s.FPS),
		"-c:v", s.Codec, "-preset", "ultrafast", "-pix_fmt", s.PixFmt,
	)
	if s.Codec == "libx265" {
		params := "log-level=error"
		if s.HDR10 {
			params += ":colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc"
		}
		args = append(args, "-x265-params", params)
	}
	return append(args, path)
}

// Frames est le nombre d'images de seconds secondes de cette source.
func (s SourceSpec) Frames(seconds int) int { return seconds * s.FPS }
