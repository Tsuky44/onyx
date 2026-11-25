package streaming

import (
	"testing"

	"project-player/server/streaming/capacity"
)

// Décision §0.1 : sans VIDEO_ENCODER, chaque encodeur qui a passé son essai
// est candidat, libx264 toujours. Avec, seul l'encodeur forcé l'est, libx264
// en repli.
func TestEncoderCandidates_MeasuredOrForced(t *testing.T) {
	verdicts := map[string]capacity.TrialResult{
		capacity.TrialSelectedEncoder:                     {Works: true, Choice: "libx264"},
		capacity.TrialEncoderPrefix + "libx264":           {Works: true},
		capacity.TrialEncoderPrefix + "libx265":           {Works: true},
		capacity.TrialEncoderPrefix + "h264_vaapi":        {Works: true},
		capacity.TrialEncoderPrefix + "hevc_vaapi":        {Works: false},
		capacity.TrialEncoderPrefix + "h264_videotoolbox": {Works: false},
	}
	got := names(encoderCandidates(verdicts, false))
	if want := []string{"libx264", "h264_vaapi", "libx265"}; !equalStrings(got, want) {
		t.Errorf("mesurés : %v, voulu %v", got, want)
	}

	verdicts[capacity.TrialSelectedEncoder] = capacity.TrialResult{Works: true, Choice: "h264_vaapi"}
	verdicts[capacity.TrialSelectedHEVC] = capacity.TrialResult{Works: true, Choice: "hevc_vaapi"}
	forced := encoderCandidates(verdicts, true)
	if got := names(forced); !equalStrings(got, []string{"h264_vaapi", "libx264", "hevc_vaapi"}) {
		t.Errorf("forcés : %v", got)
	}
	if !forced[1].Fallback || forced[0].Fallback {
		t.Errorf("libx264 doit être le repli de l'encodeur forcé : %+v", forced)
	}
	if !forced[0].Upload || forced[0].Surface != "vaapi" {
		t.Errorf("h264_vaapi mal décrit : %+v", forced[0])
	}
}

func names(c []capacity.EncoderCandidate) []string {
	var out []string
	for _, e := range c {
		out = append(out, e.Name)
	}
	return out
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// Tout encodeur que le profil peut nommer se retrouve, HEVC du circuit
// compris, avec son périphérique et ses réglages de débit.
func TestEncoderByName_KnowsEveryCandidate(t *testing.T) {
	for _, name := range []string{"libx264", "libx265", "h264_vaapi", "hevc_vaapi", "h264_nvenc", "hevc_nvenc", "h264_qsv", "h264_videotoolbox"} {
		enc, ok := encoderByName(name)
		if !ok || enc.Name != name || enc.rateControl == nil {
			t.Errorf("%s : %+v", name, enc.Name)
		}
	}
	if hevc, _ := encoderByName("hevc_vaapi"); len(hevc.deviceArgs) == 0 {
		t.Error("hevc_vaapi sans le périphérique de son H.264")
	}
	if _, ok := encoderByName("libsvtav1"); ok {
		t.Error("un encodeur inconnu a été trouvé")
	}
}

// Une session morte avec la chaîne sur le circuit la retire aussi du profil
// publié : le planificateur ne la propose plus.
func TestHardwareFiltersDyingRetiresThemFromTheProfile(t *testing.T) {
	resetHardwareFiltersOff(t)
	saved := capacityTrials.Results()
	t.Cleanup(func() { capacityTrials.Restore(saved) })
	filters := capacity.TrialResult{Name: capacity.TrialFiltersPrefix + "vaapi", Works: true, Choice: "vaapi"}
	capacityTrials.Restore([]capacity.TrialResult{filters})
	setProfileForTest(t, &capacity.Profile{Trials: []capacity.TrialResult{filters}})

	noteHardwareSessionDied("s", "[hwupload] Failed to upload frame\n")

	profile := capacityProfile()
	if profile.HardwareFilters("vaapi") {
		t.Error("la chaîne retirée est encore proposée")
	}
	if got, _ := profile.Trial(filters.Name); got.Retired != "[hwupload] Failed to upload frame" {
		t.Errorf("raison du retrait : %q", got.Retired)
	}
}

// Une session morte sur le Vulkan du circuit ramène le profil au rendu
// logiciel, comme les sessions.
func TestVulkanDyingMovesTheProfileToSoftware(t *testing.T) {
	resetVulkanChoice(t)
	saved := capacityTrials.Results()
	t.Cleanup(func() { capacityTrials.Restore(saved) })
	vulkan := capacity.TrialResult{Name: capacity.TrialVulkan, Works: true, Choice: "vulkan:1", GPU: true, Fallback: "vulkan:0"}
	capacityTrials.Restore([]capacity.TrialResult{vulkan})
	setProfileForTest(t, &capacity.Profile{Trials: []capacity.TrialResult{vulkan}})
	vulkanChosen.Store(&vulkanChoice{Spec: "vulkan:1", GPU: true, Fallback: "vulkan:0"})

	noteVulkanSessionDied("s", "vkQueueSubmit failed")

	usable, gpu := capacityProfile().Libplacebo()
	got, _ := capacityProfile().Trial(capacity.TrialVulkan)
	if !usable || gpu || got.Choice != "vulkan:0" {
		t.Errorf("profil après la mort sur le circuit : %+v", got)
	}
	if choice, ok := vulkanChoiceOf(capacityProfile()); !ok || choice.GPU || choice.Spec != "vulkan:0" {
		t.Errorf("un démarrage avec ce cache reprendrait %+v", choice)
	}
}

// Les encodeurs à essayer sans VIDEO_ENCODER : rien de ce que ce FFmpeg ne
// connaît pas, ni ce dont le périphérique manque.
func TestMeasuredEncoders_OnlyWhatCanRun(t *testing.T) {
	inv := capacity.Inventory{
		RenderNodes: []string{"/dev/dri/renderD128"},
		FFmpeg: capacity.FFmpegInventory{Encoders: []string{
			"h264_nvenc", "h264_vaapi", "hevc_vaapi", "libx264", "libx265",
		}},
	}
	got := map[string]bool{}
	for _, enc := range measuredEncoders(inv) {
		got[enc.Name] = true
	}
	for _, want := range []string{"libx264", "libx265", "h264_vaapi", "hevc_vaapi"} {
		if !got[want] {
			t.Errorf("%s n'est pas essayé", want)
		}
	}
	if got["h264_nvenc"] {
		t.Error("h264_nvenc essayé sans /dev/nvidia*")
	}
	if got["h264_qsv"] {
		t.Error("h264_qsv essayé alors que ce FFmpeg ne l'a pas")
	}
}

// availableHEVCEncoder suit le profil prêt : sans candidat HEVC, le HDR est
// tone mappé.
func TestAvailableHEVCEncoder_FollowsTheProfile(t *testing.T) {
	setProfileForTest(t, &capacity.Profile{Encoders: []capacity.EncoderCandidate{candidateOf(softwareEncoder)}})
	if _, ok := availableHEVCEncoder(); ok {
		t.Error("un profil sans HEVC a rendu un encodeur HEVC")
	}
	setProfileForTest(t, &capacity.Profile{Encoders: []capacity.EncoderCandidate{candidateOf(softwareHEVCEncoder)}})
	if enc, ok := availableHEVCEncoder(); !ok || enc.Name != "libx265" {
		t.Errorf("HEVC du profil : %v %v", enc.Name, ok)
	}
}

// Un démarrage avec un cache reprend les choix de démarrage sans essai :
// l'encodeur forcé, la chaîne VAAPI tant qu'elle n'est pas retirée, et le
// périphérique Vulkan de la course.
func TestChoicesFromProfile_RestoreTheStartupChoices(t *testing.T) {
	profile := &capacity.Profile{Trials: []capacity.TrialResult{
		{Name: capacity.TrialSelectedEncoder, Works: true, Choice: "h264_vaapi", Forced: "VIDEO_ENCODER=h264_vaapi"},
		{Name: capacity.TrialSelectedHEVC, Works: true, Choice: "hevc_vaapi"},
		{Name: capacity.TrialFiltersPrefix + "vaapi", Works: true, Choice: "vaapi"},
		{Name: capacity.TrialVulkan, Works: true, Choice: "vulkan:1", GPU: true, Fallback: "vulkan:0"},
	}}
	c := choicesFromProfile(profile)
	if c.encoder.Name != "h264_vaapi" || !c.hevcOK || c.hevc.Name != "hevc_vaapi" || !c.hardwareFilter || !c.libplacebo {
		t.Errorf("choix relus : %+v", c)
	}
	if c.vulkan == nil || *c.vulkan != (vulkanChoice{Spec: "vulkan:1", GPU: true, Fallback: "vulkan:0"}) {
		t.Errorf("Vulkan relu : %+v", c.vulkan)
	}

	profile.Trials[2].Retired = "session morte"
	if choicesFromProfile(profile).hardwareFilter {
		t.Error("une chaîne retirée revient au démarrage suivant")
	}

	empty := choicesFromProfile(&capacity.Profile{})
	if empty.encoder.Name != "libx264" || empty.hevcKnown || empty.hardwareFilter || empty.libplacebo || empty.vulkan != nil {
		t.Errorf("profil vide : %+v", empty)
	}
}
