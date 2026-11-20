package handlers

import (
	"encoding/json"
	"log"
	"net/http"

	"project-player/server/config"
	"project-player/server/libraries"

	"github.com/julienschmidt/httprouter"
)

// L'état de l'assistant du premier lancement (ADR-0164).
//
// Chaque étape se calcule depuis les données : une bibliothèque existe, une clé
// TMDB est réglée, un service de demandes est réglé. Un serveur configuré à la
// main (ou par l'ancien écran de réglages) voit donc ses étapes faites sans
// que personne ait « fait » l'assistant. Seul `completed` est un drapeau
// (setup_completed) : il dit que l'administrateur a fini ou écarté l'assistant,
// et que l'app ne le lui propose plus.

type setupLibrariesState struct {
	Count int  `json:"count"`
	Done  bool `json:"done"`
}

type setupTMDBState struct {
	Done bool `json:"done"`
}

type setupRequestsState struct {
	// Done : une adresse et une clé de service de demandes sont réglées.
	Done bool `json:"done"`
	// Available : les demandes sont possibles, c'est-à-dire qu'une clé TMDB
	// existe (enregistrée ou en variable d'environnement). Sans elle, l'étape
	// ne se propose pas.
	Available bool `json:"available"`
}

type setupStateResponse struct {
	Completed bool                `json:"completed"`
	Libraries setupLibrariesState `json:"libraries"`
	TMDB      setupTMDBState      `json:"tmdb"`
	Requests  setupRequestsState  `json:"requests"`
}

// GetSetupState rend où en est l'installation (GET /api/setup/state).
func GetSetupState(w http.ResponseWriter, _ *http.Request, _ httprouter.Params, _ int) {
	libs, err := libraries.List()
	if err != nil {
		log.Printf("GetSetupState: list libraries: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne de la base de données")
		return
	}
	hasTMDB := config.TMDBAPIKey() != ""
	state := setupStateResponse{
		Completed: config.SetupCompleted(),
		Libraries: setupLibrariesState{Count: len(libs), Done: len(libs) > 0},
		TMDB:      setupTMDBState{Done: hasTMDB},
		Requests: setupRequestsState{
			Done:      config.MediaHubURL() != "" && config.MediaHubAPIKey() != "",
			Available: hasTMDB,
		},
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(state)
}

// CompleteSetup note l'assistant comme terminé (POST /api/setup/complete).
// Idempotent : le rejouer ne change rien.
func CompleteSetup(w http.ResponseWriter, _ *http.Request, _ httprouter.Params, _ int) {
	if err := config.MarkSetupCompleted(); err != nil {
		log.Printf("CompleteSetup: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Impossible d’enregistrer les réglages")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
