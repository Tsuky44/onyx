package streaming

import (
	"math"
	"testing"
	"time"

	"project-player/server/playbackauth"
	"project-player/server/streaming/capacity"
)

// Une session réserve à sa création et rend sa part dès qu'elle ne coûte plus
// : gelée, sortie ou détruite. Une session en attente réserve aussi.

func cpuHeld(m *SessionManager) float64 { return m.budget.Load("").Used.CPU }

func near(a, b float64) bool { return math.Abs(a-b) < 1e-9 }

func TestSessionBudget_ReserveStandbySupersedeDestroy(t *testing.T) {
	m, ticket := newStandbyManager(t)
	m.budget = capacity.NewBudget()

	playing := &TranscodeSession{ID: "playing", TicketHash: ticket, TmpDir: t.TempDir(), reservation: capacity.Cost{CPU: 1}}
	m.CreateSession(playing)
	if !near(cpuHeld(m), 1) {
		t.Fatalf("réservé %.2f, attendu 1", cpuHeld(m))
	}

	prepared := &TranscodeSession{ID: "prepared", TicketHash: ticket, TmpDir: t.TempDir(), standby: true,
		reservation: capacity.Cost{CPU: 0.5}}
	m.CreateSession(prepared)
	if !near(cpuHeld(m), 1.5) {
		t.Fatalf("une session en attente encode déjà : réservé %.2f, attendu 1,5", cpuHeld(m))
	}
	if !near(m.LoadExcept(ticket).Used.CPU, 0) {
		t.Error("les sessions du ticket qui demande ne comptent pas pour lui")
	}

	// Au premier segment de la session préparée, l'autre est remplacée et
	// gelée : sa part revient tout de suite, sans attendre la grâce.
	m.Claim(prepared)
	if !near(cpuHeld(m), 0.5) {
		t.Errorf("après remplacement, réservé %.2f, attendu 0,5", cpuHeld(m))
	}
	m.DestroySession("prepared")
	if m.budget.Held() != 0 {
		t.Errorf("détruite, la session garde sa réservation")
	}
}

func TestSessionBudget_FreezeReleases(t *testing.T) {
	ticket := playbackauth.Digest("mine")
	s := startRealSession(t, "old", ticket)
	b := capacity.NewBudget()
	s.reservation = capacity.Cost{CPU: 2}
	s.reserveIn(b)
	if b.Held() != 1 {
		t.Fatal("la session réserve")
	}
	s.Freeze()
	if b.Held() != 0 {
		t.Error("gelée, la session rend sa réservation")
	}
}

func TestSessionBudget_ExitReleasesAndNeverReservesAgain(t *testing.T) {
	ticket := playbackauth.Digest("mine")
	s := startSessionRunning(t, "done", ticket, "true")
	b := capacity.NewBudget()
	// La réservation posée dès l'admission, avant que FFmpeg ne sorte.
	b.Reserve(s.ID, budgetOwner(ticket), capacity.Cost{CPU: 1})
	deadline := time.Now().Add(2 * time.Second)
	for s.IsActive() && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	s.reserveIn(b)
	if b.Held() != 0 {
		t.Error("un FFmpeg déjà sorti ne coûte rien : sa réservation est rendue")
	}
}
