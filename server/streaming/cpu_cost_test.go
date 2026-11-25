package streaming

import (
	"math"
	"testing"
	"time"
)

func TestCoresPerFilmSecond(t *testing.T) {
	tests := []struct {
		name  string
		cpu   time.Duration
		film  int
		cores float64
		ok    bool
	}{
		{"deux cœurs pendant toute la lecture", 80 * time.Second, 40, 2, true},
		{"moins d'un cœur : une recopie", 4 * time.Second, 40, 0.1, true},
		{"plus vite que la lecture ne change rien : c'est du CPU par film", 30 * time.Second, 10, 3, true},
		{"rien produit", 5 * time.Second, 0, 0, false},
		{"aucun temps connu", 0, 40, 0, false},
		{"temps négatif", -time.Second, 40, 0, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := coresPerFilmSecond(tt.cpu, tt.film)
			if ok != tt.ok || math.Abs(got-tt.cores) > 1e-9 {
				t.Errorf("coresPerFilmSecond(%v, %d) = %v, %v ; veut %v, %v", tt.cpu, tt.film, got, ok, tt.cores, tt.ok)
			}
		})
	}
}

func TestProcessCPUTime_ToleratesAnUnstartedProcess(t *testing.T) {
	if got := processCPUTime(nil); got != 0 {
		t.Errorf("sans ProcessState, le temps est 0 : %v", got)
	}
}
