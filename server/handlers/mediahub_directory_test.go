package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"project-player/server/config"
	"project-player/server/database"
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

// seedWatchedShow : une série de trois épisodes sur le disque (plus un
// manquant), dont le compte a fini le premier et commencé le deuxième.
func seedWatchedShow(t *testing.T, userID int) {
	t.Helper()
	show := insertMediaRow(t, "show", "Dark", "", 0)
	season := insertMediaRow(t, "season", "Saison 1", "", show)
	first := insertMediaRow(t, "episode", "E1", "/tv/dark/e1.mkv", season)
	second := insertMediaRow(t, "episode", "E2", "/tv/dark/e2.mkv", season)
	insertMediaRow(t, "episode", "E3", "/tv/dark/e3.mkv", season)
	insertMediaRow(t, "episode", "E4", "", season)
	insertMediaRow(t, "movie", "Heat", "/films/heat.mkv", 0)
	for _, p := range []struct{ media, position, finished int }{{first, 2400, 1}, {second, 300, 0}} {
		if _, err := database.DB.Exec(`INSERT INTO progressions (user_id, media_id, current_position_seconds, is_finished) VALUES (?, ?, ?, ?)`,
			userID, p.media, p.position, p.finished); err != nil {
			t.Fatalf("insert progression: %v", err)
		}
	}
}

func TestMediaHubLibraryCountsLeaveOutEpisodesWithoutAFile(t *testing.T) {
	setupDirectory(t)
	seedWatchedShow(t, createTestUser(t, "lea", false, models.DefaultPermissions()))

	rec := callWithKey(RequireMediaHubKey(MediaHubLibraryCounts), http.MethodGet, "/", directoryKey, "")
	var counts mediaHubLibraryCounts
	if err := json.Unmarshal(rec.Body.Bytes(), &counts); err != nil || rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	if counts != (mediaHubLibraryCounts{Movies: 1, Shows: 1, Episodes: 3}) {
		t.Fatalf("totaux = %+v", counts)
	}
}

func TestMediaHubLibraryCarriesTheProgressOfTheNamedAccountOnly(t *testing.T) {
	setupDirectory(t)
	lea := createTestUser(t, "lea", false, models.DefaultPermissions())
	seedWatchedShow(t, lea)

	watched := func(playerID string) showLibraryItem {
		req := httptest.NewRequest(http.MethodGet, "/api/integrations/mediahub/shows", nil)
		req.Header.Set("Authorization", "Bearer "+directoryKey)
		if playerID != "" {
			req.Header.Set("X-Player-Id", playerID)
		}
		rec := httptest.NewRecorder()
		RequireMediaHubKey(GetShows)(rec, req, nil)
		var items []showLibraryItem
		if err := json.Unmarshal(rec.Body.Bytes(), &items); err != nil || len(items) != 1 {
			t.Fatalf("séries = %s (%v)", rec.Body.String(), err)
		}
		return items[0]
	}

	got := watched(strconv.Itoa(lea))
	if got.AvailableEpisodeCount != 3 || got.WatchedEpisodeCount != 1 || got.StartedEpisodeCount != 1 {
		t.Fatalf("compte de lea : %+v", got)
	}
	for _, other := range []string{"", "999", "abc"} {
		if got := watched(other); got.WatchedEpisodeCount != 0 || got.StartedEpisodeCount != 0 {
			t.Errorf("X-Player-Id %q voit une progression : %+v", other, got)
		}
	}
}
