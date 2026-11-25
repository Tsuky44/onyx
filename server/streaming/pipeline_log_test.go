package streaming

import "testing"

func TestDescribePipeline(t *testing.T) {
	setLibplaceboForTest(true)
	t.Cleanup(func() { setLibplaceboForTest(false) })
	setFilterSetForTest("libplacebo", "zscale", "tonemap")
	setCoresForTest(t, 16)

	sdr := &ProbeResult{Video: &VideoStreamInfo{Width: 1920, Height: 1080, Codec: "h264", FrameRate: 24}}
	hdr10 := &ProbeResult{Video: &VideoStreamInfo{Width: 3840, Height: 2160, Codec: "hevc", FrameRate: 24}}
	dovi5 := &ProbeResult{Video: &VideoStreamInfo{Width: 3840, Height: 2160, Codec: "hevc", FrameRate: 24, DoviProfile: 5}}

	tests := []struct {
		name      string
		opt       TranscodeOptions
		vulkanGPU bool
		want      string
	}{
		{
			"SDR en logiciel",
			TranscodeOptions{Quality: "1080p", Probe: sdr},
			false,
			"décodage=hwaccel auto, tone mapping=aucun, encodeur=libx264, preset=veryfast, threads=16",
		},
		{
			"HDR10 : zscale sur le processeur",
			TranscodeOptions{Quality: "1080p", Probe: hdr10, Video: VideoPlan{Tonemap: true}},
			false,
			"décodage=hwaccel auto, tone mapping=zscale, encodeur=libx264, preset=veryfast, threads=16",
		},
		{
			"DV5 : libplacebo sur le circuit, décodage Vulkan",
			TranscodeOptions{Quality: "1080p", Probe: dovi5, Video: VideoPlan{Tonemap: true}},
			true,
			"décodage=vulkan, tone mapping=libplacebo@gpu, encodeur=libx264, preset=veryfast, threads=16",
		},
		{
			"DV5 : libplacebo sur lavapipe",
			TranscodeOptions{Quality: "1080p", Probe: dovi5, Video: VideoPlan{Tonemap: true}},
			false,
			"décodage=vulkan, tone mapping=libplacebo@logiciel, encodeur=libx264, preset=veryfast, threads=16",
		},
		{
			"image recopiée : rien ne s'encode",
			TranscodeOptions{Quality: "1080p", Probe: hdr10, Video: VideoPlan{Copy: true, Tonemap: true}},
			false,
			"décodage=hwaccel auto, tone mapping=aucun, encodeur=copie, preset=-, threads=-",
		},
		{
			"4K : le preset du plus haut barreau",
			TranscodeOptions{Quality: "2160p", Probe: sdr},
			false,
			"décodage=hwaccel auto, tone mapping=aucun, encodeur=libx264, preset=" + encoderPresetFor(presetFor("2160p")) + ", threads=16",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := describePipeline(tt.opt, tt.vulkanGPU); got != tt.want {
				t.Errorf("\n got %q\nwant %q", got, tt.want)
			}
		})
	}
}

// Les threads du journal sont ceux de l'encodeur, pas un second calcul.
func TestDescribePipeline_ThreadsFollowTheAvailableCores(t *testing.T) {
	setCoresForTest(t, 4)
	got := describePipeline(TranscodeOptions{
		Quality: "1080p",
		Probe:   &ProbeResult{Video: &VideoStreamInfo{Width: 1920, Height: 1080, Codec: "h264"}},
	}, false)
	if want := "décodage=hwaccel auto, tone mapping=aucun, encodeur=libx264, preset=veryfast, threads=4"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// Un encodeur matériel n'a pas de preset x264 ni de threads : le journal n'en
// invente pas, et le décodage nomme la surface du circuit.
func TestDescribePipeline_VAAPIKeepsTheFrameOnTheDevice(t *testing.T) {
	setFilterSetForTest("zscale", "tonemap")
	got := describePipeline(TranscodeOptions{
		Quality: "1080p",
		Probe:   &ProbeResult{Video: &VideoStreamInfo{Width: 3840, Height: 2160, Codec: "hevc", FrameRate: 24}},
		Encoder: vaapiEncoder(t), HardwareFilters: true,
	}, false)
	if want := "décodage=vaapi, tone mapping=aucun, encodeur=h264_vaapi, preset=-, threads=-"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestToneMappingName(t *testing.T) {
	tests := []struct {
		tm        ToneMapper
		vulkanGPU bool
		want      string
	}{
		{ToneMapper{}, false, "aucun"},
		{ToneMapper{}, true, "aucun"}, // un circuit Vulkan sans tone mapping ne fait rien
		{ToneMapper{Filter: "zscale=…"}, true, "zscale"},
		{ToneMapper{Filter: "libplacebo=…", Vulkan: true}, true, "libplacebo@gpu"},
		{ToneMapper{Filter: "libplacebo=…", Vulkan: true}, false, "libplacebo@logiciel"},
	}
	for _, tt := range tests {
		if got := toneMappingName(tt.tm, tt.vulkanGPU); got != tt.want {
			t.Errorf("%+v gpu=%v : %q, veut %q", tt.tm, tt.vulkanGPU, got, tt.want)
		}
	}
}

// La ligne dit ce que la commande fait : décoder avec Vulkan est ce que
// BuildFFmpegArgs écrit quand libplacebo travaille.
func TestDecodeModeMatchesTheCommand(t *testing.T) {
	setLibplaceboForTest(true)
	t.Cleanup(func() { setLibplaceboForTest(false) })
	setFilterSetForTest("libplacebo", "zscale", "tonemap")
	opt := TranscodeOptions{
		InputPath: "in.mkv", Quality: "1080p", TmpDir: "/tmp/s",
		Probe: &ProbeResult{Video: &VideoStreamInfo{
			Width: 3840, Height: 2160, Codec: "hevc", FrameRate: 24, DoviProfile: 5,
		}},
		SegmentDuration: 4, AudioTypedIndexes: []int{0},
		Video: VideoPlan{Tonemap: true},
	}
	if got := decodeMode(opt); got != decodeVulkan {
		t.Fatalf("decodeMode = %q", got)
	}
	args := BuildFFmpegArgs(opt)
	if !hasAnyFlag(args, "-init_hw_device") || hasFlag(args, "-hwaccel", "auto") {
		t.Errorf("la commande ne décode pas par Vulkan : %v", args)
	}
}
