package streaming

import (
	"net/url"
	"strings"
	"testing"
)

// Ce que déclare le lecteur natif d'Apple TV pour une source que sa puce ne
// décode pas (ADR-0106).
func appleTVNativeCaps() Capabilities {
	q, _ := url.ParseQuery("container=fmp4&vcodec=h264,hevc&acodec=aac,ac3,eac3&channels=8" +
		"&bitdepth=10&hdr=1&encode=hevc&progressive=1&h264bitdepth=8")
	return ParseCapabilities(q)
}

func av1HDRProbe(transfer string) *ProbeResult {
	return &ProbeResult{Video: &VideoStreamInfo{
		Codec: "av1", Width: 3840, Height: 2160, FrameRate: 24,
		PixFmt: "yuv420p10le", ColorTransfer: transfer, ColorPrimaries: "bt2020", ColorSpace: "bt2020nc",
	}}
}

func TestParseCapabilities_ReadsTheAppleTVDeclaration(t *testing.T) {
	caps := appleTVNativeCaps()
	if !caps.EncodeHEVC || !caps.ProgressiveOnly || caps.MaxH264BitDepth != 8 {
		t.Fatalf("encode=hevc, progressive=1 et h264bitdepth=8 doivent être lus : %+v", caps)
	}
	if got := caps.MaxBitDepthFor("h264"); got != 8 {
		t.Errorf("H.264 : %d bits, attendu 8", got)
	}
	if got := caps.MaxBitDepthFor("hevc"); got != 10 {
		t.Errorf("HEVC : %d bits, attendu 10", got)
	}
	// Un client qui ne dit rien garde l'ancien comportement.
	legacy := ParseCapabilities(url.Values{})
	if legacy.EncodeHEVC || legacy.ProgressiveOnly || legacy.MaxBitDepthFor("h264") != 8 {
		t.Errorf("un client muet ne demande rien de neuf : %+v", legacy)
	}
}

func TestPlanVideo_AnHDRSourceTheClientCannotDecodeKeepsItsHDRInHEVC(t *testing.T) {
	for _, transfer := range []string{"smpte2084", "arib-std-b67"} {
		plan := PlanVideo(av1HDRProbe(transfer), "1080p", false, 0, 0, appleTVNativeCaps())
		if plan.Copy || !plan.HEVC || plan.Tonemap {
			t.Errorf("%s : AV1 HDR réencodé en HEVC Main 10 sans tone mapping, obtenu %+v", transfer, plan)
		}
	}
}

func TestPlanVideo_AnSDRSourceStaysOnH264(t *testing.T) {
	probe := &ProbeResult{Video: &VideoStreamInfo{
		Codec: "vc1", Width: 1920, Height: 1080, FrameRate: 24, PixFmt: "yuv420p",
	}}
	plan := PlanVideo(probe, "1080p", false, 0, 0, appleTVNativeCaps())
	if plan.Copy || plan.HEVC || plan.Tonemap {
		t.Errorf("VC-1 SDR : H.264 sans HEVC ni tone mapping, obtenu %+v", plan)
	}
}

func TestPlanVideo_HDRIsToneMappedWithoutHEVCConsent(t *testing.T) {
	caps := appleTVNativeCaps()
	caps.EncodeHEVC = false // client qui ne le demande pas, ou serveur sans encodeur HEVC
	plan := PlanVideo(av1HDRProbe("smpte2084"), "1080p", false, 0, 0, caps)
	if plan.HEVC || !plan.Tonemap {
		t.Errorf("sans HEVC, l'AV1 HDR est tone-mappé en H.264 comme avant : %+v", plan)
	}
}

func TestPlanVideo_DolbyVisionProfile5NeverGoesToHEVC(t *testing.T) {
	plan := PlanVideo(doviProfile5Probe(), "1080p", false, 0, 0, appleTVNativeCaps())
	if plan.HEVC || !plan.Tonemap {
		t.Errorf("la couche de base du profil 5 n'est pas du HDR10 : %+v", plan)
	}
}

func TestPlanVideo_H264High10IsReencodedButHEVCMain10IsCopied(t *testing.T) {
	caps := appleTVNativeCaps()
	h264 := &ProbeResult{Video: &VideoStreamInfo{Codec: "h264", Width: 1920, Height: 1080, PixFmt: "yuv420p10le"}}
	if plan := PlanVideo(h264, "1080p", false, 0, 0, caps); plan.Copy {
		t.Error("H.264 10 bits : le décodeur d'Apple ne le lit pas, il faut réencoder")
	}
	hevc := &ProbeResult{Video: &VideoStreamInfo{Codec: "hevc", Width: 1920, Height: 1080, PixFmt: "yuv420p10le"}}
	if plan := PlanVideo(hevc, "1080p", false, 0, 0, caps); !plan.Copy {
		t.Errorf("HEVC Main 10 : recopié, obtenu %+v", plan)
	}
}

func TestPlanVideo_InterlacedSourcesAreDeinterlacedWhenReencoded(t *testing.T) {
	interlaced := &ProbeResult{Video: &VideoStreamInfo{
		Codec: "h264", Width: 1920, Height: 1080, PixFmt: "yuv420p", FieldOrder: "tt",
	}}
	plan := PlanVideo(interlaced, "1080p", false, 0, 0, appleTVNativeCaps())
	if plan.Copy || !plan.Deinterlace {
		t.Errorf("progressive=1 : une source entrelacée est réencodée et désentrelacée, obtenu %+v", plan)
	}
	// Un client qui lit l'entrelacé garde la recopie.
	if plan := PlanVideo(interlaced, "1080p", false, 0, 0, LegacyCapabilities()); !plan.Copy {
		t.Errorf("sans progressive=1, la recopie reste permise : %+v", plan)
	}
	// Mais tout réencodage la désentrelace.
	if plan := PlanVideo(interlaced, "720p", false, 0, 0, LegacyCapabilities()); plan.Copy || !plan.Deinterlace {
		t.Errorf("réencodée, une source entrelacée sort désentrelacée : %+v", plan)
	}
}

func hevcArgs(probe *ProbeResult, burn bool) []string {
	caps := appleTVNativeCaps()
	return BuildFFmpegArgs(TranscodeOptions{
		InputPath:              "in.mkv",
		Quality:                "1080p",
		TmpDir:                 "/tmp/session",
		Probe:                  probe,
		SegmentDuration:        2,
		AudioTypedIndexes:      []int{0},
		BurnSubtitle:           burn,
		BurnSubtitleTypedIndex: 0,
		Video:                  PlanVideo(probe, "1080p", burn, 0, 0, caps),
		Caps:                   caps,
	})
}

func TestBuildFFmpegArgs_HEVCKeepsTheHDRTagsOnEveryFrame(t *testing.T) {
	args := hevcArgs(av1HDRProbe("smpte2084"), false)
	for flag, want := range map[string]string{
		"-c:v": "libx265", "-pix_fmt": "yuv420p10le", "-profile:v": "main10", "-tag:v": "hvc1",
	} {
		if got, _ := argValue(args, flag); got != want {
			t.Errorf("%s = %q, attendu %q", flag, got, want)
		}
	}
	if hasArg(args, "-level") {
		t.Error("le niveau H.264 n'a rien à faire sur un encodage HEVC")
	}
	vf, _ := argValue(args, "-vf")
	if !strings.Contains(vf, "color_trc=smpte2084") || !strings.Contains(vf, "color_primaries=bt2020") {
		t.Errorf("les images doivent porter le PQ et le BT.2020 : -vf %q", vf)
	}
	if strings.Contains(vf, "tonemap") || strings.Contains(vf, "zscale") {
		t.Errorf("rien n'est tone-mappé quand le HDR est gardé : -vf %q", vf)
	}
	if strings.Index(vf, "scale=") > strings.Index(vf, "setparams") {
		t.Errorf("les étiquettes se posent après la mise à l'échelle : -vf %q", vf)
	}
}

func TestBuildFFmpegArgs_HLGKeepsItsOwnTransfer(t *testing.T) {
	vf, _ := argValue(hevcArgs(av1HDRProbe("arib-std-b67"), false), "-vf")
	if !strings.Contains(vf, "color_trc=arib-std-b67") {
		t.Errorf("un HLG reste en HLG : -vf %q", vf)
	}
}

func TestBuildFFmpegArgs_DeinterlacesBeforeScalingAndBeforeTheBurnedSubtitle(t *testing.T) {
	probe := &ProbeResult{
		Video:     &VideoStreamInfo{Codec: "mpeg2video", Width: 1920, Height: 1080, FrameRate: 25, PixFmt: "yuv422p", FieldOrder: "tt"},
		Subtitles: []SubtitleStreamInfo{{TypedIndex: 0, Codec: "dvd_subtitle", Image: true}},
	}
	vf, _ := argValue(hevcArgs(probe, false), "-vf")
	if !strings.HasPrefix(vf, "bwdif=") {
		t.Errorf("le désentrelacement passe en premier : -vf %q", vf)
	}
	burned := hevcArgs(probe, true)
	graph, _ := argValue(burned, "-filter_complex")
	if !strings.HasPrefix(graph, "[0:v:0]bwdif=") || strings.Count(graph, "bwdif") != 1 {
		t.Errorf("avec un sous-titre incrusté, une seule fois et avant l'incrustation : %q", graph)
	}
}

func TestHEVCEncoderFollowsTheOperatorsChoice(t *testing.T) {
	always := func(VideoEncoder) bool { return true }
	never := func(VideoEncoder) bool { return false }

	if got, ok := hevcEncoderFor(softwareEncoder, always); !ok || got.Name != "libx265" {
		t.Errorf("derrière libx264 : libx265, obtenu %q %v", got.Name, ok)
	}
	vaapi := vaapiEncoder(t)
	got, ok := hevcEncoderFor(vaapi, always)
	if !ok || got.Name != "hevc_vaapi" || len(got.deviceArgs) == 0 || got.rateControl == nil {
		t.Errorf("derrière VAAPI : hevc_vaapi sur le même périphérique, obtenu %+v %v", got, ok)
	}
	if !strings.Contains(got.uploadFilter, "p010") {
		t.Errorf("VAAPI envoie des images 10 bits : %q", got.uploadFilter)
	}
	// Un circuit sans HEVC ne renvoie pas vers le processeur.
	if _, ok := hevcEncoderFor(vaapi, never); ok {
		t.Error("un HEVC matériel qui ne marche pas laisse le H.264")
	}
	if _, ok := hevcEncoderFor(softwareEncoder, never); ok {
		t.Error("un FFmpeg sans libx265 laisse le H.264")
	}
}

func TestHEVCEncoderProbeAsksForMain10(t *testing.T) {
	args := encoderProbeArgs(softwareHEVCEncoder)
	if !hasFlag(args, "-pix_fmt", "yuv420p10le") || !hasFlag(args, "-profile:v", "main10") {
		t.Errorf("la sonde essaie ce que les sessions demanderont : %v", args)
	}
	if plain := encoderProbeArgs(softwareEncoder); hasAnyFlag(plain, "-profile:v") {
		t.Errorf("la sonde H.264 reste celle d'avant : %v", plain)
	}
}

func TestProbe_FieldOrderSaysInterlaced(t *testing.T) {
	v := videoStreamFrom(ffprobeStream{CodecName: "mpeg2video", PixFmt: "yuv420p", FieldOrder: "tb"})
	if !v.Interlaced() {
		t.Error("tb est entrelacé")
	}
	raw, err := MarshalProbeResult(&ProbeResult{Version: probeVersion, Video: v})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(raw, `"interlaced":true`) {
		t.Errorf("le client lit la règle du serveur : %s", raw)
	}
	for _, order := range []string{"progressive", "unknown", ""} {
		if (&VideoStreamInfo{FieldOrder: order}).Interlaced() {
			t.Errorf("%q n'est pas entrelacé", order)
		}
	}
}
