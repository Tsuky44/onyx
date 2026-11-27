package streaming

import (
	"strings"
	"testing"
)

// La chaîne matérielle sur une carte NVIDIA : NVDEC décode, scale_cuda met à
// l'échelle, NVENC prend l'image CUDA. Voir l'ADR « une image -nvidia pour les
// cartes NVIDIA ». Aucun de ces tests ne voit une vraie carte : ils épinglent
// la commande, l'essai du démarrage la valide sur la machine.

func encoderNamed(t *testing.T, name string) VideoEncoder {
	t.Helper()
	for _, encoder := range hardwareEncoders {
		if encoder.Name == name {
			return encoder
		}
	}
	t.Fatalf("%s is not among the hardware encoders", name)
	return VideoEncoder{}
}

// cudaOptions est une session 4K vers 1080p sur une carte NVIDIA.
func cudaOptions(t *testing.T, video *VideoStreamInfo, plan VideoPlan) TranscodeOptions {
	t.Helper()
	opt := hardwareOptions(t, video, plan)
	opt.Encoder = encoderNamed(t, "h264_nvenc")
	return opt
}

const cudaHead = "format=nv12|p010le|cuda,hwupload"

// Une source SDR ne quitte pas la carte. Le périphérique CUDA est ouvert et
// nommé périphérique des filtres : sans lui, la tête de la chaîne ne pourrait
// pas envoyer une image que NVDEC n'a pas su décoder.
func TestCUDAKeepsAnSDRPictureOnTheCard(t *testing.T) {
	args := BuildFFmpegArgs(cudaOptions(t, uhdHEVC(), VideoPlan{}))

	for _, want := range [][2]string{
		{"-init_hw_device", "cuda=gpu"},
		{"-filter_hw_device", "gpu"},
		{"-hwaccel", "cuda"},
		{"-hwaccel_output_format", "cuda"},
		{"-c:v", "h264_nvenc"},
	} {
		if !hasFlag(args, want[0], want[1]) {
			t.Errorf("missing %s %s in %v", want[0], want[1], args)
		}
	}
	if hasFlag(args, "-hwaccel", "auto") {
		t.Error("`-hwaccel auto` brings every decoded frame back to memory")
	}
	want := cudaHead +
		",scale_cuda=w=1920:h=1080:force_original_aspect_ratio=decrease:force_divisible_by=2:format=nv12"
	if chain, _ := argValue(args, "-vf"); chain != want {
		t.Errorf("filter chain is\n %q, want\n %q", chain, want)
	}
}

// NVENC prend d'ordinaire des images logicielles en yuv420p. Sur la chaîne
// matérielle l'image est déjà sur la carte : un -pix_fmt logiciel ferait
// insérer une conversion depuis une image CUDA, que FFmpeg refuse.
func TestCUDAFramesReachNVENCWithoutASoftwarePixelFormat(t *testing.T) {
	if args := BuildFFmpegArgs(cudaOptions(t, uhdHEVC(), VideoPlan{})); hasAnyFlag(args, "-pix_fmt") {
		t.Errorf("a software pixel format was asked of device frames: %v", args)
	}

	software := cudaOptions(t, uhdHEVC(), VideoPlan{})
	software.HardwareFilters = false
	args := BuildFFmpegArgs(software)
	if !hasFlag(args, "-pix_fmt", "yuv420p") || !hasFlag(args, "-hwaccel", "auto") {
		t.Errorf("the software-filter NVENC command changed: %v", args)
	}
	if hasAnyFlag(args, "-init_hw_device") || hasAnyFlag(args, "-filter_hw_device") {
		t.Errorf("a CUDA device was opened for a session that filters in software: %v", args)
	}
}

// Une source HDR redescend à la taille du barreau pour le tone mapping, puis
// remonte : NVENC n'a pas de filtre d'envoi à lui, la chaîne lui en donne un
// pour que sa sortie soit toujours une image de la carte.
func TestCUDAUploadsAgainAfterTheToneMapping(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap")
	args := BuildFFmpegArgs(cudaOptions(t, uhdHEVC(), VideoPlan{Tonemap: true}))

	chain, _ := argValue(args, "-vf")
	want := strings.Join([]string{
		cudaHead,
		"scale_cuda=w=1920:h=1080:force_original_aspect_ratio=decrease:force_divisible_by=2:format=p010le",
		"hwdownload",
		"format=p010le",
		hdrToSDRFilter(),
		"format=nv12,hwupload",
	}, ",")
	if chain != want {
		t.Errorf("filter chain is\n %q, want\n %q", chain, want)
	}
	if hasAnyFlag(args, "-pix_fmt") {
		t.Errorf("a software pixel format was asked of device frames: %v", args)
	}
}

// Quand la source est déjà au format du barreau, scale_cuda laisse passer les
// images du décodeur et NVENC en retient plusieurs : sans marge, NVDEC
// s'arrête sur « No decoder surfaces left ».
func TestCUDADecoderKeepsSpareSurfacesForTheEncoder(t *testing.T) {
	args := BuildFFmpegArgs(cudaOptions(t, uhdHEVC(), VideoPlan{}))
	if !hasFlag(args, "-extra_hw_frames", "8") {
		t.Errorf("no spare decoder surfaces: %v", args)
	}
	input, extra := -1, -1
	for i, arg := range args {
		switch arg {
		case "-i":
			input = i
		case "-extra_hw_frames":
			extra = i
		}
	}
	if extra > input {
		t.Error("-extra_hw_frames is a decoder option: it must come before the input")
	}
}

// Le Dolby Vision profil 5 passe par libplacebo, qui veut Vulkan comme
// périphérique des filtres (ADR-0060). NVENC l'encode quand même, puisqu'il
// prend des images logicielles ; mais aucun périphérique CUDA ne doit être
// nommé périphérique des filtres dans cette commande.
func TestCUDALeavesTheFilterDeviceToLibplacebo(t *testing.T) {
	setLibplaceboForTest(true)
	t.Cleanup(func() { setLibplaceboForTest(false) })
	setFilterSetForTest("libplacebo", "zscale", "tonemap")
	t.Cleanup(func() { setFilterSetForTest("zscale", "tonemap") })
	video := uhdHEVC()
	video.DoviProfile = 5
	args := BuildFFmpegArgs(cudaOptions(t, video, VideoPlan{Tonemap: true}))

	if !hasFlag(args, "-c:v", "h264_nvenc") {
		t.Errorf("NVENC takes software frames and can follow libplacebo: %v", args)
	}
	if hasAnyFlag(args, "-filter_hw_device") || hasAnyFlag(args, "-hwaccel") {
		t.Errorf("the filter device must stay libplacebo's: %v", args)
	}
	if !hasFlag(args, "-pix_fmt", "yuv420p") {
		t.Errorf("software frames need their pixel format: %v", args)
	}
}

// L'essai du démarrage passe par la même commande qu'une session : le
// périphérique, le décodage nommé, la chaîne, l'encodeur.
func TestCUDAProbeRunsTheSessionChain(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap")
	t.Setenv("HARDWARE_FILTERS", "")
	recorder := &probeRecorder{}
	if !detectHardwareFilters(encoderNamed(t, "h264_nvenc"), "sample.mkv", allFilters, recorder.run) {
		t.Fatal("the probe refused a card on which every command passes")
	}
	chains := 0
	for _, call := range recorder.calls {
		if !isChainProbe(call) {
			continue
		}
		chains++
		if !hasFlag(call, "-filter_hw_device", "gpu") || !hasFlag(call, "-hwaccel", "cuda") {
			t.Errorf("the probe does not open the device a session opens: %v", call)
		}
		if chain, _ := argValue(call, "-vf"); !strings.HasPrefix(chain, cudaHead+",scale_cuda=") {
			t.Errorf("the probe does not run the session chain: %q", chain)
		}
	}
	if chains != 2 {
		t.Errorf("%d chain probes, want the SDR and the HDR variants", chains)
	}
}
