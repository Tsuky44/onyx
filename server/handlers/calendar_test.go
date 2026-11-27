package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"project-player/server/calendar"
	"project-player/server/database"

	"github.com/julienschmidt/httprouter"
)

type calendarFixture struct {
	watchedShowID, watchedEpisodeID int
}

// seedCalendar : Léa (compte 1) regarde Les Veilleurs (TMDB 100), dont le
// serveur a les épisodes 1 et 2 de la saison 2. La Ligue (TMDB 300) vient de
// recevoir un épisode ; Vieille série (TMDB 200) n'a rien reçu depuis deux
// ans et personne ne la regarde.
func seedCalendar(t *testing.T) calendarFixture {
	t.Helper()
	seedRequestUser(t, 1, "lea")
	exec := func(query string, args ...any) int {
		t.Helper()
		res, err := database.DB.Exec(query, args...)
		if err != nil {
			t.Fatalf("%s: %v", query, err)
		}
		id, _ := res.LastInsertId()
		return int(id)
	}
	now := time.Now().UTC()
	old := now.AddDate(-2, 0, 0).Format("2006-01-02 15:04:05")
	recent := now.AddDate(0, 0, -3).Format("2006-01-02 15:04:05")

	var fx calendarFixture
	fx.watchedShowID = exec(`INSERT INTO medias (type, title, tmdb_id, poster_url, created_at) VALUES ('show', 'Les Veilleurs', 100, '/p/veilleurs.jpg', ?)`, old)
	season := exec(`INSERT INTO medias (type, title, parent_id, season_number, created_at) VALUES ('season', 'Saison 2', ?, 2, ?)`, fx.watchedShowID, old)
	fx.watchedEpisodeID = exec(`INSERT INTO medias (type, title, file_path, parent_id, season_number, episode_number, created_at) VALUES ('episode', 'É1', '/v/s2e1.mkv', ?, 2, 1, ?)`, season, old)
	exec(`INSERT INTO medias (type, title, file_path, parent_id, season_number, episode_number, created_at) VALUES ('episode', 'É2', '/v/s2e2.mkv', ?, 2, 2, ?)`, season, old)
	exec(`INSERT INTO progressions (user_id, media_id, current_position_seconds, updated_at) VALUES (1, ?, 600, ?)`, fx.watchedEpisodeID, recent)

	oldShow := exec(`INSERT INTO medias (type, title, tmdb_id, created_at) VALUES ('show', 'Vieille série', 200, ?)`, old)
	oldSeason := exec(`INSERT INTO medias (type, title, parent_id, season_number, created_at) VALUES ('season', 'Saison 1', ?, 1, ?)`, oldShow, old)
	exec(`INSERT INTO medias (type, title, file_path, parent_id, season_number, episode_number, created_at) VALUES ('episode', 'É1', '/o/e1.mkv', ?, 1, 1, ?)`, oldSeason, old)

	league := exec(`INSERT INTO medias (type, title, tmdb_id, created_at) VALUES ('show', 'La Ligue', 300, ?)`, recent)
	leagueSeason := exec(`INSERT INTO medias (type, title, parent_id, season_number, created_at) VALUES ('season', 'Saison 5', ?, 5, ?)`, league, recent)
	exec(`INSERT INTO medias (type, title, file_path, parent_id, season_number, episode_number, created_at) VALUES ('episode', 'É1', '/l/e1.mkv', ?, 5, 1, ?)`, leagueSeason, recent)
	return fx
}

func getCalendar(t *testing.T, query string) (int, CalendarResponse) {
	t.Helper()
	rec := httptest.NewRecorder()
	GetCalendar(rec, httptest.NewRequest(http.MethodGet, "/api/calendar"+query, nil), nil, 1)
	var resp CalendarResponse
	if rec.Code == http.StatusOK {
		if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
			t.Fatalf("decode: %v", err)
		}
	}
	return rec.Code, resp
}

func setCalendarFollow(t *testing.T, method string, tmdbID string) int {
	t.Helper()
	rec := httptest.NewRecorder()
	ps := httprouter.Params{{Key: "tmdbId", Value: tmdbID}}
	if method == http.MethodPut {
		FollowCalendarShow(rec, httptest.NewRequest(method, "/", nil), ps, 1)
	} else {
		UnfollowCalendarShow(rec, httptest.NewRequest(method, "/", nil), ps, 1)
	}
	return rec.Code
}

func followedByTMDB(resp CalendarResponse) map[int]calendar.FollowedShow {
	out := map[int]calendar.FollowedShow{}
	for _, f := range resp.Followed {
		out[f.TMDBID] = f
	}
	return out
}

// Le programme TMDB est posé dans le cache : les tests ne parlent pas à TMDB.
func primeCalendarShow(t *testing.T, tmdbID int, show calendar.Show) {
	t.Helper()
	key := calendarCacheKey(tmdbID, languageOf(httptest.NewRequest(http.MethodGet, "/", nil)))
	calendarShowCache.Put(key, show)
	t.Cleanup(func() { calendarShowCache.Delete(key) })
}

func TestCalendarShowsWatchedAndRecentServerShowsButNotTheWholeLibrary(t *testing.T) {
	fx := seedCalendar(t)
	code, resp := getCalendar(t, "")
	if code != http.StatusOK {
		t.Fatalf("status = %d", code)
	}
	followed := followedByTMDB(resp)
	if f, ok := followed[100]; !ok || f.Source != calendar.SourceWatching || f.MediaID != fx.watchedShowID || f.PosterURL != "/p/veilleurs.jpg" {
		t.Errorf("Les Veilleurs = %+v (présente : %v)", f, ok)
	}
	if f, ok := followed[300]; !ok || f.Source != calendar.SourceServer {
		t.Errorf("La Ligue, qui vient de recevoir un épisode, doit y être : %+v", resp.Followed)
	}
	if _, ok := followed[200]; ok {
		t.Errorf("une série muette depuis deux ans et jamais regardée n'a rien à faire dans le calendrier")
	}
}

func TestCalendarEntriesMarkEpisodesTheServerAlreadyHas(t *testing.T) {
	seedCalendar(t)
	today := time.Now().UTC()
	day := func(offset int) string { return today.AddDate(0, 0, offset).Format("2006-01-02") }
	primeCalendarShow(t, 100, calendar.Show{Name: "The Watchers", Episodes: []calendar.Episode{
		{Season: 2, Number: 2, AirDate: day(0)},
		{Season: 2, Number: 3, AirDate: day(7), Type: "finale"},
		{Season: 2, Number: 1, AirDate: day(-400)}, // hors fenêtre
	}})
	_, resp := getCalendar(t, "?today="+day(0))
	var veilleurs []calendar.Entry
	for _, e := range resp.Entries {
		if e.TMDBID == 100 {
			veilleurs = append(veilleurs, e)
		}
	}
	if len(veilleurs) != 2 {
		t.Fatalf("entrées = %+v", resp.Entries)
	}
	if !veilleurs[0].Ready || veilleurs[0].EpisodeMediaID == 0 || veilleurs[0].Title != "Les Veilleurs" {
		t.Errorf("l'épisode 2 est sur le serveur : %+v", veilleurs[0])
	}
	if veilleurs[1].Ready || veilleurs[1].EpisodeType != "finale" {
		t.Errorf("l'épisode 3 n'est pas encore là : %+v", veilleurs[1])
	}
	if f := followedByTMDB(resp)[100]; f.NextAirDate != day(0) || f.NextEpisode != 2 {
		t.Errorf("prochain épisode = %+v", f)
	}
}

func TestCalendarUnfollowedShowStaysOutUntilFollowedAgain(t *testing.T) {
	seedCalendar(t)
	if code := setCalendarFollow(t, http.MethodDelete, "100"); code != http.StatusNoContent {
		t.Fatalf("DELETE = %d", code)
	}
	_, resp := getCalendar(t, "")
	if _, ok := followedByTMDB(resp)[100]; ok {
		t.Fatalf("une série retirée ne revient pas parce qu'on la regarde")
	}

	if code := setCalendarFollow(t, http.MethodPut, "100"); code != http.StatusNoContent {
		t.Fatalf("PUT = %d", code)
	}
	_, resp = getCalendar(t, "")
	if f := followedByTMDB(resp)[100]; f.Source != calendar.SourceFollowed {
		t.Fatalf("après « Suivre », la série est suivie à la main : %+v", resp.Followed)
	}
}

func TestCalendarRejectsInvalidInput(t *testing.T) {
	seedCalendar(t)
	for _, q := range []string{"?from=27-11-2026", "?from=2026-12-01&to=2026-11-01", "?from=2026-01-01&to=2028-01-01", "?today=demain"} {
		if code, _ := getCalendar(t, q); code != http.StatusBadRequest {
			t.Errorf("%s : status = %d, want 400", q, code)
		}
	}
	for _, id := range []string{"0", "-3", "abc"} {
		if code := setCalendarFollow(t, http.MethodPut, id); code != http.StatusBadRequest {
			t.Errorf("PUT %s : status = %d, want 400", id, code)
		}
	}
}
