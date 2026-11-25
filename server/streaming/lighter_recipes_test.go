package streaming

import (
	"math"
	"testing"
	"time"

	"project-player/server/playbackauth"
	"project-player/server/streaming/capacity"
)

// La recette suivante d'un fichier après une session lente
// (lighter_recipes.go) et le rythme des sessions (session_pace.go).

func TestSlowdownAfter(t *testing.T) {
	for _, tt := range []struct {
		name                      string
		current, predicted, speed float64
		want                      float64
		wantOK                    bool
	}{
		{"prévu 1,4×, vu 0,7× : deux fois plus lourd", 0, 1.4, 0.7, 2, true},
		{"un fichier déjà noté s'alourdit encore", 1.5, 1.2, 0.8, 2.25, true},
		{"borné : un fichier cassé ne coule pas plus bas", 1, 4, 0.1, maxSlowdown, true},
		{"la charge explique la lenteur : rien sur le fichier", 0, 0.8, 0.9, 0, false},
		{"sans prévision : rien", 0, math.Inf(1), 0.9, 0, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := slowdownAfter(tt.current, tt.predicted, tt.speed)
			if ok != tt.wantOK || math.Abs(got-tt.want) > 1e-9 {
				t.Errorf("(%v, %v), attendu (%v, %v)", got, ok, tt.want, tt.wantOK)
			}
		})
	}
}

// Après une session lente, la recette suivante de ce fichier est plus
// légère : un preset plus rapide d'abord, au même barreau ; puis, quand il
// n'y en a plus, l'Auto descend de barreau et le manuel est prévenu.
func TestLighterRecipe_PresetFirstThenRung(t *testing.T) {
	profile := smallBox() // 2 cœurs : le 1080p HEVC n'y tient qu'en ultrafast
	in := startInputs{probe: hevc1080(), burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities(), audioMap: []int{0}}

	// Une machine de 6 cœurs, où le 1080p tient en veryfast avec marge.
	roomy := testProfile(6, softwareCosts(0.001, 0.002, 0.0005, 0.0153, 0.05, 0.128),
		[]capacity.EncoderCandidate{candidateOf(softwareEncoder)})
	first := in.tryRung("1080p", roomy, capacity.Load{})
	if first.options.Pipeline.Preset != "veryfast" {
		t.Fatalf("recette de départ %+v", first.options.Pipeline)
	}
	// Vue à 0,9× : la suivante prend un preset plus rapide, au même barreau.
	in.lighter = lighterRecipe{slowdown: mustSlowdown(t, first.options.Pipeline.Slowdown, first.speed, 0.9)}
	second := in.tryRung("1080p", roomy, capacity.Load{})
	if second.options.Quality != "1080p" || second.options.Pipeline.Preset == "veryfast" {
		t.Fatalf("après une session lente : %s en %s", second.options.Quality, second.options.Pipeline.Preset)
	}

	// Sur la petite machine, déjà en ultrafast : plus de preset, le barreau.
	in.lighter = lighterRecipe{}
	base := in.tryRung("1080p", profile, capacity.Load{})
	in.lighter = lighterRecipe{slowdown: mustSlowdown(t, 0, base.speed, 0.9)}
	m := budgetManager()
	decide := func(auto bool) admission {
		return m.admitAndReserve("s", playbackauth.Digest("v"), func(load capacity.Load) admission {
			return admit("1080p", auto, rungsBelow("1080p", 1080), func(q string) rungOption { return in.tryRung(q, profile, load) })
		})
	}
	if auto := decide(true); auto.served.options.Quality == "1080p" || auto.warning != CapacityDegraded {
		t.Errorf("Auto : %s (%q), attendu un barreau plus bas", auto.served.options.Quality, auto.warning)
	}
	m.Budget().Release("s")
	if manual := decide(false); manual.served.options.Quality != "1080p" || manual.warning != CapacityTooHeavy {
		t.Errorf("manuel : %s (%q), attendu 1080p tel quel, prévenu", manual.served.options.Quality, manual.warning)
	}
}

func mustSlowdown(t *testing.T, current, predicted, speed float64) float64 {
	t.Helper()
	got, ok := slowdownAfter(current, predicted, speed)
	if !ok {
		t.Fatalf("slowdownAfter(%v, %v, %v) ne dit rien", current, predicted, speed)
	}
	return got
}

// La mémoire est par fichier : un autre fichier n'est pas touché.
func TestNoteSlowSession_OnlyThisFile(t *testing.T) {
	for _, id := range []int{7, 8} {
		lighterRecipes.Delete(lighterKey(id))
	}
	t.Cleanup(func() { lighterRecipes.Delete(lighterKey(7)) })
	noteSlowSession(7, &capacity.Pipeline{Encoder: "libx264", Preset: "veryfast"}, 1.5, 0.75)
	if got := lighterRecipeFor(7).slowdown; got != 2 {
		t.Errorf("fichier 7 : ×%v", got)
	}
	if got := lighterRecipeFor(8).slowdown; got != 0 {
		t.Errorf("fichier 8 : ×%v", got)
	}
	// Une recopie lente n'apprend rien sur l'encodeur.
	noteSlowSession(8, nil, 1.5, 0.5)
	if got := lighterRecipeFor(8).slowdown; got != 0 {
		t.Errorf("recopie : ×%v", got)
	}
}

func TestPaceWatch_TwentySecondsUnderOneTimesFlagsOnce(t *testing.T) {
	t0 := time.Unix(1_000_000, 0)
	var w paceWatch
	// 0,5× : un segment de 2 s toutes les 4 s.
	produced := func(at time.Duration) int { return int(at / (4 * time.Second)) }
	flagged := 0
	var firstAt time.Duration
	for at := time.Duration(0); at <= 60*time.Second; at += time.Second {
		if w.note(t0.Add(at), t0, produced(at)) {
			flagged++
			firstAt = at
		}
	}
	if flagged != 1 {
		t.Fatalf("signalée %d fois", flagged)
	}
	if firstAt < paceStartup+paceWindow {
		t.Errorf("signalée à %s : ni le démarrage ni moins de %s sous 1× ne comptent", firstAt, paceWindow)
	}
	if !w.slow || w.speed > 0.6 {
		t.Errorf("lente=%v à %.2f×", w.slow, w.speed)
	}
	// Une pause du bridage : elle a pris son avance, elle n'est plus lente.
	w.restart()
	if w.slow {
		t.Error("lente après une pause")
	}
}

func TestPaceWatch_AFastSessionIsNeverSlow(t *testing.T) {
	t0 := time.Unix(1_000_000, 0)
	var w paceWatch
	for at := time.Duration(0); at <= 60*time.Second; at += time.Second {
		// 2× : un segment de 2 s par seconde.
		if w.note(t0.Add(at), t0, int(at/time.Second)) {
			t.Fatalf("une session à 2× signalée lente à %s", at)
		}
	}
	if speed, ok := w.runSpeed(w.last); !ok || math.Abs(speed-2) > 0.01 {
		t.Errorf("vitesse de la course %.2f (%v), attendu 2 sans le démarrage", speed, ok)
	}
}

// Une session gelée n'est ni lente ni mesurée.
func TestWatchPace_FrozenIsNotSlow(t *testing.T) {
	s := &TranscodeSession{active: true, frozen: true, paused: true, startedAt: time.Now().Add(-time.Minute)}
	s.pace.slow = true
	if first, _ := s.watchPace(time.Now(), 3); first {
		t.Error("gelée : signalée")
	}
	if slow, _ := s.Slow(); slow {
		t.Error("gelée : lente")
	}
}
