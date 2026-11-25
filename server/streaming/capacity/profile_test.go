package capacity

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"
	"time"

	"project-player/server/streaming/capacity/bench"
)

func TestRegistry_RunSkipsKnownVerdictsUnlessFresh(t *testing.T) {
	reg := NewRegistry()
	runs := 0
	reg.Register(Trial{Name: TrialVulkan, Forced: "VULKAN_DEVICE=1", Run: func(context.Context) TrialResult {
		runs++
		return TrialResult{Works: true, Choice: "vulkan:1", GPU: true}
	}})
	reg.Record(TrialResult{Name: TrialVulkan, Works: true, Choice: "vulkan:0"})

	reg.Run(context.Background(), false)
	if runs != 0 {
		t.Fatalf("un verdict déjà connu a été réessayé %d fois", runs)
	}
	reg.Run(context.Background(), true)
	got, _ := reg.Result(TrialVulkan)
	if runs != 1 || got.Choice != "vulkan:1" || got.Forced != "VULKAN_DEVICE=1" || got.Name != TrialVulkan {
		t.Errorf("remesure : %d essais, verdict %+v", runs, got)
	}
}

func TestRegistry_RetireKeepsTheReasonOnce(t *testing.T) {
	reg := NewRegistry()
	reg.Record(TrialResult{Name: "filters/vaapi", Works: true})
	if !reg.Retire("filters/vaapi", "frame 0\n[vaapi] Failed to map frame\n") {
		t.Fatal("retrait refusé")
	}
	if reg.Retire("filters/vaapi", "autre") {
		t.Error("une recette retirée l'a été deux fois")
	}
	got, _ := reg.Result("filters/vaapi")
	if got.Usable() || got.Retired != "[vaapi] Failed to map frame" {
		t.Errorf("verdict après retrait %+v", got)
	}
	if reg.Retire("inconnu", "x") {
		t.Error("retrait d'un essai sans verdict")
	}
}

func TestProfile_CandidatesSkipRetiredEncoders(t *testing.T) {
	p := &Profile{
		Encoders: []EncoderCandidate{x264, vaapiH264, x265},
		Trials:   []TrialResult{{Name: TrialEncoderPrefix + "h264_vaapi", Works: true, Retired: "mort"}},
	}
	got := p.Candidates("h264")
	if len(got) != 1 || got[0].Name != "libx264" {
		t.Errorf("candidats %v", got)
	}
}

// Une étape que le banc n'a pas mesurée prend la référence, ramenée à la
// vitesse des cœurs de la machine par l'étalon x264 veryfast.
func TestProfile_StageCostExtrapolatesFromTheAnchor(t *testing.T) {
	p := &Profile{Costs: []StageCost{{Stage: StageEncode, Variant: "libx264/veryfast", Cost: Cost{CPU: 0.0354}}}}
	got, ok := p.StageCost(StageToneMap, ToneMapZscale, false)
	if !ok || !got.Estimated {
		t.Fatalf("zscale non estimé : %+v", got)
	}
	if want := 0.0153 * 2; diff(got.Cost.CPU, want) > 1e-9 {
		t.Errorf("zscale %.5f, voulu %.5f (machine deux fois plus lente)", got.Cost.CPU, want)
	}
	hw, ok := p.StageCost(StageEncode, "hevc_qsv", true)
	if !ok || hw.Cost.Encode == 0 {
		t.Errorf("un encodeur du circuit inconnu de la table : %+v", hw)
	}
	if _, ok := p.StageCost(StageEncode, "libsvtav1", false); ok {
		t.Error("une variante que rien ne décrit a un coût")
	}
}

func diff(a, b float64) float64 {
	if a > b {
		return a - b
	}
	return b - a
}

func TestFingerprint_ChangesWithTheMachineAndTheForcings(t *testing.T) {
	inv := Inventory{Cores: 4, CPUModel: "N100", RenderNodes: []string{"/dev/dri/renderD128"}, FFmpeg: FFmpegInventory{Version: "7.1"}}
	base := FingerprintOf(inv, "1.4.2", map[string]string{"VIDEO_ENCODER": "", "VULKAN_DEVICE": " "})
	if base.Forcings != nil {
		t.Errorf("forçages vides retenus : %v", base.Forcings)
	}
	if !base.Same(FingerprintOf(inv, "1.4.2", nil)) {
		t.Error("même machine, empreintes différentes")
	}
	changed := []Fingerprint{
		FingerprintOf(inv, "1.4.3", nil),
		FingerprintOf(inv, "1.4.2", map[string]string{"VIDEO_ENCODER": "h264_vaapi"}),
		FingerprintOf(Inventory{Cores: 2, CPUModel: "N100", RenderNodes: inv.RenderNodes, FFmpeg: inv.FFmpeg}, "1.4.2", nil),
		FingerprintOf(Inventory{Cores: 4, CPUModel: "N100", FFmpeg: inv.FFmpeg}, "1.4.2", nil),
	}
	for i, fp := range changed {
		if base.Same(fp) {
			t.Errorf("changement %d invisible dans l'empreinte", i)
		}
	}
}

// Critère 6 : un démarrage avec un cache valide ne relance aucun essai, ni
// aucune mesure ; une machine changée remesure.
func TestProfiler_CachedProfileRunsNothing(t *testing.T) {
	dir := t.TempDir()
	reg := NewRegistry()
	trials := 0
	reg.Register(Trial{Name: TrialVulkan, Run: func(context.Context) TrialResult {
		trials++
		return TrialResult{Works: true, Choice: "vulkan:1", GPU: true}
	}})
	measures := 0
	profiler := &Profiler{
		Path:     filepath.Join(dir, CacheFileName),
		Server:   "test",
		Root:     fstest.MapFS{"proc/cpuinfo": {Data: []byte("model name : Test CPU\n")}},
		Registry: reg,
		Describe: func(Inventory, []TrialResult) ([]EncoderCandidate, BenchInput) {
			return []EncoderCandidate{x264}, BenchInput{X264Presets: []string{"veryfast"}, ScaleFilter: "scale=1280:720"}
		},
		Measure: func(context.Context, []string) (bench.Result, error) {
			measures++
			return bench.Result{CPU: time.Duration(measures) * time.Second, Frames: benchFrames}, nil
		},
	}
	inv, fp := profiler.Inventory(context.Background())
	if _, ok := profiler.Cached(fp); ok {
		t.Fatal("un cache qui n'existe pas a été lu")
	}
	built, err := profiler.Build(context.Background(), inv, fp, false)
	if err != nil || built == nil {
		t.Fatalf("mesure : %v", err)
	}
	if trials != 1 || measures == 0 || len(built.Costs) == 0 {
		t.Fatalf("première mesure : %d essais, %d mesures, %d coûts", trials, measures, len(built.Costs))
	}

	trials, measures = 0, 0
	next := NewRegistry()
	profiler.Registry = next
	cached, ok := profiler.Cached(fp)
	if !ok {
		t.Fatal("le cache écrit n'est pas relu")
	}
	if trials != 0 || measures != 0 {
		t.Errorf("démarrage avec cache : %d essais, %d mesures", trials, measures)
	}
	if v, ok := next.Result(TrialVulkan); !ok || v.Choice != "vulkan:1" {
		t.Errorf("le registre n'a pas repris le verdict du cache : %+v", v)
	}
	if usable, gpu := cached.Libplacebo(); !usable || !gpu {
		t.Error("le profil relu a perdu le choix Vulkan")
	}

	otherFP := FingerprintOf(Inventory{Cores: inv.Cores + 1, CPUModel: inv.CPUModel}, "test", nil)
	if _, err := LoadProfile(profiler.Path, otherFP); !errors.Is(err, ErrStale) {
		t.Errorf("machine changée : %v", err)
	}
}

func TestSaveProfile_IsAtomic(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", CacheFileName)
	if err := SaveProfile(path, &Profile{Fingerprint: Fingerprint{Version: ProfileVersion}}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path + ".tmp"); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("fichier temporaire laissé : %v", err)
	}
	if err := os.WriteFile(path, []byte("{tronqué"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadProfile(path, Fingerprint{Version: ProfileVersion}); err == nil || errors.Is(err, ErrStale) {
		t.Errorf("un cache illisible doit être une erreur à part : %v", err)
	}
}
