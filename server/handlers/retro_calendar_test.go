package handlers

import (
	"testing"
	"time"
)

func TestRetroCalendarOpensOnDecemberFirstAndClosesAfterJanuaryFifteenth(t *testing.T) {
	at := func(y int, m time.Month, d, h, min int) time.Time { return time.Date(y, m, d, h, min, 0, 0, time.UTC) }
	cases := []struct {
		name    string
		now     time.Time
		preview bool
		year    int
		open    bool
	}{
		{"l'été annonce le prochain, fermé", at(2026, time.July, 1, 12, 0), false, 2026, false},
		{"la veille au soir, encore fermé", at(2026, time.November, 30, 23, 59), false, 2026, false},
		{"le 1er décembre à minuit", at(2026, time.December, 1, 0, 0), false, 2026, true},
		{"un 10 janvier raconte l'année d'avant", at(2027, time.January, 10, 9, 0), false, 2026, true},
		{"le 15 janvier au soir, encore ouvert", at(2027, time.January, 15, 23, 59), false, 2026, true},
		{"le 16 janvier, fermé, place au suivant", at(2027, time.January, 16, 0, 0), false, 2027, false},
		{"l'aperçu ouvre hors saison", at(2026, time.November, 26, 10, 0), true, 2026, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := retroCalendar(c.now, c.preview)
			if s.Year != c.year || s.Open != c.open {
				t.Fatalf("retroCalendar(%s) = %d, ouvert %v ; attendu %d, %v", c.now, s.Year, s.Open, c.year, c.open)
			}
			if want := at(c.year+1, time.January, 16, 0, 0); !s.EndsAt.Equal(want) {
				t.Fatalf("fin = %s ; attendu %s", s.EndsAt, want)
			}
		})
	}
}

func TestRetroWindowCountsJanuaryToNovemberInTheDevicesTimeZone(t *testing.T) {
	// Paris en hiver, UTC+1 : le 1er janvier à minuit est le 31 décembre à 23 h UTC.
	w := newRetroWindow(2026, 60)
	if want := historyStamp(time.Date(2025, time.December, 31, 23, 0, 0, 0, time.UTC)); w.since != want {
		t.Fatalf("début = %q ; attendu %q", w.since, want)
	}
	if want := historyStamp(time.Date(2026, time.November, 30, 23, 0, 0, 0, time.UTC)); w.until != want {
		t.Fatalf("fin = %q ; attendu %q", w.until, want)
	}
	if w.days != 334 {
		t.Fatalf("jours = %d ; attendu 334 (janvier à novembre 2026)", w.days)
	}
}
