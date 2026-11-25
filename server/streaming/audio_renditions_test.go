package streaming

import (
	"reflect"
	"testing"

	"project-player/server/streaming/capacity"
)

// Une petite machine publie deux pistes, la choisie et la VO ; une grosse
// jusqu'à huit (décision §0.4 du plan docs/transcodage-adaptatif.md).

func TestAudioRenditionLimit_FromTheProfile(t *testing.T) {
	x264 := candidateOf(softwareEncoder)
	vaapi := capacity.EncoderCandidate{Name: "h264_vaapi", Codec: "h264", Hardware: true, Surface: "vaapi"}
	tests := []struct {
		name    string
		profile *capacity.Profile
		want    int
	}{
		{"sans profil : comme avant", nil, maxAudioRenditions},
		{"4 cœurs sans circuit : petite", testProfile(4, nil, []capacity.EncoderCandidate{x264}), smallMachineAudioRenditions},
		{"2 cœurs sans circuit : petite", testProfile(2, nil, []capacity.EncoderCandidate{x264}), smallMachineAudioRenditions},
		{"4 cœurs avec un encodeur du circuit", testProfile(4, nil, []capacity.EncoderCandidate{x264, vaapi}), maxAudioRenditions},
		{"4 cœurs avec libplacebo sur le circuit", testProfile(4, nil, []capacity.EncoderCandidate{x264},
			capacity.TrialResult{Name: capacity.TrialVulkan, Works: true, Choice: "vulkan:0", GPU: true}), maxAudioRenditions},
		{"8 cœurs sans circuit", testProfile(8, nil, []capacity.EncoderCandidate{x264}), maxAudioRenditions},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := audioRenditionLimit(tt.profile); got != tt.want {
				t.Errorf("%d pistes, attendu %d", got, tt.want)
			}
		})
	}
}

func TestSelectAudioRenditions_ChosenAndOriginalOnASmallMachine(t *testing.T) {
	marked := func(langs []string, original, def int) *ProbeResult {
		p := audioProbe(langs...)
		if original >= 0 {
			p.Audio[original].Original = true
		}
		if def >= 0 {
			p.Audio[def].Default = true
		}
		return p
	}
	tests := []struct {
		name      string
		probe     *ProbeResult
		requested int
		want      []int
	}{
		{"la VO marquée originale", marked([]string{"fra", "eng", "deu", "jpn"}, 3, 0), 0, []int{0, 3}},
		{"sans originale, celle par défaut", marked([]string{"fra", "eng", "deu"}, -1, 1), 2, []int{1, 2}},
		{"ni l'une ni l'autre : la première", marked([]string{"fra", "eng", "deu"}, -1, -1), 2, []int{0, 2}},
		{"la VO choisie : elle et la première", marked([]string{"fra", "eng", "deu"}, 2, -1), 2, []int{0, 2}},
		{"deux pistes en tout : les deux", marked([]string{"fra", "eng"}, -1, -1), 1, []int{0, 1}},
		{"une piste demandée hors limites : la première", marked([]string{"fra", "eng", "deu"}, 1, -1), 9, []int{0, 1}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := selectAudioRenditions(tt.probe, tt.requested, smallMachineAudioRenditions)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("pistes %v, attendu %v", got, tt.want)
			}
		})
	}
}

func TestSelectAudioRenditions_BigMachineKeepsTheOriginalPastTheCap(t *testing.T) {
	langs := make([]string, maxAudioRenditions+3)
	for i := range langs {
		langs[i] = "und"
	}
	probe := audioProbe(langs...)
	probe.Audio[len(langs)-1].Original = true
	got := SelectAudioRenditions(probe, 0)
	if len(got) != maxAudioRenditions || got[len(got)-1] != len(langs)-1 {
		t.Errorf("pistes %v : la VO reste publiée au-delà du plafond", got)
	}
}
