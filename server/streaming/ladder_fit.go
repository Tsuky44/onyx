package streaming

import "project-player/server/streaming/capacity"

// La tenue prévue de chaque barreau du menu (phase 4 du plan
// docs/transcodage-adaptatif.md).
//
// Le menu Qualité reste au spectateur : toute l'échelle reste affichée et
// choisissable, et un barreau choisi est toujours celui qui est livré (§1 du
// plan, ADR-0056 §1). Ce que le serveur sait de sa machine sert seulement à
// prévenir : chaque barreau porte sa tenue prévue, `ok` (au moins 1,5×),
// `limite` (de 1 à 1,5×) ou `trop_lourd` (sous 1×), le vocabulaire du
// planificateur (capacity.Verdict). Le lecteur marquera un barreau
// `trop_lourd` (« peut saccader sur ce serveur ») sans le retirer, et l'Auto
// ouvrira au plus haut barreau `ok`.
//
// La tenue suit ce que /start ferait du barreau, au même endroit
// (startInputs.tryRung) : la décision de recopie avec les capacités que le
// client déclare (les mêmes paramètres que /start), la recette, la charge du
// moment, et ce que ce fichier doit à une session lente. Un barreau recopié ne
// coûte presque rien : il est `ok`. Sans profil prêt, ou pour un barreau
// qu'aucun encodeur du profil ne sait faire, le champ est absent, et le menu
// reste celui d'aujourd'hui.
//
// La charge est celle de toutes les sessions, celles du spectateur comprises :
// /tracks n'a pas de ticket, et le lecteur le lit avant d'ouvrir sa session.

// QualityLadder est le menu d'un fichier, chaque barreau avec sa tenue prévue.
// handlers l'appelle pour /api/media/:id/tracks (handlers.QualityLadder).
func (h *Handler) QualityLadder(mediaID int, inputPath string, probe *ProbeResult, caps Capabilities) []QualityTier {
	ladder := QualityLadderFor(sourceHeight(probe))
	profile := capacityProfile()
	if profile == nil || probe == nil || probe.Video == nil {
		return ladder
	}
	return withFit(ladder, h.ladderInputs(mediaID, inputPath, probe, caps, profile), profile, h.manager.Budget().Load(""))
}

// ladderInputs sont les entrées de /start pour ce fichier, au début du film,
// avec la piste audio par défaut et sans sous-titre incrusté.
func (h *Handler) ladderInputs(mediaID int, inputPath string, probe *ProbeResult, caps Capabilities, profile *capacity.Profile) startInputs {
	var hevcEncoder VideoEncoder
	if caps.EncodeHEVC {
		hevcEncoder, caps.EncodeHEVC = availableHEVCEncoder()
	}
	return startInputs{
		inputPath: inputPath, probe: probe, burnSubtitle: NoBurnedSubtitle, bitrate: h.sourceBitrate(mediaID),
		caps: caps, hevcEncoder: hevcEncoder,
		audioMap: selectAudioRenditions(probe, 0, audioRenditionLimit(profile)),
		lighter:  lighterRecipeFor(mediaID),
	}
}

// withFit pose la tenue de chaque barreau sous la charge load. Aucun barreau
// n'est retiré.
func withFit(ladder []QualityTier, inputs startInputs, profile *capacity.Profile, load capacity.Load) []QualityTier {
	for i := range ladder {
		ladder[i].Fit = rungFit(inputs.tryRung(ladder[i].Key, profile, load))
	}
	return ladder
}

// rungFit est la tenue d'un barreau planifié, vide quand rien ne la prévoit.
func rungFit(option rungOption) capacity.Verdict {
	switch {
	case option.options.Video.Copy:
		return capacity.VerdictOK
	case option.options.Pipeline == nil:
		return ""
	default:
		return capacity.VerdictFor(option.speed)
	}
}
