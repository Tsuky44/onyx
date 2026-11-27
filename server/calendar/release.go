package calendar

import "strings"

// Release est une date de sortie de film telle que TMDB la liste par pays
// (/movie/:id/release_dates). Type suit TMDB : 2 et 3 en salle, 4 en
// numérique, 5 en physique.
type Release struct {
	Country string
	Type    int
	Date    string // AAAA-MM-JJ ou horodatage ISO
}

// releasePreference : ce qui permet de voir le film chez soi passe d'abord,
// puisque c'est ce que le serveur pourra récupérer. La salle ne sert que
// quand rien d'autre n'est annoncé.
var releasePreference = []struct {
	tmdbType int
	name     string
}{
	{4, "digital"},
	{5, "physical"},
	{3, "theatrical"},
	{2, "theatrical"},
}

// PickRelease choisit la sortie à afficher : celle du pays du compte, sinon
// celle des États-Unis (TMDB y est le plus complet), sinon la date générale
// du film comptée comme sortie en salle. Rend ("", "") sans aucune date.
func PickRelease(releases []Release, country, fallbackDate string) (date, kind string) {
	for _, c := range []string{strings.ToUpper(country), "US"} {
		if c == "" {
			continue
		}
		for _, pref := range releasePreference {
			best := ""
			for _, r := range releases {
				if !strings.EqualFold(r.Country, c) || r.Type != pref.tmdbType {
					continue
				}
				day := dayOf(r.Date)
				if day != "" && (best == "" || day < best) {
					best = day
				}
			}
			if best != "" {
				return best, pref.name
			}
		}
	}
	if day := dayOf(fallbackDate); day != "" {
		return day, "theatrical"
	}
	return "", ""
}

func dayOf(raw string) string {
	if len(raw) < len("2006-01-02") {
		return ""
	}
	return raw[:len("2006-01-02")]
}
