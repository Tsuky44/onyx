package handlers

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"project-player/server/database"
	"project-player/server/libraries"
	"project-player/server/mediahub"
	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

// La suppression depuis l'administration d'Onyx (ADR-0115) : MediaHub
// oublie le titre avant qu'Onyx n'en efface les fichiers.

// showOnDisk crée une série de deux saisons sous une bibliothèque de séries.
func showOnDisk(t *testing.T) (show, season2 int, files []string) {
	t.Helper()
	root := t.TempDir()
	if _, err := libraries.Create("Séries", libraries.KindShows, root); err != nil {
		t.Fatalf("create library: %v", err)
	}
	show = insertMediaRow(t, "show", "Dark", "", 0)
	setStorageRow(t, show, 0, 70523, 0)
	for n := 1; n <= 2; n++ {
		season := insertMediaRow(t, "season", "Saison "+strconv.Itoa(n), "", show)
		setStorageRow(t, season, 0, 0, n)
		if n == 2 {
			season2 = season
		}
		path := filepath.Join(root, "Dark", "S0"+strconv.Itoa(n), "e1.mkv")
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
		ep := insertMediaRow(t, "episode", "E1", filepath.ToSlash(path), season)
		setStorageRow(t, ep, 1, 0, n)
		files = append(files, path)
	}
	return show, season2, files
}

func callAdminDelete(id, userID int) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	AdminDeleteStorage(rec, httptest.NewRequest(http.MethodDelete, "/api/admin/storage/"+strconv.Itoa(id), nil),
		httprouter.Params{{Key: "id", Value: strconv.Itoa(id)}}, userID)
	return rec
}

// mediaHubRemovals monte un MediaHub v1 qui répond aux retraits par status
// et garde le corps de chaque demande.
func mediaHubRemovals(t *testing.T, status int, answer string) *[]string {
	t.Helper()
	var bodies []string
	companionStub(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case mediahub.V1Path + "/ping":
			_, _ = w.Write([]byte(`{"status":"ok","service":"mediahub","apiVersion":1}`))
		case mediahub.V1Path + "/library/removals":
			body, _ := io.ReadAll(r.Body)
			bodies = append(bodies, string(body))
			if r.Header.Get("X-Player-Username") != "admin" {
				t.Errorf("appel sans le compte de l'administrateur : %v", r.Header)
			}
			w.WriteHeader(status)
			_, _ = w.Write([]byte(answer))
		default:
			http.NotFound(w, r)
		}
	})
	return &bodies
}

func TestAdminDeleteAsksMediaHubToForgetTheSeasonBeforeErasingIt(t *testing.T) {
	setupDirectory(t)
	admin := createTestUser(t, "admin", true, models.DefaultPermissions())
	_, season2, files := showOnDisk(t)
	bodies := mediaHubRemovals(t, http.StatusOK, `{"manager":"sorraa","managerRemoved":true,"requestsRemoved":1}`)

	rec := callAdminDelete(season2, admin)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if len(*bodies) != 1 || !strings.Contains((*bodies)[0], `"tmdbId":70523`) ||
		!strings.Contains((*bodies)[0], `"mediaType":"tv"`) || !strings.Contains((*bodies)[0], `"season":2`) {
		t.Fatalf("MediaHub doit recevoir la série et sa saison : %v", *bodies)
	}
	var got adminStorageDeleteResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil || got.MediaHub == nil || !got.MediaHub.ManagerRemoved || got.FilesRemoved != 1 {
		t.Fatalf("réponse = %s", rec.Body.String())
	}
	if _, err := os.Stat(files[1]); !os.IsNotExist(err) {
		t.Fatal("la saison 2 reste sur le disque")
	}
	if _, err := os.Stat(files[0]); err != nil {
		t.Fatalf("la saison 1 a disparu : %v", err)
	}
}

func TestAdminDeleteKeepsTheFilesWhenMediaHubCannotForgetTheShow(t *testing.T) {
	setupDirectory(t)
	admin := createTestUser(t, "admin", true, models.DefaultPermissions())
	show, _, files := showOnDisk(t)
	bodies := mediaHubRemovals(t, http.StatusBadGateway, `{"error":"sorraa injoignable.","code":"manager_failed"}`)

	rec := callAdminDelete(show, admin)
	if rec.Code != http.StatusBadGateway || !strings.Contains(rec.Body.String(), "sorraa injoignable.") {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if len(*bodies) != 1 || strings.Contains((*bodies)[0], "season") {
		t.Fatalf("la série entière, sans saison : %v", *bodies)
	}
	for _, f := range files {
		if _, err := os.Stat(f); err != nil {
			t.Fatalf("un fichier a été supprimé alors que sorraa suit toujours la série : %v", err)
		}
	}
	var n int
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM medias WHERE id = ?`, show).Scan(&n)
	if n != 1 {
		t.Fatal("la série a quitté le catalogue")
	}
}

func TestAdminDeleteNeverReachesMediaHubForAFileOnyxWouldRefuse(t *testing.T) {
	setupDirectory(t)
	admin := createTestUser(t, "admin", true, models.DefaultPermissions())
	outside := filepath.Join(t.TempDir(), "ailleurs.mkv")
	if err := os.WriteFile(outside, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	movie := insertMediaRow(t, "movie", "Ailleurs", filepath.ToSlash(outside), 0)
	setStorageRow(t, movie, 1, 949, 0)
	bodies := mediaHubRemovals(t, http.StatusOK, `{}`)

	if rec := callAdminDelete(movie, admin); rec.Code != http.StatusConflict {
		t.Fatalf("HTTP %d, attendu 409", rec.Code)
	}
	if len(*bodies) != 0 {
		t.Fatal("MediaHub a oublié un titre qu'Onyx refuse de supprimer")
	}
}

func TestAdminDeleteWithoutMediaHubOnlyErasesTheFiles(t *testing.T) {
	setupDirectory(t)
	admin := createTestUser(t, "admin", true, models.DefaultPermissions())
	show, _, files := showOnDisk(t)

	rec := callAdminDelete(show, admin)
	var got adminStorageDeleteResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil || rec.Code != http.StatusOK || got.MediaHub != nil || got.FilesRemoved != 2 {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	for _, f := range files {
		if _, err := os.Stat(f); !os.IsNotExist(err) {
			t.Fatalf("%s reste sur le disque", f)
		}
	}
}

func TestAdminDeleteErasesTheFilesItselfWhenSorraaKnowsNothingOfTheTitle(t *testing.T) {
	setupDirectory(t)
	admin := createTestUser(t, "admin", true, models.DefaultPermissions())
	show, _, files := showOnDisk(t)
	// Ni média ni demande chez sorraa : MediaHub n'a rien retiré.
	bodies := mediaHubRemovals(t, http.StatusOK, `{"manager":"sorraa","managerRemoved":false,"requestsRemoved":0}`)

	rec := callAdminDelete(show, admin)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if len(*bodies) != 1 {
		t.Fatalf("MediaHub doit être interrogé une fois : %v", *bodies)
	}
	for _, f := range files {
		if _, err := os.Stat(f); !os.IsNotExist(err) {
			t.Fatalf("Onyx doit effacer lui-même %s : %v", f, err)
		}
	}
	var n int
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM medias WHERE id = ?`, show).Scan(&n)
	if n != 0 {
		t.Fatal("la série reste au catalogue")
	}
}
