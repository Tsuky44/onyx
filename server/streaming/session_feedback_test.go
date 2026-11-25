package streaming

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"project-player/server/streaming/capacity"
)

// Ce qu'une session rapporte au profil (session_feedback.go).

// failingSession est une session dont FFmpeg meurt aussitôt, sans rien
// écrire, comme hardware_filters_test.go en pose une.
func failingSession(t *testing.T) *TranscodeSession {
	t.Helper()
	session := &TranscodeSession{ID: "s", TmpDir: t.TempDir()}
	session.ctx, session.cancel = context.WithCancel(context.Background())
	session.cmd = exec.Command("false")
	if err := session.cmd.Start(); err != nil {
		t.Skipf("cannot start a failing process here: %v", err)
	}
	return session
}

// plannedSession est une session 1080p d'un 4K HDR10 sur la machine de 4
// cœurs, qui a produit segments segments.
func plannedSession(t *testing.T, profile *capacity.Profile, segments int) *TranscodeSession {
	t.Helper()
	in := startInputs{probe: hdr10UHD(), burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities()}
	planned := in.tryRung("1080p", profile, capacity.Load{})
	if planned.options.Pipeline == nil {
		t.Fatal("pas de recette")
	}
	s := &TranscodeSession{ID: "s", Quality: "1080p", TmpDir: t.TempDir(), plan: planned.options.Pipeline}
	for i := 0; i < segments; i++ {
		if err := os.WriteFile(filepath.Join(s.TmpDir, fmt.Sprintf("stream_0_%03d.ts", i)), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

func TestReportSpeed_CorrectsTheClassOnce(t *testing.T) {
	profile := fourCoresNoGPU()
	setProfileForTest(t, profile)
	s := plannedSession(t, profile, 0)
	class := s.plan.Class

	// Prévue à 1,4×, vue à 0,7× : deux fois le banc, un quart du chemin.
	s.reportSpeed(s.plan.Speed / 2)
	if got := capacityProfile().CorrectionFor(class); got != 1.25 {
		t.Fatalf("correction %v, attendu 1,25", got)
	}
	s.reportSpeed(0.1)
	if got := capacityProfile().CorrectionFor(class); got != 1.25 {
		t.Errorf("une seconde vitesse de la même session a compté : %v", got)
	}
	// Le planificateur s'en sert aussitôt : la même recette coûte plus.
	in := startInputs{probe: hdr10UHD(), burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities()}
	again := in.tryRung("1080p", capacityProfile(), capacity.Load{})
	if again.options.Pipeline.Class != class || again.speed >= s.plan.Speed {
		t.Errorf("recette %s prévue à %.2f×, attendu la même classe sous %.2f×", again.options.Pipeline.Class, again.speed, s.plan.Speed)
	}
}

// La fin n'ajoute le temps CPU que s'il dit plus lourd que la vitesse.
func TestReportEnd_CPUOnlyWhenHeavierThanTheSpeed(t *testing.T) {
	for _, tt := range []struct {
		name       string
		speedRatio float64
		cpuRatio   float64
		want       float64
	}{
		{"pas de vitesse rapportée : le CPU compte", 0, 1.4, 1.1},
		{"la vitesse disait plus lourd : le CPU n'ajoute rien", 2, 1.4, 1},
		{"le CPU dit plus lourd que la vitesse : il compte", 1.2, 1.8, 1.2},
	} {
		t.Run(tt.name, func(t *testing.T) {
			profile := fourCoresNoGPU()
			setProfileForTest(t, profile)
			s := plannedSession(t, profile, reportMinSegments)
			s.speedReported, s.speedRatio = tt.speedRatio > 0, tt.speedRatio
			filmSeconds := float64(reportMinSegments * segmentDuration)
			s.exited = true
			s.cpuUsed = time.Duration(tt.cpuRatio * s.plan.Cost.CPU * filmSeconds * float64(time.Second))
			s.reportEnd()
			if got := capacityProfile().CorrectionFor(s.plan.Class); fmt.Sprintf("%.2f", got) != fmt.Sprintf("%.2f", tt.want) {
				t.Errorf("correction %v, attendu %v", got, tt.want)
			}
		})
	}
}

// Une session gelée (remplacée) ne rapporte pas de vitesse, et une session
// trop courte rien du tout.
func TestReport_FrozenOrShortSessionsSayNothing(t *testing.T) {
	profile := fourCoresNoGPU()
	setProfileForTest(t, profile)
	frozen := plannedSession(t, profile, 0)
	frozen.frozen = true
	frozen.reportSpeed(0.5)
	short := plannedSession(t, profile, reportMinSegments-1)
	short.exited, short.cpuUsed = true, time.Hour
	short.reportEnd()
	if len(capacityProfile().Corrections) != 0 {
		t.Errorf("corrections : %+v", capacityProfile().Corrections)
	}
}

// Une recopie n'a pas de recette : rien à rapporter, et sans profil non plus.
func TestReport_CopyOrNoProfileSayNothing(t *testing.T) {
	setProfileForTest(t, nil)
	s := &TranscodeSession{ID: "s", TmpDir: t.TempDir()}
	s.reportSpeed(0.5)
	s.reportEnd()
	if s.speedReported {
		t.Error("une recopie a rapporté sa vitesse")
	}
}
