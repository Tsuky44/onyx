package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"project-player/server/database"
	"project-player/server/mediahub"
	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

// Le gestionnaire de stockage de l'administration d'Onyx (ADR-0115).

func TestAdminStorageListsMoviesAndShowsWithPosterAndWithoutMediaHub(t *testing.T) {
	setupDirectory(t)
	admin := createTestUser(t, "admin", true, models.DefaultPermissions())
	heat := insertMediaRow(t, "movie", "Heat", "/films/heat.mkv", 0)
	setStorageRow(t, heat, 8_000, 949, 0)
	if _, err := database.DB.Exec(`UPDATE medias SET poster_url = '/p/heat.jpg' WHERE id = ?`, heat); err != nil {
		t.Fatalf("update poster: %v", err)
	}
	show := insertMediaRow(t, "show", "Dark", "", 0)
	s1 := insertMediaRow(t, "season", "Saison 1", "", show)
	e1 := insertMediaRow(t, "episode", "E1", "/tv/Dark/S01/e1.mkv", s1)
	setStorageRow(t, e1, 1_000, 0, 1)

	rec := httptest.NewRecorder()
	AdminStorage(rec, httptest.NewRequest(http.MethodGet, "/api/admin/storage", nil), nil, admin)
	var list adminStorageList
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil || rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if list.RequestsAvailable {
		t.Fatal("sans MediaHub, les demandes ne sont pas connues")
	}
	if len(list.Items) != 2 || list.Items[0].Title != "Heat" || list.Items[0].PosterURL != "/p/heat.jpg" || list.Items[0].Size != 8_000 {
		t.Fatalf("films d'abord, avec l'affiche : %+v", list.Items)
	}
	if list.Items[1].Type != "show" || list.Items[1].Size != 1_000 || list.Items[1].Requests == nil {
		t.Fatalf("série = %+v", list.Items[1])
	}
}

func TestAdminStorageMatchesMediaHubRequestsByTMDBAndType(t *testing.T) {
	rows := []mediaHubStorageItem{
		{ID: 1, Type: "movie", TMDBID: 949},
		{ID: 2, Type: "show", TMDBID: 949},
		{ID: 3, Type: "movie"},
	}
	lots := []mediahub.Lot{
		{MediaType: "movie", TMDBID: 949, Requester: "lea", RequestedAt: "2026-01-01T10:00:00Z", Status: "available"},
		{MediaType: "tv", TMDBID: 949, Requester: "max", Seasons: []int{1, 2}, Status: "partial"},
		{MediaType: "tv", TMDBID: 949, Requester: "  "},
		{MediaType: "movie", TMDBID: 0, Requester: "zoe"},
	}
	items := attachStorageRequests(rows, map[int]string{1: "/p.jpg"}, lots)
	if len(items[0].Requests) != 1 || items[0].Requests[0].Requester != "lea" || items[0].PosterURL != "/p.jpg" {
		t.Fatalf("film = %+v", items[0])
	}
	// MediaHub écrit « tv », Onyx « show » : même titre, même demande.
	if len(items[1].Requests) != 1 || items[1].Requests[0].Requester != "max" || len(items[1].Requests[0].Seasons) != 2 {
		t.Fatalf("série = %+v", items[1])
	}
	if items[2].Requests == nil || len(items[2].Requests) != 0 {
		t.Fatalf("sans tmdb_id, aucune demande (et une liste vide, pas null) : %+v", items[2])
	}
}

func TestAdminStorageDetailsSayWhichEpisodeEachViewerIsOn(t *testing.T) {
	setupDirectory(t)
	lea := createTestUser(t, "lea", false, models.DefaultPermissions())
	show := insertMediaRow(t, "show", "Dark", "", 0)
	s2 := insertMediaRow(t, "season", "Saison 2", "", show)
	setStorageRow(t, s2, 0, 0, 2)
	e1 := insertMediaRow(t, "episode", "E1", "/tv/Dark/S02/e1.mkv", s2)
	e4 := insertMediaRow(t, "episode", "E4", "/tv/Dark/S02/e4.mkv", s2)
	if _, err := database.DB.Exec(`UPDATE medias SET episode_number = CASE id WHEN ? THEN 1 ELSE 4 END, duration = 3000 WHERE id IN (?, ?)`, e1, e1, e4); err != nil {
		t.Fatalf("update episodes: %v", err)
	}
	addProgress(t, lea, e1, 0, true, "2026-01-01 10:00:00")
	addProgress(t, lea, e4, 750, false, "2026-01-03 10:00:00")

	rec := httptest.NewRecorder()
	MediaHubStorageDetails(rec, httptest.NewRequest(http.MethodGet, "/", nil),
		httprouter.Params{{Key: "id", Value: strconv.Itoa(show)}}, 0)
	var details mediaHubStorageDetails
	if err := json.Unmarshal(rec.Body.Bytes(), &details); err != nil || rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if len(details.Viewers) != 1 {
		t.Fatalf("spectateurs = %+v", details.Viewers)
	}
	got := details.Viewers[0].CurrentEpisode
	if got == nil || got.Season != 2 || got.Episode != 4 || got.PositionSeconds != 750 || got.DurationSeconds != 3000 || got.Finished {
		t.Fatalf("épisode en cours = %+v", got)
	}
}
