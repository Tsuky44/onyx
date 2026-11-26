package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"project-player/server/database"
	"project-player/server/models"
	"project-player/server/ttlcache"

	"github.com/julienschmidt/httprouter"
)

type retroFixture struct {
	showID, movieID int
}

// seedRetro : Léa (compte 3) commence 2026 par Severance le 1er janvier,
// enchaîne six épisodes le 14 mars, voit Dune deux fois en mai (la seconde
// convertie à la volée), un bout de Severance à 3 h 47 en juin. Ce qu'elle
// regarde fin 2025 et en décembre 2026 ne compte pas. Deux autres comptes
// regardent aussi : l'owner plus qu'elle, l'admin un peu de Dune.
func seedRetro(t *testing.T) retroFixture {
	t.Helper()
	fx := setupActivityTestDB(t)
	retroReports = ttlcache.New[*RetroReport](time.Hour, 500)
	prevNow, prevPreview := retroNow, retroPreview
	t.Cleanup(func() { retroNow, retroPreview = prevNow, prevPreview })

	mustExec := func(query string, args ...any) int {
		t.Helper()
		res, err := database.DB.Exec(query, args...)
		if err != nil {
			t.Fatalf("%s: %v", query, err)
		}
		id, _ := res.LastInsertId()
		return int(id)
	}
	r := retroFixture{movieID: fx.movieID}
	var seasonID int
	if err := database.DB.QueryRow(`SELECT id, parent_id FROM medias WHERE type = 'season'`).Scan(&seasonID, &r.showID); err != nil {
		t.Fatalf("season: %v", err)
	}
	episodes := []int{fx.episodeID}
	for n := 2; n <= 7; n++ {
		episodes = append(episodes, mustExec(`INSERT INTO medias (type, title, file_path, duration, parent_id, season_number, episode_number)
			VALUES (?, 'Épisode', '/sev.mkv', 3000, ?, 2, ?)`, models.TypeEpisode, seasonID, n))
	}

	at := func(y int, m time.Month, d, h, min int) time.Time { return time.Date(y, m, d, h, min, 0, 0, time.UTC) }
	play := func(userID, mediaID int, started time.Time, watched int, method string) {
		t.Helper()
		mediaType, title, show, duration := "movie", "Dune", "", 9000
		var showID any
		if mediaID != r.movieID {
			mediaType, title, show, duration, showID = "episode", "Épisode", "Severance", 3000, r.showID
		}
		mustExec(`INSERT INTO playback_history (user_id, media_id, media_type, title, show_id, show_title, device_name,
			client, play_method, started_at, ended_at, watched_seconds, duration_seconds)
			VALUES (?, ?, ?, ?, ?, ?, 'Salon', 'Android TV 1.4.2', ?, ?, ?, ?, ?)`,
			userID, mediaID, mediaType, title, showID, show, method,
			historyStamp(started), historyStamp(started.Add(time.Duration(watched)*time.Second)), watched, duration)
	}

	play(3, r.movieID, at(2025, time.December, 31, 22, 0), 9000, "direct") // l'an dernier
	play(3, episodes[0], at(2026, time.January, 1, 11, 2), 3000, "direct")
	for i, ep := range episodes[1:] {
		play(3, ep, at(2026, time.March, 14, 14+i, 0), 3000, "direct")
	}
	play(3, r.movieID, at(2026, time.May, 2, 20, 0), 9000, "direct")
	play(3, r.movieID, at(2026, time.May, 9, 20, 0), 9000, "transcode")
	play(3, episodes[0], at(2026, time.June, 10, 3, 47), 1200, "")
	play(3, r.movieID, at(2026, time.June, 11, 1, 10), 600, "direct") // trop court pour « vu une fois »
	play(3, r.movieID, at(2026, time.December, 5, 20, 0), 9000, "direct")

	play(1, episodes[0], at(2026, time.April, 1, 20, 0), 50000, "direct")
	play(2, r.movieID, at(2026, time.August, 1, 20, 0), 1000, "direct")
	return r
}

func TestRetroTellsTheCallersYearFromJanuaryToNovember(t *testing.T) {
	fx := seedRetro(t)
	r, err := computeRetro(3, 2026, 0)
	if err != nil {
		t.Fatal(err)
	}
	if !r.Eligible || r.WatchedSeconds != 40800 || r.Plays != 11 || r.Titles != 2 || r.MovieSeconds != 18600 {
		t.Fatalf("totaux = éligible %v, %d s, %d lectures, %d titres, %d s de films (fin 2025 et décembre exclus)",
			r.Eligible, r.WatchedSeconds, r.Plays, r.Titles, r.MovieSeconds)
	}
	want := []retroTitle{
		{MediaID: fx.showID, Title: "Severance", MediaType: "show", PosterURL: "/sev.jpg", Watched: 22200, Episodes: 7},
		{MediaID: fx.movieID, Title: "Dune", MediaType: "movie", PosterURL: "/dune.jpg", Watched: 18600, Times: 2},
	}
	if len(r.Top) != len(want) {
		t.Fatalf("top = %+v", r.Top)
	}
	for i := range want {
		if r.Top[i] != want[i] {
			t.Fatalf("top[%d] = %+v ; attendu %+v", i, r.Top[i], want[i])
		}
	}
	if r.Months[0] != 3000 || r.Months[2] != 18000 || r.Months[4] != 18000 || r.Months[5] != 1800 || r.Months[11] != 0 {
		t.Fatalf("mois = %v", r.Months)
	}
	if r.Hours[3] != 1200 || r.Hours[1] != 600 || r.Hours[20] != 18000 {
		t.Fatalf("heures = %v", r.Hours)
	}
	// Le 14 mars, le 2 et le 9 mai 2026 sont des samedis : la grille
	// commence le lundi.
	if r.Weekdays[5] != 36000 {
		t.Fatalf("jours = %v", r.Weekdays)
	}
	if m := r.Marathon; m == nil || m.Title != "Severance" || m.Episodes != 6 || m.Date != "2026-03-14" {
		t.Fatalf("marathon = %+v", m)
	}
	if f := r.FirstPlay; f == nil || f.Title != "Severance" || f.At != "2026-01-01T11:02" {
		t.Fatalf("première séance = %+v", f)
	}
	if n := r.LatestNight; n == nil || n.Title != "Severance" || n.At != "2026-06-10T03:47" {
		t.Fatalf("plus tardive = %+v", n)
	}
	if len(r.Devices) != 1 || r.Devices[0].Label != "Salon" {
		t.Fatalf("appareils = %+v", r.Devices)
	}
	if r.DirectPercent != 77 {
		t.Fatalf("lecture directe = %d %% ; attendu 77 (une méthode vide compte comme directe)", r.DirectPercent)
	}
	if r.Archetype != archetypeMarathon {
		t.Fatalf("profil = %q", r.Archetype)
	}
	s := r.Server
	if s.Members != 3 || s.WatchedSeconds != 91800 || s.Rank != 2 || s.TopTitle != "Severance" || s.TopTitleViewers != 2 {
		t.Fatalf("serveur = %+v", s)
	}
}

func TestRetroUnderFiveHoursSaysOnlyThat(t *testing.T) {
	seedRetro(t)
	r, err := computeRetro(2, 2026, 0)
	if err != nil {
		t.Fatal(err)
	}
	if r.Eligible || r.WatchedSeconds != 0 || len(r.Top) != 0 || r.Archetype != "" || r.Server.Members != 0 {
		t.Fatalf("sous le seuil = %+v", r)
	}
}

func TestRetroRoutesFollowTheCalendarAndRememberTheView(t *testing.T) {
	seedRetro(t)
	retroNow = func() time.Time { return time.Date(2026, time.November, 26, 10, 0, 0, 0, time.UTC) }
	retroPreview = func() bool { return false }

	status := func() RetroStatus {
		t.Helper()
		rec := httptest.NewRecorder()
		GetMyRetroStatus(rec, httptest.NewRequest(http.MethodGet, "/api/me/retro?tz_offset=0", nil), nil, 3)
		if rec.Code != http.StatusOK {
			t.Fatalf("statut : %d %s", rec.Code, rec.Body)
		}
		var s RetroStatus
		if err := json.NewDecoder(rec.Body).Decode(&s); err != nil {
			t.Fatal(err)
		}
		return s
	}
	call := func(handler func(http.ResponseWriter, *http.Request, httprouter.Params, int), method, year string) int {
		rec := httptest.NewRecorder()
		handler(rec, httptest.NewRequest(method, "/api/me/retro/"+year, nil), httprouter.Params{{Key: "year", Value: year}}, 3)
		return rec.Code
	}

	if s := status(); s.Open || s.Eligible || s.Year != 2026 || s.EndsAt != "2027-01-16T00:00:00Z" {
		t.Fatalf("en novembre = %+v", s)
	}
	if code := call(GetMyRetro, http.MethodGet, "2026"); code != http.StatusNotFound {
		t.Fatalf("Rétro en novembre : %d ; attendu 404", code)
	}

	retroPreview = func() bool { return true }
	if s := status(); !s.Open || !s.Eligible || s.Seen {
		t.Fatalf("en aperçu = %+v", s)
	}
	if code := call(GetMyRetro, http.MethodGet, "2026"); code != http.StatusOK {
		t.Fatalf("Rétro en aperçu : %d", code)
	}
	if code := call(GetMyRetro, http.MethodGet, "2025"); code != http.StatusNotFound {
		t.Fatalf("une autre année : %d ; attendu 404", code)
	}
	if code := call(GetMyRetro, http.MethodGet, "deux-mille"); code != http.StatusBadRequest {
		t.Fatalf("année illisible : %d ; attendu 400", code)
	}
	for i := 0; i < 2; i++ { // la seconde fois ne change rien
		if code := call(MarkMyRetroSeen, http.MethodPost, "2026"); code != http.StatusNoContent {
			t.Fatalf("vu : %d", code)
		}
	}
	if s := status(); !s.Seen {
		t.Fatalf("après l'ouverture = %+v", s)
	}
}
