package streaming

import (
	"time"

	"project-player/server/streaming/capacity"
)

// suggested_quality dans /health (phase 5 du plan docs/transcodage-adaptatif.md).
//
// Le serveur donne une suggestion, le client décide (prolonge l'ADR-0056).
// Aujourd'hui le client voit `encoderBehind` et ne fait rien, à raison :
// descendre en débit ne soulage pas un encodeur. Le serveur, lui, sait quel
// barreau sa machine tient, et le dit :
//
//   - **descente** : la session est sous 1× depuis 20 s. La suggestion est le
//     plus haut barreau qui tient 1,3× (admitSpeed) sous la charge du moment,
//     sans compter la session elle-même, qu'il remplacera. Ce peut être le
//     barreau en cours, quand une recette plus légère y tient (un preset plus
//     rapide, lighter_recipes.go) : rouvrir le même barreau ne change pas ce
//     que le spectateur a choisi, ce qui vaut aussi en manuel ;
//   - **remontée** : de la marge est revenue (une session s'est terminée). La
//     suggestion est le plus haut barreau `ok` (1,5×) au-dessus du barreau en
//     cours, au plus le plafond de la session : le barreau que l'Auto avait
//     demandé avant d'être descendu, ou le barreau en cours s'il ne l'a jamais
//     été. Jamais au-dessus du barreau natif de la source (QualityLadderFor).
//
// L'hystérésis, pour qu'aucune suggestion ne fasse d'allers-retours :
//
//   - deux seuils : on descend sous 1× vu, on ne remonte qu'à 1,5× prévu ;
//   - une remontée attend que la session tourne depuis ascentMinAge (une
//     session ouverte par une descente ne remonte pas aussitôt), puis que le
//     même barreau tienne `ok` sans interruption pendant ascentHold ;
//   - un fichier qui a fait ramer une session garde son facteur
//     (lighter_recipes.go) : le barreau qui a ramé ne redevient `ok` qu'avec
//     bien plus de marge, jusqu'à l'expiration de cette mémoire.
//
// Absente quand il n'y a rien à suggérer, et sans profil prêt.

const (
	// ascentMinAge est l'âge minimum d'une session avant qu'une remontée soit
	// suggérée. Deux fois la fenêtre de la descente : la session ouverte par
	// une descente a eu le temps de montrer qu'elle tient.
	ascentMinAge = 2 * paceWindow
	// ascentHold est la durée pendant laquelle la marge doit tenir avant
	// qu'une remontée soit suggérée : une session voisine qui marque une
	// pause (le bridage, un spectateur en pause) libère des cœurs le temps
	// d'un tic.
	ascentHold = 30 * time.Second
)

// ladderContext est ce qu'une session garde de /start pour suggérer un
// barreau : de quoi replanifier n'importe quel barreau de sa source.
type ladderContext struct {
	inputs startInputs
	// ladder est le menu de la source (QualityLadderFor), du plus exigeant au
	// moins exigeant.
	ladder []string
	// ceiling est le plus haut barreau vers lequel une remontée peut aller.
	ceiling string
}

// suggestionState est l'hystérésis d'une session. Gardé sous s.mu.
type suggestionState struct {
	// roomFor est le barreau qui tient `ok` au-dessus du barreau en cours, et
	// roomSince depuis quand il le tient sans interruption.
	roomFor   string
	roomSince time.Time
	// last est la dernière suggestion donnée : une session ouverte à ce
	// barreau sur le même ticket hérite du plafond (ceilingAfter).
	last string
}

// suggestInput est ce que la décision lit, sans rien savoir des sessions.
type suggestInput struct {
	now     time.Time
	started time.Time
	current string
	ceiling string
	ladder  []string
	// slow dit que la session est sous 1× depuis paceWindow.
	slow bool
	// try planifie un barreau sous la charge du moment, sans la session.
	try func(quality string) rungOption
	// sameRecipe dit qu'une option referait l'image de la session avec sa
	// recette actuelle, à la même hauteur : le barreau en cours, ou un
	// barreau de même résolution à un autre débit. Le coût suit les pixels,
	// pas le débit : la session vient de montrer que cette recette ne tient
	// pas, quoi qu'en prévoie le modèle.
	sameRecipe func(rungOption) bool
}

// suggestQuality décide la suggestion, et fait avancer l'hystérésis.
func suggestQuality(in suggestInput, st *suggestionState) string {
	pos := indexOf(in.ladder, in.current)
	if pos < 0 {
		return ""
	}
	if in.slow {
		st.roomFor, st.roomSince = "", time.Time{}
		return descend(in, pos)
	}
	return ascend(in, pos, st)
}

// descend est le plus haut barreau, du barreau en cours vers le bas, qui
// tient admitSpeed avec une autre recette que celle qui vient de ramer ; à
// défaut, le plus rapide s'il suit la lecture.
func descend(in suggestInput, pos int) string {
	best, bestSpeed := "", 0.0
	for _, quality := range in.ladder[pos:] {
		option := in.try(quality)
		if in.sameRecipe(option) {
			continue
		}
		if option.speed >= admitSpeed {
			return quality
		}
		if option.speed > bestSpeed {
			best, bestSpeed = quality, option.speed
		}
	}
	if bestSpeed >= hardLimitSpeed {
		return best
	}
	return ""
}

// ascend est le plus haut barreau `ok` au-dessus du barreau en cours, au plus
// le plafond, une fois l'hystérésis passée.
func ascend(in suggestInput, pos int, st *suggestionState) string {
	top := indexOf(in.ladder, in.ceiling)
	if top < 0 {
		// Un plafond hors du menu de cette source : au-dessus d'elle, donc
		// son barreau natif, le premier du menu.
		top = 0
	}
	if top >= pos || in.now.Sub(in.started) < ascentMinAge {
		st.roomFor, st.roomSince = "", time.Time{}
		return ""
	}
	room := ""
	for _, quality := range in.ladder[top:pos] {
		if capacity.VerdictFor(in.try(quality).speed) == capacity.VerdictOK {
			room = quality
			break
		}
	}
	if room == "" {
		st.roomFor, st.roomSince = "", time.Time{}
		return ""
	}
	if room != st.roomFor {
		st.roomFor, st.roomSince = room, in.now
	}
	if in.now.Sub(st.roomSince) < ascentHold {
		return ""
	}
	return room
}

// ceilingAfter est le plafond d'une nouvelle session du ticket :
//
//   - le barreau que l'Auto avait demandé, s'il a été descendu à l'admission ;
//   - celui de la session qu'elle remplace, si elle s'ouvre au même barreau
//     (un saut, une autre piste audio) ou au barreau que le serveur venait de
//     suggérer (l'Auto a suivi une descente) : la remontée reste possible
//     jusqu'à ce que le spectateur ou l'Auto choisisse autre chose ;
//   - sinon le barreau servi : pas de remontée au-dessus d'un choix.
func ceilingAfter(served, requested string, previous *TranscodeSession) string {
	if requested != "" && requested != served {
		return requested
	}
	if previous != nil {
		previous.mu.Lock()
		last := previous.suggestion.last
		ctx := previous.ladder
		previous.mu.Unlock()
		if ctx != nil && ctx.ceiling != "" && (served == previous.Quality || served == last) {
			return ctx.ceiling
		}
	}
	return served
}

func indexOf(list []string, key string) int {
	for i, k := range list {
		if k == key {
			return i
		}
	}
	return -1
}

// ladderKeys sont les clés du menu d'une source, dans son ordre.
func ladderKeys(sourceHeight int) []string {
	ladder := QualityLadderFor(sourceHeight)
	keys := make([]string, len(ladder))
	for i, tier := range ladder {
		keys[i] = tier.Key
	}
	return keys
}

// samePipeline dit que deux recettes lanceraient la même commande vidéo.
func samePipeline(a, b *capacity.Pipeline) bool {
	if a == nil || b == nil {
		return a == b
	}
	return a.Encoder == b.Encoder && a.Preset == b.Preset && a.Decode == b.Decode &&
		a.Scale == b.Scale && a.ToneMap == b.ToneMap && a.ToneMapOnGPU == b.ToneMapOnGPU
}

// suggestionFor est la suggestion de /health pour cette session, vide sans
// profil, sans contexte ou sans rien à suggérer.
func (h *Handler) suggestionFor(s *TranscodeSession, now time.Time) string {
	profile := capacityProfile()
	s.mu.Lock()
	ctx := s.ladder
	plan := s.plan
	started := s.startedAt
	frozen := s.frozen
	s.mu.Unlock()
	if profile == nil || ctx == nil || frozen {
		return ""
	}
	slow, _ := s.Slow()
	inputs := ctx.inputs
	inputs.lighter = lighterRecipeFor(s.MediaID)
	load := h.manager.LoadExcept(s.TicketHash)
	in := suggestInput{
		now: now, started: started, current: s.Quality, ceiling: ctx.ceiling, ladder: ctx.ladder, slow: slow,
		try: func(quality string) rungOption { return inputs.tryRung(quality, profile, load) },
		sameRecipe: func(option rungOption) bool {
			return option.options.Video.Copy == (plan == nil) && samePipeline(option.options.Pipeline, plan) &&
				presetFor(option.options.Quality).H == presetFor(s.Quality).H
		},
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	suggested := suggestQuality(in, &s.suggestion)
	if suggested != "" {
		s.suggestion.last = suggested
	}
	return suggested
}
