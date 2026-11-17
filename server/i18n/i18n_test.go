package i18n

import (
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestTranslatesThroughTheFrenchKey(t *testing.T) {
	if got := T("en", "Liste introuvable"); got != "List not found" {
		t.Errorf("en = %q", got)
	}
	if got := T("fr", "Liste introuvable"); got != "Liste introuvable" {
		t.Errorf("fr = %q, want the key itself", got)
	}
}

// Une clé absente ou une langue inconnue rend le français : un message jamais
// traduit reste lisible.
func TestMissingEntryFallsBackToFrench(t *testing.T) {
	for _, lang := range []string{"en", "es", "ja", ""} {
		if got := T(lang, "Une phrase qui n'a pas de traduction"); got != "Une phrase qui n'a pas de traduction" {
			t.Errorf("lang %q = %q", lang, got)
		}
	}
	if got := T("es", "Liste introuvable"); got != "Liste introuvable" {
		t.Errorf("a language without a dictionary must answer French, got %q", got)
	}
}

func TestPlaceholdersAreFilledInBothLanguages(t *testing.T) {
	fr := T("fr", "Donnez un nom à la bibliothèque ({0} caractères au plus)", 80)
	if fr != "Donnez un nom à la bibliothèque (80 caractères au plus)" {
		t.Errorf("fr = %q", fr)
	}
	en := T("en", "Donnez un nom à la bibliothèque ({0} caractères au plus)", 80)
	if en != "Give the library a name (80 characters at most)" {
		t.Errorf("en = %q", en)
	}
	// Les valeurs se placent où la grammaire de la langue les veut : l'ordre
	// des emplacements n'est pas celui des arguments.
	if got := fill("{1} avant {0}", []any{"a", "b"}); got != "b avant a" {
		t.Errorf("fill = %q", got)
	}
	// Un emplacement sans valeur reste visible.
	if got := fill("valeur {1}", []any{"a"}); got != "valeur {1}" {
		t.Errorf("fill = %q", got)
	}
}

func TestLanguageOfTheRequest(t *testing.T) {
	cases := map[string]string{
		"":                  "fr",
		"fr":                "fr",
		"fr-FR,fr;q=0.9":    "fr",
		"en":                "en",
		"en-US,en;q=0.9":    "en",
		"EN_gb":             "en",
		"de-DE, en":         "en", // la première langue que le serveur parle
		"ja,zh;q=0.8":       "fr", // aucune : le français, comme avant ce réglage
		"*":                 "fr",
		"  en  ;q=0.5":      "en",
		"en-US;q=0.9, fr;q": "en",
	}
	for header, want := range cases {
		if got := FromHeader(header); got != want {
			t.Errorf("FromHeader(%q) = %q, want %q", header, got, want)
		}
	}
	r := httptest.NewRequest(http.MethodGet, "/api/x", nil)
	r.Header.Set("Accept-Language", "en-US")
	if got := FromRequest(r); got != "en" {
		t.Errorf("FromRequest = %q", got)
	}
}

func TestMiddlewareTagsApiResponsesOnly(t *testing.T) {
	handler := Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := FromWriter(w); got != "en" && r.URL.Path == "/api/x" {
			t.Errorf("FromWriter = %q on an API route", got)
		}
	}))
	for path, want := range map[string]string{"/api/x": "en", "/index.html": ""} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.Header.Set("Accept-Language", "en")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if got := rec.Header().Get("Content-Language"); got != want {
			t.Errorf("%s: Content-Language = %q, want %q", path, got, want)
		}
	}
}

func TestErrorfKeepsTheFrenchTextForLogs(t *testing.T) {
	err := Errorf("Photo trop grande ({0} px de côté au plus)", 2048)
	if err.Error() != "Photo trop grande (2048 px de côté au plus)" {
		t.Errorf("Error() = %q", err.Error())
	}
}

// main.go doit monter le middleware : sans lui, les 550 appels d'erreur
// répondent en français quelle que soit la langue demandée, et aucun autre
// test ne le verrait.
func TestMainMountsTheLanguageMiddleware(t *testing.T) {
	source, err := os.ReadFile("../main.go")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(source), "i18n.Middleware(") {
		t.Error("main.go no longer wraps the router in i18n.Middleware: error messages would stay French for every language")
	}
}
