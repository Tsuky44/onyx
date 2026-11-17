package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/julienschmidt/httprouter"

	"project-player/server/i18n"
)

// publishWithLanguage envoie une annonce vide à PublishAnnouncement, dans la
// chaîne que main.go monte (i18n.Middleware devant le handler), avec la
// langue demandée.
func publishWithLanguage(t *testing.T, acceptLanguage string) (int, string) {
	t.Helper()
	handler := i18n.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		PublishAnnouncement(w, r, httprouter.Params{}, 1)
	}))
	req := httptest.NewRequest(http.MethodPut, "/api/announcement", strings.NewReader(`{"title":"","message":""}`))
	if acceptLanguage != "" {
		req.Header.Set("Accept-Language", acceptLanguage)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	var body struct {
		Error string `json:"error"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	return rec.Code, body.Error
}

func TestErrorsFollowTheLanguageOfTheRequest(t *testing.T) {
	cases := []struct {
		name, header, want string
	}{
		{"english", "en", "The message is empty or too long (title 120, message 4000 characters at most)"},
		{"english region", "en-US,en;q=0.9", "The message is empty or too long (title 120, message 4000 characters at most)"},
		{"french", "fr", "Le message est vide ou trop long (titre 120, message 4000 caractères au plus)"},
		// Une app d'avant ce réglage n'envoie rien : elle reçoit le français.
		{"no header", "", "Le message est vide ou trop long (titre 120, message 4000 caractères au plus)"},
		// Une langue que le serveur ne parle pas retombe sur le français.
		{"unknown language", "ja", "Le message est vide ou trop long (titre 120, message 4000 caractères au plus)"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			status, got := publishWithLanguage(t, tc.header)
			if status != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", status)
			}
			if got != tc.want {
				t.Errorf("error = %q, want %q", got, tc.want)
			}
		})
	}
}

// Un handler appelé sans le middleware (un test, un outil) répond en français
// au lieu d'échouer.
func TestErrorsWithoutMiddlewareStayFrench(t *testing.T) {
	rec := httptest.NewRecorder()
	writeJSONError(rec, http.StatusNotFound, "Liste introuvable")
	if !strings.Contains(rec.Body.String(), "Liste introuvable") {
		t.Errorf("body = %q, want the French message", rec.Body.String())
	}
}

func TestMediaHubErrorsFollowTheLanguageOfTheRequest(t *testing.T) {
	handler := i18n.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeMediaHubError(w, http.StatusBadGateway, "{0} ne répond pas", "MediaHub")
	}))
	req := httptest.NewRequest(http.MethodGet, "/api/mediahub/anything", nil)
	req.Header.Set("Accept-Language", "en")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if !strings.Contains(rec.Body.String(), "MediaHub isn't responding") {
		t.Errorf("body = %q, want the English message", rec.Body.String())
	}
}

// writeJSONFailure traduit une i18n.Error, même enveloppée, et garde brute
// l'erreur d'un système extérieur derrière une phrase traduite.
func TestWriteJSONFailureTranslatesOnlyOurOwnErrors(t *testing.T) {
	respond := func(err error) string {
		handler := i18n.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			writeJSONFailure(w, http.StatusBadGateway, err)
		}))
		req := httptest.NewRequest(http.MethodGet, "/api/x", nil)
		req.Header.Set("Accept-Language", "en")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		var body struct {
			Error string `json:"error"`
		}
		_ = json.NewDecoder(rec.Body).Decode(&body)
		return body.Error
	}

	own := &embyStatusError{status: 502, err: i18n.Errorf("Emby a répondu {0} sur {1}", 500, "/Users")}
	if got, want := respond(own), "Emby answered 500 on /Users"; got != want {
		t.Errorf("own error = %q, want %q", got, want)
	}
	if got := respond(errors.New("dial tcp 10.0.0.1:8096: refused")); got != "Error: dial tcp 10.0.0.1:8096: refused" {
		t.Errorf("foreign error = %q, want it raw behind a translated sentence", got)
	}
}
