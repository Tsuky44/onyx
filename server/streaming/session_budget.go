package streaming

import "project-player/server/streaming/capacity"

// La réservation d'une session dans le budget du gestionnaire.
//
// Une session réserve à sa création (CreateSession) et rend sa part dès
// qu'elle ne coûte plus : gelée (Freeze, une session remplacée), FFmpeg sorti
// (watch), ou détruite (Kill). Release est sans effet la deuxième fois, et les
// trois passent sous s.mu, comme reserveIn : une session dont FFmpeg meurt
// avant d'être posée dans le gestionnaire ne réserve donc jamais.

// budgetOwner regroupe les sessions d'un même lecteur : celles que sa
// prochaine demande remplacera.
func budgetOwner(ticket [32]byte) string { return string(ticket[:]) }

// reserveIn pose la réservation de la session dans b, sauf si elle ne coûte
// déjà plus rien : celle que /start a posée dès l'admission est alors rendue.
func (s *TranscodeSession) reserveIn(b *capacity.Budget) {
	if b == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.exited || s.frozen {
		b.Release(s.ID)
		return
	}
	s.budget = b
	b.Reserve(s.ID, budgetOwner(s.TicketHash), s.reservation)
}

// releaseBudgetLocked rend la réservation. Appelé sous s.mu.
func (s *TranscodeSession) releaseBudgetLocked() {
	if s.budget != nil {
		s.budget.Release(s.ID)
	}
}

// LoadExcept est la charge réservée par les sessions vivantes, sauf celles de
// ce ticket, que la nouvelle session va remplacer.
func (m *SessionManager) LoadExcept(ticket [32]byte) capacity.Load {
	return m.budget.Load(budgetOwner(ticket))
}

// Budget rend le budget des sessions, pour les phases suivantes (tenue des
// barreaux, suggested_quality) : Budget.Margin y donne la marge du moment.
func (m *SessionManager) Budget() *capacity.Budget { return m.budget }

// admitAndReserve décide l'admission d'une session sous la charge des autres,
// et réserve aussitôt son coût sous l'identifiant qu'elle aura.
//
// Sous admitMu : deux /start simultanés liraient sinon la même charge, et
// seraient admis tous les deux là où un seul tient. La réservation précède le
// lancement de FFmpeg ; CreateSession la reprend sous le même identifiant, et
// un échec entre les deux la rend (Budget().Release).
func (m *SessionManager) admitAndReserve(id string, ticket [32]byte, decide func(capacity.Load) admission) admission {
	m.admitMu.Lock()
	defer m.admitMu.Unlock()
	decision := decide(m.LoadExcept(ticket))
	if decision.refused == "" {
		m.budget.Reserve(id, budgetOwner(ticket), decision.served.cost)
	}
	return decision
}
