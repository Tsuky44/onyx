package streaming

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// hardwareOptions est une session 4K vers 1080p sur le circuit VAAPI.
func hardwareOptions(t *testing.T, video *VideoStreamInfo, plan VideoPlan) TranscodeOptions {
	t.Helper()
	return TranscodeOptions{
		InputPath: "in.mkv", Quality: "1080p", TmpDir: "/tmp/s",
		Probe:           &ProbeResult{Video: video},
		SegmentDuration: 4, AudioTypedIndexes: []int{0},
		Encoder:         vaapiEncoder(t),
		HardwareFilters: true,
		Video:           plan,
	}
}

func uhdHEVC() *VideoStreamInfo {
	return &VideoStreamInfo{Width: 3840, Height: 2160, Codec: "hevc", FrameRate: 24}
}

const hardwareHead = "format=nv12|p010le|vaapi,hwupload"

// Une source SDR ne quitte jamais le périphérique : décodée dessus, mise à
// l'échelle dessus, encodée dessus. Aucun filtre logiciel, aucun envoi final.
func TestHardwareFiltersKeepAnSDRPictureOnTheDevice(t *testing.T) {
	args := BuildFFmpegArgs(hardwareOptions(t, uhdHEVC(), VideoPlan{}))

	if !hasFlag(args, "-hwaccel", "vaapi") || !hasFlag(args, "-hwaccel_output_format", "vaapi") {
		t.Errorf("decoding must be named and keep its frames on the device: %v", args)
	}
	if hasFlag(args, "-hwaccel", "auto") {
		t.Error("`-hwaccel auto` brings every decoded frame back to memory")
	}
	want := hardwareHead +
		",scale_vaapi=w=1920:h=1080:force_original_aspect_ratio=decrease:force_divisible_by=2:format=nv12"
	if chain, _ := argValue(args, "-vf"); chain != want {
		t.Errorf("filter chain is\n %q, want\n %q", chain, want)
	}
	if !hasFlag(args, "-c:v", "h264_vaapi") || hasAnyFlag(args, "-pix_fmt") {
		t.Errorf("the encoder must take the device frames as they are: %v", args)
	}
}

// Une source HDR redescend une seule fois, à la taille du barreau, pour le
// tone mapping : c'est le 4K ramené en mémoire qui tenait le serveur à 0,7×.
func TestHardwareFiltersScaleBeforeTheToneMappingComesDown(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap")
	args := BuildFFmpegArgs(hardwareOptions(t, uhdHEVC(), VideoPlan{Tonemap: true}))

	chain, _ := argValue(args, "-vf")
	want := strings.Join([]string{
		hardwareHead,
		"scale_vaapi=w=1920:h=1080:force_original_aspect_ratio=decrease:force_divisible_by=2:format=p010le",
		"hwdownload",
		"format=p010le",
		hdrToSDRFilter(),
		"format=nv12,hwupload",
	}, ",")
	if chain != want {
		t.Errorf("filter chain is\n %q, want\n %q", chain, want)
	}
	if scale, down := strings.Index(chain, "scale_vaapi"), strings.Index(chain, "hwdownload"); scale > down {
		t.Error("the picture comes down before it is scaled")
	}
	if !hasFlag(args, "-colorspace", "bt709") {
		t.Error("a tone-mapped picture must still be tagged BT.709")
	}
}

// Une source déjà à la taille du barreau garde le passage par le circuit pour
// son format : un H.264 ne prend pas une image SDR en 10 bits telle quelle.
func TestHardwareFiltersConvertWithoutScaling(t *testing.T) {
	video := &VideoStreamInfo{Width: 1920, Height: 1080, Codec: "hevc", FrameRate: 24}
	args := BuildFFmpegArgs(hardwareOptions(t, video, VideoPlan{}))
	if chain, _ := argValue(args, "-vf"); chain != hardwareHead+",scale_vaapi=format=nv12" {
		t.Errorf("filter chain is %q", chain)
	}
}

// Tout ce qui a besoin d'images logicielles, ou que personne n'a vu tourner
// sur un circuit, garde la chaîne de toujours.
func TestHardwareFiltersStepAside(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap")
	hd := &VideoStreamInfo{Width: 1920, Height: 1080, Codec: "hevc", FrameRate: 24}
	cases := []struct {
		name   string
		change func(o *TranscodeOptions)
	}{
		{"essai du démarrage non passé", func(o *TranscodeOptions) { o.HardwareFilters = false }},
		{"encodeur logiciel", func(o *TranscodeOptions) { o.Encoder = softwareEncoder }},
		{"encodeur matériel sans surface", func(o *TranscodeOptions) { o.Encoder = encoderNamed(t, "h264_qsv") }},
		{"sous-titre incrusté", func(o *TranscodeOptions) { o.BurnSubtitle = true }},
		{"désentrelacement", func(o *TranscodeOptions) { o.Video.Deinterlace = true }},
		{"image recopiée", func(o *TranscodeOptions) { o.Video.Copy = true }},
		{"HDR gardé en HEVC", func(o *TranscodeOptions) { o.Video.HEVC = true }},
		{"HDR qui tient dans le barreau", func(o *TranscodeOptions) {
			o.Probe = &ProbeResult{Video: hd}
			o.Video.Tonemap = true
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			opt := hardwareOptions(t, uhdHEVC(), VideoPlan{})
			tc.change(&opt)
			if opt.usesHardwareFilters() {
				t.Fatal("this session must keep its software filters")
			}
			args := BuildFFmpegArgs(opt)
			if hasAnyFlag(args, "-hwaccel_output_format") {
				t.Errorf("frames left on the device with nothing to take them: %v", args)
			}
			for _, flag := range []string{"-vf", "-filter_complex"} {
				if chain, _ := argValue(args, flag); strings.Contains(chain, "scale_vaapi") {
					t.Errorf("%s still scales on the device: %q", flag, chain)
				}
			}
		})
	}
}

// Sans zscale, une source HDR n'a pas de tone mapping du tout : elle garde la
// chaîne logicielle plutôt que de passer en NV12 sans être tone mappée.
func TestHardwareFiltersNeedAToneMapperForHDR(t *testing.T) {
	setFilterSetForTest()
	t.Cleanup(func() { setFilterSetForTest("zscale", "tonemap") })
	if hardwareOptions(t, uhdHEVC(), VideoPlan{Tonemap: true}).usesHardwareFilters() {
		t.Error("an HDR source went to the device without a tone mapper")
	}
}

// Le Dolby Vision profil 5 garde libplacebo et libx264, comme avant.
func TestHardwareFiltersLeaveDolbyVisionProfile5Alone(t *testing.T) {
	setLibplaceboForTest(true)
	t.Cleanup(func() { setLibplaceboForTest(false) })
	setFilterSetForTest("libplacebo", "zscale", "tonemap")
	video := uhdHEVC()
	video.DoviProfile = 5
	args := BuildFFmpegArgs(hardwareOptions(t, video, VideoPlan{Tonemap: true}))
	if !hasFlag(args, "-c:v", "libx264") || hasAnyFlag(args, "-hwaccel") {
		t.Errorf("a libplacebo session was sent to the device: %v", args)
	}
}

// --- L'essai du démarrage

// probeRecorder joue FFmpeg : il note les commandes et échoue où on lui dit.
type probeRecorder struct {
	calls [][]string
	fail  func(args []string) bool
}

func (p *probeRecorder) run(args []string) error {
	p.calls = append(p.calls, args)
	if p.fail != nil && p.fail(args) {
		return errors.New("exit status 1")
	}
	return nil
}

func allFilters(string) bool { return true }

func isChainProbe(args []string) bool {
	return hasAnyFlag(args, "-c:v") && hasAnyFlag(args, "-hwaccel")
}

func isDecodeProbe(args []string) bool {
	return hasAnyFlag(args, "-hwaccel") && !hasAnyFlag(args, "-c:v")
}

// L'essai passe par le périphérique, le décodage, la chaîne et l'encodeur
// d'une session, dans ses deux variantes : c'est ce qui le rend crédible.
func TestHardwareFiltersProbeRunsTheSessionChains(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap")
	recorder := &probeRecorder{}
	if !detectHardwareFilters(vaapiEncoder(t), "sample.mkv", allFilters, recorder.run) {
		t.Fatal("a host where every probe passes must get hardware filters")
	}
	var chains []string
	for _, call := range recorder.calls {
		if !isChainProbe(call) {
			continue
		}
		if !hasAnyFlag(call, "-vaapi_device") || !hasFlag(call, "-hwaccel_output_format", "vaapi") ||
			!hasFlag(call, "-c:v", "h264_vaapi") {
			t.Errorf("chain probe does not look like a session: %v", call)
		}
		chain, _ := argValue(call, "-vf")
		chains = append(chains, chain)
	}
	if len(chains) != 2 {
		t.Fatalf("want the SDR and the HDR chain probed, got %d: %v", len(chains), chains)
	}
	for tonemap, chain := range map[bool]string{false: chains[0], true: chains[1]} {
		opt := hardwareProbeOptions(vaapiEncoder(t), tonemap)
		if want := hardwareFilterChain(opt, presetFor(opt.Quality)); chain != want {
			t.Errorf("probe (tonemap=%v) ran %q, a session runs %q", tonemap, chain, want)
		}
		if !strings.Contains(chain, "scale_vaapi=w=") {
			t.Errorf("probe (tonemap=%v) does not scale: %q", tonemap, chain)
		}
	}
}

// Une chaîne qui échoue à l'essai n'atteint aucun spectateur, que ce soit la
// variante SDR ou la variante HDR, reconnaissable à sa redescente.
func TestHardwareFiltersProbeFailureKeepsSoftware(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap")
	for _, hdr := range []bool{false, true} {
		recorder := &probeRecorder{fail: func(args []string) bool {
			chain, _ := argValue(args, "-vf")
			return isChainProbe(args) && strings.Contains(chain, "hwdownload") == hdr
		}}
		if detectHardwareFilters(vaapiEncoder(t), "sample.mkv", allFilters, recorder.run) {
			t.Errorf("a failing chain (hdr=%v) still turned hardware filters on", hdr)
		}
	}
}

// Un circuit qui ne décode pas le HEVC 10 bits garde la chaîne : sa tête
// envoie l'image décodée en logiciel. Le journal le dit, c'est tout.
func TestHardwareFiltersSurviveAFailedDecodeProbe(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap")
	recorder := &probeRecorder{fail: isDecodeProbe}
	if !detectHardwareFilters(vaapiEncoder(t), "sample.mkv", allFilters, recorder.run) {
		t.Error("the decode probe is a diagnosis, not a verdict")
	}
}

func TestHardwareFiltersNeedTheirFilters(t *testing.T) {
	recorder := &probeRecorder{}
	missing := func(name string) bool { return name != "scale_vaapi" }
	if detectHardwareFilters(vaapiEncoder(t), "sample.mkv", missing, recorder.run) {
		t.Error("hardware filters on without scale_vaapi")
	}
	if len(recorder.calls) != 0 {
		t.Errorf("FFmpeg was run for a chain it cannot build: %v", recorder.calls)
	}
}

// Sans source d'essai (un FFmpeg sans libx265), rien n'a été prouvé.
func TestHardwareFiltersNeedTheirSample(t *testing.T) {
	recorder := &probeRecorder{fail: func(args []string) bool { return hasFlag(args, "-c:v", "libx265") }}
	if detectHardwareFilters(vaapiEncoder(t), "sample.mkv", allFilters, recorder.run) {
		t.Error("hardware filters on without having been tested")
	}
	if len(recorder.calls) != 1 {
		t.Errorf("probes ran without a sample: %v", recorder.calls)
	}
}

func TestHardwareFiltersCanBeSwitchedOff(t *testing.T) {
	for _, value := range []string{"off", "0", "false", "OFF"} {
		t.Setenv("HARDWARE_FILTERS", value)
		recorder := &probeRecorder{}
		if detectHardwareFilters(vaapiEncoder(t), "sample.mkv", allFilters, recorder.run) {
			t.Errorf("HARDWARE_FILTERS=%s ignored", value)
		}
	}
}

func TestSoftwareEncoderIsNeverProbedForHardwareFilters(t *testing.T) {
	recorder := &probeRecorder{}
	if detectHardwareFilters(softwareEncoder, "sample.mkv", allFilters, recorder.run) || len(recorder.calls) != 0 {
		t.Error("libx264 has no device to keep a picture on")
	}
}

// La source d'essai doit exister pour de bon : FFmpeg l'écrit, et c'est bien
// du HEVC Main 10 marqué HDR10. Sans libx265 sur la machine, rien à vérifier.
func TestHardwareProbeSampleIsHDR10HEVC(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("no ffmpeg on this machine")
	}
	sample := filepath.Join(t.TempDir(), "sample.mkv")
	if err := runFFmpegProbe(hardwareProbeSampleArgs(sample)); err != nil {
		t.Skipf("this ffmpeg cannot write the sample: %v", err)
	}
	out, err := exec.CommandContext(context.Background(), "ffprobe", "-v", "error",
		"-select_streams", "v:0",
		"-show_entries", "stream=codec_name,pix_fmt,color_transfer",
		"-of", "csv=p=0", sample).Output()
	if err != nil {
		t.Fatalf("ffprobe: %v", err)
	}
	if got := strings.TrimSpace(string(out)); got != "hevc,yuv420p10le,smpte2084" {
		t.Errorf("sample is %q, want hevc,yuv420p10le,smpte2084", got)
	}
}

// --- Le retrait en cours de route

func resetHardwareFiltersOff(t *testing.T) {
	t.Helper()
	hardwareFiltersOff.Store(false)
	t.Cleanup(func() { hardwareFiltersOff.Store(false) })
}

// Une session morte avec la chaîne matérielle avant son premier segment la
// retire pour tout le serveur : l'essai n'a vu qu'une source de synthèse.
func TestSessionDyingWithHardwareFiltersTurnsThemOff(t *testing.T) {
	resetHardwareFiltersOff(t)
	session := &TranscodeSession{ID: "s", TmpDir: t.TempDir(), hardwareFilters: true}
	session.ctx, session.cancel = context.WithCancel(context.Background())
	session.cmd = exec.Command("false")
	if err := session.cmd.Start(); err != nil {
		t.Skipf("cannot start a failing process here: %v", err)
	}
	session.watch()
	if !hardwareFiltersOff.Load() {
		t.Error("the hardware chain survived a session it killed")
	}
}

// Ni une session qu'on arrête, ni une session qui a déjà écrit, ni une
// session logicielle ne condamnent la chaîne.
func TestHardwareFiltersStayOnWhenTheSessionIsNotToBlame(t *testing.T) {
	resetHardwareFiltersOff(t)
	failed := errors.New("exit status 1")

	stopped := &TranscodeSession{ID: "stopped", TmpDir: t.TempDir()}
	stopped.ctx, stopped.cancel = context.WithCancel(context.Background())
	stopped.cancel()
	if stopped.diedBeforeFirstSegment(failed) {
		t.Error("a session that was stopped is not a session that died")
	}

	wrote := &TranscodeSession{ID: "wrote", TmpDir: t.TempDir()}
	wrote.ctx, wrote.cancel = context.WithCancel(context.Background())
	if err := os.WriteFile(filepath.Join(wrote.TmpDir, "stream_0_000.ts"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if wrote.diedBeforeFirstSegment(failed) {
		t.Error("a session that wrote a segment had a working chain")
	}

	clean := &TranscodeSession{ID: "clean", TmpDir: t.TempDir()}
	clean.ctx, clean.cancel = context.WithCancel(context.Background())
	if clean.diedBeforeFirstSegment(nil) {
		t.Error("FFmpeg ending without an error did not die")
	}
}
