package streaming

import (
	"log"
	"sort"
	"strings"
	"sync"

	"project-player/server/safego"
	"project-player/server/streaming/capacity"
)

// Ce que streaming dit au profil de ses encodeurs, et ce qu'il en reprend
// quand une session meurt.

// describeCapacity dit au profileur, d'après les verdicts des essais, quels
// encodeurs sont candidats et quoi mesurer. Le banc reçoit les filtres et les
// encodeurs des sessions, pour mesurer ce qu'elles lancent vraiment.
func describeCapacity(_ capacity.Inventory, results []capacity.TrialResult) ([]capacity.EncoderCandidate, capacity.BenchInput) {
	verdicts := map[string]capacity.TrialResult{}
	for _, r := range results {
		verdicts[r.Name] = r
	}
	encoders := encoderCandidates(verdicts, forcedValue("VIDEO_ENCODER") != "")

	input := capacity.BenchInput{
		ScaleFilter: buildScaleFilter(&ProbeResult{Video: &VideoStreamInfo{Width: 1920, Height: 1080}},
			qualityPreset{W: 1280, H: 720}),
		ZscaleFilter: hdrToSDRFilter(),
		X264Presets:  capacity.X264Presets,
	}
	if v := verdicts[capacity.TrialVulkan]; v.Works && v.Choice != "" {
		input.Libplacebo = &capacity.LibplaceboBench{
			InitArgs: []string{"-init_hw_device", v.Choice}, Filter: doviToSDRFilter, GPU: v.GPU,
		}
	}
	for _, c := range encoders {
		enc, ok := encoderByName(c.Name)
		if !c.Hardware || !ok {
			continue
		}
		input.Hardware = append(input.Hardware, capacity.EncoderBench{
			Candidate: c, DeviceArgs: enc.deviceArgs, Upload: enc.uploadFilter, PixFmt: enc.PixelFormat,
		})
		if c.Surface == "vaapi" {
			input.VAAPIDevice = vaapiDevice()
		}
	}
	return encoders, input
}

// encoderCandidates rend les encodeurs que le planificateur peut prendre.
//
// Forcé (VIDEO_ENCODER posé) : l'encodeur retenu et son HEVC, comme avant le
// profil, plus libx264 en repli pour ce que l'encodeur forcé ne sait pas
// faire (un profil 5 tone mappé par libplacebo avec h264_vaapi, voir
// TranscodeOptions.encoder()). Mesuré : libx264, le défaut de toujours, et
// chaque encodeur qui a passé son essai.
func encoderCandidates(verdicts map[string]capacity.TrialResult, forced bool) []capacity.EncoderCandidate {
	if forced {
		selected := softwareEncoder
		if enc, ok := encoderByName(verdicts[capacity.TrialSelectedEncoder].Choice); ok {
			selected = enc
		}
		out := []capacity.EncoderCandidate{candidateOf(selected)}
		if selected.Name != softwareEncoder.Name {
			fallback := candidateOf(softwareEncoder)
			fallback.Fallback = true
			out = append(out, fallback)
		}
		if hevc := verdicts[capacity.TrialSelectedHEVC]; hevc.Works {
			if enc, ok := encoderByName(hevc.Choice); ok {
				out = append(out, candidateOf(enc))
			}
		}
		return out
	}

	out := []capacity.EncoderCandidate{candidateOf(softwareEncoder)}
	for name, verdict := range verdicts {
		if !strings.HasPrefix(name, capacity.TrialEncoderPrefix) || !verdict.Works {
			continue
		}
		enc, ok := encoderByName(strings.TrimPrefix(name, capacity.TrialEncoderPrefix))
		if !ok || enc.Name == softwareEncoder.Name {
			continue
		}
		out = append(out, candidateOf(enc))
	}
	// Un ordre stable, pour un cache et un journal qui ne bougent pas d'un
	// démarrage à l'autre.
	rest := out[1:]
	sort.Slice(rest, func(i, j int) bool { return rest[i].Name < rest[j].Name })
	return out
}

// candidateOf décrit un encodeur au planificateur.
func candidateOf(enc VideoEncoder) capacity.EncoderCandidate {
	codec := "h264"
	if enc.isHEVC() {
		codec = "hevc"
	}
	return capacity.EncoderCandidate{
		Name: enc.Name, Codec: codec, Hardware: enc.Hardware,
		Surface: enc.surface, Upload: enc.uploadFilter != "",
	}
}

// retireHardwareFiltersInProfile retire la chaîne sur le circuit du profil :
// une session est morte avec elle avant son premier segment.
func retireHardwareFiltersInProfile(stderr string) {
	changed := false
	for _, r := range capacityTrials.Results() {
		if strings.HasPrefix(r.Name, capacity.TrialFiltersPrefix) && r.Usable() {
			changed = capacityTrials.Retire(r.Name, stderr) || changed
		}
	}
	if changed {
		publishTrials()
	}
}

// noteVulkanFallbackInProfile ramène libplacebo du profil sur le rendu
// logiciel spec, comme noteVulkanSessionDied l'a fait pour les sessions.
func noteVulkanFallbackInProfile(spec, stderr string) {
	if capacityTrials.Update(capacity.TrialVulkan, func(r *capacity.TrialResult) {
		r.Choice, r.GPU, r.Fallback = spec, false, ""
		r.Retired = ""
		r.Note = "retour au rendu logiciel après une session morte sur le circuit : " + strings.TrimSpace(stderr)
	}) {
		publishTrials()
	}
}

// savingProfile sérialise les écritures du cache.
var savingProfile sync.Mutex

// publishTrials publie le profil avec les verdicts du registre, et l'écrit.
// Sans profil encore prêt, la mesure en cours reprendra les verdicts du
// registre.
func publishTrials() {
	profile := capacityProfile()
	if profile == nil {
		return
	}
	next := profile.WithTrials(capacityTrials.Results())
	currentProfile.Store(next)
	profiler := activeProfiler.Load()
	if profiler == nil {
		return
	}
	go safego.Run("capacity-save", func() {
		savingProfile.Lock()
		defer savingProfile.Unlock()
		if err := capacity.SaveProfile(profiler.Path, next); err != nil {
			log.Printf("Streaming: retrait non écrit dans le profil matériel : %v", err)
		}
	})
}
