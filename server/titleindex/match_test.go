package titleindex

import "testing"

func TestFoldMatchesTheApp(t *testing.T) {
	cases := map[string]string{
		"L’Empire contre-attaque": "l empire contre attaque",
		"Amélie":                  "amelie",
		"WALL·E":                  "wall e",
		"  Spider-Man  ":          "spider man",
		"Œdipe":                   "oedipe",
	}
	for in, want := range cases {
		if got := Fold(in); got != want {
			t.Errorf("Fold(%q) = %q, attendu %q", in, got, want)
		}
	}
}

func TestMatchRank(t *testing.T) {
	cases := []struct {
		title, query string
		rank         int
		ok           bool
	}{
		{"Dune", "dune", 0, true},
		{"Batman Begins", "bat", 1, true},
		// L'article de tête ne compte pas : « The Batman » commence par « bat ».
		{"The Batman", "bat", 1, true},
		{"Le Chevalier noir", "chevalier", 1, true},
		{"Les Enfants de Dune", "dune", 2, true},
		{"The Dark Knight", "dark kni", 1, true},
		{"Le Fabuleux Destin d'Amélie Poulain", "amelie poulain", 2, true},
		{"Le Fabuleux Destin d'Amélie Poulain", "poulain fab", 3, true},
		{"Spider-Man", "spiderman", 5, true},
		{"Inception", "bat", 0, false},
	}
	for _, c := range cases {
		rank, ok := MatchRank(Fold(c.title), Fold(c.query))
		if ok != c.ok || (ok && rank != c.rank) {
			t.Errorf("MatchRank(%q, %q) = %d, %v ; attendu %d, %v", c.title, c.query, rank, ok, c.rank, c.ok)
		}
	}
}
