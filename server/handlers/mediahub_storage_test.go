package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"project-player/server/database"
	"project-player/server/libraries"
	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

// Le gestionnaire de stockage de MediaHub sur Onyx (ADR-0114).

func callStorage(handle httprouter.Handle, method string, id int, key string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, "/", nil)
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	rec := httptest.NewRecorder()
	handle(rec, req, httprouter.Params{{Key: "id", Value: strconv.Itoa(id)}})
	return rec
}

func setStorageRow(t *testing.T, id int, size int64, tmdbID, season int) {
	t.Helper()
	if _, err := database.DB.Exec(`UPDATE medias SET file_size = ?, tmdb_id = ?, season_number = ? WHERE id = ?`, size, tmdbID, season, id); err != nil {
		t.Fatalf("update media %d: %v", id, err)
	}
}

func addProgress(t *testing.T, userID, mediaID, position int, finished bool, at string) {
	t.Helper()
	if _, err := database.DB.Exec(`INSERT INTO progressions (user_id, media_id, current_position_seconds, is_finished, updated_at) VALUES (?, ?, ?, ?, ?)`,
		userID, mediaID, position, finished, at); err != nil {
		t.Fatalf("insert progression: %v", err)
	}
}

func TestMediaHubStorageNeedsTheIntegrationKey(t *testing.T) {
	setupDirectory(t)
	for name, handle := range map[string]httprouter.Handle{
		"list":    RequireMediaHubKey(MediaHubStorage),
		"details": RequireMediaHubKey(MediaHubStorageDetails),
		"delete":  RequireMediaHubKey(MediaHubDeleteStorage),
	} {
		for _, key := range []string{"", "autre"} {
			if rec := callStorage(handle, http.MethodGet, 1, key); rec.Code != http.StatusUnauthorized {
				t.Errorf("%s avec la clé %q : HTTP %d, attendu 401", name, key, rec.Code)
			}
		}
	}
}

func TestMediaHubStorageListsSizesAndTheLastPlayOfAnyAccount(t *testing.T) {
	setupDirectory(t)
	lea := createTestUser(t, "lea", false, models.DefaultPermissions())
	max := createTestUser(t, "max", false, models.DefaultPermissions())

	heat := insertMediaRow(t, "movie", "Heat", "/films/Heat (1995)/heat.mkv", 0)
	setStorageRow(t, heat, 8_000, 949, 0)
	insertMediaRow(t, "movie", "Alien", "/films/alien.mkv", 0)
	show := insertMediaRow(t, "show", "Dark", "", 0)
	setStorageRow(t, show, 0, 70523, 0)
	s1 := insertMediaRow(t, "season", "Saison 1", "", show)
	s2 := insertMediaRow(t, "season", "Saison 2", "", show)
	e1 := insertMediaRow(t, "episode", "E1", "/tv/Dark/S01/e1.mkv", s1)
	e2 := insertMediaRow(t, "episode", "E2", "/tv/Dark/S02/e1.mkv", s2)
	insertMediaRow(t, "episode", "Sans fichier", "", s2)
	setStorageRow(t, e1, 1_000, 0, 1)
	setStorageRow(t, e2, 2_000, 0, 2)

	addProgress(t, lea, heat, 600, false, "2026-01-01 10:00:00")
	addProgress(t, max, heat, 0, true, "2026-03-01 10:00:00")
	addProgress(t, lea, e2, 1200, false, "2026-02-01 10:00:00")

	rec := callStorage(RequireMediaHubKey(MediaHubStorage), http.MethodGet, 0, directoryKey)
	var list mediaHubStorageList
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil || rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if len(list.Movies) != 2 || list.Movies[1].Title != "Heat" {
		t.Fatalf("films = %+v", list.Movies)
	}
	got := list.Movies[1]
	if got.Size != 8_000 || got.TMDBID != 949 || got.LastPlayedAt != "2026-03-01T10:00:00Z" || got.Path != "/films/Heat (1995)/heat.mkv" {
		t.Fatalf("Heat = %+v", got)
	}
	if list.Movies[0].LastPlayedAt != "" {
		t.Fatalf("Alien n'a jamais été lu : %+v", list.Movies[0])
	}
	if len(list.Shows) != 1 {
		t.Fatalf("séries = %+v", list.Shows)
	}
	dark := list.Shows[0]
	if dark.Size != 3_000 || dark.EpisodeCount != 2 || dark.Path != "/tv/Dark" || dark.LastPlayedAt != "2026-02-01T10:00:00Z" || dark.TMDBID != 70523 {
		t.Fatalf("Dark = %+v", dark)
	}
}

func TestMediaHubStorageDetailsCountWatchedEpisodesPerAccountAndSeason(t *testing.T) {
	setupDirectory(t)
	lea := createTestUser(t, "lea", false, models.DefaultPermissions())
	max := createTestUser(t, "max", false, models.DefaultPermissions())
	show := insertMediaRow(t, "show", "Dark", "", 0)
	s1 := insertMediaRow(t, "season", "Saison 1", "", show)
	s2 := insertMediaRow(t, "season", "Saison 2", "", show)
	setStorageRow(t, s1, 0, 0, 1)
	setStorageRow(t, s2, 0, 0, 2)
	var eps []int
	for i, p := range []string{"/tv/Dark/S01/e1.mkv", "/tv/Dark/S01/e2.mkv", "/tv/Dark/S02/e1.mkv"} {
		parent, season := s1, 1
		if i == 2 {
			parent, season = s2, 2
		}
		id := insertMediaRow(t, "episode", "E", p, parent)
		setStorageRow(t, id, 500, 0, season)
		eps = append(eps, id)
	}
	addProgress(t, lea, eps[0], 0, true, "2026-01-01 10:00:00")
	addProgress(t, lea, eps[1], 0, true, "2026-01-02 10:00:00")
	addProgress(t, max, eps[2], 300, false, "2026-05-01 10:00:00")

	rec := callStorage(RequireMediaHubKey(MediaHubStorageDetails), http.MethodGet, show, directoryKey)
	var details mediaHubStorageDetails
	if err := json.Unmarshal(rec.Body.Bytes(), &details); err != nil || rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if len(details.Seasons) != 2 || details.Seasons[0].Size != 1_000 || details.Seasons[0].EpisodeCount != 2 || details.Seasons[0].Path != "/tv/Dark/S01" {
		t.Fatalf("saisons = %+v", details.Seasons)
	}
	if details.Path != "/tv/Dark" {
		t.Fatalf("chemin = %q", details.Path)
	}
	if len(details.Viewers) != 2 || details.Viewers[0].Username != "max" {
		t.Fatalf("le compte le plus récent d'abord : %+v", details.Viewers)
	}
	l := details.Viewers[1]
	if l.WatchedEpisodes != 2 || l.TotalEpisodes != 3 || l.Finished || len(l.Seasons) != 2 || l.Seasons[0].Watched != 2 || l.Seasons[1].Watched != 0 {
		t.Fatalf("lea = %+v", l)
	}
	if rec := callStorage(RequireMediaHubKey(MediaHubStorageDetails), http.MethodGet, s1, directoryKey); rec.Code != http.StatusNotFound {
		t.Fatalf("une saison n'a pas de fiche : HTTP %d", rec.Code)
	}
}

func TestMediaHubDeletesTheMovieFolderButNeverTheLibraryRoot(t *testing.T) {
	setupDirectory(t)
	root := t.TempDir()
	if _, err := libraries.Create("Films", libraries.KindMovies, root); err != nil {
		t.Fatalf("create library: %v", err)
	}
	folder := filepath.Join(root, "Heat (1995)")
	if err := os.MkdirAll(folder, 0o755); err != nil {
		t.Fatal(err)
	}
	video := filepath.Join(folder, "heat.mkv")
	for _, f := range []string{video, filepath.Join(folder, "heat.nfo"), filepath.Join(root, "flat.mkv")} {
		if err := os.WriteFile(f, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	heat := insertMediaRow(t, "movie", "Heat", filepath.ToSlash(video), 0)
	setStorageRow(t, heat, 1, 0, 0)
	flat := insertMediaRow(t, "movie", "Flat", filepath.ToSlash(filepath.Join(root, "flat.mkv")), 0)

	if rec := callStorage(RequireMediaHubKey(MediaHubDeleteStorage), http.MethodDelete, heat, directoryKey); rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if _, err := os.Stat(folder); !os.IsNotExist(err) {
		t.Fatalf("le dossier du film reste : %v", err)
	}
	var n int
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM medias WHERE id = ?`, heat).Scan(&n)
	if n != 0 {
		t.Fatal("le film reste au catalogue")
	}

	if rec := callStorage(RequireMediaHubKey(MediaHubDeleteStorage), http.MethodDelete, flat, directoryKey); rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if _, err := os.Stat(root); err != nil {
		t.Fatalf("la racine de la bibliothèque a disparu : %v", err)
	}
}

func TestMediaHubRefusesToDeleteAFileOutsideTheLibraries(t *testing.T) {
	setupDirectory(t)
	outside := filepath.Join(t.TempDir(), "ailleurs.mkv")
	if err := os.WriteFile(outside, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	id := insertMediaRow(t, "movie", "Ailleurs", filepath.ToSlash(outside), 0)
	if rec := callStorage(RequireMediaHubKey(MediaHubDeleteStorage), http.MethodDelete, id, directoryKey); rec.Code != http.StatusConflict {
		t.Fatalf("HTTP %d, attendu 409", rec.Code)
	}
	if _, err := os.Stat(outside); err != nil {
		t.Fatalf("le fichier hors bibliothèque a été supprimé : %v", err)
	}
	if rec := callStorage(RequireMediaHubKey(MediaHubDeleteStorage), http.MethodDelete, 9999, directoryKey); rec.Code != http.StatusNotFound {
		t.Fatalf("média inconnu : HTTP %d, attendu 404", rec.Code)
	}
}

func TestStorageCommonDirIsTheFolderSharedByEveryFile(t *testing.T) {
	for _, c := range []struct {
		paths []string
		want  string
	}{
		{nil, ""},
		{[]string{"/tv/Dark/S01/e1.mkv"}, "/tv/Dark/S01"},
		{[]string{"/tv/Dark/S01/e1.mkv", "/tv/Dark/S01/e1.mkv"}, "/tv/Dark/S01"},
		{[]string{"/tv/Dark/S01/e1.mkv", "/tv/Dark/S02/e1.mkv"}, "/tv/Dark"},
		{[]string{"/tv/Dark/e1.mkv", "/tv/Darker/e1.mkv"}, "/tv"},
		{[]string{"/tv/Dark/S01/", "/tv/Dark/S02/"}, "/tv/Dark"},
	} {
		if got := commonDir(c.paths); got != c.want {
			t.Errorf("commonDir(%v) = %q, attendu %q", c.paths, got, c.want)
		}
	}
}
