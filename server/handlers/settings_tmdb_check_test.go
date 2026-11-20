package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

const secretTMDBKey = "cle-tmdb-secrete-0123456789"

type tmdbRoundTrip func(*http.Request) (*http.Response, error)

func (f tmdbRoundTrip) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

// fakeTMDB remplace le client du test par un TMDB simulé : status dit ce qu'il
// répond selon la clé reçue, et seen note les clés présentées.
func stubTMDBKeyCheck(t *testing.T, answer func(key string) (int, error)) (seen *[]string) {
	t.Helper()
	var mu sync.Mutex
	keys := []string{}
	previous := tmdbKeyClient
	tmdbKeyClient = &http.Client{Transport: tmdbRoundTrip(func(r *http.Request) (*http.Response, error) {
		key := r.URL.Query().Get("api_key")
		mu.Lock()
		keys = append(keys, key)
		mu.Unlock()
		code, err := answer(key)
		if err != nil {
			return nil, err
		}
		return &http.Response{StatusCode: code, Body: io.NopCloser(strings.NewReader("{}"))}, nil
	})}
	t.Cleanup(func() { tmdbKeyClient = previous })
	return &keys
}

func runTMDBTest(t *testing.T, body, acceptLanguage string) tmdbKeyTestResult {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/api/settings/tmdb/test", strings.NewReader(body))
	if acceptLanguage != "" {
		req.Header.Set("Accept-Language", acceptLanguage)
	}
	rec := httptest.NewRecorder()
	TestTMDBKey(rec, req, nil, 1)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), secretTMDBKey) {
		t.Fatalf("la réponse renvoie la clé : %s", rec.Body.String())
	}
	var result tmdbKeyTestResult
	if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
		t.Fatalf("décodage : %v", err)
	}
	return result
}

func TestTMDBTestAcceptsAKeyTMDBAccepts(t *testing.T) {
	t.Setenv("TMDB_API_KEY", "")
	seen := stubTMDBKeyCheck(t, func(key string) (int, error) { return http.StatusOK, nil })

	result := runTMDBTest(t, `{"tmdb_api_key":"`+secretTMDBKey+`"}`, "")
	if !result.OK || result.Reason != "ok" || result.Message == "" {
		t.Fatalf("résultat = %+v", result)
	}
	// La clé du formulaire est celle qui est testée, pas une clé enregistrée.
	if len(*seen) != 1 || (*seen)[0] != secretTMDBKey {
		t.Fatalf("clés présentées = %v", *seen)
	}
}

func TestTMDBTestSaysInvalidKeyOnA401(t *testing.T) {
	t.Setenv("TMDB_API_KEY", "")
	stubTMDBKeyCheck(t, func(string) (int, error) { return http.StatusUnauthorized, nil })

	result := runTMDBTest(t, `{"tmdb_api_key":"`+secretTMDBKey+`"}`, "")
	if result.OK || result.Reason != "invalid_key" || result.Message == "" {
		t.Fatalf("résultat = %+v", result)
	}
}

// Pas d'Internet dans le conteneur, DNS cassé, délai dépassé, TMDB en panne :
// le serveur n'a pas pu juger la clé, et ne dit surtout pas qu'elle est fausse.
func TestTMDBTestSaysUnreachableWhenTMDBCannotBeReached(t *testing.T) {
	t.Setenv("TMDB_API_KEY", "")

	for name, answer := range map[string]func(string) (int, error){
		"réseau": func(string) (int, error) { return 0, &netErr{} },
		"délai":  func(string) (int, error) { return 0, context.DeadlineExceeded },
		"5xx":    func(string) (int, error) { return http.StatusBadGateway, nil },
	} {
		stubTMDBKeyCheck(t, answer)
		result := runTMDBTest(t, `{"tmdb_api_key":"`+secretTMDBKey+`"}`, "")
		if result.OK || result.Reason != "unreachable" || !strings.Contains(result.Message, "Internet") {
			t.Errorf("%s : résultat = %+v", name, result)
		}
	}
}

type netErr struct{}

func (*netErr) Error() string { return "dial tcp: lookup api.themoviedb.org: no such host" }

func TestTMDBTestWithoutAnyKeyAsksNothing(t *testing.T) {
	t.Setenv("TMDB_API_KEY", "")
	seen := stubTMDBKeyCheck(t, func(string) (int, error) { return http.StatusOK, nil })

	for _, body := range []string{``, `{}`, `{"tmdb_api_key":"   "}`} {
		result := runTMDBTest(t, body, "")
		if result.OK || result.Reason != "no_key" {
			t.Errorf("corps %q : résultat = %+v", body, result)
		}
	}
	if len(*seen) != 0 {
		t.Fatalf("TMDB appelé sans clé : %v", *seen)
	}
}

// Un corps vide teste la clé en place (réglage ou variable d'environnement).
func TestTMDBTestFallsBackToTheSavedKey(t *testing.T) {
	t.Setenv("TMDB_API_KEY", secretTMDBKey)
	seen := stubTMDBKeyCheck(t, func(key string) (int, error) { return http.StatusOK, nil })

	if result := runTMDBTest(t, ``, ""); !result.OK {
		t.Fatalf("résultat = %+v", result)
	}
	if len(*seen) != 1 || (*seen)[0] != secretTMDBKey {
		t.Fatalf("clés présentées = %v", *seen)
	}
	// Mais celle du formulaire prime.
	if result := runTMDBTest(t, `{"tmdb_api_key":"autre"}`, ""); !result.OK || (*seen)[1] != "autre" {
		t.Fatalf("résultat = %+v, clés %v", result, *seen)
	}
}

func TestTMDBTestAnswersInTheLanguageOfTheRequest(t *testing.T) {
	t.Setenv("TMDB_API_KEY", "")
	stubTMDBKeyCheck(t, func(string) (int, error) { return http.StatusUnauthorized, nil })

	french := runTMDBTest(t, `{"tmdb_api_key":"x"}`, "fr-FR")
	english := runTMDBTest(t, `{"tmdb_api_key":"x"}`, "en-US")
	if french.Message == english.Message || !strings.Contains(english.Message, "TMDB rejects") {
		t.Fatalf("fr = %q, en = %q", french.Message, english.Message)
	}
}

func TestTMDBTestRejectsABrokenBody(t *testing.T) {
	rec := httptest.NewRecorder()
	TestTMDBKey(rec, httptest.NewRequest(http.MethodPost, "/api/settings/tmdb/test", strings.NewReader(`{`)), nil, 1)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("HTTP %d, want 400", rec.Code)
	}
}

// La clé ne se journalise jamais, même quand TMDB est injoignable : c'est là
// que net/http cite l'URL entière, clé comprise.
func TestTMDBTestNeverLogsTheKey(t *testing.T) {
	t.Setenv("TMDB_API_KEY", "")
	var logs bytes.Buffer
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(io.Discard) })

	// fakeTMDB passe par un vrai http.Client : net/http enveloppe l'erreur
	// dans une *url.Error qui cite l'URL, clé comprise, comme en production.
	stubTMDBKeyCheck(t, func(string) (int, error) { return 0, context.DeadlineExceeded })
	runTMDBTest(t, `{"tmdb_api_key":"`+secretTMDBKey+`"}`, "")

	if strings.Contains(logs.String(), secretTMDBKey) || strings.Contains(logs.String(), "api_key") {
		t.Fatalf("la clé est dans le journal : %s", logs.String())
	}
	if logs.Len() == 0 {
		t.Fatal("la panne de TMDB doit être journalisée")
	}
}
