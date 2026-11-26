package handlers

// Le profil de fin du Rétro. Le serveur le choisit, l'app le nomme : en
// français comme en anglais, chaque nom est neutre, Onyx ne connaissant pas le
// genre de ses membres (ADR 2026-11-26-tsuky-retro-annuel).

const (
	archetypeMarathon     = "marathon"
	archetypeNightOwl     = "night_owl"
	archetypeCinephile    = "cinephile"
	archetypeExplorer     = "explorer"
	archetypeWeekend      = "weekend"
	archetypeGoodAudience = "good_audience"
)

// Les seuils des règles, dans l'ordre où elles sont lues.
const (
	marathonMinEpisodes = 6
	nightOwlMinShare    = 0.40 // part du temps entre 22 h et 4 h
	cinephileMinShare   = 0.60 // part du temps sur des films
	explorerMinTitles   = 40
	weekendMinShare     = 0.50 // part du temps le samedi et le dimanche
)

// chooseArchetype lit les règles dans l'ordre ; la première qui correspond
// gagne. Un marathon dit plus de quelqu'un qu'une heure de coucher : il passe
// avant.
func chooseArchetype(r *RetroReport) string {
	total := float64(r.WatchedSeconds)
	if total <= 0 {
		return archetypeGoodAudience
	}
	share := func(seconds int) float64 { return float64(seconds) / total }

	night := 0
	for hour, seconds := range r.Hours {
		if hour >= 22 || hour < 4 {
			night += seconds
		}
	}
	weekend := 0
	if len(r.Weekdays) == 7 {
		// La semaine commence le lundi, comme la grille de « Mes stats ».
		weekend = r.Weekdays[5] + r.Weekdays[6]
	}

	switch {
	case r.Marathon != nil && r.Marathon.Episodes >= marathonMinEpisodes:
		return archetypeMarathon
	case share(night) > nightOwlMinShare:
		return archetypeNightOwl
	case share(r.MovieSeconds) > cinephileMinShare:
		return archetypeCinephile
	case r.Titles > explorerMinTitles:
		return archetypeExplorer
	case share(weekend) > weekendMinShare:
		return archetypeWeekend
	}
	return archetypeGoodAudience
}
