package streaming

import (
	"reflect"
	"strings"
	"testing"

	"project-player/server/streaming/capacity"
)

// La non-régression de la phase 2 : là où le planificateur n'a rien de mieux à
// proposer, la commande qu'il fait lancer est exactement celle d'avant le
// profil.

// setProfileForTest publie un profil le temps d'un test.
func setProfileForTest(t *testing.T, p *capacity.Profile) {
	t.Helper()
	previous := currentProfile.Load()
	currentProfile.Store(p)
	t.Cleanup(func() { currentProfile.Store(previous) })
}

// testProfile décrit une machine par ses coûts par mégapixel·image.
func testProfile(cores int, costs map[string]capacity.Cost, encoders []capacity.EncoderCandidate, trials ...capacity.TrialResult) *capacity.Profile {
	p := &capacity.Profile{
		Inventory: capacity.Inventory{Cores: cores, FFmpeg: capacity.FFmpegInventory{
			Filters: []string{"libplacebo", "scale", "tonemap", "zscale"},
		}},
		Encoders: encoders,
		Trials:   trials,
	}
	for key, cost := range costs {
		stage, variant, _ := strings.Cut(key, ":")
		p.Costs = append(p.Costs, capacity.StageCost{Stage: capacity.Stage(stage), Variant: variant, Cost: cost})
	}
	return p
}

func softwareCosts(h264, hevc10, scale, zscale, veryfast, libplacebo float64) map[string]capacity.Cost {
	return map[string]capacity.Cost{
		"decode:" + capacity.DecodeH264CPU:   {CPU: h264},
		"decode:" + capacity.DecodeHEVC10CPU: {CPU: hevc10},
		"scale:" + capacity.ScaleSoftware:    {CPU: scale},
		"tonemap:zscale":                     {CPU: zscale},
		"tonemap:libplacebo":                 {CPU: libplacebo},
		"encode:libx264/veryfast":            {CPU: veryfast},
		"encode:libx264/superfast":           {CPU: veryfast * 0.6},
		"encode:libx264/ultrafast":           {CPU: veryfast * 0.34},
		"encode:libx265/ultrafast":           {CPU: veryfast * 2.1},
	}
}

// xeonProfile est la prod : 32 cœurs, pas de circuit, libplacebo sur lavapipe.
func xeonProfile() *capacity.Profile {
	return testProfile(32, softwareCosts(0.0035, 0.0115, 0.0012, 0.0214, 0.0248, 0.18),
		[]capacity.EncoderCandidate{candidateOf(softwareEncoder), candidateOf(softwareHEVCEncoder)},
		capacity.TrialResult{Name: capacity.TrialVulkan, Works: true, Choice: "vulkan:0"})
}

// sameArgs compare la commande d'avant le profil à celle du planificateur.
func sameArgs(t *testing.T, name string, before TranscodeOptions, profile *capacity.Profile) capacity.Pipeline {
	t.Helper()
	want := BuildFFmpegArgs(before)
	setProfileForTest(t, profile)
	planned, _ := planPipeline(before, profile, capacity.Load{})
	got := BuildFFmpegArgs(planned)
	currentProfile.Store(nil)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("%s : la commande a changé\navant : %v\naprès : %v", name, want, got)
	}
	if planned.Pipeline == nil && !before.Video.Copy {
		t.Errorf("%s : le planificateur n'a rien rendu", name)
	}
	if planned.Pipeline != nil {
		return *planned.Pipeline
	}
	return capacity.Pipeline{}
}

func hdr10UHD() *ProbeResult {
	return &ProbeResult{Video: &VideoStreamInfo{
		Width: 3840, Height: 2160, Codec: "hevc", PixFmt: "yuv420p10le",
		BitDepth: 10, ColorTransfer: "smpte2084", ColorPrimaries: "bt2020", FrameRate: 24,
	}}
}

// Les cas de ffmpeg_test.go, plus ceux des chemins qu'il ne couvre pas
// (profil 5, HDR gardé, désentrelacement, 60 i/s), sur le Xeon au repos.
func TestPlanner_XeonWithoutGPUKeepsTodaysCommand(t *testing.T) {
	setCoresForTest(t, 32)
	setFilterSetForTest("zscale", "tonemap", "scale", "libplacebo")
	setLibplaceboForTest(true)
	t.Cleanup(func() { setLibplaceboForTest(false) })
	resetVulkanChoice(t)

	base := func(quality string, probe *ProbeResult) TranscodeOptions {
		return TranscodeOptions{
			InputPath: "/tmp/in.mkv", Quality: quality, TmpDir: "/tmp/out",
			Probe: probe, SegmentDuration: 2,
		}
	}
	var cases []struct {
		name string
		opt  TranscodeOptions
	}
	add := func(name string, opt TranscodeOptions) {
		cases = append(cases, struct {
			name string
			opt  TranscodeOptions
		}{name, opt})
	}
	for _, q := range []string{"360p", "480p", "720p", "1080p", "2160p"} {
		add("4K vers "+q, base(q, probeWith(3840, 2160, 24)))
	}
	shape := base("720p", probeWith(1920, 1080, 24))
	shape.AudioTypedIndexes = []int{0, 1}
	add("forme du flux", shape)
	burn := base("720p", probeWith(1920, 1080, 24))
	burn.AudioTypedIndexes, burn.BurnSubtitle, burn.BurnSubtitleTypedIndex = []int{0}, true, 2
	add("sous-titre incrusté", burn)
	burnNative := base("1080p", probeWith(1920, 1080, 24))
	burnNative.BurnSubtitle = true
	add("sous-titre incrusté sans mise à l'échelle", burnNative)
	seek := base("720p", probeWith(1920, 1080, 24))
	seek.StartSeconds = 600
	add("saut", seek)
	hdr := base("1080p", hdr10UHD())
	hdr.Video = VideoPlan{Tonemap: true}
	add("4K HDR10 tone mappé", hdr)
	dv := base("1080p", doviProfile5Probe())
	dv.Video = VideoPlan{Tonemap: true}
	add("4K profil 5 tone mappé", dv)
	kept := base("2160p", av1HDRProbe("smpte2084"))
	kept.Video = VideoPlan{HEVC: true}
	add("HDR gardé en HEVC", kept)
	interlaced := base("1080p", probeWith(1920, 1080, 25))
	interlaced.Video = VideoPlan{Deinterlace: true}
	add("désentrelacé", interlaced)
	add("1080p60", base("1080p", probeWith(1920, 1080, 60)))
	copied := base("1080p", probeWith(1920, 1080, 24))
	copied.Video = VideoPlan{Copy: true}
	add("recopie", copied)

	for _, c := range cases {
		pipe := sameArgs(t, c.name, c.opt, xeonProfile())
		if !c.opt.Video.Copy && pipe.Verdict != capacity.VerdictOK {
			t.Errorf("%s : verdict %s sur le Xeon (%s)", c.name, pipe.Verdict, pipe)
		}
	}
}

// Avec VIDEO_ENCODER=h264_vaapi forcé et la chaîne utilisable, la commande
// reste celle de fytroz : la chaîne sur le circuit quand elle s'applique,
// l'envoi seul sinon, et libx264 pour le profil 5.
func TestPlanner_ForcedVAAPIKeepsFytrozCommand(t *testing.T) {
	setCoresForTest(t, 16)
	setFilterSetForTest("zscale", "tonemap", "scale", "libplacebo", "scale_vaapi", "hwupload", "hwdownload")
	setLibplaceboForTest(true)
	t.Cleanup(func() { setLibplaceboForTest(false) })
	resetVulkanChoice(t)
	vulkanChosen.Store(&vulkanChoice{Spec: "vulkan:1", GPU: true, Fallback: "vulkan:0"})

	costs := softwareCosts(0.0033, 0.0107, 0.0011, 0.02, 0.023, 0.45)
	costs["decode:"+capacity.DecodeHEVC10VAAPI] = capacity.Cost{CPU: 0.0003, Decode: 0.0015}
	costs["decode:"+capacity.DecodeH264VAAPI] = capacity.Cost{CPU: 0.0002, Decode: 0.001}
	costs["scale:vaapi"] = capacity.Cost{CPU: 0.0001, Compute: 0.0004}
	costs["encode:h264_vaapi"] = capacity.Cost{CPU: 0.0008, Encode: 0.005}
	costs["tonemap:libplacebo"] = capacity.Cost{CPU: 0.001, Compute: 0.012}
	fallback := candidateOf(softwareEncoder)
	fallback.Fallback = true
	forced := testProfile(16, costs,
		[]capacity.EncoderCandidate{candidateOf(vaapiEncoder(t)), fallback},
		capacity.TrialResult{Name: capacity.TrialSelectedEncoder, Works: true, Choice: "h264_vaapi", Forced: "VIDEO_ENCODER=h264_vaapi"},
		capacity.TrialResult{Name: capacity.TrialFiltersPrefix + "vaapi", Works: true, Choice: "vaapi"},
		capacity.TrialResult{Name: capacity.TrialVulkan, Works: true, Choice: "vulkan:1", GPU: true, Fallback: "vulkan:0"})

	sdr := hardwareOptions(t, uhdHEVC(), VideoPlan{})
	hdr := hardwareOptions(t, uhdHEVC(), VideoPlan{Tonemap: true})
	hdr.Probe = hdr10UHD()
	dv := hardwareOptions(t, doviProfile5Probe().Video, VideoPlan{Tonemap: true})
	burn := hardwareOptions(t, uhdHEVC(), VideoPlan{})
	burn.BurnSubtitle, burn.BurnSubtitleTypedIndex = true, 0
	native := hardwareOptions(t, uhdHEVC(), VideoPlan{Tonemap: true})
	native.Probe, native.Quality = hdr10UHD(), "2160p"
	small := hardwareOptions(t, &VideoStreamInfo{Width: 1920, Height: 1080, Codec: "h264", FrameRate: 24}, VideoPlan{})
	small.Quality = "720p"

	for name, opt := range map[string]TranscodeOptions{
		"SDR 4K sur le circuit":       sdr,
		"HDR10 4K, zscale redescendu": hdr,
		"profil 5 : libx264":          dv,
		"sous-titre : envoi seul":     burn,
		"HDR sans mise à l'échelle":   native,
		"1080p H.264 vers 720p":       small,
	} {
		sameArgs(t, name, opt, forced)
	}
}

// Le planificateur choisit sur un N100 la chaîne VAAPI pour un 4K HDR10 que
// x264 ne tient pas : withPipeline la rend dans les champs du rendu.
func TestWithPipeline_FeedsTheRenderFields(t *testing.T) {
	opt := TranscodeOptions{Quality: "1080p", Probe: hdr10UHD(), Video: VideoPlan{Tonemap: true}}
	got := opt.withPipeline(capacity.Pipeline{Encoder: "h264_vaapi", Decode: "vaapi", Scale: "vaapi", Hardware: true})
	if got.Encoder.Name != "h264_vaapi" || !got.HardwareFilters || got.Pipeline == nil {
		t.Errorf("options %+v", got)
	}
	x264 := opt.withPipeline(capacity.Pipeline{Encoder: "libx264", Decode: "cpu", Preset: "superfast", Threads: 4})
	args := BuildFFmpegArgs(x264)
	if flagValue(args, "-preset", "") != "superfast" || flagValue(args, "-threads", "") != "4" {
		t.Errorf("le preset et les threads de la recette ne sont pas dans la commande : %v", args)
	}
	kept := TranscodeOptions{Video: VideoPlan{HEVC: true}}.withPipeline(capacity.Pipeline{Encoder: "libx265"})
	if kept.HEVCEncoder.Name != "libx265" || kept.Encoder.Name != "" {
		t.Errorf("HDR gardé : %+v / %+v", kept.HEVCEncoder.Name, kept.Encoder.Name)
	}
	if unknown := opt.withPipeline(capacity.Pipeline{Encoder: "libsvtav1"}); unknown.Pipeline != nil {
		t.Error("un encodeur inconnu ne doit pas changer les options")
	}
}

// Le journal de démarrage d'une session dit le preset que la recette a pris.
func TestDescribePipeline_ShowsThePlannedPreset(t *testing.T) {
	opt := TranscodeOptions{Quality: "1080p", Probe: probeWith(1920, 1080, 24)}
	opt = opt.withPipeline(capacity.Pipeline{Encoder: "libx264", Decode: "cpu", Preset: "ultrafast", Threads: 3})
	if got := describePipeline(opt, false); !strings.Contains(got, "preset=ultrafast, threads=3") {
		t.Errorf("journal %q", got)
	}
}
