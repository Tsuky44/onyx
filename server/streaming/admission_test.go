package streaming

import (
	"math"
	"testing"

	"project-player/server/playbackauth"
	"project-player/server/streaming/capacity"
)

// L'admission d'une session contre le budget (admission.go, décision §0.5 du
// plan docs/transcodage-adaptatif.md).

// fakeRungs rend, pour chaque barreau, la vitesse prévue qu'on lui donne.
func fakeRungs(speeds map[string]float64) func(string) rungOption {
	return func(q string) rungOption {
		return rungOption{options: TranscodeOptions{Quality: q}, speed: speeds[q]}
	}
}

func TestAdmit_Rules(t *testing.T) {
	below := []string{"720p-6m", "720p", "480p", "360p"}
	tests := []struct {
		name        string
		auto        bool
		speeds      map[string]float64
		wantQuality string
		wantWarning string
		wantRefused bool
	}{
		{
			name:        "le barreau demandé tient : servi sans avertissement",
			speeds:      map[string]float64{"1080p": 2},
			wantQuality: "1080p",
		},
		{
			name:        "sans profil, la vitesse est infinie : rien ne change",
			auto:        true,
			speeds:      map[string]float64{"1080p": math.Inf(1)},
			wantQuality: "1080p",
		},
		{
			name:        "Auto : descend jusqu'au plus haut qui tient 1,3×",
			auto:        true,
			speeds:      map[string]float64{"1080p": 0.8, "720p-6m": 1.1, "720p": 1.4, "480p": 3},
			wantQuality: "720p", wantWarning: CapacityDegraded,
		},
		{
			name:        "manuel : servi tel quel, avec l'avertissement",
			speeds:      map[string]float64{"1080p": 0.8, "720p-6m": 1.1, "720p": 1.4, "480p": 3},
			wantQuality: "1080p", wantWarning: CapacityTooHeavy,
		},
		{
			name:        "manuel entre 1× et 1,3× : servi tel quel, avec l'avertissement",
			speeds:      map[string]float64{"1080p": 1.2},
			wantQuality: "1080p", wantWarning: CapacityTooHeavy,
		},
		{
			name:        "Auto, rien ne tient 1,3× : le plus rapide, s'il suit la lecture",
			auto:        true,
			speeds:      map[string]float64{"1080p": 0.7, "720p-6m": 0.9, "720p": 1.1, "480p": 1.2, "360p": 1.2},
			wantQuality: "480p", wantWarning: CapacityDegraded,
		},
		{
			name:        "Auto, le demandé est le plus rapide sans tenir 1,3× : too_heavy",
			auto:        true,
			speeds:      map[string]float64{"1080p": 1.1, "720p-6m": 1.0},
			wantQuality: "1080p", wantWarning: CapacityTooHeavy,
		},
		{
			name:        "limite dure, Auto : aucun barreau ne suit la lecture",
			auto:        true,
			speeds:      map[string]float64{"1080p": 0.3, "720p-6m": 0.5, "720p": 0.6, "480p": 0.8, "360p": 0.9},
			wantRefused: true,
		},
		{
			name:        "limite dure, manuel : aucun barreau ne suit la lecture",
			speeds:      map[string]float64{"1080p": 0.3, "720p-6m": 0.5, "720p": 0.6, "480p": 0.8, "360p": 0.9},
			wantRefused: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := admit("1080p", tt.auto, below, fakeRungs(tt.speeds))
			if (got.refused != "") != tt.wantRefused {
				t.Fatalf("refusé = %q, attendu %v", got.refused, tt.wantRefused)
			}
			if tt.wantRefused {
				return
			}
			if got.served.options.Quality != tt.wantQuality || got.warning != tt.wantWarning {
				t.Errorf("servi %s (%q), attendu %s (%q)", got.served.options.Quality, got.warning, tt.wantQuality, tt.wantWarning)
			}
			if got.requested != "1080p" {
				t.Errorf("barreau demandé %q", got.requested)
			}
		})
	}
}

func TestRungsBelow_FollowTheMenuDownward(t *testing.T) {
	got := rungsBelow("1080p", 1080)
	if len(got) == 0 || got[0] != "720p-6m" {
		t.Fatalf("sous 1080p, le premier est 720p-6m (même débit, moins de lignes) : %v", got)
	}
	for _, q := range got {
		if EstimateBandwidth(q) > EstimateBandwidth("1080p") {
			t.Errorf("%s demande plus à la ligne que le barreau choisi par l'Auto", q)
		}
	}
	if got := rungsBelow("360p-420k", 1080); len(got) != 0 {
		t.Errorf("rien sous le plus bas : %v", got)
	}
	// Hors du menu de la source (4K demandé pour un 1080p) : tout ce qui
	// demande moins à la ligne.
	if got := rungsBelow("2160p-40m", 1080); len(got) == 0 || got[0] != "1080p-20m" {
		t.Errorf("sous un barreau hors du menu : %v", got)
	}
}

// smallBox est une machine de deux cœurs sans circuit, où l'encodage pèse
// plus que le décodage : x264 veryfast à 0,05 cœur-seconde par Mpx·image, un
// décodage HEVC 1080p à 0,1 cœur. Un 1080p n'y tient qu'en ultrafast.
func smallBox() *capacity.Profile {
	return testProfile(2, softwareCosts(0.001, 0.002, 0.0005, 0.0153, 0.05, 0.128),
		[]capacity.EncoderCandidate{candidateOf(softwareEncoder)})
}

// hevc1080 est un 1080p HEVC SDR, qu'un client d'avant les capacités ne
// décode pas : l'image est encodée.
func hevc1080() *ProbeResult {
	return &ProbeResult{
		Version:  probeVersion,
		Duration: 3600,
		Video:    &VideoStreamInfo{Codec: "hevc", Width: 1920, Height: 1080, PixFmt: "yuv420p", FrameRate: 24, BitDepth: 8},
		Audio:    []AudioStreamInfo{{Codec: "aac", Channels: 2}},
	}
}

// startAs refait l'admission de /start pour un lecteur, et réserve comme elle.
func startAs(m *SessionManager, profile *capacity.Profile, viewer, quality string, auto bool) admission {
	in := startInputs{probe: hevc1080(), burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities(), audioMap: []int{0}}
	return m.admitAndReserve(viewer+"/"+quality, playbackauth.Digest(viewer), func(load capacity.Load) admission {
		return admit(quality, auto, rungsBelow(quality, 1080), func(q string) rungOption {
			return planRung(in.optionsFor(q), profile, load, len(in.audioMap))
		})
	})
}

func budgetManager() *SessionManager {
	return &SessionManager{sessions: map[string]*TranscodeSession{}, budget: capacity.NewBudget()}
}

func TestAdmission_CheaperRecipeAtTheSameRungFirst(t *testing.T) {
	got := startAs(budgetManager(), smallBox(), "alice", "1080p", true)
	if got.refused != "" || got.warning != "" || got.served.options.Quality != "1080p" {
		t.Fatalf("servi %s (%q, %q) : une recette moins chère tient au même barreau",
			got.served.options.Quality, got.warning, got.refused)
	}
	if p := got.served.options.Pipeline; p == nil || p.Preset != "ultrafast" {
		t.Fatalf("recette %+v : veryfast et superfast ne tiennent pas, ultrafast oui", p)
	}
	if got.served.speed < admitSpeed {
		t.Errorf("vitesse prévue %.2f", got.served.speed)
	}
}

// Le test du plan : deux sessions trop lourdes pour tenir ensemble. La seconde
// est dégradée, et elle n'est pas admise au prix de saturer la première.
func TestAdmission_SecondHeavySessionIsDegradedInsteadOfSaturatingTheFirst(t *testing.T) {
	m, profile := budgetManager(), smallBox()
	first := startAs(m, profile, "alice", "1080p", true)
	if first.warning != "" || first.served.options.Quality != "1080p" {
		t.Fatalf("la première est servie telle quelle : %s (%q)", first.served.options.Quality, first.warning)
	}

	second := startAs(m, profile, "bob", "1080p", true)
	if second.refused != "" || second.warning != CapacityDegraded {
		t.Fatalf("la seconde est dégradée : %q, %q", second.warning, second.refused)
	}
	if second.served.options.Quality == "1080p" || second.requested != "1080p" {
		t.Errorf("servi %s pour %s demandé", second.served.options.Quality, second.requested)
	}
	if second.served.speed < admitSpeed {
		t.Errorf("la seconde est admise à %.2f×, sous %.1f×", second.served.speed, admitSpeed)
	}
	// La première garde de quoi tenir, avec la seconde réservée.
	others := m.LoadExcept(playbackauth.Digest("alice"))
	if speed := capacity.SpeedUnder(first.served.cost, profile, others); speed < admitSpeed {
		t.Errorf("la seconde laisse %.2f× à la première", speed)
	}
	if used := m.budget.Load("").Used.CPU; used > 2 {
		t.Errorf("%.2f cœurs réservés sur 2", used)
	}

	// Un choix manuel au même moment est servi tel quel, avec l'avertissement.
	manual := startAs(m, profile, "carol", "1080p", false)
	if manual.served.options.Quality != "1080p" || manual.warning != CapacityTooHeavy {
		t.Errorf("manuel : %s (%q), attendu 1080p (too_heavy)", manual.served.options.Quality, manual.warning)
	}
}

func TestAdmission_HardLimitRefuses(t *testing.T) {
	for _, auto := range []bool{true, false} {
		m, profile := budgetManager(), smallBox()
		m.budget.Reserve("x", "someone", capacity.Cost{CPU: 2})
		got := startAs(m, profile, "dave", "1080p", auto)
		if got.refused == "" {
			t.Errorf("auto=%v : machine entièrement réservée, 503 attendu, servi %s", auto, got.served.options.Quality)
		}
		if m.budget.Held() != 1 {
			t.Errorf("auto=%v : un refus ne réserve rien", auto)
		}
	}
}

func TestAdmission_AQualityChangeIsNotJudgedAgainstTheSessionItReplaces(t *testing.T) {
	m, profile := budgetManager(), smallBox()
	startAs(m, profile, "alice", "1080p", true)
	again := startAs(m, profile, "alice", "1080p-10m", true)
	if again.warning != "" || again.served.options.Quality != "1080p-10m" {
		t.Errorf("changement de qualité : %s (%q)", again.served.options.Quality, again.warning)
	}
}

func TestAdmission_WithoutProfileNothingChanges(t *testing.T) {
	got := startAs(budgetManager(), nil, "alice", "1080p", true)
	if got.warning != "" || got.refused != "" || got.served.options.Quality != "1080p" {
		t.Errorf("sans profil : %s (%q, %q)", got.served.options.Quality, got.warning, got.refused)
	}
	if got.served.options.Pipeline != nil || got.served.cost != (capacity.Cost{}) {
		t.Error("sans profil, ni recette ni réservation")
	}
}

func TestAdmission_ACopyCostsAlmostNothing(t *testing.T) {
	probe := hevc1080()
	probe.Video.Codec = "h264"
	in := startInputs{probe: probe, burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities(), audioMap: []int{0}}
	got := planRung(in.optionsFor("1080p"), smallBox(), capacity.Load{}, 1)
	if !got.options.Video.Copy {
		t.Fatal("un H.264 1080p se recopie")
	}
	if got.cost.CPU > 0.1 || got.speed < admitSpeed {
		t.Errorf("recopie : %.2f cœur, %.1f×", got.cost.CPU, got.speed)
	}
}

func TestSessionCap_OnlyForcedOnceTheProfileIsReady(t *testing.T) {
	t.Setenv("MAX_TRANSCODES", "")
	if got := sessionCap(false); got != defaultMaxTranscodes() {
		t.Errorf("sans profil : %d, le plafond d'avant %d", got, defaultMaxTranscodes())
	}
	if got := sessionCap(true); got != 0 {
		t.Errorf("profil prêt, rien de forcé : le budget seul, pas %d", got)
	}
	t.Setenv("MAX_TRANSCODES", "3")
	if sessionCap(true) != 3 || sessionCap(false) != 3 {
		t.Error("MAX_TRANSCODES reste un plafond forcé")
	}
}
