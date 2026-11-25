package streaming

import (
	"runtime"
	"testing"
)

func setCoresForTest(t *testing.T, n int) {
	t.Helper()
	saved := availableCores
	availableCores = func() int { return n }
	t.Cleanup(func() { availableCores = saved })
}

func TestEncoderThreads_FollowTheAvailableCoresUpToTheCap(t *testing.T) {
	tests := []struct{ cores, want int }{
		{0, 1}, // ne doit jamais demander zéro thread
		{1, 1},
		{4, 4}, // docker --cpus=4 sur un gros hôte
		{16, 16},
		{64, 16}, // le plafond du Xeon de prod
	}
	for _, tt := range tests {
		setCoresForTest(t, tt.cores)
		if got := encoderThreads(); got != tt.want {
			t.Errorf("%d cœur(s) : %d threads, veut %d", tt.cores, got, tt.want)
		}
	}
}

func TestDefaultMaxTranscodes_IsHalfTheCoresWithAFloorOfFour(t *testing.T) {
	tests := []struct{ cores, want int }{
		{1, 4}, {4, 4}, {8, 4}, {10, 5}, {32, 16},
	}
	for _, tt := range tests {
		setCoresForTest(t, tt.cores)
		t.Setenv("MAX_TRANSCODES", "")
		if got := maxTranscodes(); got != tt.want {
			t.Errorf("%d cœur(s) : %d sessions, veut %d", tt.cores, got, tt.want)
		}
	}
}

// Le plafond d'un conteneur bridé : par défaut, availableCores vient de
// GOMAXPROCS, que Go règle sur le quota cgroup, pas sur NumCPU.
func TestAvailableCores_DefaultsToGOMAXPROCS(t *testing.T) {
	if got, want := availableCores(), runtime.GOMAXPROCS(0); got != want {
		t.Errorf("availableCores = %d, GOMAXPROCS = %d", got, want)
	}
}

func TestSoftwareEncoder_ThreadsFlagUsesTheAvailableCores(t *testing.T) {
	setCoresForTest(t, 4)
	args := softwareEncoder.rateControl(presetFor("1080p"))
	if got := flagValue(args, "-threads", ""); got != "4" {
		t.Errorf("-threads = %q sur 4 cœurs", got)
	}
}
