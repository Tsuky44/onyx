package handlers

import (
	"os"
	"time"
)

// Le calendrier du Rétro : quelle année il raconte, et s'il est visible.
// Voir l'ADR 2026-11-26-tsuky-retro-annuel et docs/retro-annuel.md.
//
// Il compte du 1er janvier au 30 novembre, dans le fuseau de l'appareil qui le
// demande, et se montre du 1er décembre au 15 janvier, à l'heure du serveur.
// La fenêtre comptée étant fermée quand il s'ouvre, ses chiffres ne bougent
// plus : pas besoin d'en garder un instantané.

// retroPreviewEnv ouvre le Rétro hors saison : sans lui, rien ne se teste
// avant décembre, ni sur un téléphone ni sur un serveur de recette.
const retroPreviewEnv = "ONYX_RETRO_PREVIEW"

// retroPreview et retroNow sont remplacés par les tests.
var (
	retroPreview = func() bool { return os.Getenv(retroPreviewEnv) == "1" }
	retroNow     = time.Now
)

type retroSeason struct {
	Year int
	Open bool
	// EndsAt est le premier instant où il n'est plus visible : le 16 janvier
	// à minuit, heure du serveur.
	EndsAt time.Time
}

// retroCalendar dit quel Rétro vaut à cet instant. Hors saison, c'est le
// prochain : celui de l'année en cours, fermé.
func retroCalendar(now time.Time, preview bool) retroSeason {
	year := now.Year()
	open := now.Month() == time.December
	if now.Month() == time.January && now.Day() <= 15 {
		year, open = year-1, true
	}
	return retroSeason{
		Year:   year,
		Open:   open || preview,
		EndsAt: time.Date(year+1, time.January, 16, 0, 0, 0, 0, now.Location()),
	}
}

// newRetroWindow est la période comptée d'une année : du 1er janvier au
// 1er décembre (exclu), découpée dans le fuseau de l'appareil.
func newRetroWindow(year, offsetMinutes int) statsWindow {
	zone := time.FixedZone("client", offsetMinutes*60)
	first := time.Date(year, time.January, 1, 0, 0, 0, 0, zone)
	end := time.Date(year, time.December, 1, 0, 0, 0, 0, zone)
	return statsWindow{
		days:     int(end.Sub(first).Hours() / 24),
		today:    end.AddDate(0, 0, -1),
		firstDay: first,
		since:    historyStamp(first),
		until:    historyStamp(end),
		modifier: tzModifier(offsetMinutes),
	}
}
