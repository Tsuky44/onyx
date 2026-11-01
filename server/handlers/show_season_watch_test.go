package handlers

import (
	"testing"

	"project-player/server/database"
)

// Le tour d'une bulle de saison se remplit selon ce que l'utilisateur a vu des
// épisodes que le serveur possède : un épisode terminé compte, un épisode
// seulement commencé compte à part, un épisode sans fichier ne compte pas.
func TestSeasonWatchStatsCountOnlyHeldEpisodesOfTheCaller(t *testing.T) {
	seasonID, episodeIDs := setupWatchedBatchTestDB(t, 4)
	var showID int
	if err := database.DB.QueryRow(
		"SELECT parent_id FROM medias WHERE id = ?", seasonID,
	).Scan(&showID); err != nil {
		t.Fatalf("show id: %v", err)
	}

	if _, err := database.DB.Exec(
		"INSERT INTO progressions (user_id, media_id, current_position_seconds, is_finished) VALUES (1, ?, 1000, 1), (1, ?, 120, 0)",
		episodeIDs[0], episodeIDs[1],
	); err != nil {
		t.Fatalf("insert progressions: %v", err)
	}
	// Un espace réservé TMDB : pas de fichier, donc hors du décompte.
	if _, err := database.DB.Exec(
		"INSERT INTO medias (type, title, parent_id, episode_number) VALUES ('episode', 'À venir', ?, 5)",
		seasonID,
	); err != nil {
		t.Fatalf("insert placeholder: %v", err)
	}

	stats, err := loadSeasonWatchStats(showID, 1)
	if err != nil {
		t.Fatalf("loadSeasonWatchStats: %v", err)
	}

	got := stats[seasonID]
	if got.available != 4 || got.watched != 1 || got.started != 1 {
		t.Fatalf("got %+v, want available 4, watched 1, started 1", got)
	}

	other, err := loadSeasonWatchStats(showID, 2)
	if err != nil {
		t.Fatalf("loadSeasonWatchStats other user: %v", err)
	}
	if other[seasonID].watched != 0 {
		t.Fatalf("another account must not inherit the progress, got %+v", other[seasonID])
	}
}

func TestApplySeasonWatchStatsLeavesUnheldSeasonsAtZero(t *testing.T) {
	seasons := []showSeasonPayload{
		{Media: mediaWithSeason(1, "Saison 1")},
		{Media: mediaWithSeason(2, "Saison 2")},
	}
	seasons[0].ID = 10

	applySeasonWatchStats(seasons, map[int]seasonWatchStats{10: {available: 8, watched: 8}})

	if seasons[0].AvailableEpisodeCount != 8 || seasons[0].WatchedEpisodeCount != 8 {
		t.Fatalf("held season lost its counts: %+v", seasons[0])
	}
	if seasons[1].AvailableEpisodeCount != 0 || seasons[1].WatchedEpisodeCount != 0 {
		t.Fatalf("virtual season must stay at zero: %+v", seasons[1])
	}
}
