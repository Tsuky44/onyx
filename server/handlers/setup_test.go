package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"project-player/server/config"
	"project-player/server/database"
	"project-player/server/libraries"
)

// resetSettings vide les réglages à la fin du test : le cache de config survit
// d'un test à l'autre.
func resetSettings(t *testing.T) {
	t.Helper()
	t.Setenv("TMDB_API_KEY", "")
	t.Setenv("MEDIAHUB_URL", "")
	t.Setenv("MEDIAHUB_API_KEY", "")
	clearSettings(t)
	t.Cleanup(func() { clearSettings(t) })
}

func clearSettings(t *testing.T) {
	t.Helper()
	if _, err := database.DB.Exec(`DELETE FROM app_settings`); err != nil {
		t.Errorf("nettoyage des réglages : %v", err)
	}
	config.LoadCache()
}

func setupState(t *testing.T) setupStateResponse {
	t.Helper()
	rec := httptest.NewRecorder()
	GetSetupState(rec, httptest.NewRequest(http.MethodGet, "/api/setup/state", nil), nil, 1)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", rec.Code, rec.Body.String())
	}
	var state setupStateResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &state); err != nil {
		t.Fatal(err)
	}
	return state
}

func putSettings(t *testing.T, body string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	UpdateSettings(rec, httptest.NewRequest(http.MethodPut, "/api/settings", bytes.NewBufferString(body)), nil, 1)
	return rec
}

func TestSetupStateOfAFreshServer(t *testing.T) {
	setupAuthDB(t)
	resetSettings(t)

	if got, want := setupState(t), (setupStateResponse{}); got != want {
		t.Fatalf("état = %+v, want %+v", got, want)
	}
}

// Les étapes se lisent dans les données, sans drapeau : un serveur réglé à la
// main a ses étapes faites sans que personne ait lancé l'assistant.
func TestSetupStateIsComputedFromTheData(t *testing.T) {
	setupAuthDB(t)
	resetSettings(t)

	if _, err := libraries.Create("Films", libraries.KindMovies, t.TempDir()); err != nil {
		t.Fatal(err)
	}
	state := setupState(t)
	if state.Libraries != (setupLibrariesState{Count: 1, Done: true}) || state.TMDB.Done || state.Requests.Available || state.Completed {
		t.Fatalf("avec une bibliothèque = %+v", state)
	}

	// Une clé TMDB (ici en variable d'environnement) ouvre l'étape des demandes.
	t.Setenv("TMDB_API_KEY", "cle-tmdb")
	state = setupState(t)
	if !state.TMDB.Done || !state.Requests.Available || state.Requests.Done {
		t.Fatalf("avec une clé TMDB = %+v", state)
	}

	// Le service de demandes est fait quand son adresse et sa clé sont réglées.
	if rec := putSettings(t, `{"mediahub_url":"http://hub:3000","mediahub_api_key":"cle-hub"}`); rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", rec.Code, rec.Body.String())
	}
	if state = setupState(t); !state.Requests.Done || state.Completed {
		t.Fatalf("avec un service de demandes = %+v", state)
	}
}

func TestCompletingTheSetupIsRememberedAndIdempotent(t *testing.T) {
	setupAuthDB(t)
	resetSettings(t)

	for i := 0; i < 2; i++ {
		rec := httptest.NewRecorder()
		CompleteSetup(rec, httptest.NewRequest(http.MethodPost, "/api/setup/complete", nil), nil, 1)
		if rec.Code != http.StatusNoContent || rec.Body.Len() != 0 {
			t.Fatalf("appel %d : HTTP %d, corps %q, want 204 sans corps", i+1, rec.Code, rec.Body.String())
		}
	}
	if !setupState(t).Completed {
		t.Fatal("completed = false après l'appel")
	}

	// Le drapeau est dans la base : il survit à un redémarrage.
	config.LoadCache()
	if !setupState(t).Completed {
		t.Fatal("completed perdu au rechargement des réglages")
	}
}

// Le drapeau n'est pas un réglage que PUT /api/settings écrit, et l'instantané
// des réglages ne le montre pas : un seul chemin le pose.
func TestSetupFlagIsNotASettingOfTheForm(t *testing.T) {
	setupAuthDB(t)
	resetSettings(t)

	putSettings(t, `{"setup_completed":"true"}`)
	if config.SetupCompleted() {
		t.Fatal("PUT /api/settings a posé setup_completed")
	}
}
