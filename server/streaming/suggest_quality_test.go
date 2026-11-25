package streaming

import (
	"testing"
	"time"

	"project-player/server/streaming/capacity"
)

// suggested_quality (suggest_quality.go, phase 5 du plan
// docs/transcodage-adaptatif.md) : la descente, la remontée et l'hystérésis.

var testLadder = []string{"2160p", "1080p-10m", "1080p", "720p-6m", "720p", "480p", "360p"}

func suggestFor(current, ceiling string, slow bool, speeds map[string]float64, now, started time.Time) suggestInput {
	return suggestInput{
		now: now, started: started, current: current, ceiling: ceiling, ladder: testLadder, slow: slow,
		try:        fakeRungs(speeds),
		sameRecipe: func(o rungOption) bool { return o.options.Quality == current },
	}
}

func TestSuggestQuality_Descent(t *testing.T) {
	t0 := time.Unix(1_000_000, 0)
	tests := []struct {
		name   string
		speeds map[string]float64
		same   bool
		want   string
	}{
		{
			name:   "sous 1× : le plus haut barreau qui tient 1,3×, sans la session",
			speeds: map[string]float64{"1080p": 0.8, "720p-6m": 1.2, "720p": 1.4, "480p": 3},
			same:   true, want: "720p",
		},
		{
			name:   "une recette plus légère tient au même barreau : le rouvrir",
			speeds: map[string]float64{"1080p": 1.6, "720p": 3},
			same:   false, want: "1080p",
		},
		{
			name:   "la même recette au même barreau ne change rien : plus bas",
			speeds: map[string]float64{"1080p": 1.6, "720p-6m": 1.5},
			same:   true, want: "720p-6m",
		},
		{
			name:   "rien ne tient 1,3× : le plus rapide, s'il suit la lecture",
			speeds: map[string]float64{"1080p": 0.5, "720p-6m": 0.9, "720p": 1.1, "480p": 1.2, "360p": 1.05},
			same:   true, want: "480p",
		},
		{
			name:   "rien ne suit la lecture : pas de suggestion",
			speeds: map[string]float64{"1080p": 0.5, "360p": 0.9},
			same:   true, want: "",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			in := suggestFor("1080p", "1080p", true, tt.speeds, t0.Add(time.Minute), t0)
			same := tt.same
			in.sameRecipe = func(option rungOption) bool { return same && option.options.Quality == "1080p" }
			var st suggestionState
			if got := suggestQuality(in, &st); got != tt.want {
				t.Errorf("suggestion %q, attendu %q", got, tt.want)
			}
		})
	}
}

func TestSuggestQuality_AscentWaitsForLastingRoom(t *testing.T) {
	t0 := time.Unix(1_000_000, 0)
	speeds := map[string]float64{"2160p": 1.2, "1080p-10m": 1.6, "1080p": 1.7}
	var st suggestionState
	ask := func(at time.Duration, speeds map[string]float64) string {
		return suggestQuality(suggestFor("720p", "1080p-10m", false, speeds, t0.Add(at), t0), &st)
	}

	// Une session ouverte par une descente ne remonte pas aussitôt.
	if got := ask(10*time.Second, speeds); got != "" {
		t.Fatalf("à 10 s : %q", got)
	}
	// Assez vieille : la marge doit encore tenir ascentHold.
	if got := ask(ascentMinAge, speeds); got != "" {
		t.Fatalf("première vue de la marge : %q", got)
	}
	// La marge s'interrompt (une voisine reprend) : l'attente recommence.
	if got := ask(ascentMinAge+20*time.Second, map[string]float64{"1080p-10m": 1.4, "1080p": 1.45}); got != "" {
		t.Fatalf("marge interrompue : %q", got)
	}
	if got := ask(ascentMinAge+40*time.Second, speeds); got != "" {
		t.Fatalf("marge revenue depuis 0 s : %q", got)
	}
	if got := ask(ascentMinAge+40*time.Second+ascentHold, speeds); got != "1080p-10m" {
		t.Fatalf("marge tenue %s : %q, attendu le plafond 1080p-10m (la 2160p n'est pas `ok`, et au-dessus du plafond)", ascentHold, got)
	}
}

func TestSuggestQuality_AscentNeverAboveTheCeiling(t *testing.T) {
	t0 := time.Unix(1_000_000, 0)
	all := map[string]float64{"2160p": 5, "1080p-10m": 5, "1080p": 5, "720p-6m": 5, "720p": 5}
	for _, tt := range []struct {
		name, current, ceiling, want string
	}{
		{"jamais dégradée : plafond = barreau en cours, rien à suggérer", "720p", "720p", ""},
		{"dégradée depuis 1080p : au plus 1080p", "720p", "1080p", "1080p"},
		{"plafond hors du menu (au-dessus de la source) : le natif", "720p", "4320p", "2160p"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			st := suggestionState{}
			in := suggestFor(tt.current, tt.ceiling, false, all, t0.Add(ascentMinAge), t0)
			suggestQuality(in, &st)
			in.now = in.now.Add(ascentHold)
			if got := suggestQuality(in, &st); got != tt.want {
				t.Errorf("%q, attendu %q", got, tt.want)
			}
		})
	}
}

// Deux seuils : à 1,3× prévu, une session lente descend, mais une session
// saine ne remonte pas. Pas d'aller-retour sur le même barreau.
func TestSuggestQuality_HysteresisBetweenDescentAndAscent(t *testing.T) {
	t0 := time.Unix(1_000_000, 0)
	speeds := map[string]float64{"1080p": 1.4, "720p-6m": 1.4, "720p": 3}
	var st suggestionState
	down := suggestQuality(suggestFor("1080p", "1080p", true, speeds, t0.Add(time.Minute), t0), &st)
	if down != "720p-6m" {
		t.Fatalf("descente : %q", down)
	}
	// La nouvelle session à 720p-6m, plafond hérité 1080p : 1,4× n'est pas `ok`.
	st = suggestionState{}
	for at := ascentMinAge; at < ascentMinAge+3*ascentHold; at += 5 * time.Second {
		if up := suggestQuality(suggestFor("720p-6m", "1080p", false, speeds, t0.Add(at), t0), &st); up != "" {
			t.Fatalf("à %s : remontée vers %q à 1,4× prévu", at, up)
		}
	}
}

func TestCeilingAfter(t *testing.T) {
	previous := &TranscodeSession{Quality: "1080p", ladder: &ladderContext{ceiling: "2160p"}}
	previous.suggestion.last = "720p"
	for _, tt := range []struct {
		name, served, requested string
		previous                *TranscodeSession
		want                    string
	}{
		{"l'Auto descendu à l'admission : le barreau demandé", "720p", "1080p", nil, "1080p"},
		{"sans session avant : le barreau servi", "720p", "", nil, "720p"},
		{"l'Auto a suivi la descente suggérée : le plafond d'avant", "720p", "", previous, "2160p"},
		{"un saut au même barreau : le plafond d'avant", "1080p", "", previous, "2160p"},
		{"un autre choix : le barreau servi", "480p", "", previous, "480p"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if got := ceilingAfter(tt.served, tt.requested, tt.previous); got != tt.want {
				t.Errorf("%q, attendu %q", got, tt.want)
			}
		})
	}
}

// Sans profil, /health ne suggère rien.
func TestSuggestionFor_WithoutProfileNothing(t *testing.T) {
	setProfileForTest(t, nil)
	h := &Handler{manager: budgetManager()}
	s := &TranscodeSession{Quality: "1080p", ladder: &ladderContext{ladder: testLadder, ceiling: "2160p"}}
	if got := h.suggestionFor(s, time.Now()); got != "" {
		t.Errorf("%q sans profil", got)
	}
}

// De bout en bout sur la machine de 4 cœurs : une session 1080p lente sur un
// 4K HDR10, l'Auto se voit conseiller le 720p.
func TestSuggestionFor_SlowSessionOnFourCores(t *testing.T) {
	profile := fourCoresNoGPU()
	setProfileForTest(t, profile)
	lighterRecipes.Delete(lighterKey(42))
	t.Cleanup(func() { lighterRecipes.Delete(lighterKey(42)) })
	h := &Handler{manager: budgetManager()}
	in := startInputs{probe: hdr10UHD(), burnSubtitle: NoBurnedSubtitle, caps: LegacyCapabilities()}
	served := in.tryRung("1080p", profile, capacity.Load{})
	s := &TranscodeSession{MediaID: 42, Quality: "1080p", plan: served.options.Pipeline, startedAt: time.Now().Add(-time.Minute),
		ladder: &ladderContext{inputs: in, ladder: ladderKeys(2160), ceiling: "1080p"}}
	s.pace.slow = true
	// Le modèle prévoyait 1,4× en ultrafast : les 1080p à d'autres débits
	// referaient la même image avec la même recette, ils sont sautés.
	if got := h.suggestionFor(s, time.Now()); got != "720p-6m" {
		t.Errorf("suggestion %q, attendu 720p-6m", got)
	}

	// La session a vu 0,9× : ce fichier coûte 1,56 fois la prévision, et
	// seul le 360p tient encore 1,3× (le décodage du 4K HEVC, 1,63 cœur,
	// reste à payer à chaque barreau).
	noteSlowSession(42, served.options.Pipeline, served.speed, 0.9)
	s.suggestion = suggestionState{}
	if got := h.suggestionFor(s, time.Now()); got != "360p" {
		t.Errorf("suggestion %q après la note du fichier lent, attendu 360p", got)
	}
}
