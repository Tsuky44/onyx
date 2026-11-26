package indexer

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"time"

	"project-player/server/database"
	"project-player/server/httpx"
	"project-player/server/tmdb"
)

// Les genres d'un titre ne servent qu'aux statistiques (« Mes genres ») : ils
// ne passent pas par l'enrichissement du scan, qui reste aussi court qu'avant.
// Une tâche de fond les lit après coup, par petits lots, et rattrape seule une
// bibliothèque indexée avant leur arrivée. Voir l'ADR
// 2026-11-26-tsuky-statistiques-personnelles.

const (
	// genreBatch borne une passe : TMDB tolère une quarantaine de requêtes
	// par seconde, on en reste très loin.
	genreBatch = 40
	genrePause = 250 * time.Millisecond
	// genreIdle sépare deux passes quand il n'y a plus rien à lire : les
	// titres ajoutés entre-temps attendent au plus ce délai.
	genreIdle  = 30 * time.Minute
	genreStart = 2 * time.Minute
)

// errGenreNotFound : la fiche n'existe plus chez TMDB. On la marque lue, sans
// genre, plutôt que de la redemander à chaque passe.
var errGenreNotFound = errors.New("tmdb: title not found")

// fetchGenreIDs lit les genres d'une fiche TMDB. Variable pour les tests.
var fetchGenreIDs = func(ctx context.Context, kind string, tmdbID int) ([]int, error) {
	resp, err := tmdb.GetContext(ctx, httpx.Standard, fmt.Sprintf("/%s/%d", kind, tmdbID))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil, errGenreNotFound
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("tmdb: status %d", resp.StatusCode)
	}
	var body struct {
		Genres []struct {
			ID int `json:"id"`
		} `json:"genres"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("tmdb: decode genres: %w", err)
	}
	ids := make([]int, 0, len(body.Genres))
	for _, g := range body.Genres {
		if g.ID > 0 {
			ids = append(ids, g.ID)
		}
	}
	return ids, nil
}

// RunGenreFiller lit les genres manquants tant qu'il en reste, puis attend.
func RunGenreFiller(ctx context.Context) {
	wait := genreStart
	for {
		select {
		case <-ctx.Done():
			return
		case <-time.After(wait):
		}
		filled, err := FillMissingGenres(ctx, genreBatch)
		switch {
		case errors.Is(err, tmdb.ErrNoKey):
			wait = genreIdle
		case err != nil:
			log.Printf("Genres: %v", err)
			wait = genreIdle
		case filled == genreBatch:
			// Il en reste sans doute : la passe suivante part tout de suite.
			wait = genrePause
		default:
			wait = genreIdle
		}
	}
}

// FillMissingGenres lit les genres d'au plus limit films et séries qui ne les
// ont pas encore, et renvoie combien de fiches ont été traitées. Une fiche
// qu'on n'a pas pu lire (réseau, TMDB indisponible) reste à lire.
func FillMissingGenres(ctx context.Context, limit int) (int, error) {
	rows, err := database.DB.QueryContext(ctx, `
		SELECT id, type, tmdb_id FROM medias
		WHERE type IN ('movie', 'show') AND COALESCE(tmdb_id, 0) > 0 AND genres_checked_at IS NULL
		ORDER BY id LIMIT ?`, limit)
	if err != nil {
		return 0, fmt.Errorf("list titles without genres: %w", err)
	}
	type pending struct {
		id, tmdbID int
		kind       string
	}
	var todo []pending
	for rows.Next() {
		var p pending
		var mediaType string
		if err := rows.Scan(&p.id, &mediaType, &p.tmdbID); err != nil {
			rows.Close()
			return 0, fmt.Errorf("scan title without genres: %w", err)
		}
		p.kind = "movie"
		if mediaType == "show" {
			p.kind = "tv"
		}
		todo = append(todo, p)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return 0, err
	}
	rows.Close()

	done := 0
	for i, p := range todo {
		if i > 0 {
			select {
			case <-ctx.Done():
				return done, nil
			case <-time.After(genrePause):
			}
		}
		ids, err := fetchGenreIDs(ctx, p.kind, p.tmdbID)
		if errors.Is(err, tmdb.ErrNoKey) {
			return done, err
		}
		if err != nil && !errors.Is(err, errGenreNotFound) {
			continue
		}
		if err := storeGenres(p.id, ids); err != nil {
			return done, err
		}
		done++
	}
	return done, nil
}

func storeGenres(mediaID int, ids []int) error {
	tx, err := database.DB.Begin()
	if err != nil {
		return fmt.Errorf("store genres of %d: %w", mediaID, err)
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM media_genres WHERE media_id = ?`, mediaID); err != nil {
		return fmt.Errorf("clear genres of %d: %w", mediaID, err)
	}
	for _, id := range ids {
		if _, err := tx.Exec(`INSERT OR IGNORE INTO media_genres (media_id, genre_id) VALUES (?, ?)`, mediaID, id); err != nil {
			return fmt.Errorf("insert genre %d of %d: %w", id, mediaID, err)
		}
	}
	if _, err := tx.Exec(`UPDATE medias SET genres_checked_at = CURRENT_TIMESTAMP WHERE id = ?`, mediaID); err != nil {
		return fmt.Errorf("mark genres of %d: %w", mediaID, err)
	}
	return tx.Commit()
}
