package handlers

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"project-player/server/indexer"
	"project-player/server/libraries"

	"github.com/julienschmidt/httprouter"
)

// BrowseFolders est l'explorateur de dossiers de l'assistant du premier
// lancement (GET /api/fs/browse?path=…, ADR-0164). Il montre le disque du
// conteneur : manage_settings, comme la liste des dossiers à côté de lui, et il
// ne sort jamais de la racine des médias (libraries.Browse).
//
// Le premier lancement l'appelle avant que la moindre bibliothèque existe : la
// racine absente, illisible ou vide n'est donc pas une erreur, c'est le
// diagnostic (empty_root) que l'app affiche.
func BrowseFolders(w http.ResponseWriter, r *http.Request, _ httprouter.Params, _ int) {
	libs, err := libraries.List()
	if err != nil {
		log.Printf("BrowseFolders: list libraries: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne de la base de données")
		return
	}
	listing, err := libraries.Browse(r.Context(), libraries.MediaRoot(), r.URL.Query().Get("path"), libs, indexer.IsVideoFile)
	switch {
	case errors.Is(err, libraries.ErrOutsideRoot):
		writeJSONError(w, http.StatusBadRequest, "Ce chemin est en dehors du dossier des médias")
		return
	case errors.Is(err, libraries.ErrFolderNotFound):
		writeJSONError(w, http.StatusNotFound, "Ce dossier n'existe pas sur le serveur")
		return
	case err != nil:
		log.Printf("BrowseFolders: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Impossible de lire ce dossier")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(listing)
}
