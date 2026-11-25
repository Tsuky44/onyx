package streaming

import (
	"testing"

	"project-player/server/streaming/capacity"
)

// La tenue prévue des barreaux du menu (ladder_fit.go, phase 4 du plan
// docs/transcodage-adaptatif.md), sur les machines fictives du plan.

// fourCoresNoGPU est la machine de fytroz sans circuit : 4 cœurs, les coûts de
// référence (capacity/cost.go), libplacebo sur lavapipe. Un 4K HDR10 vers
// 1080p y coûte 3,44 cœurs et tient 1,1× (mesuré).
func fourCoresNoGPU() *capacity.Profile {
	return testProfile(4, softwareCosts(0.0025, 0.0082, 0.00085, 0.0153, 0.0177, 0.128),
		[]capacity.EncoderCandidate{candidateOf(softwareEncoder), candidateOf(softwareHEVCEncoder)},
		capacity.TrialResult{Name: capacity.TrialVulkan, Works: true, Choice: "vulkan:0"})
}

// i7WithIGPU est l'i7-10700K + UHD 630 de fytroz, sans VIDEO_ENCODER : la
// mesure a retenu libx264, libx265 et h264_vaapi, la chaîne VAAPI et
// libplacebo sur le circuit.
func i7WithIGPU(t *testing.T) *capacity.Profile {
	costs := softwareCosts(0.0033, 0.0107, 0.0011, 0.02, 0.023, 0.45)
	costs["decode:"+capacity.DecodeHEVC10VAAPI] = capacity.Cost{CPU: 0.0003, Decode: 0.0015}
	costs["decode:"+capacity.DecodeH264VAAPI] = capacity.Cost{CPU: 0.0002, Decode: 0.001}
	costs["scale:vaapi"] = capacity.Cost{CPU: 0.0001, Compute: 0.0004}
	costs["encode:h264_vaapi"] = capacity.Cost{CPU: 0.0008, Encode: 0.005}
	costs["tonemap:libplacebo"] = capacity.Cost{CPU: 0.001, Compute: 0.012}
	return testProfile(16, costs,
		[]capacity.EncoderCandidate{candidateOf(softwareEncoder), candidateOf(softwareHEVCEncoder), candidateOf(vaapiEncoder(t))},
		capacity.TrialResult{Name: capacity.TrialEncoderPrefix + "h264_vaapi", Works: true, Choice: "h264_vaapi", GPU: true},
		capacity.TrialResult{Name: capacity.TrialFiltersPrefix + "vaapi", Works: true, Choice: "vaapi", GPU: true},
		capacity.TrialResult{Name: capacity.TrialVulkan, Works: true, Choice: "vulkan:1", GPU: true, Fallback: "vulkan:0"})
}

// h264SDR1080 est un 1080p H.264 8 bits qu'un client sans capacités déclarées
// lit : son barreau natif se recopie.
func h264SDR1080() *ProbeResult {
	return &ProbeResult{Version: probeVersion, Video: &VideoStreamInfo{
		Codec: "h264", Width: 1920, Height: 1080, PixFmt: "yuv420p", FrameRate: 24, BitDepth: 8,
	}}
}

func fitsOf(ladder []QualityTier) map[string]capacity.Verdict {
	out := map[string]capacity.Verdict{}
	for _, tier := range ladder {
		out[tier.Key] = tier.Fit
	}
	return out
}

func TestQualityLadder_FitOnEachMachine(t *testing.T) {
	ok, limit, heavy := capacity.VerdictOK, capacity.VerdictLimit, capacity.VerdictTooHeavy
	// Treize cœurs sur seize pris par d'autres sessions, le circuit libre.
	busyI7 := capacity.Load{Used: capacity.Cost{CPU: 13}}
	tests := []struct {
		name    string
		profile *capacity.Profile
		probe   *ProbeResult
		load    capacity.Load
		want    map[string]capacity.Verdict
	}{
		{
			name:    "4 cœurs sans GPU, 4K HDR10 : la 4K en encodage est trop lourde, le 1080p limite (1,1× mesuré), le 720p tient",
			profile: fourCoresNoGPU(), probe: hdr10UHD(),
			want: map[string]capacity.Verdict{"2160p": heavy, "2160p-40m": heavy, "1080p": limit, "1080p-2m": limit, "720p": ok, "360p": ok},
		},
		{
			name:    "Xeon sans GPU, 4K HDR10, au repos : tout tient",
			profile: xeonProfile(), probe: hdr10UHD(),
			want: map[string]capacity.Verdict{"2160p": ok, "1080p-20m": ok, "720p": ok},
		},
		{
			name:    "i7 + iGPU, 4K HDR10, au repos : tout tient",
			profile: i7WithIGPU(t), probe: hdr10UHD(),
			want: map[string]capacity.Verdict{"2160p": ok, "1080p": ok, "720p": ok},
		},
		{
			name:    "i7 + iGPU, processeur presque plein : la 4K (x264) ne tient plus, la chaîne VAAPI garde le 1080p",
			profile: i7WithIGPU(t), probe: hdr10UHD(), load: busyI7,
			want: map[string]capacity.Verdict{"2160p": heavy, "1080p": ok, "720p-1m": ok},
		},
		{
			name:    "4 cœurs sans GPU, 1080p H.264 : le barreau natif se recopie, il est ok",
			profile: fourCoresNoGPU(), probe: h264SDR1080(),
			want: map[string]capacity.Verdict{"1080p": ok},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			in := startInputs{probe: tt.probe, burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities()}
			ladder := withFit(QualityLadderFor(sourceHeight(tt.probe)), in, tt.profile, tt.load)
			if len(ladder) != len(QualityLadderFor(sourceHeight(tt.probe))) {
				t.Fatalf("%d barreaux sur %d : aucun barreau n'est retiré", len(ladder), len(QualityLadderFor(sourceHeight(tt.probe))))
			}
			got := fitsOf(ladder)
			for key, want := range tt.want {
				if got[key] != want {
					t.Errorf("%s : %q, attendu %q (%v)", key, got[key], want, got)
				}
			}
		})
	}
}

// Une recopie ne coûte presque rien : elle est ok même sur une machine pleine.
func TestQualityLadder_ACopiedRungIsOKEvenWhenTheServerIsFull(t *testing.T) {
	in := startInputs{probe: h264SDR1080(), burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities()}
	full := capacity.Load{Used: capacity.Cost{CPU: 4}}
	got := fitsOf(withFit(QualityLadderFor(1080), in, fourCoresNoGPU(), full))
	if got["1080p"] != capacity.VerdictOK {
		t.Errorf("1080p recopié : %q", got["1080p"])
	}
	if got["720p"] != capacity.VerdictTooHeavy {
		t.Errorf("720p encodé sur une machine pleine : %q", got["720p"])
	}
}

// Sans profil prêt, le champ est absent : le menu reste celui d'avant.
func TestQualityLadder_WithoutProfileNoFit(t *testing.T) {
	setProfileForTest(t, nil)
	h := &Handler{manager: budgetManager()}
	ladder := h.QualityLadder(1, "/x.mkv", hdr10UHD(), LegacyCapabilities())
	if len(ladder) != len(QualityLadderFor(2160)) {
		t.Fatalf("%d barreaux", len(ladder))
	}
	for _, tier := range ladder {
		if tier.Fit != "" {
			t.Errorf("%s : tenue %q sans profil", tier.Key, tier.Fit)
		}
	}
}

// Un fichier qui a fait ramer une session voit sa tenue baisser aussitôt.
func TestQualityLadder_ASlowFileShowsItsRealFit(t *testing.T) {
	in := startInputs{probe: hdr10UHD(), burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities()}
	before := fitsOf(withFit(QualityLadderFor(2160), in, fourCoresNoGPU(), capacity.Load{}))
	in.lighter = lighterRecipe{slowdown: 1.6}
	after := fitsOf(withFit(QualityLadderFor(2160), in, fourCoresNoGPU(), capacity.Load{}))
	if before["720p"] != capacity.VerdictOK || after["720p"] != capacity.VerdictLimit {
		t.Errorf("720p : %q avant, %q après une session 1,6 fois plus lente que prévu", before["720p"], after["720p"])
	}
}
