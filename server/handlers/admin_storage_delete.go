package handlers

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"time"

	"project-player/server/database"
	"project-player/server/indexer"
	"project-player/server/mediahub"

	"github.com/julienschmidt/httprouter"
)

// La suppression depuis l'administration d'Onyx (ADR-0115) : MediaHub
// retire d'abord le titre de sorraa ou de Radarr/Sonarr et en supprime les
// demandes, puis Onyx efface les fichiers. Dans cet ordre : un titre effacé
// du disque mais toujours suivi serait retéléchargé dans l'heure.

// adminStorageForgetTimeout : sorraa répond vite, mais Sonarr relit toute sa
// liste de séries pour trouver la bonne par TMDB.
const adminStorageForgetTimeout = 60 * time.Second

// storageTarget est ce qu'il faut à MediaHub pour retrouver le titre.
type storageTarget struct {
	mediaType string // « movie » ou « tv », comme chez MediaHub
	tmdbID    int
	season    *int
}

type adminStorageDeleteResponse struct {
	indexer.DeleteReport
	// MediaHub est nul sans MediaHub configuré, ou pour un titre sans TMDB.
	MediaHub *mediahub.Removal `json:"mediahub"`
}

// AdminDeleteStorage supprime le film, la série ou la saison :id partout
// (DELETE /api/admin/storage/:id).
func AdminDeleteStorage(w http.ResponseWriter, r *http.Request, ps httprouter.Params, userID int) {
	id, err := strconv.Atoi(ps.ByName("id"))
	if err != nil || id <= 0 {
		writeJSONError(w, http.StatusBadRequest, "Invalid media ID")
		return
	}
	target, err := loadStorageTarget(id)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSONError(w, http.StatusNotFound, "Média introuvable dans Onyx")
		return
	}
	if err != nil {
		log.Printf("AdminDeleteStorage: load %d: %v", id, err)
		writeJSONError(w, http.StatusInternalServerError, "Internal database error")
		return
	}
	if err := indexer.CheckDeletable(id); err != nil {
		writeStorageDeleteError(w, "AdminDeleteStorage", err)
		return
	}

	var removal *mediahub.Removal
	if target.tmdbID > 0 {
		got, err := forgetInMediaHub(r.Context(), userID, target)
		switch {
		case errors.Is(err, mediahub.ErrNotConfigured):
			// Pas de MediaHub : ni gestionnaire ni demandes à prévenir.
		case err != nil:
			writeForgetFailure(w, err)
			return
		default:
			removal = &got
		}
	}

	report, err := indexer.DeleteMedia(id)
	if err != nil {
		writeStorageDeleteError(w, "AdminDeleteStorage", err)
		return
	}
	if target.tmdbID > 0 {
		invalidateMediaHubStatus(target.tmdbID)
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(adminStorageDeleteResponse{DeleteReport: report, MediaHub: removal})
}

// loadStorageTarget lit le type et le TMDB du média ; une saison prend ceux
// de sa série et son numéro. Un épisode seul n'est pas proposé ici.
func loadStorageTarget(id int) (storageTarget, error) {
	var mediaType string
	var tmdbID, seasonNumber, parentTMDB int
	err := database.DB.QueryRow(`SELECT m.type, COALESCE(m.tmdb_id, 0), COALESCE(m.season_number, 0), COALESCE(p.tmdb_id, 0)
		FROM medias m LEFT JOIN medias p ON p.id = m.parent_id
		WHERE m.id = ? AND m.type IN ('movie', 'show', 'season')`, id).
		Scan(&mediaType, &tmdbID, &seasonNumber, &parentTMDB)
	if err != nil {
		return storageTarget{}, err
	}
	switch mediaType {
	case "movie":
		return storageTarget{mediaType: "movie", tmdbID: tmdbID}, nil
	case "show":
		return storageTarget{mediaType: "tv", tmdbID: tmdbID}, nil
	default:
		return storageTarget{mediaType: "tv", tmdbID: parentTMDB, season: &seasonNumber}, nil
	}
}

func forgetInMediaHub(parent context.Context, userID int, target storageTarget) (mediahub.Removal, error) {
	account, err := mediaHubAccount(userID)
	if err != nil {
		return mediahub.Removal{}, err
	}
	ctx, cancel := context.WithTimeout(parent, adminStorageForgetTimeout)
	defer cancel()
	return mediaHubClient(mediaHubHTTPClient).ForgetMedia(ctx, account, target.tmdbID, target.mediaType, target.season)
}

// writeForgetFailure : rien n'a été supprimé. Toujours 502, jamais le 401
// de MediaHub tel quel, que l'app prendrait pour une session expirée.
func writeForgetFailure(w http.ResponseWriter, err error) {
	var status *mediahub.StatusError
	message := "MediaHub ne répond pas : rien n'a été supprimé."
	switch {
	case errors.As(err, &status) && status.Status == http.StatusNotFound:
		message = "MediaHub est trop ancien pour retirer le titre de sorraa ou de Radarr/Sonarr : mettez-le à jour. Rien n'a été supprimé."
	case errors.As(err, &status) && (status.Status == http.StatusUnauthorized || status.Status == http.StatusForbidden):
		message = "MediaHub refuse : votre compte n'y a pas le droit de supprimer des médias. Rien n'a été supprimé."
	case errors.As(err, &status):
		var body errorResponse
		if json.Unmarshal(status.Body, &body) == nil && body.Error != "" {
			message = body.Error + " Rien n'a été supprimé."
		}
	case errors.Is(err, mediahub.ErrUnsupported):
		message = "OnyxHub ne sait pas retirer un titre de son gestionnaire : rien n'a été supprimé."
	default:
		log.Printf("AdminDeleteStorage: mediahub: %v", err)
	}
	writeJSONError(w, http.StatusBadGateway, message)
}
