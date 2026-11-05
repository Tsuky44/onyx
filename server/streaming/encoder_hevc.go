package streaming

import (
	"log"
	"strings"
	"sync"
)

// L'encodeur HEVC d'une session dont l'image garde son HDR (VideoPlan.HEVC,
// ADR-0106).
//
// Il suit le choix de l'opérateur pour le H.264 : libx265 derrière libx264,
// le même circuit derrière un encodeur matériel. Un circuit qui ne sait pas
// faire de HEVC Main 10 ne renvoie pas vers libx265 : l'opérateur a choisi le
// matériel parce que le processeur est la ressource rare, et libx265 coûte
// deux à trois fois libx264 (mesuré sur 10 s de 1080p bruité, 8 cœurs Apple :
// libx264 veryfast 6,5 s, libx265 ultrafast 13,7 s, superfast 19,9 s). La
// session repart alors en H.264 tone-mappé, comme avant.
//
// Toujours en 10 bits : c'est la profondeur que porte le HDR10 et le HLG, et
// la seule raison d'encoder en HEVC ici.

// softwareHEVCEncoder est libx265, en ultrafast à tous les barreaux : déjà au
// double de libx264 veryfast, un réglage plus lent ne tiendrait plus le temps
// réel sur l'hôte sans GPU.
var softwareHEVCEncoder = VideoEncoder{
	Name:        "libx265",
	Codec:       "hevc",
	PixelFormat: "yuv420p10le",
	rateControl: func(preset qualityPreset) []string {
		return []string{
			"-preset", "ultrafast",
			// L'équivalent du CRF 23 de libx264 : le HEVC tient la même image
			// avec moins de bits.
			"-crf", "26",
			"-b:v", "0",
			"-maxrate", preset.VideoBitrate,
			"-bufsize", doubleBitrate(preset.VideoBitrate),
			// Une image I demandée par -force_key_frames n'est pas une IDR chez
			// x265 sans ceci, et le découpage HLS a besoin d'IDR. scenecut=0 est
			// le sc_threshold de libx264 ; open-gop=0 rend chaque segment lisible
			// seul.
			"-forced-idr", "1",
			"-x265-params", "log-level=error:scenecut=0:open-gop=0",
		}
	},
}

// hevcSiblings associe chaque encodeur H.264 matériel au HEVC du même
// circuit. Les réglages de débit sont les mêmes ; seul le format d'image
// change, en 10 bits.
var hevcSiblings = map[string]VideoEncoder{
	"h264_videotoolbox": {
		Name: "hevc_videotoolbox", Codec: "hevc", Hardware: true, PixelFormat: "p010le",
	},
	"h264_nvenc": {
		Name: "hevc_nvenc", Codec: "hevc", Hardware: true, PixelFormat: "p010le",
	},
	"h264_qsv": {
		Name: "hevc_qsv", Codec: "hevc", Hardware: true, PixelFormat: "p010le",
	},
	"h264_vaapi": {
		Name: "hevc_vaapi", Codec: "hevc", Hardware: true,
		uploadFilter: "format=p010,hwupload",
	},
}

var (
	hevcEncoderOnce     sync.Once
	resolvedHEVCEncoder VideoEncoder
	hevcEncoderOK       bool
)

// SelectedHEVCEncoder est l'encodeur HEVC des sessions, et faux quand ce
// serveur n'en a pas qui marche.
func SelectedHEVCEncoder() (VideoEncoder, bool) {
	hevcEncoderOnce.Do(func() {
		resolvedHEVCEncoder, hevcEncoderOK = hevcEncoderFor(SelectedVideoEncoder(), encoderRuns)
		if hevcEncoderOK {
			log.Printf("Streaming: HEVC encoder %s (hardware=%v)", resolvedHEVCEncoder.Name, resolvedHEVCEncoder.Hardware)
		} else {
			log.Println("Streaming: no working HEVC encoder, HDR sources are tone mapped to H.264")
		}
	})
	return resolvedHEVCEncoder, hevcEncoderOK
}

// hevcEncoderFor résout le HEVC qui va avec l'encodeur H.264 [h264]. La sonde
// est passée en argument pour se tester sans FFmpeg.
func hevcEncoderFor(h264 VideoEncoder, works func(VideoEncoder) bool) (VideoEncoder, bool) {
	candidate := softwareHEVCEncoder
	if h264.Hardware {
		sibling, ok := hevcSiblings[h264.Name]
		if !ok {
			return VideoEncoder{}, false
		}
		sibling.deviceArgs = h264.deviceArgs
		sibling.rateControl = h264.rateControl
		candidate = sibling
	}
	if !works(candidate) {
		return VideoEncoder{}, false
	}
	return candidate, true
}

// hevcEncoder résout ce que les options ont demandé, libx265 par défaut.
func (o TranscodeOptions) hevcEncoder() VideoEncoder {
	if o.HEVCEncoder.Name == "" || o.HEVCEncoder.rateControl == nil {
		return softwareHEVCEncoder
	}
	return o.HEVCEncoder
}

// hdrTagFilter écrit sur chaque image les étiquettes de couleur du HDR gardé.
//
// Les options de sortie (-color_trc…) ne suffisent pas : FFmpeg 8 prend les
// propriétés des images, et une source qui ne porte que la matrice (un AV1
// sorti de SVT-AV1, mesuré) ressortait sans primaires ni transfert. Un
// lecteur lit alors du PQ comme du gamma : l'image délavée que le tone mapping
// évite d'habitude.
func hdrTagFilter(v *VideoStreamInfo) string {
	transfer := "smpte2084"
	if v.HDRFormat() == "hlg" || (v.DoviProfile > 0 && v.DoviBLCompatID == 4) {
		transfer = "arib-std-b67"
	}
	return "setparams=color_primaries=bt2020:color_trc=" + transfer + ":colorspace=bt2020nc"
}

// deinterlaceFilter rend une image par image source (send_frame) : 25i
// devient 25p, la cadence que le GOP et le débit des barreaux supposent.
// deint=interlaced laisse passer telles quelles les images que la source
// marque progressives, ce que font beaucoup de diffusions mixtes.
const deinterlaceFilter = "bwdif=mode=send_frame:parity=auto:deint=interlaced"

// isHEVC dit un encodeur HEVC, que la commande règle en Main 10.
func (e VideoEncoder) isHEVC() bool { return strings.EqualFold(e.Codec, "hevc") }
