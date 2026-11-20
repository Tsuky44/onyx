package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"project-player/server/libraries"
	"project-player/server/models"
)

func browseCall(t *testing.T, query string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/fs/browse?"+query, nil)
	rec := httptest.NewRecorder()
	BrowseFolders(rec, req, nil, 0)
	return rec
}

func pathQuery(path string) string { return url.Values{"path": {path}}.Encode() }

// mediaRoot monte une racine de médias dans un dossier temporaire, avec son
// voisin « secret » que l'explorateur ne doit jamais montrer.
func mediaRoot(t *testing.T) (root, secret string) {
	t.Helper()
	parent := t.TempDir()
	root = filepath.Join(parent, "media")
	secret = filepath.Join(parent, "secret")
	for _, dir := range []string{filepath.Join(root, "Films", "Action"), filepath.Join(root, "Séries"), secret} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(root, "Films", "Action", "a.mkv"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MEDIA_ROOT", root)
	return root, secret
}

// Aucune demande ne sort de /media : ni par « .. », ni par un chemin absolu
// d'ailleurs. C'est le garde de la route, vue de l'extérieur.
func TestBrowseRefusesEveryPathOutsideTheRoot(t *testing.T) {
	setupAuthDB(t)
	root, secret := mediaRoot(t)

	for name, path := range map[string]string{
		"parent par ..":    root + "/..",
		"échappée":         root + "/Films/../../secret",
		"dossier voisin":   secret,
		"racine du disque": "/",
		"chemin relatif":   "Films",
	} {
		rec := browseCall(t, pathQuery(path))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s (%q) : HTTP %d, want 400 : %s", name, path, rec.Code, rec.Body.String())
		}
	}
}

func TestBrowseAnswersNotFoundForAMissingFolder(t *testing.T) {
	setupAuthDB(t)
	root, _ := mediaRoot(t)
	if rec := browseCall(t, pathQuery(filepath.Join(root, "Absent"))); rec.Code != http.StatusNotFound {
		t.Fatalf("HTTP %d, want 404 : %s", rec.Code, rec.Body.String())
	}
}

// La forme de la réponse est celle du contrat : le premier lancement de l'app
// la lit telle quelle.
func TestBrowseAnswersTheContractShape(t *testing.T) {
	setupAuthDB(t)
	root, _ := mediaRoot(t)
	if _, err := libraries.Create("Séries", libraries.KindShows, filepath.Join(root, "Séries")); err != nil {
		t.Fatal(err)
	}

	rec := browseCall(t, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", rec.Code, rec.Body.String())
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	keys := make([]string, 0, len(raw))
	for key := range raw {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	want := []string{"breadcrumb", "empty_root", "folders", "parent", "path", "readable", "root"}
	if !reflect.DeepEqual(keys, want) {
		t.Fatalf("clés = %v, want %v", keys, want)
	}
	if string(raw["parent"]) != "null" {
		t.Fatalf("parent à la racine = %s, want null", raw["parent"])
	}

	var listing libraries.Listing
	if err := json.Unmarshal(rec.Body.Bytes(), &listing); err != nil {
		t.Fatal(err)
	}
	if listing.Root != root || listing.Path != root || !listing.Readable || listing.EmptyRoot || len(listing.Folders) != 2 {
		t.Fatalf("racine = %+v", listing)
	}
	films, series := listing.Folders[0], listing.Folders[1]
	if films.Name != "Films" || films.Kind != libraries.KindMovies || films.Covered || films.VideoCount != 1 || films.VideoCountCapped {
		t.Fatalf("Films = %+v", films)
	}
	if !series.Covered {
		t.Fatalf("Séries = %+v, want couvert par la bibliothèque", series)
	}

	// Un sous-dossier : son parent et son fil d'Ariane.
	rec = browseCall(t, pathQuery(filepath.Join(root, "Films")))
	var inside libraries.Listing
	if err := json.Unmarshal(rec.Body.Bytes(), &inside); err != nil || rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", rec.Code, rec.Body.String())
	}
	if inside.Parent == nil || *inside.Parent != root || len(inside.Breadcrumb) != 2 {
		t.Fatalf("Films = %+v", inside)
	}
}

// Une racine non montée n'est pas une erreur : l'assistant en tire le
// diagnostic « montez votre dossier dans le compose ».
func TestBrowseDiagnosesAMissingRootInsteadOfFailing(t *testing.T) {
	setupAuthDB(t)
	t.Setenv("MEDIA_ROOT", filepath.Join(t.TempDir(), "absente"))

	rec := browseCall(t, "")
	var listing libraries.Listing
	if err := json.Unmarshal(rec.Body.Bytes(), &listing); err != nil || rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", rec.Code, rec.Body.String())
	}
	if listing.Readable || !listing.EmptyRoot || len(listing.Folders) != 0 {
		t.Fatalf("racine absente = %+v", listing)
	}
}

// Elle montre le plan du disque du conteneur : réservée à manage_settings.
func TestBrowseNeedsManageSettings(t *testing.T) {
	setupAuthDB(t)
	mediaRoot(t)
	id := createTestUser(t, "bob", false, models.DefaultPermissions())
	token := createTestSession(t, id)

	called := false
	guarded := RequirePermission(models.PermManageSettings, okHandler(&called))
	rec := httptest.NewRecorder()
	guarded(rec, authedRequest(http.MethodGet, "/api/fs/browse", "", token), nil)
	if called || rec.Code != http.StatusForbidden {
		t.Fatalf("called=%v, HTTP %d, want 403 sans appel", called, rec.Code)
	}
}
