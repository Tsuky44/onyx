package streaming

import (
	"log"
	"math"
	"time"

	"project-player/server/streaming/capacity"
)

// Ce qu'une session rapporte au profil (phase 5 du plan
// docs/transcodage-adaptatif.md, capacity/correction.go).
//
// Deux moments :
//
//   - la vitesse à plein régime, quand on la connaît pour la première fois :
//     à la première pause du bridage (l'encodeur a couru sans frein depuis le
//     démarrage), ou dès qu'il passe 20 s sous 1× (il ne prendra jamais de
//     pause) ;
//   - le temps CPU réel, à la fin, connu seulement à la sortie de FFmpeg.
//
// La fin n'ajoute un échantillon que s'il dit plus lourd que la vitesse :
// une seule correction sert à la vitesse prévue et à la réservation, et elle
// suit le plus prudent des deux signaux sans compter deux fois la même session.
//
// Une recopie n'a pas de recette, une session sans profil non plus : elles ne
// rapportent rien. Une session gelée (remplacée) ne rapporte pas de vitesse :
// le temps passé gelée n'est pas une vitesse.

// afterTick suit la session à chaque tic du bridage : sa vitesse sous 1×, et
// sa vitesse à la première pause.
func (s *TranscodeSession) afterTick(now time.Time, produced int) {
	if firstSlow, speed := s.watchPace(now, produced); firstSlow {
		log.Printf("Session %s: %s sous la vitesse de lecture depuis %s (%.2f×)",
			s.ID, s.Quality, paceWindow, speed)
		s.reportSpeed(speed)
		noteSlowSession(s.MediaID, s.recipe(), s.predictedSpeed(), speed)
	}
	if speed, ok := s.firstPauseSpeed(); ok {
		s.reportSpeed(speed)
	}
}

// recipe est la recette prévue de la session, nil pour une recopie.
func (s *TranscodeSession) recipe() *capacity.Pipeline {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.plan
}

// firstPauseSpeed rend, une seule fois, la vitesse de la première course,
// quand le bridage vient de l'arrêter.
func (s *TranscodeSession) firstPauseSpeed() (float64, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.paused || s.frozen || s.speedReported || s.plan == nil {
		return 0, false
	}
	speed, ok := s.pace.runSpeed(paceSample{at: s.pausedAt, produced: s.pausedProduced})
	if !ok {
		// Une avance prise en moins de dix secondes : trop vite pour dire
		// quoi que ce soit (capacity.speedRatioCeiling), et rien de plus tard
		// ne vaudra mieux.
		s.speedReported = true
		return 0, false
	}
	return speed, true
}

// reportSpeed rapporte la vitesse à plein régime, une fois par session.
func (s *TranscodeSession) reportSpeed(speed float64) {
	s.mu.Lock()
	if s.plan == nil || s.speedReported || s.frozen || speed <= 0 {
		s.mu.Unlock()
		return
	}
	s.speedReported = true
	obs := s.observationLocked(speed, 0)
	s.mu.Unlock()
	if ratio, ok := observeProfile(obs, 0); ok {
		s.mu.Lock()
		s.speedRatio = ratio
		s.mu.Unlock()
	}
}

// reportEnd rapporte le temps CPU réel à la fin de la session, et la vitesse
// d'une session qui n'a jamais été mise en pause ni gelée. Appelé par Kill,
// une fois FFmpeg attendu.
func (s *TranscodeSession) reportEnd() {
	if s.countVideoSegments() < reportMinSegments {
		// Moins de vingt secondes de film : le démarrage pèse plus que
		// l'encodage, et un saut aussitôt suivi d'un autre ne dit rien.
		return
	}
	cores, cpuKnown := s.CPUCost()
	s.mu.Lock()
	if s.plan == nil {
		s.mu.Unlock()
		return
	}
	speed := 0.0
	if !s.speedReported && !s.frozen && s.burstSpeed == 0 {
		speed, _ = s.pace.runSpeed(s.pace.last)
	}
	if !cpuKnown {
		cores = 0
	}
	above := s.speedRatio
	obs := s.observationLocked(speed, cores)
	s.mu.Unlock()
	if speed == 0 && cores == 0 {
		return
	}
	observeProfile(obs, above)
}

// observationLocked décrit la session au profil ; s.mu est tenu. La charge est
// celle des autres lecteurs au moment du rapport.
func (s *TranscodeSession) observationLocked(speed, cpu float64) capacity.Observation {
	var load capacity.Load
	if s.budget != nil {
		load = s.budget.Load(budgetOwner(s.TicketHash))
	}
	// Le facteur du fichier est retiré avec celui de la classe : la classe
	// apprend contre le banc, pas contre ce qu'un fichier a déjà appris.
	return capacity.Observation{
		Class: s.plan.Class, Cost: s.plan.Cost, Correction: s.plan.Correction * math.Max(s.plan.Slowdown, 1),
		Extra: s.extraCost, Load: load, Speed: speed, CPU: cpu, At: time.Now(),
	}
}

// predictedSpeed est la vitesse que le planificateur prévoit pour la recette
// de la session sous la charge du moment : ce qu'elle aurait dû tenir.
func (s *TranscodeSession) predictedSpeed() float64 {
	profile := capacityProfile()
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.plan == nil || profile == nil {
		return 0
	}
	load := capacity.Load{}
	if s.budget != nil {
		load = s.budget.Load(budgetOwner(s.TicketHash))
	}
	return capacity.SpeedUnder(s.plan.Cost, profile, capacity.Load{Used: load.Used.Plus(s.extraCost)})
}

// observeProfile corrige le profil publié avec l'observation, si elle dit
// plus lourd que above, et l'écrit. ok est faux quand elle n'a rien changé.
func observeProfile(obs capacity.Observation, above float64) (ratio float64, ok bool) {
	editProfile(func(p *capacity.Profile) *capacity.Profile {
		r, good := obs.Ratio(p)
		if !good || r <= above {
			return nil
		}
		before := p.CorrectionFor(obs.Class)
		next, _, _ := p.Observe(obs)
		ratio, ok = r, true
		log.Printf("Streaming: correction de %s : ×%.2f → ×%.2f (session à ×%.2f du banc)",
			obs.Class, before, next.CorrectionFor(obs.Class), r)
		return next
	})
	return ratio, ok
}
