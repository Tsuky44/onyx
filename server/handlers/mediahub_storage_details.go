package handlers

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"sort"
	"strconv"
	"time"

	"project-player/server/database"

	"github.com/julienschmidt/httprouter"
)

// Le détail d'un média dans le gestionnaire de stockage de MediaHub
// (ADR-0114) : sa fiche, ses saisons avec leur taille, et l'activité de
// chaque compte qui l'a commencé.

type mediaHubStorageSeason struct {
	ID           int    `json:"id"`
	Number       int    `json:"number"`
	Title        string `json:"title"`
	Size         int64  `json:"size"`
	EpisodeCount int    `json:"episode_count"`
	Path         string `json:"path"`
}

type mediaHubViewerSeason struct {
	Number  int `json:"number"`
	Total   int `json:"total"`
	Watched int `json:"watched"`
}

// mediaHubStorageViewer : ce qu'un compte a vu du média. Film : position et
// durée ; série : épisodes vus sur le total, saison par saison.
type mediaHubStorageViewer struct {
	UserID          int                    `json:"user_id"`
	Username        string                 `json:"username"`
	Finished        bool                   `json:"finished"`
	LastPlayedAt    string                 `json:"last_played_at,omitempty"`
	PositionSeconds int                    `json:"position_seconds"`
	DurationSeconds int                    `json:"duration_seconds"`
	WatchedEpisodes int                    `json:"watched_episodes,omitempty"`
	TotalEpisodes   int                    `json:"total_episodes,omitempty"`
	Seasons         []mediaHubViewerSeason `json:"seasons,omitempty"`
}

type mediaHubStorageDetails struct {
	ID          int                     `json:"id"`
	Type        string                  `json:"type"`
	Title       string                  `json:"title"`
	Overview    string                  `json:"overview,omitempty"`
	ReleaseDate string                  `json:"release_date,omitempty"`
	Duration    int                     `json:"duration,omitempty"`
	Path        string                  `json:"path,omitempty"`
	Seasons     []mediaHubStorageSeason `json:"seasons"`
	Viewers     []mediaHubStorageViewer `json:"viewers"`
}

// storagePlay est la progression d'un compte sur un fichier (film ou épisode).
type storagePlay struct {
	userID     int
	username   string
	mediaID    int
	season     int
	position   int
	duration   int
	finished   bool
	lastPlayed time.Time
}

// MediaHubStorageDetails rend le détail du film ou de la série :id
// (GET /api/integrations/mediahub/storage/:id).
func MediaHubStorageDetails(w http.ResponseWriter, _ *http.Request, ps httprouter.Params, _ int) {
	id, err := strconv.Atoi(ps.ByName("id"))
	if err != nil || id <= 0 {
		writeJSONError(w, http.StatusBadRequest, "Invalid media ID")
		return
	}
	details := mediaHubStorageDetails{ID: id, Seasons: []mediaHubStorageSeason{}, Viewers: []mediaHubStorageViewer{}}
	var overview, release, filePath sql.NullString
	err = database.DB.QueryRow(`SELECT type, title, overview, release_date, COALESCE(duration, 0), file_path
		FROM medias WHERE id = ? AND type IN ('movie', 'show')`, id).
		Scan(&details.Type, &details.Title, &overview, &release, &details.Duration, &filePath)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSONError(w, http.StatusNotFound, "Média introuvable dans Onyx")
		return
	}
	if err != nil {
		log.Printf("MediaHubStorageDetails: load %d: %v", id, err)
		writeJSONError(w, http.StatusInternalServerError, "Internal database error")
		return
	}
	details.Overview, details.ReleaseDate, details.Path = overview.String, release.String, filePath.String

	var plays []storagePlay
	totals := map[int]int{}
	if details.Type == "show" {
		if details.Seasons, err = loadStorageSeasons(id); err == nil {
			for _, s := range details.Seasons {
				totals[s.Number] += s.EpisodeCount
			}
			details.Path = commonDir(seasonPaths(details.Seasons))
			plays, err = loadStoragePlays(`e.type = 'episode' AND COALESCE(e.file_path, '') != ''
				AND (e.parent_id = ?1 OR e.parent_id IN (SELECT id FROM medias WHERE type = 'season' AND parent_id = ?1))`, id)
		}
	} else {
		plays, err = loadStoragePlays(`e.id = ?1`, id)
	}
	if err != nil {
		log.Printf("MediaHubStorageDetails: %d: %v", id, err)
		writeJSONError(w, http.StatusInternalServerError, "Internal database error")
		return
	}
	details.Viewers = aggregateStorageViewers(plays, details.Type == "show", totals)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(details)
}

func seasonPaths(seasons []mediaHubStorageSeason) []string {
	paths := make([]string, 0, len(seasons))
	for _, s := range seasons {
		if s.Path != "" {
			paths = append(paths, s.Path+"/")
		}
	}
	return paths
}

func loadStorageSeasons(showID int) ([]mediaHubStorageSeason, error) {
	rows, err := database.DB.Query(`
		SELECT se.id, COALESCE(se.season_number, 0), se.title, COUNT(e.id), COALESCE(SUM(e.file_size), 0),
			COALESCE(MIN(e.file_path), ''), COALESCE(MAX(e.file_path), '')
		FROM medias se
		LEFT JOIN medias e ON e.parent_id = se.id AND e.type = 'episode' AND COALESCE(e.file_path, '') != ''
		WHERE se.type = 'season' AND se.parent_id = ?
		GROUP BY se.id
		ORDER BY se.season_number`, showID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	seasons := []mediaHubStorageSeason{}
	for rows.Next() {
		var s mediaHubStorageSeason
		var first, last string
		if err := rows.Scan(&s.ID, &s.Number, &s.Title, &s.EpisodeCount, &s.Size, &first, &last); err != nil {
			return nil, err
		}
		if first != "" {
			s.Path = commonDir([]string{first, last})
		}
		seasons = append(seasons, s)
	}
	return seasons, rows.Err()
}

// loadStoragePlays lit les progressions des comptes sur les fichiers que
// where choisit (alias e, paramètre ?1), avec la dernière lecture de
// l'historique. Le numéro de saison est celui de la saison parente, le même
// que celui des totaux de loadStorageSeasons.
func loadStoragePlays(where string, id int) ([]storagePlay, error) {
	rows, err := database.DB.Query(`
		SELECT p.user_id, u.username, e.id, COALESCE(se.season_number, e.season_number, 0), p.current_position_seconds,
			COALESCE(e.duration, 0), p.is_finished, p.updated_at,
			(SELECT MAX(h.ended_at) FROM playback_history h WHERE h.user_id = p.user_id AND h.media_id = e.id)
		FROM medias e
		JOIN progressions p ON p.media_id = e.id
		JOIN users u ON u.id = p.user_id
		LEFT JOIN medias se ON se.id = e.parent_id AND se.type = 'season'
		WHERE (p.current_position_seconds > 0 OR p.is_finished = 1) AND `+where, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var plays []storagePlay
	for rows.Next() {
		var p storagePlay
		var progressAt, historyAt sql.NullString
		if err := rows.Scan(&p.userID, &p.username, &p.mediaID, &p.season, &p.position, &p.duration, &p.finished, &progressAt, &historyAt); err != nil {
			return nil, err
		}
		p.lastPlayed = latest(scanSQLiteTime(progressAt), scanSQLiteTime(historyAt))
		plays = append(plays, p)
	}
	return plays, rows.Err()
}

// aggregateStorageViewers fait une ligne par compte, la plus récente en tête.
// Série : les épisodes finis comptent comme vus, saison par saison sur le
// total d'épisodes de la saison (seasonTotals).
func aggregateStorageViewers(plays []storagePlay, show bool, seasonTotals map[int]int) []mediaHubStorageViewer {
	type acc struct {
		viewer  mediaHubStorageViewer
		last    time.Time
		watched map[int]int
	}
	byUser := map[int]*acc{}
	var order []int
	for _, p := range plays {
		a := byUser[p.userID]
		if a == nil {
			a = &acc{viewer: mediaHubStorageViewer{UserID: p.userID, Username: p.username}, watched: map[int]int{}}
			byUser[p.userID] = a
			order = append(order, p.userID)
		}
		if p.lastPlayed.After(a.last) || a.last.IsZero() {
			a.last = p.lastPlayed
			if !show {
				a.viewer.PositionSeconds, a.viewer.DurationSeconds, a.viewer.Finished = p.position, p.duration, p.finished
			}
		}
		if show && p.finished {
			a.watched[p.season]++
		}
	}

	totalEpisodes := 0
	numbers := make([]int, 0, len(seasonTotals))
	for n, total := range seasonTotals {
		totalEpisodes += total
		numbers = append(numbers, n)
	}
	sort.Ints(numbers)

	viewers := make([]mediaHubStorageViewer, 0, len(order))
	for _, userID := range order {
		a := byUser[userID]
		a.viewer.LastPlayedAt = formatStorageTime(a.last)
		if show {
			a.viewer.TotalEpisodes = totalEpisodes
			for _, n := range numbers {
				watched := min(a.watched[n], seasonTotals[n])
				a.viewer.WatchedEpisodes += watched
				a.viewer.Seasons = append(a.viewer.Seasons, mediaHubViewerSeason{Number: n, Total: seasonTotals[n], Watched: watched})
			}
			a.viewer.Finished = totalEpisodes > 0 && a.viewer.WatchedEpisodes >= totalEpisodes
		}
		viewers = append(viewers, a.viewer)
	}
	sort.SliceStable(viewers, func(i, j int) bool {
		return byUser[viewers[i].UserID].last.After(byUser[viewers[j].UserID].last)
	})
	return viewers
}
