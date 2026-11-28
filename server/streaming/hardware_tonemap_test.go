package streaming

import (
	"context"
	"os/exec"
	"strings"
	"testing"
)

// Le tone mapping sur la carte (hardware_tonemap.go). Comme ceux de la
// chaîne CUDA, ces tests épinglent la commande ; c'est l'essai du démarrage
// qui la valide sur la machine.

// cudaHDROptions est une session 4K HDR vers 1080p dont le tone mapping peut
// se faire sur la carte.
func cudaHDROptions(t *testing.T, video *VideoStreamInfo) TranscodeOptions {
	t.Helper()
	opt := cudaOptions(t, video, VideoPlan{Tonemap: true})
	opt.HardwareToneMap = true
	return opt
}

// Une source HDR ne passe plus par zscale : la carte décode, met à l'échelle,
// puis libplacebo fait le tone mapping sur elle. C'est zscale qui tenait la
// session à 1,1× quand la carte seule tient 7×.
func TestCUDAToneMapsHDROnTheCard(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap", "libplacebo")
	t.Cleanup(func() { setFilterSetForTest("zscale", "tonemap") })
	args := BuildFFmpegArgs(cudaHDROptions(t, uhdHEVC()))

	chain, _ := argValue(args, "-vf")
	want := strings.Join([]string{
		cudaHead,
		"scale_cuda=w=1920:h=1080:force_original_aspect_ratio=decrease:force_divisible_by=2:format=p010le",
		"hwdownload",
		"format=p010le",
		cudaToneMapFilter,
		"format=nv12,hwupload",
	}, ",")
	if chain != want {
		t.Errorf("filter chain is\n %q, want\n %q", chain, want)
	}
	if strings.Contains(chain, "zscale") {
		t.Error("the CPU tone mapping is still in the chain")
	}
	if !hasFlag(args, "-hwaccel", "cuda") || !hasFlag(args, "-c:v", "h264_nvenc") || hasAnyFlag(args, "-pix_fmt") {
		t.Errorf("the session left the hardware chain: %v", args)
	}
	if !hasFlag(args, "-colorspace", "bt709") {
		t.Error("a tone-mapped picture must still be tagged BT.709")
	}
}

// Le réglage est celui que l'image de référence a fait retenir : la courbe
// la plus proche de la chaîne zscale, et sa saturation ramenée au même
// niveau. Sortie en NV12, que l'envoi vers la carte prend sans conversion.
func TestCUDAToneMapKeepsTheMeasuredSettings(t *testing.T) {
	for _, want := range []string{
		"libplacebo=", "tonemapping=st2094-40", "saturation=0.85",
		"colorspace=bt709", "color_primaries=bt709", "color_trc=bt709", "range=tv",
		"format=nv12",
	} {
		if !strings.Contains(cudaToneMapFilter, want) {
			t.Errorf("the device tone mapping lost %q: %s", want, cudaToneMapFilter)
		}
	}
}

// Tant que l'essai du démarrage ne l'a pas vu marcher, le tone mapping reste
// celui du processeur, sur la chaîne matérielle.
func TestCUDAToneMapWaitsForItsProbe(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap", "libplacebo")
	t.Cleanup(func() { setFilterSetForTest("zscale", "tonemap") })
	opt := cudaHDROptions(t, uhdHEVC())
	opt.HardwareToneMap = false
	if opt.usesHardwareToneMap() {
		t.Fatal("tone mapping on the device without its probe")
	}
	chain, _ := argValue(BuildFFmpegArgs(opt), "-vf")
	if !strings.Contains(chain, hdrToSDRFilter()) || strings.Contains(chain, "libplacebo") {
		t.Errorf("the CPU tone mapping must stay: %q", chain)
	}
	if !strings.Contains(chain, "scale_cuda") {
		t.Errorf("the hardware chain itself must stay: %q", chain)
	}
}

// Une source HDR déjà à la taille du barreau ne gagnait rien à la chaîne
// matérielle tant que son tone mapping redescendait sur le processeur. Avec
// le tone mapping sur la carte elle la prend, sans mise à l'échelle.
func TestCUDAToneMapTakesHDRThatAlreadyFitsTheRung(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap", "libplacebo")
	t.Cleanup(func() { setFilterSetForTest("zscale", "tonemap") })
	hd := &VideoStreamInfo{Width: 1920, Height: 1080, Codec: "hevc", FrameRate: 24}

	opt := cudaHDROptions(t, hd)
	chain, _ := argValue(BuildFFmpegArgs(opt), "-vf")
	want := strings.Join([]string{
		cudaHead, "scale_cuda=format=p010le", "hwdownload", "format=p010le",
		cudaToneMapFilter, "format=nv12,hwupload",
	}, ",")
	if chain != want {
		t.Errorf("filter chain is\n %q, want\n %q", chain, want)
	}

	opt.HardwareToneMap = false
	if opt.usesHardwareFilters() {
		t.Error("without tone mapping on the device, this source has nothing to gain from the hardware chain")
	}
}

// libplacebo n'a pas besoin de zscale : un FFmpeg sans libzimg garde quand
// même le tone mapping sur la carte.
func TestCUDAToneMapDoesNotNeedZscale(t *testing.T) {
	setFilterSetForTest("libplacebo")
	t.Cleanup(func() { setFilterSetForTest("zscale", "tonemap") })
	opt := cudaHDROptions(t, uhdHEVC())
	if !opt.usesHardwareToneMap() {
		t.Fatal("the device tone mapping was dropped for want of zscale")
	}
	if chain, _ := argValue(BuildFFmpegArgs(opt), "-vf"); !strings.Contains(chain, cudaToneMapFilter) {
		t.Errorf("filter chain is %q", chain)
	}
}

// Ce qui ne le concerne pas ne change pas : une source SDR, un encodeur sans
// tone mapping matériel (VAAPI), et le Dolby Vision profil 5, qui garde son
// libplacebo à lui pour appliquer la couche RPU avant toute mise à l'échelle.
func TestCUDAToneMapLeavesTheRestAlone(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap", "libplacebo")
	t.Cleanup(func() { setFilterSetForTest("zscale", "tonemap") })

	sdr := cudaOptions(t, uhdHEVC(), VideoPlan{})
	sdr.HardwareToneMap = true
	if sdr.usesHardwareToneMap() {
		t.Error("an SDR source has no tone mapping to move")
	}
	if chain, _ := argValue(BuildFFmpegArgs(sdr), "-vf"); strings.Contains(chain, "libplacebo") {
		t.Errorf("an SDR source went through libplacebo: %q", chain)
	}

	vaapi := hardwareOptions(t, uhdHEVC(), VideoPlan{Tonemap: true})
	vaapi.HardwareToneMap = true
	if vaapi.usesHardwareToneMap() {
		t.Error("VAAPI has no device tone mapping")
	}
	if chain, _ := argValue(BuildFFmpegArgs(vaapi), "-vf"); !strings.Contains(chain, hdrToSDRFilter()) {
		t.Errorf("the VAAPI chain lost its CPU tone mapping: %q", chain)
	}

	setLibplaceboForTest(true)
	t.Cleanup(func() { setLibplaceboForTest(false) })
	dovi := uhdHEVC()
	dovi.DoviProfile = 5
	p5 := cudaHDROptions(t, dovi)
	if p5.usesHardwareToneMap() || p5.usesHardwareFilters() {
		t.Error("Dolby Vision profile 5 must keep its own libplacebo")
	}
	chain, _ := argValue(BuildFFmpegArgs(p5), "-vf")
	if !strings.Contains(chain, doviToSDRFilter) || strings.Contains(chain, "st2094-40") ||
		strings.Contains(chain, "scale_cuda") {
		t.Errorf("the Dolby Vision chain changed: %q", chain)
	}
}

// --- L'essai du démarrage

// L'essai passe par la commande d'une session : le périphérique, le décodage
// nommé, la chaîne avec libplacebo, l'encodeur.
func TestHardwareToneMapProbeRunsTheSessionChain(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap", "libplacebo")
	t.Cleanup(func() { setFilterSetForTest("zscale", "tonemap") })
	t.Setenv("HARDWARE_TONEMAP", "on")
	recorder := &probeRecorder{}
	nvenc := encoderNamed(t, "h264_nvenc")
	if !detectHardwareToneMap(nvenc, "sample.mkv", allFilters, recorder.run) {
		t.Fatal("the probe refused a card on which the command passes")
	}
	if len(recorder.calls) != 1 {
		t.Fatalf("want one probe, got %d: %v", len(recorder.calls), recorder.calls)
	}
	call := recorder.calls[0]
	if !hasFlag(call, "-filter_hw_device", "gpu") || !hasFlag(call, "-hwaccel", "cuda") ||
		!hasFlag(call, "-c:v", "h264_nvenc") {
		t.Errorf("the probe does not look like a session: %v", call)
	}
	opt := hardwareProbeOptions(nvenc, true)
	opt.HardwareToneMap = true
	chain, _ := argValue(call, "-vf")
	if want := hardwareFilterChain(opt, presetFor(opt.Quality)); chain != want {
		t.Errorf("the probe ran %q, a session runs %q", chain, want)
	}
	if !strings.Contains(chain, cudaToneMapFilter) {
		t.Errorf("the probe did not go through the device tone mapping: %q", chain)
	}
}

// Un échec ne retire que ce tone mapping : la fonction dit non, et rien
// d'autre n'est touché.
func TestHardwareToneMapProbeFailureKeepsTheCPU(t *testing.T) {
	t.Setenv("HARDWARE_TONEMAP", "on")
	recorder := &probeRecorder{fail: func([]string) bool { return true }}
	if detectHardwareToneMap(encoderNamed(t, "h264_nvenc"), "sample.mkv", allFilters, recorder.run) {
		t.Error("a failing probe still turned the device tone mapping on")
	}
}

func TestHardwareToneMapNeedsLibplaceboAndADevice(t *testing.T) {
	t.Setenv("HARDWARE_TONEMAP", "on")
	recorder := &probeRecorder{}
	noLibplacebo := func(name string) bool { return name != "libplacebo" }
	if detectHardwareToneMap(encoderNamed(t, "h264_nvenc"), "sample.mkv", noLibplacebo, recorder.run) {
		t.Error("device tone mapping on without libplacebo")
	}
	if detectHardwareToneMap(vaapiEncoder(t), "sample.mkv", allFilters, recorder.run) {
		t.Error("device tone mapping on for an encoder that has none")
	}
	if len(recorder.calls) != 0 {
		t.Errorf("FFmpeg was run for a chain it cannot build: %v", recorder.calls)
	}
}

// Le tone mapping sur le matériel ne s'active que sur demande : au banc il
// tenait 3× et plus, dans les premières vraies sessions 0,7×. Sans la demande,
// aucun essai n'est lancé et les sessions gardent zscale.
func TestHardwareToneMapIsOptIn(t *testing.T) {
	for _, value := range []string{"", "off", "0", "auto"} {
		t.Setenv("HARDWARE_TONEMAP", value)
		recorder := &probeRecorder{}
		if detectHardwareToneMap(encoderNamed(t, "h264_nvenc"), "sample.mkv", allFilters, recorder.run) {
			t.Errorf("HARDWARE_TONEMAP=%q turned the device tone mapping on", value)
		}
		if len(recorder.calls) != 0 {
			t.Errorf("HARDWARE_TONEMAP=%q still ran a probe", value)
		}
	}
	for _, value := range []string{"on", "1", "true", "ON"} {
		t.Setenv("HARDWARE_TONEMAP", value)
		if !detectHardwareToneMap(encoderNamed(t, "h264_nvenc"), "sample.mkv", allFilters, (&probeRecorder{}).run) {
			t.Errorf("HARDWARE_TONEMAP=%s ignored", value)
		}
	}
}

// --- Le retrait en cours de route

// Une session morte avec le tone mapping sur la carte ne retire que lui : la
// chaîne matérielle, vue marcher sans lui, reste pour la tentative suivante.
func TestSessionDyingWithDeviceToneMapKeepsTheHardwareChain(t *testing.T) {
	resetHardwareFiltersOff(t)
	hardwareToneMapOff.Store(false)
	t.Cleanup(func() { hardwareToneMapOff.Store(false) })

	session := &TranscodeSession{ID: "s", TmpDir: t.TempDir(), hardwareFilters: true, hardwareToneMap: true}
	session.ctx, session.cancel = context.WithCancel(context.Background())
	session.cmd = exec.Command("false")
	if err := session.cmd.Start(); err != nil {
		t.Skipf("cannot start a failing process here: %v", err)
	}
	session.watch()
	if !hardwareToneMapOff.Load() {
		t.Error("the device tone mapping survived a session it killed")
	}
	if hardwareFiltersOff.Load() {
		t.Error("the hardware chain was dropped for a failure of the tone mapping")
	}
}
