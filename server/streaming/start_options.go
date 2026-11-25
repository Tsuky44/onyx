package streaming

import "project-player/server/streaming/capacity"

// Les options d'une session, pour un barreau donné.
//
// Extrait de handleStart (handler.go, près de la limite de 800 lignes,
// ADR-0052) : l'admission (admission.go) essaie plusieurs barreaux pour la
// même demande, et chaque essai refait la décision de recopie et le budget
// audio de son barreau à partir des mêmes entrées.

// startInputs est ce que /start sait de la demande, hors barreau.
type startInputs struct {
	inputPath    string
	probe        *ProbeResult
	burnSubtitle int
	bitrate      int64
	caps         Capabilities
	hevcEncoder  VideoEncoder
	startSeconds int
	audioMap     []int
	subtitles    []int
	// lighter est ce que ce fichier doit prendre de plus léger après une
	// session trop lente (lighter_recipes.go).
	lighter lighterRecipe
}

// optionsFor rend les options de la session au barreau quality, avant toute
// recette : celles d'avant le profil. TmpDir est posé après l'admission, pour
// qu'un refus ne crée aucun dossier.
func (in startInputs) optionsFor(quality string) TranscodeOptions {
	videoPlan := PlanVideo(in.probe, quality, in.burnSubtitle >= 0, in.bitrate, in.caps.CopyCeiling(copyBitrateCeiling()), in.caps)
	return TranscodeOptions{
		InputPath:              in.inputPath,
		Quality:                quality,
		Encoder:                SelectedVideoEncoder(),
		HardwareFilters:        HardwareFiltersUsable(),
		HEVCEncoder:            in.hevcEncoder,
		StartSeconds:           in.startSeconds,
		Probe:                  in.probe,
		SegmentDuration:        segmentDuration,
		AudioTypedIndexes:      in.audioMap,
		BurnSubtitle:           in.burnSubtitle >= 0,
		BurnSubtitleTypedIndex: in.burnSubtitle,
		Video:                  videoPlan,
		AudioBudgetBps:         AudioBudget(quality, videoPlan),
		Caps:                   in.caps,
		LiveSubtitles:          in.subtitles,
		slowdown:               in.lighter.slowdown,
	}
}

// tryRung planifie le barreau quality sous la charge load, avec ce que ce
// fichier doit à une session lente.
func (in startInputs) tryRung(quality string, profile *capacity.Profile, load capacity.Load) rungOption {
	return planRung(in.optionsFor(quality), profile, load, len(in.audioMap))
}

// sourceHeight est la hauteur de l'image source, 0 si la sonde ne la connaît
// pas (QualityLadderFor donne alors toute l'échelle).
func sourceHeight(probe *ProbeResult) int {
	if probe == nil || probe.Video == nil {
		return 0
	}
	return probe.Video.Height
}
