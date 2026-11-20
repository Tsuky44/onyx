package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"project-player/server/config"
	"project-player/server/mediahub"
)

// Le catalogue, les fiches et les épisodes des demandes viennent de TMDB pour
// les trois services (tmdb_requests.go) : un service de demandes enregistré
// sans clé TMDB ne montrerait que des écrans vides (ADR-0164).

func errorOf(t *testing.T, body string) string {
	t.Helper()
	var payload struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		t.Fatalf("corps d'erreur illisible : %s", body)
	}
	return payload.Error
}

func TestARequestServiceIsRefusedWithoutATMDBKey(t *testing.T) {
	setupAuthDB(t)
	resetSettings(t)
	t.Setenv("REQUEST_SERVICE", "")

	for name, body := range map[string]string{
		"MediaHub":   `{"request_service":"mediahub","mediahub_url":"http://hub:3000","mediahub_api_key":"cle"}`,
		"Overseerr":  `{"request_service":"overseerr","mediahub_url":"http://seerr:5055","mediahub_api_key":"cle"}`,
		"Jellyseerr": `{"request_service":"jellyseerr"}`,
		"adresse":    `{"mediahub_url":"http://hub:3000"}`,
		"clé":        `{"mediahub_api_key":"cle"}`,
	} {
		rec := putSettings(t, body)
		if rec.Code != http.StatusConflict {
			t.Errorf("%s : HTTP %d, want 409 : %s", name, rec.Code, rec.Body.String())
			continue
		}
		if message := errorOf(t, rec.Body.String()); !strings.Contains(message, "TMDB") {
			t.Errorf("%s : message = %q, want qu'il parle de la clé TMDB", name, message)
		}
	}
	// Rien n'a été écrit, même pas la moitié de la requête.
	if config.MediaHubURL() != "" || config.MediaHubAPIKey() != "" || config.RequestService() != mediahub.ServiceMediaHub {
		t.Fatalf("un refus a écrit : %q %q %q", config.MediaHubURL(), config.MediaHubAPIKey(), config.RequestService())
	}
}

func TestARequestServiceIsAcceptedOnceATMDBKeyExists(t *testing.T) {
	setupAuthDB(t)
	resetSettings(t)
	t.Setenv("REQUEST_SERVICE", "")

	// La clé de la même requête compte : l'assistant peut tout envoyer d'un coup.
	body := `{"tmdb_api_key":"cle-tmdb","request_service":"overseerr","mediahub_url":"http://seerr:5055","mediahub_api_key":"cle"}`
	if rec := putSettings(t, body); rec.Code != http.StatusOK {
		t.Fatalf("avec la clé dans la requête : HTTP %d : %s", rec.Code, rec.Body.String())
	}
	if config.RequestService() != mediahub.ServiceOverseerr || config.MediaHubURL() != "http://seerr:5055" {
		t.Fatalf("réglages = %q %q", config.RequestService(), config.MediaHubURL())
	}

	// Une clé en variable d'environnement vaut une clé enregistrée.
	clearSettings(t)
	t.Setenv("TMDB_API_KEY", "cle-tmdb")
	if rec := putSettings(t, `{"mediahub_url":"http://hub:3000"}`); rec.Code != http.StatusOK {
		t.Fatalf("avec la clé de l'environnement : HTTP %d : %s", rec.Code, rec.Body.String())
	}
}

// Retirer la clé TMDB ne peut pas non plus laisser un service de demandes
// enregistré dans la même requête sans clé.
func TestTheTMDBKeyCannotBeClearedInTheSameRequestAsAService(t *testing.T) {
	setupAuthDB(t)
	resetSettings(t)
	t.Setenv("REQUEST_SERVICE", "")
	if rec := putSettings(t, `{"tmdb_api_key":"cle-tmdb"}`); rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d : %s", rec.Code, rec.Body.String())
	}

	rec := putSettings(t, `{"clear_tmdb_api_key":true,"mediahub_url":"http://hub:3000"}`)
	if rec.Code != http.StatusConflict {
		t.Fatalf("HTTP %d, want 409 : %s", rec.Code, rec.Body.String())
	}
	if config.TMDBAPIKey() == "" {
		t.Fatal("le refus a effacé la clé TMDB")
	}
}

// Une configuration déjà en place n'est jamais touchée : ni par un PUT qui la
// rejoue, ni par l'effacement de ce qu'elle contient, ni par un PUT sans lien
// avec elle, même si la clé TMDB a disparu depuis.
func TestAnExistingRequestSetupIsNeverBlocked(t *testing.T) {
	setupAuthDB(t)
	resetSettings(t)
	t.Setenv("REQUEST_SERVICE", "")
	if rec := putSettings(t, `{"tmdb_api_key":"cle-tmdb","request_service":"jellyseerr","mediahub_url":"http://seerr:5055","mediahub_api_key":"cle"}`); rec.Code != http.StatusOK {
		t.Fatalf("mise en place : HTTP %d : %s", rec.Code, rec.Body.String())
	}
	// La clé TMDB disparaît (variable retirée, réglage effacé).
	if rec := putSettings(t, `{"clear_tmdb_api_key":true}`); rec.Code != http.StatusOK {
		t.Fatalf("effacement de la clé : HTTP %d : %s", rec.Code, rec.Body.String())
	}

	for name, body := range map[string]string{
		"rejouer les valeurs":     `{"request_service":"jellyseerr","mediahub_url":"http://seerr:5055/","mediahub_api_key":"cle"}`,
		"un réglage sans rapport": `{"tmdb_language":"fr-FR","playback_logs_enabled":true}`,
		"effacer la clé":          `{"clear_mediahub_api_key":true}`,
		"effacer l'adresse":       `{"mediahub_url":""}`,
	} {
		if rec := putSettings(t, body); rec.Code != http.StatusOK {
			t.Errorf("%s : HTTP %d, want 200 : %s", name, rec.Code, rec.Body.String())
		}
	}
}
