package handlers

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"

	"project-player/server/database"
	"project-player/server/indexer"

	"github.com/julienschmidt/httprouter"
)

// Le gestionnaire de stockage de MediaHub sur Onyx (ADR-0114) : la même page
// qu'avec Emby, qui liste films et séries par taille, dit quand ils ont été
// regardés pour la dernière fois et par qui, et les supprime du disque.

// mediaHubStorageItem est une ligne de la liste. LastPlayedAt est la dernière
// lecture tous comptes confondus : c'est sur elle que MediaHub filtre « pas vu
// depuis N mois ».
type mediaHubStorageItem struct {
	ID           int    `json:"id"`
	Type         string `json:"type"`
	Title        string `json:"title"`
	TMDBID       int    `json:"tmdb_id,omitempty"`
	Path         string `json:"path"`
	Size         int64  `json:"size"`
	EpisodeCount int    `json:"episode_count,omitempty"`
	AddedAt      string `json:"added_at,omitempty"`
	LastPlayedAt string `json:"last_played_at,omitempty"`
}

type mediaHubStorageList struct {
	Movies []mediaHubStorageItem `json:"movies"`
	Shows  []mediaHubStorageItem `json:"shows"`
}

// lastPlayedCTE : la dernière lecture de chaque média, d'un côté par la
// progression (une position ou « vu »), de l'autre par l'historique. Les deux
// tables n'écrivent pas leurs dates au même format : le plus récent des deux
// se choisit en Go, après lecture.
const lastPlayedCTE = `
	WITH pp AS (
		SELECT media_id, MAX(updated_at) AS at FROM progressions
		WHERE current_position_seconds > 0 OR is_finished = 1 GROUP BY media_id
	), hh AS (
		SELECT media_id, MAX(ended_at) AS at FROM playback_history
		WHERE media_id IS NOT NULL GROUP BY media_id
	)`

// MediaHubStorage rend films et séries avec leur taille sur le disque
// (GET /api/integrations/mediahub/storage).
func MediaHubStorage(w http.ResponseWriter, _ *http.Request, _ httprouter.Params, _ int) {
	movies, err := loadStorageMovies()
	if err == nil {
		var shows []mediaHubStorageItem
		if shows, err = loadStorageShows(); err == nil {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(mediaHubStorageList{Movies: movies, Shows: shows})
			return
		}
	}
	log.Printf("MediaHubStorage: %v", err)
	writeJSONError(w, http.StatusInternalServerError, "Internal database error")
}

func loadStorageMovies() ([]mediaHubStorageItem, error) {
	rows, err := database.DB.Query(lastPlayedCTE + `
		SELECT m.id, m.title, COALESCE(m.tmdb_id, 0), COALESCE(m.file_path, ''), COALESCE(m.file_size, 0),
			m.created_at, pp.at, hh.at
		FROM medias m
		LEFT JOIN pp ON pp.media_id = m.id
		LEFT JOIN hh ON hh.media_id = m.id
		WHERE m.type = 'movie'
		ORDER BY m.title`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	movies := []mediaHubStorageItem{}
	for rows.Next() {
		item := mediaHubStorageItem{Type: "movie"}
		var added, progressAt, historyAt sql.NullString
		if err := rows.Scan(&item.ID, &item.Title, &item.TMDBID, &item.Path, &item.Size, &added, &progressAt, &historyAt); err != nil {
			return nil, err
		}
		item.AddedAt = formatStorageTime(scanSQLiteTime(added))
		item.LastPlayedAt = formatStorageTime(latest(scanSQLiteTime(progressAt), scanSQLiteTime(historyAt)))
		movies = append(movies, item)
	}
	return movies, rows.Err()
}

// storageEpisode est un fichier d'épisode rattaché à sa série.
type storageEpisode struct {
	showID     int
	path       string
	size       int64
	lastPlayed time.Time
}

func loadStorageShows() ([]mediaHubStorageItem, error) {
	rows, err := database.DB.Query(`SELECT id, title, COALESCE(tmdb_id, 0), created_at FROM medias WHERE type = 'show' ORDER BY title`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	shows := []mediaHubStorageItem{}
	for rows.Next() {
		item := mediaHubStorageItem{Type: "show"}
		var added sql.NullString
		if err := rows.Scan(&item.ID, &item.Title, &item.TMDBID, &added); err != nil {
			return nil, err
		}
		item.AddedAt = formatStorageTime(scanSQLiteTime(added))
		shows = append(shows, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()

	// Un épisode pend à une saison, ou directement à sa série.
	epRows, err := database.DB.Query(lastPlayedCTE + `
		SELECT CASE WHEN par.type = 'season' THEN par.parent_id ELSE par.id END,
			e.file_path, COALESCE(e.file_size, 0), pp.at, hh.at
		FROM medias e
		JOIN medias par ON par.id = e.parent_id
		LEFT JOIN pp ON pp.media_id = e.id
		LEFT JOIN hh ON hh.media_id = e.id
		WHERE e.type = 'episode' AND COALESCE(e.file_path, '') != ''`)
	if err != nil {
		return nil, err
	}
	defer epRows.Close()
	var episodes []storageEpisode
	for epRows.Next() {
		var ep storageEpisode
		var showID sql.NullInt64
		var progressAt, historyAt sql.NullString
		if err := epRows.Scan(&showID, &ep.path, &ep.size, &progressAt, &historyAt); err != nil {
			return nil, err
		}
		if !showID.Valid {
			continue
		}
		ep.showID = int(showID.Int64)
		ep.lastPlayed = latest(scanSQLiteTime(progressAt), scanSQLiteTime(historyAt))
		episodes = append(episodes, ep)
	}
	if err := epRows.Err(); err != nil {
		return nil, err
	}
	return addEpisodesToShows(shows, episodes), nil
}

// addEpisodesToShows additionne tailles et épisodes par série, garde la
// dernière lecture de n'importe quel épisode et prend pour chemin le dossier
// commun de ses fichiers.
func addEpisodesToShows(shows []mediaHubStorageItem, episodes []storageEpisode) []mediaHubStorageItem {
	type acc struct {
		size       int64
		count      int
		lastPlayed time.Time
		paths      []string
	}
	byShow := map[int]*acc{}
	for _, ep := range episodes {
		a := byShow[ep.showID]
		if a == nil {
			a = &acc{}
			byShow[ep.showID] = a
		}
		a.size += ep.size
		a.count++
		a.lastPlayed = latest(a.lastPlayed, ep.lastPlayed)
		a.paths = append(a.paths, ep.path)
	}
	for i := range shows {
		a := byShow[shows[i].ID]
		if a == nil {
			continue
		}
		shows[i].Size = a.size
		shows[i].EpisodeCount = a.count
		shows[i].LastPlayedAt = formatStorageTime(a.lastPlayed)
		shows[i].Path = commonDir(a.paths)
	}
	return shows
}

// commonDir rend le plus long dossier commun aux chemins. Celui du plus petit
// et du plus grand dans l'ordre lexical est celui de tous.
func commonDir(paths []string) string {
	if len(paths) == 0 {
		return ""
	}
	sorted := append([]string(nil), paths...)
	sort.Strings(sorted)
	first, last := strings.ReplaceAll(sorted[0], "\\", "/"), strings.ReplaceAll(sorted[len(sorted)-1], "\\", "/")
	if first == last {
		return strings.TrimSuffix(path.Dir(first), "/")
	}
	n := 0
	for n < len(first) && n < len(last) && first[n] == last[n] {
		n++
	}
	prefix := first[:n]
	if n < len(first) || n < len(last) {
		if i := strings.LastIndex(prefix, "/"); i >= 0 {
			prefix = prefix[:i]
		}
	}
	return strings.TrimSuffix(prefix, "/")
}

func latest(a, b time.Time) time.Time {
	if b.After(a) {
		return b
	}
	return a
}

func formatStorageTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}

// MediaHubDeleteStorage supprime du disque et d'Onyx le film, la série ou la
// saison :id (DELETE /api/integrations/mediahub/storage/:id).
func MediaHubDeleteStorage(w http.ResponseWriter, _ *http.Request, ps httprouter.Params, _ int) {
	id, err := strconv.Atoi(ps.ByName("id"))
	if err != nil || id <= 0 {
		writeJSONError(w, http.StatusBadRequest, "Invalid media ID")
		return
	}
	var tmdbID int
	_ = database.DB.QueryRow(`SELECT COALESCE(tmdb_id, 0) FROM medias WHERE id = ?`, id).Scan(&tmdbID)

	report, err := indexer.DeleteMedia(id)
	switch {
	case errors.Is(err, indexer.ErrMediaNotFound):
		writeJSONError(w, http.StatusNotFound, "Média introuvable dans Onyx")
		return
	case errors.Is(err, indexer.ErrOutsideLibrary):
		writeJSONError(w, http.StatusConflict, "Un fichier du média n'est dans aucune bibliothèque de films ou de séries d'Onyx")
		return
	case err != nil:
		log.Printf("MediaHubDeleteStorage: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Onyx n'a pas pu supprimer tous les fichiers (droits d'écriture sur le disque ?)")
		return
	}
	if tmdbID > 0 {
		invalidateMediaHubStatus(tmdbID)
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(report)
}
