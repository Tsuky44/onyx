package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"project-player/server/database"
	"project-player/server/models"
)

func TestStreaksKeepTheRunAliveUntilTheEndOfTheNextDay(t *testing.T) {
	today := time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC)
	cases := []struct {
		name          string
		dates         []string
		current, best int
	}{
		{"aucune lecture", nil, 0, 0},
		{"aujourd'hui seulement", []string{"2026-09-14"}, 1, 1},
		{"hier compte encore", []string{"2026-09-12", "2026-09-13"}, 2, 2},
		{"avant-hier casse la série", []string{"2026-09-11", "2026-09-12"}, 0, 2},
		{"un trou remet à un", []string{"2026-09-01", "2026-09-02", "2026-09-03", "2026-09-13", "2026-09-14"}, 2, 3},
		{"changement de mois", []string{"2026-08-31", "2026-09-01"}, 0, 2},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			current, best := streaks(c.dates, today)
			if current != c.current || best != c.best {
				t.Fatalf("streaks(%v) = %d, %d ; attendu %d, %d", c.dates, current, best, c.current, c.best)
			}
		})
	}
}

type personalFixture struct {
	now                         time.Time
	movieID, tenetID, showID    int
	episode1, episode2, special int
}

// seedPersonalStats : Léa (compte 3) a vu deux épisodes de Severance lundi
// soir, Dune dimanche et il y a 40 jours, la moitié de Tenet jeudi, et un
// bout d'épisode la semaine d'avant.
func seedPersonalStats(t *testing.T) personalFixture {
	t.Helper()
	fx := setupActivityTestDB(t)
	mustExec := func(query string, args ...any) int {
		t.Helper()
		res, err := database.DB.Exec(query, args...)
		if err != nil {
			t.Fatalf("%s: %v", query, err)
		}
		id, _ := res.LastInsertId()
		return int(id)
	}
	p := personalFixture{now: fx.clock, movieID: fx.movieID, episode1: fx.episodeID}
	if err := database.DB.QueryRow(`SELECT id FROM medias WHERE type = 'show'`).Scan(&p.showID); err != nil {
		t.Fatalf("show: %v", err)
	}
	var seasonID int
	if err := database.DB.QueryRow(`SELECT id FROM medias WHERE type = 'season'`).Scan(&seasonID); err != nil {
		t.Fatalf("season: %v", err)
	}
	p.episode2 = mustExec(`INSERT INTO medias (type, title, file_path, duration, parent_id, season_number, episode_number)
		VALUES (?, 'Goodbye, Mrs. Selvig', '/sev2.mkv', 3000, ?, 2, 2)`, models.TypeEpisode, seasonID)
	p.special = mustExec(`INSERT INTO medias (type, title, file_path, duration, parent_id, season_number, episode_number)
		VALUES (?, 'Making of', '/sev0.mkv', 600, ?, 0, 1)`, models.TypeEpisode, seasonID)
	p.tenetID = mustExec(`INSERT INTO medias (type, title, file_path, duration, release_date) VALUES (?, 'Tenet', '/tenet.mkv', 9000, '2020-08-26')`, models.TypeMovie)
	mustExec(`UPDATE medias SET release_date = '2024-02-27' WHERE id = ?`, p.movieID)
	mustExec(`UPDATE medias SET release_date = '2022-02-18' WHERE id = ?`, p.showID)
	for _, g := range [][2]int{{p.movieID, 878}, {p.movieID, 12}, {p.showID, 10765}, {p.showID, 18}} {
		mustExec(`INSERT INTO media_genres (media_id, genre_id) VALUES (?, ?)`, g[0], g[1])
	}
	mustExec(`INSERT INTO progressions (user_id, media_id, current_position_seconds, is_finished) VALUES (3, ?, 3000, 1)`, p.episode1)
	mustExec(`INSERT INTO progressions (user_id, media_id, current_position_seconds, is_finished) VALUES (3, ?, 3000, 1)`, p.episode2)
	mustExec(`INSERT INTO progressions (user_id, media_id, current_position_seconds, is_finished) VALUES (3, ?, 4500, 0)`, p.tenetID)

	play := func(mediaID int, mediaType, title, device, client string, started time.Time, watched, duration int) {
		t.Helper()
		var showID any
		show := ""
		if mediaType == "episode" {
			showID, show = p.showID, "Severance"
		}
		mustExec(`INSERT INTO playback_history (user_id, media_id, media_type, title, show_id, show_title, device_name,
			client, play_method, started_at, ended_at, watched_seconds, duration_seconds)
			VALUES (3, ?, ?, ?, ?, ?, ?, ?, 'direct', ?, ?, ?, ?)`,
			mediaID, mediaType, title, showID, show, device, client,
			historyStamp(started), historyStamp(started), watched, duration)
	}
	now := p.now // lundi 14 septembre 2026, 20 h UTC
	play(p.episode1, "episode", "Hello, Ms. Cobel", "Salon", "Android TV 1.4.2", now.Add(-2*time.Hour), 3000, 3000)
	play(p.episode2, "episode", "Goodbye, Mrs. Selvig", "Salon", "Android TV 1.4.2", now.Add(-time.Hour), 3000, 3000)
	play(p.movieID, "movie", "Dune", "PC", "Windows 1.4.3", now.Add(-26*time.Hour), 9000, 9000)
	play(p.tenetID, "movie", "Tenet", "PC", "Windows 1.4.3", now.Add(-3*24*time.Hour), 1800, 9000)
	play(p.episode1, "episode", "Hello, Ms. Cobel", "Salon", "Android TV 1.4.2", now.Add(-11*24*time.Hour), 600, 3000)
	play(p.movieID, "movie", "Dune", "PC", "Windows 1.4.3", now.Add(-40*24*time.Hour), 9000, 9000)
	// Une autre personne : rien d'elle ne doit apparaître.
	mustExec(`INSERT INTO playback_history (user_id, media_id, media_type, title, started_at, ended_at, watched_seconds, duration_seconds)
		VALUES (1, ?, 'movie', 'Dune', ?, ?, 9000, 9000)`, p.movieID, historyStamp(now.Add(-time.Hour)), historyStamp(now))
	return p
}

func TestPersonalStatsDescribeOnlyTheCallersViewing(t *testing.T) {
	fx := seedPersonalStats(t)
	p, err := computePersonalStats(3, newStatsWindow(7, 0, fx.now), false)
	if err != nil {
		t.Fatal(err)
	}

	if p.Previous == nil || p.Previous.Plays != 1 || p.Previous.Watched != 600 {
		t.Fatalf("previous = %+v", p.Previous)
	}
	if p.Streak.Current != 2 || p.Streak.Best != 2 || p.FirstPlay != "2026-08-05" {
		t.Fatalf("streak = %+v, first play = %q", p.Streak, p.FirstPlay)
	}
	if p.WeekdayHour[0][18] != 3000 || p.WeekdayHour[0][19] != 3000 || p.WeekdayHour[6][18] != 9000 {
		t.Fatalf("lundi = %v, dimanche = %v", p.WeekdayHour[0], p.WeekdayHour[6])
	}
	if p.LongestPlay == nil || p.LongestPlay.Title != "Dune" || p.LongestPlay.Watched != 9000 {
		t.Fatalf("longest = %+v", p.LongestPlay)
	}
	if p.Marathon == nil || p.Marathon.Title != "Severance" || p.Marathon.Episodes != 2 || p.Marathon.Date != "2026-09-14" {
		t.Fatalf("marathon = %+v", p.Marathon)
	}
	if p.ShowsCount != 1 || p.ShowsFinished != 1 || len(p.Shows) != 1 {
		t.Fatalf("shows = %d / %d, %+v", p.ShowsCount, p.ShowsFinished, p.Shows)
	}
	if s := p.Shows[0]; s.Title != "Severance" || s.EpisodesSeen != 2 || s.EpisodesTotal != 2 || !s.Finished || s.PosterURL != "/sev.jpg" {
		t.Fatalf("Severance = %+v (le spécial de la saison 0 ne compte pas)", s)
	}
	if len(p.UnfinishedMovies) != 1 || p.UnfinishedMovies[0].Title != "Tenet" || p.UnfinishedMovies[0].Percent != 50 {
		t.Fatalf("à finir = %+v", p.UnfinishedMovies)
	}
	if p.AverageMovieSeconds != 9000 {
		t.Fatalf("durée moyenne = %d", p.AverageMovieSeconds)
	}
	if len(p.Decades) != 1 || p.Decades[0].Decade != 2020 || p.Decades[0].Titles != 3 {
		t.Fatalf("décennies = %+v", p.Decades)
	}
	wantGenres := []genreStat{{878, 2, 15000}, {12, 1, 9000}, {14, 1, 6000}, {18, 1, 6000}}
	if len(p.Genres) != len(wantGenres) {
		t.Fatalf("genres = %+v", p.Genres)
	}
	for i, g := range wantGenres {
		if p.Genres[i] != g {
			t.Fatalf("genres = %+v ; attendu %+v (Sci-Fi & Fantasy replié sur 878 et 14)", p.Genres, wantGenres)
		}
	}
	if len(p.Devices) != 2 || p.Devices[0].Label != "PC" || p.Devices[0].Watched != 10800 || p.Devices[1].Secondary != "Android TV 1.4.2" {
		t.Fatalf("appareils = %+v", p.Devices)
	}
	if p.Lifetime.Plays != 6 || p.Lifetime.Watched != 26400 {
		t.Fatalf("depuis le début = %+v", p.Lifetime)
	}
	if r := p.Lifetime.MostRewatched; r == nil || r.Title != "Dune" || r.Times != 2 {
		t.Fatalf("le plus revu = %+v", r)
	}
}

func TestMyStatsAllTimeStartsAtTheFirstPlay(t *testing.T) {
	seedPersonalStats(t)
	rec := httptest.NewRecorder()
	GetMyPlaybackStats(rec, httptest.NewRequest(http.MethodGet, "/api/me/stats?all=1&tz_offset=0", nil), nil, 3)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body)
	}
	var stats PlaybackStats
	if err := json.NewDecoder(rec.Body).Decode(&stats); err != nil {
		t.Fatal(err)
	}
	// Le serveur compte en heure réelle : la première lecture remonte au
	// moins à 40 jours avant le 14 septembre 2026.
	if stats.Personal == nil || !stats.Personal.AllTime || stats.Personal.Previous != nil {
		t.Fatalf("personal = %+v", stats.Personal)
	}
	if stats.Days < 41 || len(stats.Daily) != stats.Days || stats.TopUsers != nil {
		t.Fatalf("days = %d, daily = %d, top users = %v", stats.Days, len(stats.Daily), stats.TopUsers)
	}
}

func TestAdminStatsCarryNoPersonalSection(t *testing.T) {
	seedPersonalStats(t)
	rec := httptest.NewRecorder()
	GetPlaybackStats(rec, httptest.NewRequest(http.MethodGet, "/api/admin/stats?days=7", nil), nil, 1)
	var raw map[string]any
	if err := json.NewDecoder(rec.Body).Decode(&raw); err != nil {
		t.Fatal(err)
	}
	if _, ok := raw["personal"]; ok {
		t.Fatal("les statistiques du serveur ne portent pas le détail d'un compte")
	}
}
