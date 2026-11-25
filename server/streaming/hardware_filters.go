package streaming

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// L'image qui reste sur le circuit vidéo.
//
// Avec h264_vaapi seul, le circuit n'encodait que la fin : `-hwaccel auto`
// ramenait chaque image décodée en mémoire, en 4K, puis la mise à l'échelle et
// le tone mapping tournaient sur les cœurs avant le renvoi à l'encodeur.
//
// Ce chemin n'a pas de mesure sur un vrai circuit. Celle qui l'a fait écrire
// (0,7× sur un i7-10700K) venait d'un Dolby Vision profil 5, qui ne passe pas
// par ici mais par libplacebo : voir vulkan_device.go. Reste le raisonnement :
// 24 Mo par image 4K à ramener puis à réduire, pour rien.
//
// Ici le décodage rend des images du périphérique et la mise à l'échelle s'y
// fait (`scale_vaapi`). Une source SDR ne redescend plus du tout ; une source
// HDR redescend une fois, déjà à la taille du barreau, pour le tone mapping,
// qui reste logiciel : le pilote Intel ne sait le faire sur le circuit qu'à
// partir d'Ice Lake (tableau « HDR10 TM » de son README), et rien ne permet
// de l'essayer sans la machine.
//
// Rien de tout cela n'a tourné sur un vrai circuit avant d'être écrit. D'où
// les trois gardes : l'essai du démarrage, qui passe par la même chaîne
// qu'une session ; HARDWARE_FILTERS=off ; et le retrait de la chaîne pour
// tout le serveur dès qu'une session meurt avec elle avant son premier
// segment. Voir l'ADR « la chaîne VAAPI ne ramène plus le 4K en mémoire ».

// hardwareDecodeArgs demande le décodage sur le circuit de l'encodeur, images
// laissées sur le périphérique. Si le circuit ne décode pas ce flux, FFmpeg
// décode en logiciel et la tête de la chaîne envoie l'image elle-même.
func hardwareDecodeArgs(encoder VideoEncoder) []string {
	return []string{"-hwaccel", encoder.surface, "-hwaccel_output_format", encoder.surface}
}

// usesHardwareFilters dit si cette session garde son image sur le circuit.
//
// Tout ce qui a besoin d'images logicielles reste sur la chaîne de toujours :
// un sous-titre incrusté et le désentrelacement, qui se font avant la mise à
// l'échelle. Le HEVC qui garde son HDR aussi, tant que personne ne l'a vu
// tourner. Une source HDR qui tient déjà dans le barreau n'a rien à gagner :
// sans mise à l'échelle, l'aller-retour ne ferait que la ramener en mémoire.
func (o TranscodeOptions) usesHardwareFilters() bool {
	if !o.HardwareFilters || o.Video.Copy || o.Video.HEVC || o.Video.Deinterlace {
		return false
	}
	if o.BurnSubtitle && o.BurnSubtitleTypedIndex >= 0 {
		return false
	}
	if o.encoder().surface == "" {
		return false
	}
	if !o.Video.Tonemap {
		return true
	}
	if sessionToneMapper(o).Filter == "" {
		return false
	}
	return buildScaleFilter(o.Probe, presetFor(o.Quality)) != ""
}

// hardwareFilterChain est la chaîne d'une session dont l'image reste sur le
// circuit. Elle produit la même taille que buildScaleFilter.
func hardwareFilterChain(opt TranscodeOptions, preset qualityPreset) string {
	encoder := opt.encoder()
	// La tête prend les deux : une image déjà sur le périphérique passe telle
	// quelle, une image que le décodeur a dû rendre en logiciel (codec que le
	// circuit ne connaît pas) y est envoyée. C'est ce qui évite qu'une telle
	// source tue la session.
	head := "format=nv12|p010le|" + encoder.surface + ",hwupload"
	scale := "scale_" + encoder.surface + "="
	if buildScaleFilter(opt.Probe, preset) != "" {
		scale += fmt.Sprintf(
			"w=%d:h=%d:force_original_aspect_ratio=decrease:force_divisible_by=2:",
			preset.W, preset.H,
		)
	}
	tonemap := sessionToneMapper(opt).Filter
	if tonemap == "" {
		// Sortie en NV12 : une source SDR en 10 bits y est ramenée à 8 par le
		// circuit, et l'encodeur prend l'image sans qu'elle ait quitté le
		// périphérique.
		return head + "," + scale + "format=nv12"
	}
	// Le tone mapping lit du 10 bits : l'image redescend à la taille du
	// barreau, quatre fois moins de pixels qu'une source 4K, puis remonte.
	return strings.Join([]string{
		head,
		scale + "format=p010le",
		"hwdownload",
		"format=p010le",
		tonemap,
		encoder.uploadFilter,
	}, ",")
}

var (
	hardwareFiltersOnce sync.Once
	hardwareFiltersOK   bool
	// hardwareFiltersOff est posé quand une session est morte avec la chaîne
	// matérielle : l'essai du démarrage ne voit qu'une source de synthèse.
	hardwareFiltersOff atomic.Bool
)

// HardwareFiltersUsable dit si les sessions peuvent garder leur image sur le
// circuit. Résolu une fois, au démarrage, par un essai réel.
func HardwareFiltersUsable() bool {
	hardwareFiltersOnce.Do(func() {
		hardwareFiltersOK = resolveHardwareFilters(SelectedVideoEncoder())
	})
	return hardwareFiltersOK && !hardwareFiltersOff.Load()
}

// resolveHardwareFilters fabrique la source d'essai et lance l'essai.
func resolveHardwareFilters(encoder VideoEncoder) bool {
	if encoder.surface == "" {
		return false
	}
	dir, err := os.MkdirTemp("", "onyx-hwprobe-*")
	if err != nil {
		log.Printf("Streaming: hardware filters not tested, keeping software filters: %v", err)
		return false
	}
	defer os.RemoveAll(dir)
	return detectHardwareFilters(encoder, filepath.Join(dir, "sample.mkv"), ffmpegHasFilter, runFFmpegProbe)
}

// detectHardwareFilters décide si la chaîne matérielle tient sur cet hôte.
//
// Les deux variantes d'une session y passent, sur une source HEVC 10 bits
// marquée HDR10 : celle d'une source SDR, qui ne quitte pas le circuit, et
// celle d'une source HDR, qui redescend pour le tone mapping. Une seule qui
// échoue et tout le serveur garde ses filtres logiciels.
//
// L'essai du décodage, lui, ne décide de rien : la chaîne marche aussi quand
// le circuit ne décode pas. Mais c'est la ligne du journal qui dit pourquoi
// un serveur « matériel » occupe encore tous ses cœurs.
func detectHardwareFilters(
	encoder VideoEncoder,
	sample string,
	hasFilter func(name string) bool,
	run func(args []string) error,
) bool {
	if encoder.surface == "" {
		return false
	}
	if hardwareFiltersDisabledByEnv() {
		log.Println("Streaming: HARDWARE_FILTERS=off, keeping software filters")
		return false
	}
	scale := "scale_" + encoder.surface
	if !hasFilter(scale) || !hasFilter("hwdownload") || !hasFilter("hwupload") {
		log.Printf("Streaming: this FFmpeg has no %s/hwdownload/hwupload, keeping software filters", scale)
		return false
	}
	if err := run(hardwareProbeSampleArgs(sample)); err != nil {
		log.Printf("Streaming: hardware filters not tested (no HEVC 10-bit sample), keeping software filters: %v", err)
		return false
	}

	if err := run(hardwareDecodeProbeArgs(encoder, sample)); err != nil {
		log.Printf("Streaming: %s does not decode HEVC 10-bit here, such sources are decoded on the CPU: %v",
			encoder.surface, err)
	} else {
		log.Printf("Streaming: %s decodes HEVC 10-bit", encoder.surface)
	}

	for _, tonemap := range []bool{false, true} {
		opt := hardwareProbeOptions(encoder, tonemap)
		if !opt.usesHardwareFilters() {
			// Pas de zscale dans ce FFmpeg : la variante HDR n'existe pas, et
			// ses sessions gardent la chaîne logicielle.
			continue
		}
		if err := run(hardwareChainProbeArgs(opt, sample)); err != nil {
			log.Printf("Streaming: hardware filters unusable (tonemap=%v), keeping software filters: %v", tonemap, err)
			return false
		}
	}
	log.Printf("Streaming: hardware filters on (%s): decoding and scaling stay on the device", encoder.surface)
	return true
}

// hardwareFiltersDisabledByEnv lit HARDWARE_FILTERS : le moyen de revenir à la
// chaîne logicielle sans attendre une image du serveur.
func hardwareFiltersDisabledByEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("HARDWARE_FILTERS"))) {
	case "0", "off", "false", "no":
		return true
	}
	return false
}

// hardwareProbeQuality est un barreau plus petit que la source d'essai, pour
// que la mise à l'échelle ait lieu.
const hardwareProbeQuality = "360p"

// hardwareProbeSampleArgs écrit la source d'essai : six images de 720p en
// HEVC Main 10, marquées BT.2020 PQ comme un film HDR10.
//
// Les marques sont posées deux fois, sur les images (`setparams`) et dans le
// flux par x265 lui-même, et pas par `-color_trc` sur la sortie : le FFmpeg
// du runner de la CI ignore cette option et écrivait une source sans
// transfert. Or zscale refuse une image dont il ne connaît pas le transfert,
// donc l'essai de la variante HDR aurait échoué sur un circuit qui marche.
func hardwareProbeSampleArgs(path string) []string {
	return []string{
		"-hide_banner", "-loglevel", "error", "-y",
		"-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=24," +
			"setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc",
		"-frames:v", "6",
		"-c:v", "libx265", "-preset", "ultrafast", "-pix_fmt", "yuv420p10le",
		"-x265-params", "log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc",
		path,
	}
}

// hardwareProbeOptions décrit la source d'essai comme une session la verrait.
func hardwareProbeOptions(encoder VideoEncoder, tonemap bool) TranscodeOptions {
	return TranscodeOptions{
		Quality: hardwareProbeQuality,
		Probe: &ProbeResult{Video: &VideoStreamInfo{
			Width: 1280, Height: 720, Codec: "hevc", FrameRate: 24,
		}},
		Encoder:         encoder,
		HardwareFilters: true,
		Video:           VideoPlan{Tonemap: tonemap},
	}
}

// hardwareChainProbeArgs passe deux images de la source d'essai par le
// périphérique, le décodage, la chaîne et l'encodeur d'une session.
func hardwareChainProbeArgs(opt TranscodeOptions, sample string) []string {
	encoder := opt.encoder()
	args := []string{"-hide_banner", "-loglevel", "error"}
	args = append(args, encoder.deviceArgs...)
	args = append(args, hardwareDecodeArgs(encoder)...)
	return append(args,
		"-i", sample,
		"-vf", hardwareFilterChain(opt, presetFor(opt.Quality)),
		"-c:v", encoder.Name,
		"-frames:v", "2",
		"-f", "null", "-",
	)
}

// hardwareDecodeProbeArgs n'a pas la tête qui accepte une image logicielle :
// la commande échoue donc si le circuit n'a pas décodé lui-même.
func hardwareDecodeProbeArgs(encoder VideoEncoder, sample string) []string {
	args := []string{"-hide_banner", "-loglevel", "error"}
	args = append(args, encoder.deviceArgs...)
	args = append(args, hardwareDecodeArgs(encoder)...)
	return append(args,
		"-i", sample,
		"-vf", "scale_"+encoder.surface+"=w=640:h=360,hwdownload,format=p010le",
		"-frames:v", "2",
		"-f", "null", "-",
	)
}

// runFFmpegProbe lance un essai et rend ce que FFmpeg a dit en échouant.
func runFFmpegProbe(args []string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, "ffmpeg", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}
