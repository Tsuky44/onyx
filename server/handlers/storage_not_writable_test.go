//go:build linux || darwin

package handlers

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"project-player/server/database"
	"project-player/server/libraries"
	"project-player/server/mediahub"
	"project-player/server/models"
)

// Un dossier de médias où Onyx ne peut pas écrire (« :ro », PUID) : Onyx le
// dit avant de toucher à quoi que ce soit, et laisse le gestionnaire, qui a
// le droit d'écrire, effacer les fichiers (ADR-0128).

// readOnlyMovie crée un film dans un dossier en lecture seule d'une
// bibliothèque de films.
func readOnlyMovie(t *testing.T) (id int, folder, video string) {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Skip("root écrit partout : le dossier en lecture seule ne bloque rien")
	}
	root := t.TempDir()
	if _, err := libraries.Create("Films", libraries.KindMovies, root); err != nil {
		t.Fatalf("create library: %v", err)
	}
	folder = filepath.Join(root, "Heat (1995)")
	if err := os.MkdirAll(folder, 0o755); err != nil {
		t.Fatal(err)
	}
	video = filepath.Join(folder, "heat.mkv")
	if err := os.WriteFile(video, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(folder, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(folder, 0o755) })
	id = insertMediaRow(t, "movie", "Heat", filepath.ToSlash(video), 0)
	setStorageRow(t, id, 1, 949, 0)
	return id, folder, video
}

func assertMovieUntouched(t *testing.T, id int, video string) {
	t.Helper()
	if _, err := os.Stat(video); err != nil {
		t.Fatalf("le fichier a disparu : %v", err)
	}
	var n int
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM medias WHERE id = ?`, id).Scan(&n)
	if n != 1 {
		t.Fatal("le film a quitté le catalogue")
	}
}

func TestMediaHubLearnsBeforehandThatOnyxCannotWriteInTheMovieFolder(t *testing.T) {
	setupDirectory(t)
	id, folder, video := readOnlyMovie(t)

	rec := callStorage(RequireMediaHubKey(MediaHubCheckDeletableStorage), http.MethodGet, id, directoryKey)
	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), "Heat (1995)") ||
		!strings.Contains(rec.Body.String(), ":ro") {
		t.Fatalf("pré-vérification : HTTP %d %s, attendu 409 qui nomme le dossier", rec.Code, rec.Body.String())
	}
	if rec := callStorage(RequireMediaHubKey(MediaHubDeleteStorage), http.MethodDelete, id, directoryKey); rec.Code != http.StatusConflict {
		t.Fatalf("suppression : HTTP %d %s, attendu 409", rec.Code, rec.Body.String())
	}
	assertMovieUntouched(t, id, video)

	if err := os.Chmod(folder, 0o755); err != nil {
		t.Fatal(err)
	}
	if rec := callStorage(RequireMediaHubKey(MediaHubCheckDeletableStorage), http.MethodGet, id, directoryKey); rec.Code != http.StatusNoContent {
		t.Fatalf("dossier inscriptible : HTTP %d %s, attendu 204", rec.Code, rec.Body.String())
	}
	assertMovieUntouched(t, id, video)
}

func TestAdminDeleteLetsTheManagerEraseWhatOnyxCannotWrite(t *testing.T) {
	setupDirectory(t)
	admin := createTestUser(t, "admin", true, models.DefaultPermissions())
	id, folder, video := readOnlyMovie(t)
	// sorraa, lui, a le droit d'écrire : il efface le film quand MediaHub le
	// lui retire (ADR-0128).
	var removals int
	companionStub(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case mediahub.V1Path + "/ping":
			_, _ = w.Write([]byte(`{"status":"ok","service":"mediahub","apiVersion":1}`))
		case mediahub.V1Path + "/library/removals":
			removals++
			_ = os.Chmod(folder, 0o755)
			_ = os.Remove(video)
			_, _ = w.Write([]byte(`{"manager":"sorraa","managerRemoved":true,"requestsRemoved":0}`))
		default:
			http.NotFound(w, r)
		}
	})

	if rec := callAdminDelete(id, admin); rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s, attendu 200 : sorraa a effacé le fichier", rec.Code, rec.Body.String())
	}
	if removals != 1 {
		t.Fatalf("MediaHub appelé %d fois, attendu une", removals)
	}
	var n int
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM medias WHERE id = ?`, id).Scan(&n)
	if n != 0 {
		t.Fatal("le film reste au catalogue après que sorraa l'a effacé")
	}
}
