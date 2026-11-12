package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"project-player/server/database"
	"project-player/server/mediahub"

	"github.com/julienschmidt/httprouter"
)

// Le gestionnaire de stockage dans l'administration d'Onyx (ADR-0115) : la
// même liste que celle de MediaHub (ADR-0114), plus l'affiche et qui a
// demandé chaque titre, pour faire de la place depuis l'app. Le détail et la
// suppression sont les handlers de MediaHub, derrière une permission d'Onyx.

// adminStorageRequest : une demande MediaHub du titre, par compte.
type adminStorageRequest struct {
	Requester   string `json:"requester"`
	RequestedAt string `json:"requested_at,omitempty"`
	Status      string `json:"status"`
	Seasons     []int  `json:"seasons,omitempty"`
}

type adminStorageItem struct {
	mediaHubStorageItem
	PosterURL string                `json:"poster_url,omitempty"`
	Requests  []adminStorageRequest `json:"requests"`
}

// adminStorageList : RequestsAvailable dit si MediaHub a répondu. Faux,
// « aucune demande » ne veut rien dire et l'app n'affiche pas la colonne.
type adminStorageList struct {
	Items             []adminStorageItem `json:"items"`
	RequestsAvailable bool               `json:"requests_available"`
}

// adminStorageRequestsTimeout : la liste vient du disque et ne doit pas
// attendre un MediaHub lent ; sans réponse, elle part sans les demandes.
const adminStorageRequestsTimeout = 6 * time.Second

// AdminStorage rend films et séries avec taille, dernière lecture, affiche et
// demandeurs (GET /api/admin/storage).
func AdminStorage(w http.ResponseWriter, r *http.Request, _ httprouter.Params, userID int) {
	movies, err := loadStorageMovies()
	var shows []mediaHubStorageItem
	if err == nil {
		shows, err = loadStorageShows()
	}
	var posters map[int]string
	if err == nil {
		posters, err = loadStoragePosters()
	}
	if err != nil {
		log.Printf("AdminStorage: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Internal database error")
		return
	}

	lots, available := loadStorageRequests(r.Context(), userID)
	items := attachStorageRequests(append(movies, shows...), posters, lots)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(adminStorageList{Items: items, RequestsAvailable: available})
}

func loadStoragePosters() (map[int]string, error) {
	rows, err := database.DB.Query(`SELECT id, COALESCE(poster_url, '') FROM medias
		WHERE type IN ('movie', 'show') AND COALESCE(poster_url, '') != ''`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	posters := map[int]string{}
	for rows.Next() {
		var id int
		var url string
		if err := rows.Scan(&id, &url); err != nil {
			return nil, err
		}
		posters[id] = url
	}
	return posters, rows.Err()
}

// loadStorageRequests lit toutes les demandes au nom de l'administrateur.
// Un serveur sans MediaHub n'est pas une panne : il n'a simplement pas de
// demandes à montrer.
func loadStorageRequests(parent context.Context, userID int) ([]mediahub.Lot, bool) {
	account, err := mediaHubAccount(userID)
	if err != nil {
		log.Printf("AdminStorage: account %d: %v", userID, err)
		return nil, false
	}
	ctx, cancel := context.WithTimeout(parent, adminStorageRequestsTimeout)
	defer cancel()
	lots, err := mediaHubClient(mediaHubHTTPClient).Requests(ctx, account, mediahub.ScopeAll)
	if err != nil {
		if !errors.Is(err, mediahub.ErrNotConfigured) && !errors.Is(err, mediahub.ErrUnsupported) {
			log.Printf("AdminStorage: requests: %v", err)
		}
		return nil, false
	}
	return lots, true
}

// storageRequestKey rapproche une ligne du disque d'une demande MediaHub :
// MediaHub écrit « tv » là où Onyx écrit « show ».
func storageRequestKey(mediaType string, tmdbID int) string {
	if mediaType == "tv" {
		mediaType = "show"
	}
	return mediahub.AvailabilityKey(mediaType, tmdbID)
}

// attachStorageRequests pose affiche et demandes sur chaque ligne. Un titre
// sans tmdb_id n'a pas pu être demandé : il reste sans demande.
func attachStorageRequests(rows []mediaHubStorageItem, posters map[int]string, lots []mediahub.Lot) []adminStorageItem {
	byKey := map[string][]adminStorageRequest{}
	for _, lot := range lots {
		if lot.TMDBID <= 0 || strings.TrimSpace(lot.Requester) == "" {
			continue
		}
		key := storageRequestKey(lot.MediaType, lot.TMDBID)
		byKey[key] = append(byKey[key], adminStorageRequest{
			Requester:   lot.Requester,
			RequestedAt: lot.RequestedAt,
			Status:      lot.Status,
			Seasons:     lot.Seasons,
		})
	}
	items := make([]adminStorageItem, 0, len(rows))
	for _, row := range rows {
		item := adminStorageItem{mediaHubStorageItem: row, PosterURL: posters[row.ID], Requests: []adminStorageRequest{}}
		if row.TMDBID > 0 {
			if requests := byKey[storageRequestKey(row.Type, row.TMDBID)]; requests != nil {
				item.Requests = requests
			}
		}
		items = append(items, item)
	}
	return items
}
