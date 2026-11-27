package calendar

import "testing"

func TestPickReleasePrefersWatchingAtHome(t *testing.T) {
	cases := []struct {
		name               string
		releases           []Release
		country, fallback  string
		wantDate, wantKind string
	}{
		{
			name: "le numérique du pays passe avant la salle",
			releases: []Release{
				{Country: "FR", Type: 3, Date: "2026-10-01T00:00:00.000Z"},
				{Country: "FR", Type: 4, Date: "2026-12-16T00:00:00.000Z"},
			},
			country: "FR", wantDate: "2026-12-16", wantKind: "digital",
		},
		{
			name: "sans date du pays, les États-Unis",
			releases: []Release{
				{Country: "US", Type: 4, Date: "2026-12-01T00:00:00.000Z"},
				{Country: "DE", Type: 4, Date: "2026-11-01T00:00:00.000Z"},
			},
			country: "FR", wantDate: "2026-12-01", wantKind: "digital",
		},
		{
			name:     "la plus tôt des dates du même type",
			releases: []Release{{Country: "FR", Type: 5, Date: "2027-02-01"}, {Country: "FR", Type: 5, Date: "2027-01-10"}},
			country:  "fr", wantDate: "2027-01-10", wantKind: "physical",
		},
		{
			name:     "seulement la salle",
			releases: []Release{{Country: "FR", Type: 3, Date: "2026-12-24T00:00:00.000Z"}},
			country:  "FR", wantDate: "2026-12-24", wantKind: "theatrical",
		},
		{
			name: "rien par pays : la date générale", fallback: "2026-12-05",
			country: "FR", wantDate: "2026-12-05", wantKind: "theatrical",
		},
		{name: "aucune date", country: "FR"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			date, kind := PickRelease(c.releases, c.country, c.fallback)
			if date != c.wantDate || kind != c.wantKind {
				t.Fatalf("PickRelease = (%q, %q), want (%q, %q)", date, kind, c.wantDate, c.wantKind)
			}
		})
	}
}
