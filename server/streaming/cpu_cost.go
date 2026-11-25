package streaming

import (
	"log"
	"os"
	"time"
)

// Le coût réel d'une session, en cœurs par seconde de film.
//
// Le plan du transcodage adaptatif (docs/transcodage-adaptatif.md, phase 0)
// part de ce chiffre : combien de processeur FFmpeg a vraiment brûlé pour une
// seconde de film produite. Il règle l'admission d'une session de plus et le
// nombre de threads, et il dit si un preset ou une chaîne GPU tient sa
// promesse. Jusque-là, seule la vitesse d'encodage était journalisée, et elle
// ne dit pas ce qu'il en coûte à la machine.

// reportMinSegments est ce qu'une session doit avoir produit pour que sa
// vitesse et son coût soient journalisés : en dessous, le démarrage de FFmpeg
// pèse plus que l'encodage et le chiffre ne dit rien.
const reportMinSegments = 10

// processCPUTime est le temps processeur (utilisateur et système) d'un
// processus terminé ; 0 quand rien n'est connu.
func processCPUTime(state *os.ProcessState) time.Duration {
	if state == nil {
		return 0
	}
	return state.UserTime() + state.SystemTime()
}

// coresPerFilmSecond rapporte un temps processeur aux secondes de film
// produites : 2,0 veut dire deux cœurs occupés pendant toute la lecture. ok est
// faux quand le rapport n'a pas de sens (rien produit, ou aucun temps connu).
func coresPerFilmSecond(cpu time.Duration, filmSeconds int) (cores float64, ok bool) {
	if cpu <= 0 || filmSeconds <= 0 {
		return 0, false
	}
	return cpu.Seconds() / float64(filmSeconds), true
}

// CPUCost est le temps processeur de FFmpeg rapporté aux secondes de film que
// la session a produites. Il n'est connu qu'une fois FFmpeg sorti : ok est faux
// avant. Il compte aussi l'encodage jeté (le début d'un saut) et le démarrage,
// donc il surestime légèrement une session courte.
func (s *TranscodeSession) CPUCost() (cores float64, ok bool) {
	produced := s.countVideoSegments()
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.exited {
		return 0, false
	}
	return coresPerFilmSecond(s.cpuUsed, produced*segmentDuration)
}

// logCPUCost journalise le coût de la session à sa fin, à côté de la ligne
// « encodé à N× » : mêmes sessions, même seuil.
func (s *TranscodeSession) logCPUCost() {
	if s.countVideoSegments() < reportMinSegments {
		return
	}
	if cores, ok := s.CPUCost(); ok {
		log.Printf("Session %s: %s a coûté %.2f cœur par seconde de film", s.ID, s.Quality, cores)
	}
}
