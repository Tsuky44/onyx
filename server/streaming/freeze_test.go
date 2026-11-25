package streaming

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"project-player/server/playbackauth"
)

// Une session remplacée est gelée (SIGSTOP) tout de suite, et le bridage ne la
// relance jamais. Ces tests lancent un vrai processus : le signal est ce qui
// compte, et seul /proc dit si le processus est arrêté. Ils sautent là où il
// manque.

// startRealSession lance `sleep` dans une session, comme Start le fait pour
// FFmpeg : même surveillance, même annulation.
func startRealSession(t *testing.T, id string, ticket [32]byte) *TranscodeSession {
	t.Helper()
	if _, err := os.Stat("/proc/self/stat"); err != nil {
		t.Skip("pas de /proc : l'état du processus ne peut pas être lu")
	}
	if _, err := exec.LookPath("sleep"); err != nil {
		t.Skip("pas de sleep")
	}
	return startSessionRunning(t, id, ticket, "sleep", "60")
}

func startSessionRunning(t *testing.T, id string, ticket [32]byte, name string, args ...string) *TranscodeSession {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	s := &TranscodeSession{
		ID: id, TicketHash: ticket, TmpDir: t.TempDir(),
		ctx: ctx, cancel: cancel,
		cmd: exec.CommandContext(ctx, name, args...),
	}
	if err := s.Start(); err != nil {
		cancel()
		t.Fatalf("start %s: %v", name, err)
	}
	t.Cleanup(s.Kill)
	return s
}

// processState est la lettre d'état du noyau : R, S (en cours) ou T (arrêté).
func processState(t *testing.T, s *TranscodeSession) string {
	t.Helper()
	raw, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", s.cmd.Process.Pid))
	if err != nil {
		t.Fatalf("lecture de /proc: %v", err)
	}
	// « pid (nom) état … » : le nom peut contenir des espaces et des parenthèses.
	rest := string(raw)[strings.LastIndex(string(raw), ")")+2:]
	return rest[:1]
}

func waitState(t *testing.T, s *TranscodeSession, stopped bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if (processState(t, s) == "T") == stopped {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("état %q, arrêté attendu: %v", processState(t, s), stopped)
}

func TestFreeze_StopsTheProcessAndTheThrottleNeverResumesIt(t *testing.T) {
	s := startRealSession(t, "old", playbackauth.Digest("mine"))
	waitState(t, s, false)

	s.Freeze()
	waitState(t, s, true)
	if !s.Frozen() {
		t.Fatal("Freeze doit poser l'état gelé")
	}

	// Aucune avance : le bridage relancerait une session seulement mise en pause.
	s.mu.Lock()
	s.lastRequestedSegment = 100
	s.mu.Unlock()
	s.throttleStep(0)
	time.Sleep(50 * time.Millisecond)
	if processState(t, s) != "T" {
		t.Error("le bridage a relancé une session gelée : elle encoderait pendant sa grâce")
	}
}

// La contre-épreuve : sans gel, le bridage continue de relancer.
func TestThrottleStep_StillResumesAPausedSessionThatIsNotFrozen(t *testing.T) {
	s := startRealSession(t, "playing", playbackauth.Digest("mine"))

	s.throttleStep(segmentsAhead + 1) // avance pleine : pause
	waitState(t, s, true)
	if s.Frozen() {
		t.Fatal("une pause du bridage n'est pas un gel")
	}
	s.throttleStep(0) // l'avance est retombée : reprise
	waitState(t, s, false)
}

func TestFreeze_IsIdempotentAndAfterAThrottlePauseStaysFrozen(t *testing.T) {
	s := startRealSession(t, "old", playbackauth.Digest("mine"))
	s.throttleStep(segmentsAhead + 1)
	waitState(t, s, true)

	s.Freeze()
	s.Freeze()
	s.throttleStep(0)
	time.Sleep(50 * time.Millisecond)
	if processState(t, s) != "T" {
		t.Error("une session déjà en pause puis gelée doit le rester")
	}
}

func TestKill_ResumesAndEndsAFrozenSession(t *testing.T) {
	s := startRealSession(t, "old", playbackauth.Digest("mine"))
	s.Freeze()
	waitState(t, s, true)

	done := make(chan struct{})
	go func() { s.Kill(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Kill n'est pas venu à bout d'une session gelée")
	}
	if s.IsActive() {
		t.Error("le processus gelé tourne encore après Kill")
	}
}

func TestSupersede_FreezesTheReplacedSessionButServesItDuringTheGrace(t *testing.T) {
	m, ticket := newStandbyManager(t)
	supersedeGrace = time.Hour // la session doit survivre : on regarde son état
	old := startRealSession(t, "old", ticket)
	fresh := &TranscodeSession{ID: "new", TicketHash: ticket, TmpDir: t.TempDir()}
	m.CreateSession(old)
	m.CreateSession(fresh)

	m.Supersede(ticket, "new")

	waitState(t, old, true)
	if _, ok := m.GetSession("old"); !ok {
		t.Error("la session remplacée reste servie pendant sa grâce (ADR-0033)")
	}
	if fresh.Frozen() {
		t.Error("la session qui remplace ne doit pas être gelée")
	}
}

// Une session en attente n'est jamais remplacée avant Claim : le gel ne la
// concerne pas, même quand un départ ordinaire emporte les autres du ticket.
func TestSupersede_NeverFreezesAStandbySession(t *testing.T) {
	m, ticket := newStandbyManager(t)
	supersedeGrace = time.Hour
	waiting := startRealSession(t, "waiting", ticket)
	waiting.standby = true
	m.CreateSession(waiting)

	m.Supersede(ticket, "new")

	if waiting.Frozen() || processState(t, waiting) == "T" {
		t.Error("une session en attente ne se gèle pas : Claim ne la dégèlerait pas")
	}
}

// Les sessions que les tests posent sans FFmpeg ne portent pas de commande.
func TestFreeze_ToleratesASessionWithoutProcess(t *testing.T) {
	s := &TranscodeSession{ID: "bare", active: true}
	s.Freeze()
	if !s.Frozen() {
		t.Error("le gel se pose même sans processus à arrêter")
	}
}

func TestFreeze_IgnoresASessionThatAlreadyExited(t *testing.T) {
	s := &TranscodeSession{ID: "gone"}
	s.Freeze()
	if s.Frozen() {
		t.Error("rien à geler quand FFmpeg est déjà sorti")
	}
}

// CPUCost : le coût réel d'une session, connu à la sortie de FFmpeg.
func TestCPUCost_IsReportedOnceTheProcessHasExited(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("pas de sh")
	}
	s := startSessionRunning(t, "busy", playbackauth.Digest("mine"),
		"sh", "-c", "i=0; while [ $i -lt 200000 ]; do i=$((i+1)); done")
	// Dix segments produits : de quoi rapporter un coût.
	for i := 0; i < reportMinSegments; i++ {
		name := filepath.Join(s.TmpDir, fmt.Sprintf("stream_0_%03d.ts", i))
		if err := os.WriteFile(name, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	deadline := time.Now().Add(20 * time.Second)
	for s.IsActive() && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if s.IsActive() {
		t.Fatal("la boucle de test ne se termine pas")
	}

	cores, ok := s.CPUCost()
	if !ok || cores <= 0 {
		t.Fatalf("CPUCost = %v, %v ; un processus qui a calculé coûte du processeur", cores, ok)
	}
}

func TestCPUCost_IsUnknownWhileTheProcessRuns(t *testing.T) {
	s := startRealSession(t, "running", playbackauth.Digest("mine"))
	if _, ok := s.CPUCost(); ok {
		t.Error("le temps processeur n'est connu qu'à la sortie")
	}
}
