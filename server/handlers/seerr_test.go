package handlers

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"project-player/server/config"
	"project-player/server/database"
	"project-player/server/mediahub"
)

// Overseerr et Jellyseerr branchés comme compagnon de demandes (ADR-0136),
// vus des routes d'Onyx. Le détail du dialecte est testé dans le package
// mediahub ; ici, ce que l'app reçoit et ce que le réglage ferme.

const seerrContractDir = "../../contract/seerr"

// seerrStub monte un faux Seerr servi par contract/seerr/ et le règle comme
// compagnon. Les routes données passent d'abord (« POST /request »).
func seerrStub(t *testing.T, service string, routes map[string]http.HandlerFunc) {
	t.Helper()
	files := map[string]string{
		"GET /status":          "status.json",
		"GET /settings/public": "settings_public.json",
		"GET /auth/me":         "auth_me.json",
		"GET /user":            "users.json",
		"GET /request":         "requests.json",
		"GET /movie/603":       "movie.json",
		"GET /tv/1399":         "tv.json",
	}
	companionStub(t, func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, mediahub.SeerrPath) {
			http.NotFound(w, r)
			return
		}
		key := r.Method + " " + strings.TrimPrefix(r.URL.Path, mediahub.SeerrPath)
		public := key == "GET /status" || key == "GET /settings/public"
		if !public && r.Header.Get("X-Api-Key") != "cle" {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"status":403,"error":"You do not have permission to access this endpoint"}`))
			return
		}
		if handler, ok := routes[key]; ok {
			handler(w, r)
			return
		}
		file, ok := files[key]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"message":"Unable to retrieve movie."}`))
			return
		}
		data, err := os.ReadFile(filepath.Join(seerrContractDir, file))
		if err != nil {
			t.Errorf("contract/seerr/%s : %v", file, err)
		}
		_, _ = w.Write(data)
	})
	t.Setenv("REQUEST_SERVICE", service)
}

func TestSeerrLinkTestSaysTheVersionAndHowTheAdminActs(t *testing.T) {
	seedRequestUser(t, 1, "lea")
	seerrStub(t, "jellyseerr", nil)
	linked := runLinkTest(t, `{}`)
	if !linked.OK || linked.Service != "jellyseerr" || linked.Version != "2.7.3" ||
		!strings.Contains(linked.Message, "Jellyseerr 2.7.3") || len(linked.Notes) != 0 {
		t.Fatalf("compte homonyme = %+v", linked)
	}

	if _, err := database.DB.Exec(`UPDATE users SET username = 'patron' WHERE id = 1`); err != nil {
		t.Fatal(err)
	}
	alone := runLinkTest(t, `{}`)
	if !alone.OK || len(alone.Notes) != 1 ||
		!strings.Contains(alone.Notes[0], "« patron »") || !strings.Contains(alone.Notes[0], "« admin »") {
		t.Fatalf("compte sans homonyme = %+v", alone)
	}
}

func TestSeerrLinkTestSaysTheKeyIsRefused(t *testing.T) {
	seerrStub(t, "overseerr", nil)
	refused := runLinkTest(t, `{"mediahub_api_key":"autre"}`)
	if refused.OK || refused.Service != "overseerr" || !strings.Contains(refused.Message, "Overseerr répond, mais refuse") {
		t.Fatalf("clé refusée = %+v", refused)
	}
}

func TestLinkTestTestsTheServiceChosenInTheForm(t *testing.T) {
	// Le formulaire n'est pas encore enregistré : le serveur est réglé sur
	// MediaHub, l'administrateur vient de choisir Overseerr.
	seerrStub(t, "", nil)
	chosen := runLinkTest(t, `{"request_service":"overseerr"}`)
	if !chosen.OK || chosen.Service != "overseerr" {
		t.Fatalf("service du formulaire = %+v", chosen)
	}

	recorder := httptest.NewRecorder()
	TestMediaHubLink(recorder, httptest.NewRequest(http.MethodPost, "/api/settings/mediahub/test",
		strings.NewReader(`{"request_service":"ombi"}`)), nil, 1)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("service inconnu : HTTP %d", recorder.Code)
	}
}

func TestLinkTestSaysWhenTheAddressIsASeerrButMediaHubIsChosen(t *testing.T) {
	seerrStub(t, "", nil)
	wrong := runLinkTest(t, `{}`)
	if wrong.OK || !strings.Contains(wrong.Message, "Overseerr ou Jellyseerr") {
		t.Fatalf("mauvais service = %+v", wrong)
	}
}

func TestSeerrMyRequestsComeInOnyxLots(t *testing.T) {
	seedRequestUser(t, 3, "lea")
	seerrStub(t, "jellyseerr", nil)
	recorder := httptest.NewRecorder()
	MediaHubMyRequests(recorder, httptest.NewRequest(http.MethodGet, "/api/requests/mine", nil), nil, 3)
	var body myRequestsResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil || recorder.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", recorder.Code, recorder.Body.String())
	}
	if len(body.Requests) != 4 || body.Requests[1].Title != "Game of Thrones" || body.Requests[1].Status != "partial" {
		t.Fatalf("lots = %+v", body.Requests)
	}
}

func TestSeerrRequestIsRelayedWithTheRefusalInFrench(t *testing.T) {
	seedRequestUser(t, 3, "lea")
	seerrStub(t, "jellyseerr", map[string]http.HandlerFunc{
		"POST /request": func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("X-Api-User") != "2" {
				t.Errorf("demande au nom de %q, attendu le compte Seerr de lea", r.Header.Get("X-Api-User"))
			}
			w.WriteHeader(http.StatusConflict)
			_, _ = w.Write([]byte(`{"message":"Request for this media already exists."}`))
		},
	})
	recorder := httptest.NewRecorder()
	MediaHubRequest(recorder, httptest.NewRequest(http.MethodPost, "/api/requests",
		strings.NewReader(`{"tmdbId":603,"mediaType":"movie","title":"Matrix"}`)), nil, 3)
	var body errorResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil || recorder.Code != http.StatusConflict ||
		body.Error != "Ce titre est déjà demandé." {
		t.Fatalf("HTTP %d : %s", recorder.Code, recorder.Body.String())
	}
}

func TestAccessOffersModerationOnlyToWhoMayManageSettings(t *testing.T) {
	// « inconnue » n'a pas d'homonyme chez Seerr : elle agit par le compte de
	// la clé, administrateur. Onyx refuserait pourtant ses routes de
	// modération : l'app ne doit pas les lui proposer.
	seedRequestUser(t, 3, "inconnue")
	seerrStub(t, "jellyseerr", nil)
	read := func() mediahub.Access {
		recorder := httptest.NewRecorder()
		MediaHubRequestAccess(recorder, httptest.NewRequest(http.MethodGet, "/api/requests/access", nil), nil, 3)
		var access mediahub.Access
		if err := json.Unmarshal(recorder.Body.Bytes(), &access); err != nil || recorder.Code != http.StatusOK {
			t.Fatalf("HTTP %d : %s", recorder.Code, recorder.Body.String())
		}
		return access
	}

	guest := read()
	if guest.Service != "jellyseerr" || guest.Linked || !guest.Can.Request ||
		guest.Can.ReadAllRequests || guest.Can.Moderate || guest.Can.Delete {
		t.Fatalf("compte sans manage_settings = %+v", guest)
	}
	if _, err := database.DB.Exec(`UPDATE users SET perm_manage_settings = 1 WHERE id = 3`); err != nil {
		t.Fatal(err)
	}
	admin := read()
	if !admin.Can.ReadAllRequests || !admin.Can.Moderate || !admin.Can.Delete {
		t.Fatalf("compte avec manage_settings = %+v", admin)
	}
}

func TestSeerrKeyOpensNothingMediaHubReadsOnOnyx(t *testing.T) {
	// La clé réglée est celle de Seerr, qui n'appelle jamais Onyx : les routes
	// ouvertes à MediaHub par sa clé (annuaire, stockage, évènements, rachat
	// d'un code) restent fermées, même à qui la présente.
	setupDirectory(t)
	t.Setenv("REQUEST_SERVICE", "jellyseerr")
	if rec := callWithKey(RequireMediaHubKey(MediaHubAccounts), http.MethodGet, "/", directoryKey, ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("annuaire : HTTP %d, attendu 401", rec.Code)
	}
	if rec := callWithKey(RequireMediaHubKey(MediaHubDeleteStorage), http.MethodDelete, "/", directoryKey, ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("stockage : HTTP %d, attendu 401", rec.Code)
	}
	if rec := callWithKey(MediaHubEvents, http.MethodPost, "/", directoryKey, `{}`); rec.Code != http.StatusUnauthorized {
		t.Errorf("évènements : HTTP %d, attendu 401", rec.Code)
	}
	if rec := callWithKey(RedeemMediaHubSSO, http.MethodPost, "/", directoryKey, `{"code":"x"}`); rec.Code != http.StatusUnauthorized {
		t.Errorf("rachat : HTTP %d, attendu 401", rec.Code)
	}
	if rec := callWithKey(OnyxHubImported, http.MethodPost, "/", directoryKey, `{}`); rec.Code != http.StatusUnauthorized {
		t.Errorf("import OnyxHub : HTTP %d, attendu 401", rec.Code)
	}

	// Revenu à MediaHub, la même clé ouvre à nouveau.
	t.Setenv("REQUEST_SERVICE", "mediahub")
	if rec := callWithKey(RequireMediaHubKey(MediaHubAccounts), http.MethodGet, "/", directoryKey, ""); rec.Code != http.StatusOK {
		t.Errorf("annuaire avec MediaHub : HTTP %d", rec.Code)
	}
}

func TestSeerrHasNoSSOLanding(t *testing.T) {
	seedRequestUser(t, 3, "lea")
	seerrStub(t, "overseerr", nil)
	recorder := httptest.NewRecorder()
	IssueMediaHubSSO(recorder, httptest.NewRequest(http.MethodPost, "/api/integrations/mediahub/sso", nil), nil, 3)
	if recorder.Code != http.StatusNotImplemented {
		t.Fatalf("HTTP %d : %s", recorder.Code, recorder.Body.String())
	}
}

func TestAMuteCompanionIsNamedInTheError(t *testing.T) {
	seedRequestUser(t, 3, "lea")
	seerrStub(t, "jellyseerr", nil)
	t.Setenv("MEDIAHUB_URL", "http://127.0.0.1:1")
	recorder := httptest.NewRecorder()
	MediaHubMyRequests(recorder, httptest.NewRequest(http.MethodGet, "/api/requests/mine", nil), nil, 3)
	if recorder.Code != http.StatusBadGateway || !strings.Contains(recorder.Body.String(), "Jellyseerr ne répond pas") {
		t.Fatalf("HTTP %d : %s", recorder.Code, recorder.Body.String())
	}
}

func TestSettingsKeepTheChosenRequestService(t *testing.T) {
	setupAuthDB(t)
	t.Setenv("REQUEST_SERVICE", "")
	// Un service de demandes ne s'enregistre pas sans clé TMDB (ADR-0164).
	t.Setenv("TMDB_API_KEY", "cle-tmdb")
	// Le cache de config survit d'un test à l'autre : on le relit d'une table
	// vidée, pour que le service choisi ici ne masque pas REQUEST_SERVICE
	// dans les tests suivants.
	t.Cleanup(func() {
		if _, err := database.DB.Exec(`DELETE FROM app_settings`); err != nil {
			t.Errorf("nettoyage des réglages : %v", err)
		}
		config.LoadCache()
	})
	if got := config.Snapshot().RequestService; got != "mediahub" {
		t.Fatalf("service d'une installation d'avant le choix = %q", got)
	}

	put := func(body string) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		UpdateSettings(recorder, httptest.NewRequest(http.MethodPut, "/api/settings", bytes.NewBufferString(body)), nil, 1)
		return recorder
	}
	saved := put(`{"request_service":"jellyseerr","mediahub_url":"http://seerr:5055/"}`)
	var snapshot config.PublicSettings
	if err := json.Unmarshal(saved.Body.Bytes(), &snapshot); err != nil || saved.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", saved.Code, saved.Body.String())
	}
	if snapshot.RequestService != "jellyseerr" || snapshot.MediaHubURL != "http://seerr:5055" ||
		config.RequestService() != mediahub.ServiceJellyseerr {
		t.Fatalf("réglages = %+v", snapshot)
	}

	// Un service inconnu est refusé avant toute écriture : l'adresse qui
	// l'accompagne ne remplace pas celle du service encore réglé.
	if refused := put(`{"request_service":"ombi","mediahub_url":"http://ombi:3579"}`); refused.Code != http.StatusBadRequest {
		t.Fatalf("service inconnu : HTTP %d", refused.Code)
	}
	if config.RequestService() != mediahub.ServiceJellyseerr || config.MediaHubURL() != "http://seerr:5055" {
		t.Fatalf("un refus a écrit : %q %q", config.RequestService(), config.MediaHubURL())
	}
	unknown := "ombi"
	if _, err := config.ApplyUpdate(config.UpdateRequest{RequestService: &unknown}); !errors.Is(err, config.ErrInvalidRequestService) {
		t.Fatalf("erreur = %v", err)
	}

	// Un PUT qui ne parle pas du service (une app d'avant, ou MediaHub) le garde.
	if kept := put(`{"mediahub_url":"http://seerr:5056"}`); kept.Code != http.StatusOK || config.RequestService() != mediahub.ServiceJellyseerr {
		t.Fatalf("service perdu : HTTP %d, %q", kept.Code, config.RequestService())
	}
}
