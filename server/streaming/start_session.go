package streaming

import "time"

// Ce qu'une session reçoit de /start en plus de ses paramètres de lecture :
// sa réservation, les recettes que sa mort retirerait, ce qu'elle rapportera
// au profil, et de quoi suggérer un barreau (/health).
//
// Extrait de handler.go, près de la limite de 800 lignes (ADR-0052).

// prepare pose sur la session ce que l'admission a décidé. previous est la
// session que le ticket lisait jusqu'ici, nil s'il n'en avait pas : la
// nouvelle hérite de son plafond de remontée (ceilingAfter).
func (s *TranscodeSession) prepare(decision admission, inputs startInputs, previous *TranscodeSession) {
	options := decision.served.options
	s.reservation = decision.served.cost
	// Une image recopiée n'a pas de chaîne : usesHardwareFilters le sait.
	s.hardwareFilters = options.usesHardwareFilters()
	s.vulkanGPU = sessionToneMapper(options).Vulkan && vulkanOnGPU()
	if plan := options.Pipeline; plan != nil {
		s.plan = plan
		s.extraCost = audioCost(len(inputs.audioMap))
		if plan.Hardware {
			s.hardwareEncoder = plan.Encoder
		}
	}
	s.ladder = &ladderContext{
		inputs:  inputs,
		ladder:  ladderKeys(sourceHeight(inputs.probe)),
		ceiling: ceilingAfter(s.Quality, decision.requested, previous),
	}
}

// currentFor est la session que ce ticket lit en ce moment : ni remplacée, ni
// en attente. La plus récente s'il y en a plusieurs.
func (m *SessionManager) currentFor(ticket [32]byte) *TranscodeSession {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var current *TranscodeSession
	var currentStart time.Time
	for _, s := range m.sessions {
		if s.TicketHash != ticket || s.superseded || s.standby {
			continue
		}
		s.mu.Lock()
		started := s.startedAt
		s.mu.Unlock()
		if current == nil || started.After(currentStart) {
			current, currentStart = s, started
		}
	}
	return current
}
