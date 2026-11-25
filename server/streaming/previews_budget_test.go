package streaming

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"project-player/server/streaming/capacity"
)

// La passe de fond des aperçus ne tourne que sur le budget libre, et se met en
// pause dès qu'une session le prend (previews_budget.go).

func TestPreviewsMayRun_OnlyOnTheFreeBudget(t *testing.T) {
	profile := testProfile(4, nil, nil)
	tests := []struct {
		name     string
		profile  *capacity.Profile
		reserved float64
		want     bool
	}{
		{"sans profil : comme avant", nil, 4, true},
		{"machine libre", profile, 0, true},
		{"un cœur libre", profile, 3, true},
		{"moins d'un cœur libre", profile, 3.2, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b := capacity.NewBudget()
			b.Reserve("s", "o", capacity.Cost{CPU: tt.reserved})
			if got := previewsMayRun(tt.profile, b); got != tt.want {
				t.Errorf("passe autorisée = %v, attendu %v", got, tt.want)
			}
		})
	}
}

func TestPreviewWarm_PausesWhileASessionNeedsTheCPU(t *testing.T) {
	saved := previewBudgetPoll
	previewBudgetPoll = 5 * time.Millisecond
	t.Cleanup(func() { previewBudgetPoll = saved })

	g := newPreviewGenerator(t.TempDir(), nil)
	var free atomic.Bool
	var extracted atomic.Int32
	g.mayRun = free.Load
	g.run = func(ctx context.Context, args []string, background bool) ([]byte, error) {
		extracted.Add(1)
		return []byte("jpeg"), nil
	}
	set := testPreviewSet(t, g, 10)
	g.warm(set, [32]byte{})

	time.Sleep(50 * time.Millisecond)
	if n := extracted.Load(); n != 0 {
		t.Fatalf("%d images extraites pendant que le budget est pris", n)
	}
	free.Store(true)
	g.mu.Lock()
	job := g.jobs[set.dir]
	g.mu.Unlock()
	select {
	case <-job.done:
	case <-time.After(2 * time.Second):
		t.Fatal("la passe ne reprend pas quand le budget se libère")
	}
	for i := 0; i < 10; i++ {
		if !fileExists(set.path(i)) {
			t.Fatalf("image %d manquante après la reprise", i)
		}
	}
}

func TestPreviewWarm_StopsWhilePaused(t *testing.T) {
	g := newPreviewGenerator(t.TempDir(), nil)
	g.mayRun = func() bool { return false }
	g.run = func(ctx context.Context, args []string, background bool) ([]byte, error) {
		t.Error("aucune extraction pendant la pause")
		return nil, nil
	}
	set := testPreviewSet(t, g, 5)
	g.warm(set, [32]byte{})
	done := make(chan struct{})
	go func() { g.stopAll(); close(done) }()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("une passe en pause doit s'arrêter avec le serveur")
	}
}
