package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"project-player/server/config"
	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

// Ce que MediaHub lit chez Onyx avec la clé d'intégration (ADR-0102), à la
// place de la session d'un administrateur Onyx.

const directoryKey = "cle-de-test-0123456789abcdef0123456789abcdef"

// setupDirectory ouvre une base, pose la clé et efface derrière ce que le test
// a écrit dans les réglages : le cache de config survit d'un test à l'autre.
func setupDirectory(t *testing.T) {
	t.Helper()
	setupAuthDB(t)
	t.Setenv("MEDIAHUB_URL", "")
	t.Setenv("MEDIAHUB_API_KEY", directoryKey)
	t.Cleanup(func() {
		empty := ""
		if _, err := config.ApplyUpdate(config.UpdateRequest{MediaHubURL: &empty, ClearMediaHubAPIKey: true}); err != nil {
			t.Errorf("nettoyage des réglages : %v", err)
		}
	})
}

func callWithKey(handle httprouter.Handle, method, target, key, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, target, strings.NewReader(body))
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	rec := httptest.NewRecorder()
	handle(rec, req, nil)
	return rec
}

func TestMediaHubDirectoryNeedsTheIntegrationKey(t *testing.T) {
	setupDirectory(t)
	routes := map[string]httprouter.Handle{
		"users":  RequireMediaHubKey(MediaHubAccounts),
		"movies": RequireMediaHubKey(GetMovies),
		"shows":  RequireMediaHubKey(GetShows),
		"link":   RequireMediaHubKey(GetMediaHubLink),
	}
	for name, handle := range routes {
		for _, key := range []string{"", "autre"} {
			if rec := callWithKey(handle, http.MethodGet, "/", key, ""); rec.Code != http.StatusUnauthorized {
				t.Errorf("%s avec la clé %q : HTTP %d, attendu 401", name, key, rec.Code)
			}
		}
		if rec := callWithKey(handle, http.MethodGet, "/", directoryKey, ""); rec.Code != http.StatusOK {
			t.Errorf("%s avec la bonne clé : HTTP %d %s", name, rec.Code, rec.Body.String())
		}
	}
}

func TestMediaHubDirectoryIsClosedWhileOnyxHasNoKey(t *testing.T) {
	setupDirectory(t)
	t.Setenv("MEDIAHUB_API_KEY", "")
	if rec := callWithKey(RequireMediaHubKey(MediaHubAccounts), http.MethodGet, "/", "", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("HTTP %d, attendu 401", rec.Code)
	}
}

func TestMediaHubContractAccountsCarryIdNameAndRights(t *testing.T) {
	setupDirectory(t)
	createTestUser(t, "lea", true, models.Permissions{ManageSettings: true, ManageUsers: true})
	createPasswordUser(t, "max", models.DefaultPermissions())

	rec := callWithKey(RequireMediaHubKey(MediaHubAccounts), http.MethodGet, "/api/integrations/mediahub/users", directoryKey, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "password") || strings.Contains(rec.Body.String(), "invite_grants") {
		t.Fatalf("MediaHub n'a pas à lire plus que l'id, le nom et les droits : %s", rec.Body.String())
	}
	pinOnyxContract(t, "onyx_integration_users.json", rec.Body.Bytes(), nil)
}

func TestMediaHubWritesItsAddressAndRotatesItsKeyWithTheCurrentOne(t *testing.T) {
	setupDirectory(t)
	update := RequireMediaHubKey(UpdateMediaHubLink)

	rec := callWithKey(update, http.MethodPut, "/api/integrations/mediahub/link", directoryKey, `{"mediahub_url":"https://hub.example.org/"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	var state mediaHubLinkState
	if err := json.Unmarshal(rec.Body.Bytes(), &state); err != nil || state.MediaHubURL != "https://hub.example.org" {
		t.Fatalf("état = %+v (%v)", state, err)
	}
	if config.MediaHubURL() != "https://hub.example.org" {
		t.Fatalf("adresse enregistrée = %q", config.MediaHubURL())
	}
	pinOnyxContract(t, "onyx_integration_link.json", rec.Body.Bytes(), func(v map[string]interface{}) {
		v["server_version"] = "dev"
	})

	next := strings.Repeat("ab", 32)
	if rec := callWithKey(update, http.MethodPut, "/", directoryKey, `{"mediahub_api_key":"`+next+`"}`); rec.Code != http.StatusOK {
		t.Fatalf("rotation : HTTP %d %s", rec.Code, rec.Body.String())
	}
	if rec := callWithKey(RequireMediaHubKey(GetMediaHubLink), http.MethodGet, "/", directoryKey, ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("l'ancienne clé ouvre encore : HTTP %d", rec.Code)
	}
	if rec := callWithKey(RequireMediaHubKey(GetMediaHubLink), http.MethodGet, "/", next, ""); rec.Code != http.StatusOK {
		t.Fatalf("la nouvelle clé n'ouvre pas : HTTP %d", rec.Code)
	}
}

func TestMediaHubLinkRefusesABadAddressOrAShortKey(t *testing.T) {
	setupDirectory(t)
	update := RequireMediaHubKey(UpdateMediaHubLink)
	for _, body := range []string{
		`{"mediahub_url":"ftp://hub"}`,
		`{"mediahub_url":"hub.example.org"}`,
		`{"mediahub_url":"https://hub.example.org/?x=1"}`,
		`{"mediahub_api_key":"courte"}`,
		`pas du json`,
	} {
		if rec := callWithKey(update, http.MethodPut, "/", directoryKey, body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s : HTTP %d, attendu 400", body, rec.Code)
		}
	}
	if config.MediaHubAPIKey() != directoryKey {
		t.Fatal("une requête refusée a changé la clé")
	}
}
