package streaming

import (
	"project-player/server/streaming/capacity"
)

// La recette d'une session, dans /start.
//
// Extrait de handler.go, qui approche la limite de 800 lignes (ADR-0052).
// Quand le profil matériel est prêt, le planificateur choisit la recette de
// chaque session qui réencode l'image ; sinon, les options gardent l'encodeur
// et la chaîne choisis au démarrage, comme avant le profil.

// planPipeline remplit les options avec la recette du planificateur, sous la
// charge load (les réservations des autres sessions, admission.go). ok est
// faux quand rien n'est planifié : pas de profil, une recopie, ou aucun
// encodeur du profil pour ce travail ; les options restent alors celles
// d'avant le profil.
func planPipeline(options TranscodeOptions, profile *capacity.Profile, load capacity.Load) (TranscodeOptions, bool) {
	if profile == nil || options.Video.Copy {
		return options, false
	}
	pipe, ok := capacity.PlanPipeline(jobFor(options), profile, load)
	if !ok {
		return options, false
	}
	return options.withPipeline(pipe), true
}

// jobFor décrit au planificateur ce que la session fait de l'image.
func jobFor(o TranscodeOptions) capacity.Job {
	tier := presetFor(o.Quality)
	job := capacity.Job{
		Target:  capacity.Target{Width: tier.W, Height: tier.H, Preset: encoderPresetFor(tier)},
		ToneMap: o.Video.Tonemap,
		KeepHDR: o.Video.HEVC,
		// Ce qui travaille sur des images logicielles avant la mise à
		// l'échelle garde la chaîne logicielle (usesHardwareFilters).
		SoftwareOnly: o.Video.Deinterlace || (o.BurnSubtitle && o.BurnSubtitleTypedIndex >= 0),
	}
	if o.Probe != nil && o.Probe.Video != nil {
		v := o.Probe.Video
		job.Source = capacity.Source{
			Width: v.Width, Height: v.Height, FPS: v.FrameRate,
			Codec: canonicalVideoCodec(v.Codec), BitDepth: v.DepthOrDefault(),
			DV5: needsDolbyVisionDecoder(v),
		}
	}
	return job
}

// withPipeline rend la recette dans les champs que le rendu lit : l'encodeur
// (ou l'encodeur HEVC d'une image qui garde son HDR), la chaîne sur le
// circuit, et la recette elle-même pour le preset et les threads.
//
// Les champs Encoder, HEVCEncoder et HardwareFilters restent, plutôt que de
// laisser place au seul Pipeline : les tests de la chaîne VAAPI et des
// encodeurs les remplissent directement, et les garder tels quels est la
// preuve qu'ils ne sont pas affaiblis. Le pipeline les alimente.
func (o TranscodeOptions) withPipeline(p capacity.Pipeline) TranscodeOptions {
	enc, ok := encoderByName(p.Encoder)
	if !ok {
		return o
	}
	if o.Video.HEVC {
		o.HEVCEncoder = enc
	} else {
		o.Encoder = enc
	}
	o.HardwareFilters = enc.surface != "" && p.Decode == enc.surface
	o.Pipeline = &p
	return o
}

// availableHEVCEncoder dit si ce serveur sait garder le HDR en HEVC, et avec
// quel encodeur tant que le planificateur n'a pas choisi : celui qui suit
// VIDEO_ENCODER avant le profil, le premier candidat HEVC après.
func availableHEVCEncoder() (VideoEncoder, bool) {
	if profile := capacityProfile(); profile != nil {
		for _, c := range profile.Candidates("hevc") {
			if enc, ok := encoderByName(c.Name); ok {
				return enc, true
			}
		}
		return VideoEncoder{}, false
	}
	return SelectedHEVCEncoder()
}
