package streaming

import (
	"fmt"
	"strings"
)

// Ce que le journal dit du pipeline d'une session.
//
// Deux jours se sont perdus sur une session dont rien ne disait quel tone
// mapping elle faisait : zscale sur le processeur, ou libplacebo sur le
// circuit, ou sur lavapipe. La ligne de démarrage nomme donc tout le chemin
// de l'image : décodage, tone mapping, encodeur, preset, threads.

// Les valeurs de decodeMode. Tout le reste est le nom d'une surface matérielle
// (`vaapi`), celle que hardware_filters.go demande à FFmpeg de garder.
const (
	decodeAuto   = "hwaccel auto"
	decodeVulkan = "vulkan"
)

// decodeMode dit comment la commande de cette session décode, et c'est lui qui
// l'écrit (BuildFFmpegArgs) : le journal ne peut pas raconter autre chose que
// ce qui est lancé.
//
// Vulkan quand libplacebo fait le tone mapping : la commande ouvre alors un
// périphérique Vulkan, et `-hwaccel auto` tenterait de décoder avec lui. La
// surface de l'encodeur quand l'image reste sur le circuit. `hwaccel auto`
// sinon, que FFmpeg replie en silence sur le logiciel.
func decodeMode(opt TranscodeOptions) string {
	switch {
	case sessionToneMapper(opt).Vulkan:
		return decodeVulkan
	case opt.usesHardwareFilters():
		return opt.encoder().surface
	default:
		return decodeAuto
	}
}

// toneMappingName nomme le tone mapping : `aucun` (source SDR, image recopiée,
// ou FFmpeg sans zscale), `zscale` sur le processeur, ou `libplacebo@gpu` /
// `libplacebo@logiciel` selon que le périphérique Vulkan choisi est un circuit.
func toneMappingName(tm ToneMapper, vulkanOnGPU bool) string {
	switch {
	case tm.Filter == "":
		return "aucun"
	case !tm.Vulkan:
		return "zscale"
	case vulkanOnGPU:
		return "libplacebo@gpu"
	default:
		return "libplacebo@logiciel"
	}
}

// describePipeline écrit le pipeline que BuildFFmpegArgs construit pour ces
// options, pour la ligne de démarrage de la session.
//
// Le preset et les threads se lisent dans les arguments de l'encodeur
// lui-même (rateControl) plutôt que d'être recalculés : l'encodeur matériel
// n'en a pas toujours, et la valeur journalisée est ainsi celle qui part à
// FFmpeg.
func describePipeline(opt TranscodeOptions, vulkanOnGPU bool) string {
	tonemap := toneMappingName(sessionToneMapper(opt), vulkanOnGPU)
	encoder, preset, threads := "copie", "-", "-"
	if !opt.Video.Copy {
		enc := opt.encoder()
		encoder = enc.Name
		if enc.rateControl != nil {
			flags := enc.rateControl(presetFor(opt.Quality))
			preset = flagValue(flags, "-preset", preset)
			threads = flagValue(flags, "-threads", threads)
		}
	}
	return fmt.Sprintf("décodage=%s, tone mapping=%s, encodeur=%s, preset=%s, threads=%s",
		decodeMode(opt), tonemap, encoder, preset, threads)
}

// flagValue est la valeur qui suit name dans args, ou fallback.
func flagValue(args []string, name, fallback string) string {
	for i := 0; i+1 < len(args); i++ {
		if strings.EqualFold(args[i], name) {
			return args[i+1]
		}
	}
	return fallback
}
