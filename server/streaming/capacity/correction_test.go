package capacity

import (
	"context"
	"errors"
	"math"
	"path/filepath"
	"testing"
	"time"

	"project-player/server/streaming/capacity/bench"
)

// La correction apprise des sessions (correction.go).

// fourCores est la machine de fytroz sans circuit : 4 cœurs, les coûts de
// référence.
func fourCores() *Profile {
	return machine(4, cpuCosts(0.0025, 0.0082, 0.00085, 0.0153, 0.0177, 0.0106, 0.006), []EncoderCandidate{x264})
}

// observed est une session de 3 cœurs prévue, sans charge.
func observed(class string, speed, cpu float64) Observation {
	return Observation{Class: class, Cost: Cost{CPU: 3}, Correction: 1, Speed: speed, CPU: cpu, At: time.Unix(1, 0)}
}

func TestObservation_Ratio(t *testing.T) {
	p := fourCores() // 3 cœurs sur 4 : prévue à 1,33×
	for _, tt := range []struct {
		name   string
		obs    Observation
		want   float64
		wantOK bool
	}{
		{"vitesse deux fois plus lente que prévu", observed("c", 4.0/3/2, 0), 2, true},
		{"CPU 1,2 fois le banc", observed("c", 0, 3.6), 1.2, true},
		{"les deux : le plus prudent", observed("c", 4.0/3/1.5, 3.3), 1.5, true},
		{"une session aberrante est bornée", observed("c", 0.01, 0), SampleMax, true},
		{"plus rapide que prévu : borné en bas", observed("c", 100, 0.3), SampleMin, true},
		{"sans rien de mesuré", observed("c", 0, 0), 0, false},
		{"sans classe", observed("", 0.5, 3), 0, false},
		{
			"le coût déjà corrigé est ramené au banc",
			Observation{Class: "c", Cost: Cost{CPU: 3.6}, Correction: 1.2, CPU: 3.6}, 1.2, true,
		},
		{
			"une recette du circuit : son temps CPU ne dit rien",
			Observation{Class: "c", Cost: Cost{CPU: 0.1, Encode: 0.5}, Correction: 1, CPU: 0.4}, 0, false,
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := tt.obs.Ratio(p)
			if ok != tt.wantOK || math.Abs(got-tt.want) > 1e-9 {
				t.Errorf("(%v, %v), attendu (%v, %v)", got, ok, tt.want, tt.wantOK)
			}
		})
	}
}

// Au-delà de 4× prévu, la vitesse réelle bute sur autre chose que les cœurs.
func TestObservation_SpeedFarAbovePlaybackSaysNothing(t *testing.T) {
	light := Observation{Class: "c", Cost: Cost{CPU: 0.2}, Correction: 1, Speed: 5}
	if _, ok := light.Ratio(fourCores()); ok {
		t.Error("un 360p prévu à 20× et vu à 5× a corrigé le profil")
	}
}

func TestObserve_EWMAAndItsBounds(t *testing.T) {
	p := fourCores()
	// Une session deux fois plus lente : un quart du chemin.
	next, ratio, ok := p.Observe(observed("c", 4.0/3/2, 0))
	if !ok || ratio != 2 || next.CorrectionFor("c") != 1.25 || next.Corrections["c"].Samples != 1 {
		t.Fatalf("après une session : %+v (rapport %v)", next.Corrections["c"], ratio)
	}
	// Le profil d'avant n'a pas bougé : il ne change jamais en place.
	if p.CorrectionFor("c") != 1 || len(p.Corrections) != 0 {
		t.Error("le profil publié a été modifié en place")
	}
	// Une session aberrante seule ne fait pas basculer une classe neutre.
	wild, _, _ := p.Observe(observed("c", 0.001, 0))
	if got := wild.CorrectionFor("c"); got != 1+CorrectionAlpha*(SampleMax-1) {
		t.Errorf("une session aberrante : ×%v", got)
	}
	// Beaucoup de sessions concordantes : la correction converge, bornée.
	for i := 0; i < 50; i++ {
		next, _, _ = next.Observe(observed("c", 0.001, 0))
	}
	if got := next.CorrectionFor("c"); math.Abs(got-SampleMax) > 0.01 || got > CorrectionMax {
		t.Errorf("après cinquante sessions lentes : ×%v", got)
	}
	for i := 0; i < 50; i++ {
		next, _, _ = next.Observe(observed("c", 100, 0))
	}
	if got := next.CorrectionFor("c"); math.Abs(got-SampleMin) > 0.01 || got < CorrectionMin {
		t.Errorf("après cinquante sessions rapides : ×%v", got)
	}
	// Une autre classe n'est pas touchée.
	if next.CorrectionFor("autre") != 1 {
		t.Error("la correction a débordé sur une autre classe")
	}
}

// Le planificateur multiplie les coûts de la classe, et le dit.
func TestPlanPipeline_AppliesTheClassCorrection(t *testing.T) {
	p := fourCores()
	job := Job{Source: Source{Width: 3840, Height: 2160, FPS: 24, Codec: "hevc", BitDepth: 10},
		Target: Target{Width: 1920, Height: 1080, Preset: "veryfast"}, ToneMap: true}
	before, _ := PlanPipeline(job, p, Load{})
	if before.Correction != 1 || before.Class != "hevc10/cpu|1080p|zscale|libx264" {
		t.Fatalf("recette neutre : classe %q, ×%v", before.Class, before.Correction)
	}
	p.Corrections = map[string]Correction{before.Class: {Factor: 1.5, Samples: 4}}
	after, _ := PlanPipeline(job, p, Load{})
	if after.Correction != 1.5 || after.Speed >= before.Speed {
		t.Errorf("corrigée : ×%v, %.2f× (avant %.2f×)", after.Correction, after.Speed, before.Speed)
	}
	// Le facteur d'un fichier lent s'ajoute à celui de la classe.
	job.Slowdown = 2
	slow, _ := PlanPipeline(job, p, Load{})
	if slow.Slowdown != 2 || slow.Speed >= after.Speed {
		t.Errorf("fichier lent : ×%v, %.2f×", slow.Slowdown, slow.Speed)
	}
}

func TestRecipeClass(t *testing.T) {
	for _, tt := range []struct {
		pipe     Pipeline
		heavy    bool
		height   int
		software bool
		want     string
	}{
		{Pipeline{Decode: "cpu", ToneMap: ToneMapZscale, Encoder: "libx264", Preset: "veryfast"}, true, 1080, false, "hevc10/cpu|1080p|zscale|libx264"},
		{Pipeline{Decode: "cpu", ToneMap: ToneMapZscale, Encoder: "libx264", Preset: "ultrafast"}, true, 1080, false, "hevc10/cpu|1080p|zscale|libx264"},
		{Pipeline{Decode: "vaapi", Encoder: "h264_vaapi"}, false, 720, false, "h264/vaapi|720p|aucun|h264_vaapi"},
		{Pipeline{Decode: "cpu", ToneMap: ToneMapLibplacebo, ToneMapOnGPU: true, Encoder: "libx264"}, true, 804, false, "hevc10/cpu|1080p|libplacebo@gpu|libx264"},
		{Pipeline{Decode: "cpu", Encoder: "libx264"}, false, 2160, true, "h264/cpu|2160p|aucun|libx264|filtres"},
		{Pipeline{Decode: "cpu", Encoder: "libx264"}, false, 360, false, "h264/cpu|sd|aucun|libx264"},
	} {
		if got := recipeClass(tt.pipe, tt.heavy, tt.height, tt.software); got != tt.want {
			t.Errorf("%q, attendu %q", got, tt.want)
		}
	}
}

// La correction est écrite avec le profil, et repart de zéro avec une
// remesure ou une autre empreinte.
func TestCorrections_PersistedAndResetByRemeasure(t *testing.T) {
	path := filepath.Join(t.TempDir(), CacheFileName)
	fp := Fingerprint{Version: ProfileVersion, CPUModel: "i7", Cores: 4}
	p := fourCores()
	p.Fingerprint = fp
	p, _, _ = p.Observe(observed("c", 4.0/3/2, 0))
	if err := SaveProfile(path, p); err != nil {
		t.Fatal(err)
	}
	cached, err := LoadProfile(path, fp)
	if err != nil {
		t.Fatal(err)
	}
	if got := cached.CorrectionFor("c"); got != 1.25 || cached.Corrections["c"].Samples != 1 {
		t.Errorf("relue du cache : %+v", cached.Corrections)
	}

	other := fp
	other.Cores = 8
	if _, err := LoadProfile(path, other); !errors.Is(err, ErrStale) {
		t.Errorf("une autre machine relit les corrections de celle-ci : %v", err)
	}

	// Une remesure (Build, fresh) construit un profil neuf : sans correction.
	reg := NewRegistry()
	profiler := &Profiler{
		Path: path, Registry: reg,
		Describe: func(Inventory, []TrialResult) ([]EncoderCandidate, BenchInput) { return nil, BenchInput{} },
		Measure: func(context.Context, []string) (bench.Result, error) {
			return bench.Result{}, errors.New("pas de FFmpeg dans ce test")
		},
	}
	fresh, err := profiler.Build(context.Background(), Inventory{Cores: 4}, fp, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(fresh.Corrections) != 0 {
		t.Errorf("une remesure garde %+v", fresh.Corrections)
	}
	reread, _ := LoadProfile(path, fp)
	if len(reread.Corrections) != 0 {
		t.Errorf("le cache garde %+v après la remesure", reread.Corrections)
	}
}

func TestWithdraw_KeepsEveryReason(t *testing.T) {
	reg := NewRegistry()
	reg.Record(TrialResult{Name: TrialVulkan, Works: true, Choice: "vulkan:1", GPU: true})
	at := time.Unix(10, 0)
	ok := reg.Withdraw(TrialVulkan, "vulkan:1", "frame 0\nvkQueueSubmit failed\n", at, func(r *TrialResult, _ string) bool {
		r.GPU = false
		return true
	})
	if !ok {
		t.Fatal("retrait refusé")
	}
	got, _ := reg.Result(TrialVulkan)
	if got.GPU || len(got.Withdrawals) != 1 || got.Withdrawals[0].Reason != "vkQueueSubmit failed" || !got.Withdrawals[0].At.Equal(at) {
		t.Errorf("après le retrait : %+v", got)
	}
	if !got.Usable() {
		t.Error("le retour au rendu logiciel ne rend pas l'essai inutilisable")
	}
	if reg.Withdraw("inconnu", "x", "y", at, func(*TrialResult, string) bool { return true }) {
		t.Error("retrait d'un essai sans verdict")
	}
	if reg.Withdraw(TrialVulkan, "x", "y", at, func(*TrialResult, string) bool { return false }) {
		t.Error("un retrait déjà fait compte deux fois")
	}
}
