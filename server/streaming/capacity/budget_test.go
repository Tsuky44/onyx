package capacity

import (
	"math"
	"sync"
	"testing"
)

// Le budget compte ce que les sessions réservent, et le rend dès qu'elles ne
// coûtent plus.

func TestBudget_ReserveReleaseAndLoad(t *testing.T) {
	tests := []struct {
		name    string
		steps   func(b *Budget)
		except  string
		wantCPU float64
		held    int
	}{
		{
			name:    "vide",
			steps:   func(b *Budget) {},
			wantCPU: 0,
		},
		{
			name: "deux sessions de deux lecteurs s'additionnent",
			steps: func(b *Budget) {
				b.Reserve("a", "alice", Cost{CPU: 2.9, Encode: 0.1})
				b.Reserve("b", "bob", Cost{CPU: 0.5})
			},
			wantCPU: 3.4, held: 2,
		},
		{
			name: "les sessions du lecteur qui demande ne comptent pas",
			steps: func(b *Budget) {
				b.Reserve("a", "alice", Cost{CPU: 2.9})
				b.Reserve("a2", "alice", Cost{CPU: 1})
				b.Reserve("b", "bob", Cost{CPU: 0.5})
			},
			except: "alice", wantCPU: 0.5, held: 3,
		},
		{
			name: "une session rendue (gelée, sortie ou détruite) ne compte plus",
			steps: func(b *Budget) {
				b.Reserve("a", "alice", Cost{CPU: 2.9})
				b.Reserve("b", "bob", Cost{CPU: 0.5})
				b.Release("a")
			},
			wantCPU: 0.5, held: 1,
		},
		{
			name: "rendre deux fois ne rend qu'une fois",
			steps: func(b *Budget) {
				b.Reserve("a", "alice", Cost{CPU: 2.9})
				b.Reserve("b", "bob", Cost{CPU: 0.5})
				b.Release("a")
				b.Release("a")
			},
			wantCPU: 0.5, held: 1,
		},
		{
			name: "réserver de nouveau remplace : la réservation de l'admission, reprise à la création",
			steps: func(b *Budget) {
				b.Reserve("a", "alice", Cost{CPU: 2.9})
				b.Reserve("a", "alice", Cost{CPU: 1.2})
			},
			wantCPU: 1.2, held: 1,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b := NewBudget()
			tt.steps(b)
			if got := b.Load(tt.except).Used.CPU; math.Abs(got-tt.wantCPU) > 1e-9 {
				t.Errorf("charge CPU %.2f, attendu %.2f", got, tt.wantCPU)
			}
			if got := b.Held(); got != tt.held {
				t.Errorf("%d réservations, attendu %d", got, tt.held)
			}
		})
	}
}

func TestBudget_NilReservesNothing(t *testing.T) {
	var b *Budget
	b.Reserve("a", "alice", Cost{CPU: 4})
	if b.Release("a") || b.Held() != 0 || b.Load("").Used != (Cost{}) {
		t.Error("un budget nil ne réserve rien")
	}
}

func TestBudget_MarginIsWhatIsLeftOfEachResource(t *testing.T) {
	profile := machine(4, cpuCosts(0.0025, 0.0082, 0.00085, 0.0153, 0.0177, 0.0106, 0.006), nil)
	b := NewBudget()
	b.Reserve("a", "alice", Cost{CPU: 2.9, Encode: 0.3})
	b.Reserve("b", "bob", Cost{CPU: 3})

	margin, ok := b.Margin(profile, "")
	if !ok {
		t.Fatal("un profil prêt donne une marge")
	}
	if margin.CPU != 0 {
		t.Errorf("CPU réservé au-delà des cœurs : la marge est 0, pas %.2f", margin.CPU)
	}
	if math.Abs(margin.Encode-0.7) > 1e-9 || margin.Decode != 1 {
		t.Errorf("marge du circuit %+v", margin)
	}
	if margin, _ := b.Margin(profile, "bob"); math.Abs(margin.CPU-1.1) > 1e-9 {
		t.Errorf("sans les sessions de bob, il reste 1,1 cœur, pas %.2f", margin.CPU)
	}
	if _, ok := b.Margin(nil, ""); ok {
		t.Error("sans profil, pas de marge")
	}
}

func TestSpeedUnder_FreePartOverCost(t *testing.T) {
	profile := machine(4, cpuCosts(0.0025, 0.0082, 0.00085, 0.0153, 0.0177, 0.0106, 0.006), nil)
	tests := []struct {
		name string
		cost Cost
		used Cost
		want float64
	}{
		{"machine libre", Cost{CPU: 2}, Cost{}, 2},
		{"la ressource la plus tendue décide", Cost{CPU: 1, Encode: 0.5}, Cost{Encode: 0.75}, 0.5},
		{"réservée au-delà de tout", Cost{CPU: 1}, Cost{CPU: 5}, 0},
		{"un coût nul tient toujours", Cost{}, Cost{CPU: 4}, math.Inf(1)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := SpeedUnder(tt.cost, profile, Load{Used: tt.used}); got != tt.want {
				t.Errorf("vitesse %.2f, attendu %.2f", got, tt.want)
			}
		})
	}
}

func TestBudget_ConcurrentUse(t *testing.T) {
	b := NewBudget()
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			id := string(rune('a' + i%26))
			b.Reserve(id, "o", Cost{CPU: 0.1})
			_ = b.Load("")
			b.Release(id)
		}(i)
	}
	wg.Wait()
	if b.Held() != 0 {
		t.Errorf("%d réservations restent", b.Held())
	}
}
