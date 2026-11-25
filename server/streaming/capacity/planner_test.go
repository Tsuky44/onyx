package capacity

import (
	"math"
	"strings"
	"testing"
)

// Les machines fictives du plan. Les coûts sont par mégapixel·image, choisis
// pour être plausibles (la référence de fytroz, ramenée à la vitesse de chaque
// machine) ; ce qui est épinglé ici, c'est ce que la règle en déduit.

var (
	x264      = EncoderCandidate{Name: "libx264", Codec: "h264"}
	x265      = EncoderCandidate{Name: "libx265", Codec: "hevc"}
	vaapiH264 = EncoderCandidate{Name: "h264_vaapi", Codec: "h264", Hardware: true, Surface: "vaapi", Upload: true}
	nvenc     = EncoderCandidate{Name: "h264_nvenc", Codec: "h264", Hardware: true}
)

type costTable map[string]Cost

// cpuCosts sont les étapes logicielles d'une machine : décodage léger et
// lourd, swscale, zscale, x264 à ses trois presets.
func cpuCosts(h264, hevc10, scale, zscale, veryfast, superfast, ultrafast float64) costTable {
	return costTable{
		"decode:" + DecodeH264CPU:                         {CPU: h264},
		"decode:" + DecodeHEVC10CPU:                       {CPU: hevc10},
		"scale:" + ScaleSoftware:                          {CPU: scale},
		"tonemap:" + ToneMapZscale:                        {CPU: zscale},
		"encode:libx264/veryfast":                         {CPU: veryfast},
		"encode:libx264/superfast":                        {CPU: superfast},
		"encode:libx264/ultrafast":                        {CPU: ultrafast},
		"encode:" + EncodeVariant("libx265", "ultrafast"): {CPU: veryfast * 2.1},
	}
}

// intelGPU ajoute le circuit Intel : décodage, mise à l'échelle et encodage
// VAAPI, libplacebo sur le Vulkan du circuit.
func intelGPU(t costTable, encode float64) costTable {
	t["decode:"+DecodeH264VAAPI] = Cost{CPU: 0.0002, Decode: 0.001}
	t["decode:"+DecodeHEVC10VAAPI] = Cost{CPU: 0.0003, Decode: 0.0015}
	t["scale:"+ScaleVAAPI] = Cost{CPU: 0.0001, Compute: 0.0004}
	t["encode:h264_vaapi"] = Cost{CPU: 0.0008, Encode: encode}
	t["tonemap:"+ToneMapLibplacebo] = Cost{CPU: 0.001, Compute: 0.012}
	return t
}

func machine(cores int, costs costTable, encoders []EncoderCandidate, trials ...TrialResult) *Profile {
	p := &Profile{
		Inventory: Inventory{Cores: cores, FFmpeg: FFmpegInventory{Filters: []string{"libplacebo", "tonemap", "zscale"}}},
		Encoders:  encoders,
		Trials:    trials,
	}
	for key, cost := range costs {
		stage, variant, _ := strings.Cut(key, ":")
		p.Costs = append(p.Costs, StageCost{Stage: Stage(stage), Variant: variant, Cost: cost})
	}
	return p
}

var (
	vulkanGPU      = TrialResult{Name: TrialVulkan, Works: true, Choice: "vulkan:1", GPU: true}
	vulkanSoftware = TrialResult{Name: TrialVulkan, Works: true, Choice: "vulkan:0"}
	vaapiFilters   = TrialResult{Name: TrialFiltersPrefix + "vaapi", Works: true, Choice: "vaapi"}
)

func pi4() *Profile {
	t := cpuCosts(0.009, 0.03, 0.003, 0.055, 0.062, 0.037, 0.021)
	t["tonemap:"+ToneMapLibplacebo] = Cost{CPU: 0.45}
	return machine(4, t, []EncoderCandidate{x264, x265}, vulkanSoftware)
}

func n100() *Profile {
	t := intelGPU(cpuCosts(0.003, 0.0098, 0.001, 0.0184, 0.0212, 0.0127, 0.0072), 0.004)
	return machine(4, t, []EncoderCandidate{x264, vaapiH264}, vaapiFilters, vulkanGPU)
}

func i7UHD630() *Profile {
	t := intelGPU(cpuCosts(0.0033, 0.0107, 0.0011, 0.02, 0.023, 0.0138, 0.0078), 0.005)
	return machine(16, t, []EncoderCandidate{x264, vaapiH264}, vaapiFilters, vulkanGPU)
}

func xeonNoGPU() *Profile {
	t := cpuCosts(0.0035, 0.0115, 0.0012, 0.0214, 0.0248, 0.0148, 0.0084)
	t["tonemap:"+ToneMapLibplacebo] = Cost{CPU: 0.18}
	return machine(32, t, []EncoderCandidate{x264, x265}, vulkanSoftware)
}

// nvidia est un vieux 4 cœurs avec une carte NVIDIA : NVENC, mais libplacebo
// sur le rendu logiciel (le Vulkan NVIDIA n'est pas dans l'image Alpine).
func nvidia() *Profile {
	t := cpuCosts(0.0025, 0.0082, 0.00085, 0.0153, 0.0177, 0.0106, 0.006)
	t["tonemap:"+ToneMapLibplacebo] = Cost{CPU: 0.128}
	t["encode:h264_nvenc"] = Cost{CPU: 0.0009, Encode: 0.0023}
	return machine(4, t, []EncoderCandidate{x264, nvenc}, vulkanSoftware)
}

// Les quatre cas réels du plan.
var (
	uhdHDR10ToFHD = Job{
		Source:  Source{Width: 3840, Height: 2160, FPS: 24, Codec: "hevc", BitDepth: 10},
		Target:  Target{Width: 1920, Height: 1080, Preset: "veryfast"},
		ToneMap: true,
	}
	uhdDV5ToFHD = Job{
		Source:  Source{Width: 3840, Height: 2160, FPS: 24, Codec: "hevc", BitDepth: 10, DV5: true},
		Target:  Target{Width: 1920, Height: 1080, Preset: "veryfast"},
		ToneMap: true,
	}
	// L'Apple TV HD ne décode pas le HEVC : le 1080p est réencodé en H.264.
	fhdHEVCToH264 = Job{
		Source: Source{Width: 1920, Height: 1080, FPS: 24, Codec: "hevc", BitDepth: 10},
		Target: Target{Width: 1920, Height: 1080, Preset: "veryfast"},
	}
	fhdH264To720 = Job{
		Source: Source{Width: 1920, Height: 1080, FPS: 24, Codec: "h264", BitDepth: 8},
		Target: Target{Width: 1280, Height: 720, Preset: "veryfast"},
	}
)

func TestPlanPipeline_RealCasesOnEachMachine(t *testing.T) {
	type want struct {
		encoder, preset, decode, scale, tonemap string
		tonemapGPU                              bool
		verdict                                 Verdict
	}
	cases := []struct {
		name    string
		profile *Profile
		job     Job
		want    want
	}{
		// Raspberry Pi 4 : ni le 4K ni le profil 5 ne tiennent ; le plus
		// rapide est rendu, avec son verdict. Le 1080p HEVC ne tient qu'en
		// ultrafast, le 720p garde veryfast.
		{"pi4/4K HDR10", pi4(), uhdHDR10ToFHD, want{"libx264", "ultrafast", "cpu", "sw", "zscale", false, VerdictTooHeavy}},
		{"pi4/4K DV5", pi4(), uhdDV5ToFHD, want{"libx264", "ultrafast", "cpu", "sw", "libplacebo", false, VerdictTooHeavy}},
		{"pi4/1080p HEVC", pi4(), fhdHEVCToH264, want{"libx264", "ultrafast", "cpu", "", "", false, VerdictOK}},
		{"pi4/1080p→720p", pi4(), fhdH264To720, want{"libx264", "veryfast", "cpu", "sw", "", false, VerdictOK}},

		// N100 : x264 ne tient pas le 4K HDR10, la chaîne VAAPI si. Le profil 5
		// ne peut pas la prendre (un seul périphérique de filtres) : libplacebo
		// sur le circuit et x264 ultrafast.
		{"n100/4K HDR10", n100(), uhdHDR10ToFHD, want{"h264_vaapi", "", "vaapi", "vaapi", "zscale", false, VerdictOK}},
		{"n100/4K DV5", n100(), uhdDV5ToFHD, want{"libx264", "ultrafast", "cpu", "sw", "libplacebo", true, VerdictOK}},
		{"n100/1080p HEVC", n100(), fhdHEVCToH264, want{"libx264", "veryfast", "cpu", "", "", false, VerdictOK}},
		{"n100/1080p→720p", n100(), fhdH264To720, want{"libx264", "veryfast", "cpu", "sw", "", false, VerdictOK}},

		// i7-10700K + UHD 630 : seize threads, x264 veryfast tient partout avec
		// de la marge. Le profil 5 prend libplacebo sur le circuit, comme la
		// course de fytroz (2,1× mesuré).
		{"i7/4K HDR10", i7UHD630(), uhdHDR10ToFHD, want{"libx264", "veryfast", "cpu", "sw", "zscale", false, VerdictOK}},
		{"i7/4K DV5", i7UHD630(), uhdDV5ToFHD, want{"libx264", "veryfast", "cpu", "sw", "libplacebo", true, VerdictOK}},
		{"i7/1080p HEVC", i7UHD630(), fhdHEVCToH264, want{"libx264", "veryfast", "cpu", "", "", false, VerdictOK}},
		{"i7/1080p→720p", i7UHD630(), fhdH264To720, want{"libx264", "veryfast", "cpu", "sw", "", false, VerdictOK}},

		// Xeon sans GPU : la recette d'aujourd'hui partout.
		{"xeon/4K HDR10", xeonNoGPU(), uhdHDR10ToFHD, want{"libx264", "veryfast", "cpu", "sw", "zscale", false, VerdictOK}},
		{"xeon/4K DV5", xeonNoGPU(), uhdDV5ToFHD, want{"libx264", "veryfast", "cpu", "sw", "libplacebo", false, VerdictOK}},
		{"xeon/1080p HEVC", xeonNoGPU(), fhdHEVCToH264, want{"libx264", "veryfast", "cpu", "", "", false, VerdictOK}},
		{"xeon/1080p→720p", xeonNoGPU(), fhdH264To720, want{"libx264", "veryfast", "cpu", "sw", "", false, VerdictOK}},

		// NVIDIA sur 4 cœurs : NVENC prend le 4K HDR10 que x264 ne tient pas ;
		// le profil 5 sur lavapipe ne tient avec rien, NVENC est le plus rapide.
		{"nvidia/4K HDR10", nvidia(), uhdHDR10ToFHD, want{"h264_nvenc", "", "cpu", "sw", "zscale", false, VerdictOK}},
		{"nvidia/4K DV5", nvidia(), uhdDV5ToFHD, want{"h264_nvenc", "", "cpu", "sw", "libplacebo", false, VerdictTooHeavy}},
		{"nvidia/1080p HEVC", nvidia(), fhdHEVCToH264, want{"libx264", "veryfast", "cpu", "", "", false, VerdictOK}},
		{"nvidia/1080p→720p", nvidia(), fhdH264To720, want{"libx264", "veryfast", "cpu", "sw", "", false, VerdictOK}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := PlanPipeline(c.job, c.profile, Load{})
			if !ok {
				t.Fatal("aucune recette")
			}
			have := want{got.Encoder, got.Preset, got.Decode, got.Scale, got.ToneMap, got.ToneMapOnGPU, got.Verdict}
			if have != c.want {
				t.Errorf("recette %+v, voulu %+v\n%s", have, c.want, got)
			}
			if got.Verdict != VerdictFor(got.Speed) {
				t.Errorf("verdict %s pour %.2f×", got.Verdict, got.Speed)
			}
		})
	}
}

// Le coût et la vitesse prévus d'une recette se recalculent à la main : la
// somme des étapes au prorata des pixels, et la part libre sur le coût.
func TestPlanPipeline_PredictsCostAndSpeedFromTheStages(t *testing.T) {
	got, _ := PlanPipeline(uhdHDR10ToFHD, xeonNoGPU(), Load{})
	uhd, fhd := 3840*2160/1e6*24, 1920*1080/1e6*24
	want := 0.0115*uhd + 0.0012*uhd + 0.0214*fhd + 0.0248*fhd
	if math.Abs(got.Cost.CPU-want) > 1e-3 {
		t.Errorf("coût CPU %.4f, voulu %.4f", got.Cost.CPU, want)
	}
	if math.Abs(got.Speed-32/want) > 1e-2 {
		t.Errorf("vitesse %.3f, voulu %.3f", got.Speed, 32/want)
	}
	if got.Threads != 16 {
		t.Errorf("threads %d sur 32 cœurs, voulu le plafond de 16", got.Threads)
	}
}

// Sans marge, la recette qui laisse le plus de la ressource la plus tendue :
// sur un i7 dont les cœurs sont presque tous pris, la chaîne VAAPI plutôt que
// x264, même en ultrafast, qui tiendrait pourtant 1,5×.
func TestPlanPipeline_WithoutMarginSparesTheScarcestResource(t *testing.T) {
	got, _ := PlanPipeline(fhdH264To720, i7UHD630(), Load{Used: Cost{CPU: 15}})
	if got.Encoder != "h264_vaapi" || got.Decode != "vaapi" {
		t.Errorf("sans marge sur le CPU, voulu la chaîne VAAPI : %s", got)
	}
	// La même machine au repos garde la meilleure image.
	if idle, _ := PlanPipeline(fhdH264To720, i7UHD630(), Load{}); idle.Encoder != "libx264" || idle.Preset != "veryfast" {
		t.Errorf("au repos, voulu x264 veryfast : %s", idle)
	}
}

// Avec de la marge, la meilleure image passe avant la plus économe, même quand
// le circuit coûterait dix fois moins de CPU (ADR-0023).
func TestPlanPipeline_WithMarginTheBestPictureWins(t *testing.T) {
	got, _ := PlanPipeline(fhdHEVCToH264, n100(), Load{})
	if got.Encoder != "libx264" || got.Preset != "veryfast" {
		t.Errorf("voulu x264 veryfast : %s", got)
	}
	if got.Considered < 4 {
		t.Errorf("%d recettes comparées, voulu x264 aux trois presets et VAAPI", got.Considered)
	}
}

// Le preset du barreau est le plus lent permis : la 2160p reste en ultrafast,
// pour qu'une session repartie de zéro y tienne.
func TestPlanPipeline_NeverSlowerThanTheTierPreset(t *testing.T) {
	job := Job{
		Source: Source{Width: 3840, Height: 2160, FPS: 24, Codec: "h264", BitDepth: 8},
		Target: Target{Width: 3840, Height: 2160, Preset: "ultrafast"},
	}
	got, _ := PlanPipeline(job, xeonNoGPU(), Load{})
	if got.Preset != "ultrafast" || got.Considered != 1 {
		t.Errorf("2160p : %s", got)
	}
}

// Le contrat de fytroz : une commande n'a qu'un périphérique de filtres. Un
// encodeur à envoi ne prend jamais un profil 5 tone mappé par libplacebo ; le
// repli libx264 d'un VIDEO_ENCODER forcé le prend.
func TestPlanPipeline_ForcedVAAPIFallsBackToX264ForDolbyVision(t *testing.T) {
	fallback := x264
	fallback.Fallback = true
	forced := i7UHD630()
	forced.Encoders = []EncoderCandidate{vaapiH264, fallback}

	dv, ok := PlanPipeline(uhdDV5ToFHD, forced, Load{})
	if !ok || dv.Encoder != "libx264" || dv.ToneMap != ToneMapLibplacebo {
		t.Errorf("profil 5 avec h264_vaapi forcé : %s", dv)
	}
	hdr, _ := PlanPipeline(uhdHDR10ToFHD, forced, Load{})
	if hdr.Encoder != "h264_vaapi" || hdr.Decode != "vaapi" {
		t.Errorf("HDR10 avec h264_vaapi forcé : %s", hdr)
	}
}

// La chaîne sur le circuit suit les conditions du rendu : jamais avec un
// sous-titre incrusté ou un désentrelacement, ni pour un HDR déjà à la taille
// du barreau, ni quand l'essai l'a retirée.
func TestPlanPipeline_HardwareChainFollowsTheRenderConditions(t *testing.T) {
	burned := uhdHDR10ToFHD
	burned.SoftwareOnly = true
	if got, _ := PlanPipeline(burned, n100(), Load{}); got.Decode != "cpu" {
		t.Errorf("sous-titre incrusté : %s", got)
	}

	native := uhdHDR10ToFHD
	native.Target = Target{Width: 3840, Height: 2160, Preset: "ultrafast"}
	for _, r := range enumerate(native, n100(), false) {
		if r.Decode == "vaapi" {
			t.Errorf("HDR sans mise à l'échelle sur le circuit : %s", r.Pipeline)
		}
	}

	retired := n100()
	retired.Trials[0].Retired = "session morte"
	if got, _ := PlanPipeline(uhdHDR10ToFHD, retired, Load{}); got.Decode == "vaapi" {
		t.Errorf("chaîne retirée encore proposée : %s", got)
	}
}

// Le HDR gardé ne prend que les encodeurs HEVC.
func TestPlanPipeline_KeptHDRUsesAnHEVCEncoder(t *testing.T) {
	job := uhdHDR10ToFHD
	job.ToneMap, job.KeepHDR = false, true
	got, ok := PlanPipeline(job, xeonNoGPU(), Load{})
	if !ok || got.Encoder != "libx265" || got.ToneMap != "" {
		t.Errorf("HDR gardé : %s", got)
	}
	if _, ok := PlanPipeline(job, n100(), Load{}); ok {
		t.Error("une machine sans encodeur HEVC n'a pas de recette")
	}
}

// Un décodage sur le circuit qui n'a pas été mesuré n'est pas supposé : le
// circuit qui ne décode pas ce flux rend la main au processeur.
func TestPlanPipeline_UnmeasuredHardwareDecodeCountsAsCPU(t *testing.T) {
	p := n100()
	for i := range p.Costs {
		if p.Costs[i].Variant == DecodeHEVC10VAAPI {
			p.Costs[i].Estimated = true
		}
	}
	got, _ := PlanPipeline(fhdHEVCToH264, p, Load{})
	vaapi := enumerate(fhdHEVCToH264, p, false)
	for _, r := range vaapi {
		if r.Encoder == "h264_vaapi" && r.Cost.Decode != 0 {
			t.Errorf("décodage non mesuré compté sur le circuit : %+v", r.Cost)
		}
	}
	if got.Encoder == "" {
		t.Fatal("aucune recette")
	}
}

func TestVerdictFor(t *testing.T) {
	for _, c := range []struct {
		speed float64
		want  Verdict
	}{{3, VerdictOK}, {1.5, VerdictOK}, {1.49, VerdictLimit}, {1, VerdictLimit}, {0.99, VerdictTooHeavy}} {
		if got := VerdictFor(c.speed); got != c.want {
			t.Errorf("%.2f× : %s, voulu %s", c.speed, got, c.want)
		}
	}
}

func TestThreadsFor(t *testing.T) {
	for cores, want := range map[int]int{0: 1, 1: 1, 4: 4, 16: 16, 64: 16} {
		if got := ThreadsFor(cores); got != want {
			t.Errorf("ThreadsFor(%d) = %d, voulu %d", cores, got, want)
		}
	}
}

func TestFitNeverUpscales(t *testing.T) {
	for _, c := range []struct {
		w, h, bw, bh, ww, wh int
		scaled               bool
	}{
		{3840, 2160, 1920, 1080, 1920, 1080, true},
		{1280, 536, 1920, 1080, 1280, 536, false},
		{1920, 800, 1280, 720, 1280, 532, true},
		{0, 0, 1280, 720, 1280, 720, true},
	} {
		w, h, scaled := fit(c.w, c.h, c.bw, c.bh)
		if w != c.ww || h != c.wh || scaled != c.scaled {
			t.Errorf("fit(%dx%d dans %dx%d) = %dx%d %v", c.w, c.h, c.bw, c.bh, w, h, scaled)
		}
	}
}

func TestPlanPipeline_WithoutProfileOrCandidates(t *testing.T) {
	if _, ok := PlanPipeline(fhdH264To720, nil, Load{}); ok {
		t.Error("sans profil, pas de recette")
	}
	if _, ok := PlanPipeline(fhdH264To720, machine(4, costTable{}, nil), Load{}); ok {
		t.Error("sans encodeur, pas de recette")
	}
}

// Une machine que le banc n'a pas mesurée planifie sur la référence, et le
// dit.
func TestPlanPipeline_ReferenceCostsAreMarkedEstimated(t *testing.T) {
	got, ok := PlanPipeline(fhdH264To720, machine(4, costTable{}, []EncoderCandidate{x264}), Load{})
	if !ok || !got.Estimated {
		t.Errorf("recette sur la référence non marquée estimée : %s", got)
	}
	if !strings.Contains(got.String(), "estimée") {
		t.Errorf("le journal ne dit pas l'estimation : %s", got)
	}
}
