package streaming

import "time"

// Le rythme d'une session : passe-t-elle sous la vitesse de lecture ?
//
// Critère 2 du plan docs/transcodage-adaptatif.md : une session qui passe
// sous 1× plus de 20 s déclenche une action. Sans elle, un encodeur sous 1×
// ne prend jamais ses 32 s d'avance, n'est jamais mis en pause par le
// bridage, et sature le serveur jusqu'à la fin du film sans que personne le
// sache : c'est le cas de fytroz, un 4K Dolby Vision à 0,6× sur un i7.
//
// La vitesse se mesure sur une fenêtre glissante de paceWindow, seulement
// pendant que FFmpeg tourne pour de bon : ni au démarrage (ouvrir le fichier
// et chercher le point de départ prend plusieurs secondes sur un 4K), ni
// pendant une pause du bridage ou un gel, où le temps passe sans images.

const (
	// paceWindow est la durée sous 1× qui déclenche l'action (critère 2).
	paceWindow = 20 * time.Second
	// paceStartup est ce qu'on laisse au démarrage de FFmpeg avant de
	// mesurer. Mesuré sur la prod : 3 à 6 s pour le premier segment d'un 4K
	// HEVC ; le double couvre une machine chargée.
	paceStartup = 10 * time.Second
	// slowSpeed est la vitesse sous laquelle une session ne suit plus la
	// lecture.
	slowSpeed = 1.0
)

// paceSample est le nombre de segments produits à un instant.
type paceSample struct {
	at       time.Time
	produced int
}

// paceWatch suit la vitesse d'une session qui tourne. Gardé sous s.mu.
type paceWatch struct {
	// samples sont ceux de la course en cours, depuis la dernière reprise.
	samples []paceSample
	// slow dit que la dernière fenêtre complète était sous 1×, et speed est
	// sa vitesse.
	slow  bool
	speed float64
	// flagged est posé la première fois que la session passe sous 1× : l'action
	// (rapport au profil, recette plus légère) ne se fait qu'une fois.
	flagged bool
	// origin est le premier échantillon après le démarrage, et last le dernier
	// de la course en cours : la vitesse rapportée au profil se mesure entre
	// les deux (runSpeed), sans le démarrage de FFmpeg, qui la sous-estimerait.
	origin, last paceSample
}

// restart oublie la course en cours : une pause ou un gel l'ont coupée. Une
// session que le bridage arrête a pris son avance : elle n'est plus lente.
func (w *paceWatch) restart() {
	w.samples = w.samples[:0]
	w.slow = false
}

// note ajoute un échantillon et dit si la session vient de passer sous 1×
// pour la première fois.
func (w *paceWatch) note(now, startedAt time.Time, produced int) (firstSlow bool) {
	if startedAt.IsZero() || now.Sub(startedAt) < paceStartup {
		return false
	}
	sample := paceSample{at: now, produced: produced}
	if w.origin.at.IsZero() {
		w.origin = sample
	}
	w.last = sample
	w.samples = append(w.samples, sample)
	// Garder un seul échantillon plus vieux que la fenêtre : c'est le début de
	// la fenêtre qu'on mesure.
	cut := 0
	for cut+1 < len(w.samples) && now.Sub(w.samples[cut+1].at) >= paceWindow {
		cut++
	}
	w.samples = w.samples[cut:]
	first := w.samples[0]
	span := now.Sub(first.at)
	if span < paceWindow {
		return false
	}
	w.speed = float64((produced-first.produced)*segmentDuration) / span.Seconds()
	w.slow = w.speed < slowSpeed
	if w.slow && !w.flagged {
		w.flagged = true
		return true
	}
	return false
}

// runSpeed est la vitesse de la première course, du premier échantillon
// après le démarrage jusqu'à until. ok est faux sur moins de paceStartup : un
// encodeur qui prend son avance aussi vite va bien au-delà de ce que la
// correction regarde.
func (w *paceWatch) runSpeed(until paceSample) (float64, bool) {
	if w.origin.at.IsZero() {
		return 0, false
	}
	span := until.at.Sub(w.origin.at)
	if span < paceStartup || until.produced <= w.origin.produced {
		return 0, false
	}
	return float64((until.produced-w.origin.produced)*segmentDuration) / span.Seconds(), true
}

// watchPace mesure le rythme de la session, une fois par tic du bridage, et
// dit si elle vient de passer 20 s sous 1×.
func (s *TranscodeSession) watchPace(now time.Time, produced int) (firstSlow bool, speed float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.paused || s.frozen || !s.active {
		s.pace.restart()
		return false, 0
	}
	return s.pace.note(now, s.startedAt, produced), s.pace.speed
}

// Slow dit que la session est sous 1× depuis au moins paceWindow, à la
// dernière mesure, et à quelle vitesse.
func (s *TranscodeSession) Slow() (bool, float64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.frozen {
		return false, 0
	}
	return s.pace.slow, s.pace.speed
}
