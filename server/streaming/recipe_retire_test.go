package streaming

import (
	"testing"
	"time"

	"project-player/server/streaming/capacity"
)

// Le retrait unifié des recettes qui tuent leurs sessions (recipe_retire.go).
// Les tests de fytroz (hardware_filters_test.go, vulkan_device_test.go) et
// ceux du profil (capacity_profile_test.go) passent par les mêmes fonctions,
// inchangés.

func withTrials(t *testing.T, trials ...capacity.TrialResult) {
	t.Helper()
	saved := capacityTrials.Results()
	t.Cleanup(func() { capacityTrials.Restore(saved) })
	capacityTrials.Restore(trials)
	setProfileForTest(t, &capacity.Profile{Trials: trials, Encoders: []capacity.EncoderCandidate{
		candidateOf(softwareEncoder), {Name: "h264_vaapi", Codec: "h264", Hardware: true, Surface: "vaapi"},
	}})
}

func TestRecipeAtFault_TheMostPreciseRecipe(t *testing.T) {
	for _, tt := range []struct {
		name        string
		session     *TranscodeSession
		wantKind    recipeKind
		wantEncoder string
	}{
		{"la chaîne VAAPI d'abord", &TranscodeSession{hardwareFilters: true, vulkanGPU: true, hardwareEncoder: "h264_vaapi"}, recipeHardwareFilters, ""},
		{"puis libplacebo sur le circuit", &TranscodeSession{vulkanGPU: true, hardwareEncoder: "h264_nvenc"}, recipeVulkanGPU, ""},
		{"l'encodeur seul", &TranscodeSession{hardwareEncoder: "h264_vaapi"}, recipeHardwareEncoder, "h264_vaapi"},
		{"une session logicielle ne condamne rien", &TranscodeSession{}, recipeNone, ""},
	} {
		t.Run(tt.name, func(t *testing.T) {
			kind, encoder := tt.session.recipeAtFault()
			if kind != tt.wantKind || encoder != tt.wantEncoder {
				t.Errorf("(%v, %q), attendu (%v, %q)", kind, encoder, tt.wantKind, tt.wantEncoder)
			}
		})
	}
}

// Chaque retrait garde sa raison dans le profil, lisible pour la page
// d'administration, et ne se fait qu'une fois.
func TestRetireRecipe_KeepsTheReasonInTheProfile(t *testing.T) {
	resetHardwareFiltersOff(t)
	resetVulkanChoice(t)
	filters := capacity.TrialResult{Name: capacity.TrialFiltersPrefix + "vaapi", Works: true, Choice: "vaapi"}
	vulkan := capacity.TrialResult{Name: capacity.TrialVulkan, Works: true, Choice: "vulkan:1", GPU: true, Fallback: "vulkan:0"}
	withTrials(t, filters, vulkan)
	vulkanChosen.Store(&vulkanChoice{Spec: "vulkan:1", GPU: true, Fallback: "vulkan:0"})

	if !retireRecipe(recipeHardwareFilters, "", "s1", "frame=0\n[hwupload] Failed to upload frame\n") {
		t.Fatal("chaîne VAAPI non retirée")
	}
	if retireRecipe(recipeHardwareFilters, "", "s2", "encore") {
		t.Error("retirée deux fois")
	}
	if !retireRecipe(recipeVulkanGPU, "", "s3", "vkQueueSubmit failed") {
		t.Fatal("libplacebo sur le circuit non retiré")
	}

	withdrawn := capacityProfile().Withdrawn()
	if got := withdrawn[filters.Name]; len(got) != 1 || got[0].Reason != "[hwupload] Failed to upload frame" || got[0].At.IsZero() {
		t.Errorf("retrait de la chaîne : %+v", got)
	}
	if got := withdrawn[capacity.TrialVulkan]; len(got) != 1 || got[0].Recipe != "vulkan:1" || got[0].Reason != "vkQueueSubmit failed" {
		t.Errorf("retrait du circuit Vulkan : %+v", got)
	}
	// Le comportement de fytroz : la chaîne coupée, libplacebo en logiciel.
	if !hardwareFiltersOff.Load() || vulkanOnGPU() {
		t.Error("les bascules en mémoire n'ont pas suivi")
	}
	if usable, gpu := capacityProfile().Libplacebo(); !usable || gpu {
		t.Errorf("libplacebo après le retrait : usable=%v gpu=%v", usable, gpu)
	}
}

// Un encodeur du circuit choisi par la mesure sort des candidats ; un
// encodeur forcé par VIDEO_ENCODER n'a pas d'essai à son nom et reste.
func TestRetireRecipe_HardwareEncoderOnlyWhenMeasured(t *testing.T) {
	measured := capacity.TrialResult{Name: capacity.TrialEncoderPrefix + "h264_vaapi", Works: true, Choice: "h264_vaapi", GPU: true}
	withTrials(t, measured)
	if len(capacityProfile().Candidates("h264")) != 2 {
		t.Fatalf("candidats : %+v", capacityProfile().Candidates("h264"))
	}
	if !retireRecipe(recipeHardwareEncoder, "h264_vaapi", "s", "[h264_vaapi] Failed to initialise") {
		t.Fatal("encodeur mesuré non retiré")
	}
	if got := names(capacityProfile().Candidates("h264")); !equalStrings(got, []string{"libx264"}) {
		t.Errorf("candidats après le retrait : %v", got)
	}

	forced := capacity.TrialResult{Name: capacity.TrialSelectedEncoder, Works: true, Choice: "h264_vaapi", Forced: "VIDEO_ENCODER=h264_vaapi"}
	withTrials(t, forced)
	if retireRecipe(recipeHardwareEncoder, "h264_vaapi", "s", "x") {
		t.Error("un encodeur forcé par l'opérateur a été retiré")
	}
}

// La mort d'une session passe par le retrait unifié : watch nomme la recette
// fautive et la retire.
func TestWatch_RetiresTheMeasuredHardwareEncoder(t *testing.T) {
	measured := capacity.TrialResult{Name: capacity.TrialEncoderPrefix + "h264_vaapi", Works: true, Choice: "h264_vaapi", GPU: true}
	withTrials(t, measured)
	session := failingSession(t)
	session.hardwareEncoder = "h264_vaapi"
	session.watch()
	if got, _ := capacityProfile().Trial(measured.Name); got.Usable() || len(got.Withdrawals) != 1 {
		t.Errorf("après la mort de la session : %+v", got)
	}
}

func TestWithdrawalsSurviveTheCache(t *testing.T) {
	path := t.TempDir() + "/" + capacity.CacheFileName
	p := &capacity.Profile{Trials: []capacity.TrialResult{{
		Name: "filters/vaapi", Works: true, Retired: "x",
		Withdrawals: []capacity.Withdrawal{{Recipe: "filters/vaapi", Reason: "x", At: time.Unix(1, 0).UTC()}},
	}}}
	if err := capacity.SaveProfile(path, p); err != nil {
		t.Fatal(err)
	}
	got, err := capacity.LoadProfile(path, p.Fingerprint)
	if err != nil {
		t.Fatal(err)
	}
	if w := got.Withdrawn()["filters/vaapi"]; len(w) != 1 || w[0].Reason != "x" {
		t.Errorf("relu du cache : %+v", w)
	}
}
