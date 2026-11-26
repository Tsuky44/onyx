package handlers

import "testing"

func TestChooseArchetypeReadsTheRulesInOrder(t *testing.T) {
	hours := func(night, day int) []int {
		h := make([]int, 24)
		h[23], h[15] = night, day
		return h
	}
	week := func(weekday, weekend int) []int { return []int{weekday, 0, 0, 0, 0, weekend, 0} }
	cases := []struct {
		name string
		r    RetroReport
		want string
	}{
		{"rien regardé", RetroReport{}, archetypeGoodAudience},
		{"six épisodes un même jour", RetroReport{WatchedSeconds: 100, Hours: hours(0, 100), Marathon: &marathonStat{Episodes: 6}}, archetypeMarathon},
		{"cinq épisodes ne font pas un marathon", RetroReport{WatchedSeconds: 100, Hours: hours(0, 100), Marathon: &marathonStat{Episodes: 5}}, archetypeGoodAudience},
		{"le marathon passe avant la nuit", RetroReport{WatchedSeconds: 100, Hours: hours(90, 10), Marathon: &marathonStat{Episodes: 9}}, archetypeMarathon},
		{"41 % la nuit", RetroReport{WatchedSeconds: 100, Hours: hours(41, 59)}, archetypeNightOwl},
		{"40 % pile ne suffit pas", RetroReport{WatchedSeconds: 100, Hours: hours(40, 60)}, archetypeGoodAudience},
		{"la nuit passe avant les films", RetroReport{WatchedSeconds: 100, Hours: hours(50, 50), MovieSeconds: 90}, archetypeNightOwl},
		{"61 % de films", RetroReport{WatchedSeconds: 100, Hours: hours(0, 100), MovieSeconds: 61}, archetypeCinephile},
		{"41 titres", RetroReport{WatchedSeconds: 100, Hours: hours(0, 100), Titles: 41}, archetypeExplorer},
		{"le week-end", RetroReport{WatchedSeconds: 100, Hours: hours(0, 100), Weekdays: week(40, 60)}, archetypeWeekend},
		{"par défaut", RetroReport{WatchedSeconds: 100, Hours: hours(0, 100), Weekdays: week(80, 20), Titles: 12}, archetypeGoodAudience},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := chooseArchetype(&c.r); got != c.want {
				t.Fatalf("chooseArchetype = %q ; attendu %q", got, c.want)
			}
		})
	}
}
