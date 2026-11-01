package handlers

import "project-player/server/database"

// seasonWatchStats is the watch roll-up of one local season: how many episodes
// the server holds, and how many of them the caller finished or merely started.
// Same rule as the show roll-up (loadShowWatchStats): an episode without a file
// is a TMDB placeholder and never counts, or a fully watched season would stay
// one episode short forever.
type seasonWatchStats struct {
	available int
	watched   int
	started   int
}

// loadSeasonWatchStats counts, per season row of [showID], the episodes present
// on disk and the caller's progress on them.
func loadSeasonWatchStats(showID, userID int) (map[int]seasonWatchStats, error) {
	rows, err := database.DB.Query(`
		SELECT m.parent_id,
		       COUNT(*),
		       SUM(CASE WHEN COALESCE(p.is_finished, 0) != 0 THEN 1 ELSE 0 END),
		       SUM(CASE WHEN COALESCE(p.is_finished, 0) = 0
		                 AND COALESCE(p.current_position_seconds, 0) > 0
		                THEN 1 ELSE 0 END)
		FROM medias m
		JOIN medias season ON m.parent_id = season.id AND season.type = 'season'
		LEFT JOIN progressions p ON p.media_id = m.id AND p.user_id = ?
		WHERE m.type = 'episode'
		  AND m.file_path IS NOT NULL AND m.file_path != ''
		  AND season.parent_id = ?
		GROUP BY m.parent_id`, userID, showID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	stats := map[int]seasonWatchStats{}
	for rows.Next() {
		var seasonID int
		var entry seasonWatchStats
		if err := rows.Scan(&seasonID, &entry.available, &entry.watched, &entry.started); err != nil {
			return nil, err
		}
		stats[seasonID] = entry
	}
	return stats, rows.Err()
}

// applySeasonWatchStats stamps each local season with its counts. A season
// absent from [stats] (virtual TMDB season, or no episode on disk) keeps zeros,
// which the client reads as "nothing seen".
func applySeasonWatchStats(seasons []showSeasonPayload, stats map[int]seasonWatchStats) {
	for i := range seasons {
		entry, ok := stats[seasons[i].ID]
		if !ok {
			continue
		}
		seasons[i].AvailableEpisodeCount = entry.available
		seasons[i].WatchedEpisodeCount = entry.watched
		seasons[i].StartedEpisodeCount = entry.started
	}
}
