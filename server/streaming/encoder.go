package streaming

import (
	"context"
	"log"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Which H.264 encoder a session uses.
//
// The default is unchanged: libx264, on the CPU. Hardware encoding is offered,
// not assumed, because "hardware is faster" turns out not to be a property of
// hardware — it is a property of a particular box. Measured on an 8-core Apple
// Silicon machine, 20s of 2160p:
//
//	libx264 ultrafast   1.95s wall   10.4s CPU   (10.3x real-time, ~5.3 cores)
//	libx264 veryfast    4.41s wall   30.2s CPU   ( 4.5x real-time, ~6.8 cores)
//	h264_videotoolbox   8.92s wall    3.7s CPU   ( 2.2x real-time, ~0.4 cores)
//
// The hardware encoder spends a fourteenth of the CPU and is four times slower
// at it. Which of those matters depends on the host: on a machine with cores to
// spare, libx264 finishes sooner and more sessions fit; on the CPU-only Xeon
// this server was written against — where the note on the 2160p preset records
// veryfast measuring *below* real-time on a genuine HEVC source — an encoder
// that needs almost no CPU is the difference between transcoding and not.
//
// So the choice is the operator's, and the measurement is theirs to make. See
// the ADR for the one-line benchmark.

// VideoEncoder is an encoder this server can drive.
type VideoEncoder struct {
	// Name is the FFmpeg encoder name.
	Name string
	// Codec vaut "hevc" pour un encodeur HEVC (encoder_hevc.go) ; vide pour
	// le H.264, ce qu'étaient tous les encodeurs avant lui.
	Codec string
	// Hardware says the encoding leaves the CPU.
	Hardware bool
	// PixelFormat is what the filter chain must hand it. Empty for an encoder
	// that takes hardware frames: its uploadFilter sets the format instead.
	PixelFormat string
	// deviceArgs ouvre, avant l'entrée, le périphérique dont l'encodeur a besoin.
	deviceArgs []string
	// uploadFilter termine la chaîne de filtres en envoyant l'image au
	// périphérique, pour un encodeur qui ne prend pas d'images logicielles.
	uploadFilter string
	// surface nomme les images du périphérique (`vaapi`) quand le même circuit
	// sait aussi décoder et mettre à l'échelle : l'image peut alors y rester
	// de bout en bout. Vide : les filtres sont logiciels. Voir
	// hardware_filters.go.
	surface string
	// surfaceArgs est ce que le décodage sur la surface demande en plus,
	// avant l'entrée, quand deviceArgs n'ouvre pas déjà le périphérique des
	// filtres : c'est le cas d'un encodeur qui prend aussi des images
	// logicielles et n'a donc besoin d'aucun périphérique pour encoder.
	surfaceArgs []string
	// rateControl builds the flags that set quality and bitrate, which is where
	// the encoders differ most: libx264 targets a quality and caps the result,
	// while the hardware encoders take a bitrate and hold it.
	rateControl func(preset qualityPreset) []string
}

// softwareEncoder is the default and the fallback. Its flags are exactly the
// ones this server has always sent.
var softwareEncoder = VideoEncoder{
	Name:        "libx264",
	PixelFormat: "yuv420p",
	rateControl: func(preset qualityPreset) []string {
		return []string{
			"-preset", encoderPresetFor(preset),
			// CRF is the quality target; maxrate/bufsize are the VBV ceiling
			// that keeps a detailed scene from bursting past what the link
			// carries.
			"-crf", "23",
			"-b:v", "0",
			"-maxrate", preset.VideoBitrate,
			"-bufsize", doubleBitrate(preset.VideoBitrate),
			"-threads", strconv.Itoa(maxEncoderThreads),
		}
	},
}

// hardwareEncoders are tried in this order. They have one thing in common that
// keeps this change small: all three accept ordinary software frames and upload
// them internally, so the filter chain — scaling, tone mapping, burned-in
// subtitles — is the same as it has always been.
//
// VAAPI vient en dernier. C'est le seul qui ne prend pas d'images logicielles :
// il lui faut un périphérique ouvert avant l'entrée et un `hwupload` au bout de
// la chaîne de filtres (deviceArgs, uploadFilter). C'est aussi le seul chemin
// vers le circuit d'un processeur Intel ou AMD sans carte graphique sous Linux
// quand Quick Sync n'a pas son runtime — le cas de l'image Docker.
var hardwareEncoders = []VideoEncoder{
	{
		Name:        "h264_videotoolbox",
		Hardware:    true,
		PixelFormat: "yuv420p",
		rateControl: func(preset qualityPreset) []string {
			return []string{
				// No CRF here: VideoToolbox takes a bitrate and holds it. The
				// stream therefore sits at the tier's number rather than under
				// it, which is what the menu promised anyway.
				"-b:v", preset.VideoBitrate,
				"-maxrate", preset.VideoBitrate,
				"-bufsize", doubleBitrate(preset.VideoBitrate),
				// Let it fall back to its own software path rather than fail the
				// session outright if the hardware block is unavailable.
				"-allow_sw", "1",
			}
		},
	},
	{
		Name:        "h264_nvenc",
		Hardware:    true,
		PixelFormat: "yuv420p",
		// La carte décode (NVDEC) et met à l'échelle (scale_cuda) : l'image
		// peut y rester jusqu'à l'encodeur, qui prend les images CUDA telles
		// quelles. Le périphérique n'est ouvert que pour ces sessions : nommé
		// dans deviceArgs, il deviendrait le périphérique des filtres de
		// toutes, y compris de celles où libplacebo veut Vulkan (ADR-0060).
		//
		// NVDEC n'ouvre pas un décodeur de plus de 32 surfaces (nvdec.c :
		// « Using more than 32 decode surfaces might cause nvdec to fail »),
		// et FFmpeg en demande le DPB du flux, cinq de marge fixe, une par
		// thread de décodage, plus -extra_hw_frames. Vu sur une P2200 le
		// 2026-11-27 : « cuvidCreateDecoder failed -> CUDA_ERROR_INVALID_VALUE »
		// dès la source d'essai en 720p, et tout était décodé sur le
		// processeur. La cause est lue dans les sources : 16 threads (le
		// défaut de FFmpeg sur un processeur qui en a autant) et huit images
		// de marge font 29 surfaces avant même le DPB. D'où -threads 4 :
		// c'est la carte qui décode, les threads ne servent qu'au repli
		// logiciel d'un codec qu'elle ne connaît pas. Au pire, un DPB HEVC de
		// 17 : 17+5+4+4 = 30. Avec ces réglages, la même carte a décodé la
		// source d'essai.
		//
		// -extra_hw_frames 4 : quand la source est déjà à la taille et au
		// format du barreau, scale_cuda laisse passer les images du décodeur,
		// et NVENC en retient plusieurs le temps de les encoder (quatre au
		// moins, nb_surfaces dans nvenc.c). Marge raisonnée, pas mesurée.
		surface: "cuda",
		surfaceArgs: []string{
			"-init_hw_device", "cuda=gpu", "-filter_hw_device", "gpu",
			"-threads", "4", "-extra_hw_frames", "4",
		},
		rateControl: func(preset qualityPreset) []string {
			return []string{
				"-rc", "vbr",
				"-b:v", preset.VideoBitrate,
				"-maxrate", preset.VideoBitrate,
				"-bufsize", doubleBitrate(preset.VideoBitrate),
				// p4 is NVENC's middle preset: the quality-per-bit of the slower
				// ones costs wall-clock this path does not have to spare.
				"-preset", "p4",
				"-no-scenecut", "1",
				// Sans lui, NVENC rend une image I ordinaire là où
				// -force_key_frames demande une image clé : le segment qui
				// commence dessus ne se décode pas seul, et une recherche qui
				// y tombe montre des macroblocs jusqu'à la prochaine IDR.
				// Repris tel quel par hevc_nvenc (hevcSiblings).
				"-forced-idr", "1",
			}
		},
	},
	{
		Name:     "h264_qsv",
		Hardware: true,
		// Quick Sync works in NV12; handing it yuv420p makes FFmpeg insert a
		// conversion on every frame.
		PixelFormat: "nv12",
		rateControl: func(preset qualityPreset) []string {
			return []string{
				"-b:v", preset.VideoBitrate,
				"-maxrate", preset.VideoBitrate,
				"-bufsize", doubleBitrate(preset.VideoBitrate),
				"-preset", "veryfast",
			}
		},
	},
	{
		Name:         "h264_vaapi",
		Hardware:     true,
		deviceArgs:   []string{"-vaapi_device", vaapiDevice()},
		uploadFilter: "format=nv12,hwupload",
		surface:      "vaapi",
		rateControl: func(preset qualityPreset) []string {
			return []string{
				// Nommé : laissé à lui-même, FFmpeg lit un débit égal à son
				// plafond comme une demande de débit constant.
				"-rc_mode", "VBR",
				"-b:v", preset.VideoBitrate,
				"-maxrate", preset.VideoBitrate,
				"-bufsize", doubleBitrate(preset.VideoBitrate),
			}
		},
	},
}

// vaapiDevice est le nœud de rendu donné à VAAPI. VAAPI_DEVICE le change, pour
// un hôte à plusieurs cartes où le circuit voulu n'est pas le premier.
func vaapiDevice() string {
	if device := strings.TrimSpace(os.Getenv("VAAPI_DEVICE")); device != "" {
		return device
	}
	return "/dev/dri/renderD128"
}

// videoEncoderOnce caches the answer: detection runs FFmpeg, and the answer
// cannot change while the process lives.
var (
	videoEncoderOnce sync.Once
	resolvedEncoder  VideoEncoder
)

// SelectedVideoEncoder is the encoder every session uses.
func SelectedVideoEncoder() VideoEncoder {
	videoEncoderOnce.Do(func() {
		resolvedEncoder = detectVideoEncoder(encoderWorks)
		log.Printf("Streaming: video encoder %s (hardware=%v)", resolvedEncoder.Name, resolvedEncoder.Hardware)
	})
	return resolvedEncoder
}

// detectVideoEncoder resolves VIDEO_ENCODER. It takes the probe as an argument
// so the decision can be tested without an FFmpeg on the machine running the
// tests.
//
// Unset means libx264, exactly as before: a server that is transcoding happily
// today must not change encoder because it was upgraded.
func detectVideoEncoder(works func(name string) bool) VideoEncoder {
	requested := strings.TrimSpace(os.Getenv("VIDEO_ENCODER"))
	switch requested {
	case "", softwareEncoder.Name:
		return softwareEncoder
	case "auto":
		for _, candidate := range hardwareEncoders {
			if works(candidate.Name) {
				return candidate
			}
		}
		log.Println("Streaming: VIDEO_ENCODER=auto found no working hardware encoder, using libx264")
		return softwareEncoder
	}

	for _, candidate := range hardwareEncoders {
		if candidate.Name != requested {
			continue
		}
		if works(candidate.Name) {
			return candidate
		}
		// Naming an encoder that does not run is worth a loud line: the operator
		// asked for it, and silently encoding on the CPU would look like the
		// hardware was simply slow.
		log.Printf("Streaming: VIDEO_ENCODER=%s is not usable on this host, using libx264", requested)
		return softwareEncoder
	}

	log.Printf("Streaming: VIDEO_ENCODER=%q is not an encoder this server drives, using libx264", requested)
	return softwareEncoder
}

// encoderWorks encodes a single frame and throws it away.
//
// Asking `ffmpeg -encoders` only says what was compiled in, which is not the
// question: an FFmpeg built with NVENC on a machine with no NVIDIA card lists
// h264_nvenc and fails the moment a session starts. One frame costs
// milliseconds and answers the question that matters.
func encoderWorks(name string) bool {
	encoder := VideoEncoder{Name: name}
	for _, candidate := range hardwareEncoders {
		if candidate.Name == name {
			encoder = candidate
		}
	}
	return encoderRuns(encoder)
}

// encoderRuns est encoderWorks pour un encodeur déjà décrit, avec son format
// d'image et son envoi : un HEVC est essayé en 10 bits, la profondeur que ses
// sessions lui demanderont.
func encoderRuns(encoder VideoEncoder) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "ffmpeg", encoderProbeArgs(encoder)...)
	if output, err := cmd.CombinedOutput(); err != nil {
		log.Printf("Streaming: encoder %s unusable: %v %s", encoder.Name, err, strings.TrimSpace(string(output)))
		return false
	}
	return true
}

// encoderProbeArgs est la commande d'essai d'un encodeur : une image, par le
// même périphérique et le même envoi qu'une session.
func encoderProbeArgs(encoder VideoEncoder) []string {
	args := []string{"-hide_banner", "-loglevel", "error"}
	args = append(args, encoder.deviceArgs...)
	args = append(args,
		"-f", "lavfi", "-i", "testsrc2=size=320x240:rate=1",
		"-frames:v", "1",
	)
	if encoder.uploadFilter != "" {
		args = append(args, "-vf", encoder.uploadFilter)
	}
	args = append(args, "-c:v", encoder.Name)
	if encoder.isHEVC() {
		if encoder.PixelFormat != "" {
			args = append(args, "-pix_fmt", encoder.PixelFormat)
		}
		args = append(args, "-profile:v", "main10")
	}
	return append(args, "-f", "null", "-")
}

// encoder resolves what the options asked for, defaulting to software. Une
// image qui garde son HDR prend l'encodeur HEVC (encoder_hevc.go).
func (o TranscodeOptions) encoder() VideoEncoder {
	if o.Video.HEVC {
		return o.hevcEncoder()
	}
	if o.Encoder.Name == "" || o.Encoder.rateControl == nil {
		return softwareEncoder
	}
	// Une commande FFmpeg n'a qu'un périphérique de filtres. libplacebo y veut
	// Vulkan (ADR-0060), `hwupload` y veut celui de l'encodeur : un Dolby Vision
	// profil 5 à tone mapper garde donc l'encodeur logiciel.
	if o.Encoder.uploadFilter != "" && sessionToneMapper(o).Vulkan {
		return softwareEncoder
	}
	return o.Encoder
}
