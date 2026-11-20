package watchlists

import (
	"fmt"

	"project-player/server/models"
)

// listProgress est ce que le compte qui lit a fait d'une liste (ADR-0159).
type listProgress struct {
	watched  int
	onServer int
	next     *models.WatchListNext
	// watchedItems sont les éléments (et non les fiches) que le compte a vus :
	// le détail d'une liste en tire l'indicateur `watched` de chaque titre.
	watchedItems map[int]bool
}

// sqlChunk borne les paramètres d'une requête `IN (…)` : une liste porte
// jusqu'à MaxItemsPerList titres et la page en lit plusieurs.
const sqlChunk = 500

// progress calcule, pour chaque liste, combien de ses titres le serveur a,
// combien le compte en a vus et lequel regarder ensuite.
//
// Le serveur tranche, pas l'app : « vu » n'est pas un pourcentage de lecture.
//   - un film est vu quand sa progression est terminée (is_finished) ;
//   - une série est vue quand chacun de ses épisodes présents sur le disque
//     l'est. Les épisodes sans fichier ne comptent pas : ce sont des
//     emplacements TMDB que le serveur n'a pas, ils laisseraient une série
//     finie à un épisode près pour toujours (comme loadShowWatchStats).
//
// Le prochain titre est le premier non vu dans l'ordre d'ajout, parmi les
// titres que le serveur a : un titre à demander ne se lance pas.
func (s *Store) progress(viewerID int, listIDs []int) (map[int]listProgress, error) {
	out := map[int]listProgress{}
	if len(listIDs) == 0 {
		return out, nil
	}
	type entry struct {
		listID int
		next   models.WatchListNext
		isShow bool
	}
	rows, err := s.db.Query(fmt.Sprintf(resolvedItems+`
		SELECT r.list_id, r.id, r.resolved_id, m.type,
			COALESCE(NULLIF(m.title, ''), r.title),
			COALESCE(NULLIF(m.poster_url, ''), r.poster_url),
			COALESCE(NULLIF(m.release_date, ''), r.release_date)
		FROM resolved r JOIN medias m ON m.id = r.resolved_id
		WHERE r.resolved_id > 0
		ORDER BY r.list_id, r.added_at, r.id`, placeholders(len(listIDs))), intArgs(listIDs)...)
	if err != nil {
		return nil, fmt.Errorf("load watch list progress items: %w", err)
	}
	var entries []entry
	var movieIDs, showIDs []int
	for rows.Next() {
		var e entry
		var mediaType string
		if err := rows.Scan(&e.listID, &e.next.ID, &e.next.MediaID, &mediaType,
			&e.next.Title, &e.next.PosterURL, &e.next.ReleaseDate); err != nil {
			rows.Close()
			return nil, fmt.Errorf("scan watch list progress item: %w", err)
		}
		e.isShow = mediaType == string(models.TypeShow)
		e.next.MediaType = "movie"
		if e.isShow {
			e.next.MediaType = "show"
			showIDs = append(showIDs, e.next.MediaID)
		} else {
			movieIDs = append(movieIDs, e.next.MediaID)
		}
		entries = append(entries, e)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("load watch list progress items: %w", err)
	}

	finishedMovies := map[int]bool{}
	for _, chunk := range chunks(movieIDs) {
		rows, err := s.db.Query(fmt.Sprintf(`
			SELECT media_id FROM progressions
			WHERE user_id = ? AND COALESCE(is_finished, 0) <> 0 AND media_id IN (%s)`,
			placeholders(len(chunk))), append([]interface{}{viewerID}, intArgs(chunk)...)...)
		if err != nil {
			return nil, fmt.Errorf("load finished movies: %w", err)
		}
		for rows.Next() {
			var id int
			if err := rows.Scan(&id); err != nil {
				rows.Close()
				return nil, fmt.Errorf("scan finished movie: %w", err)
			}
			finishedMovies[id] = true
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return nil, fmt.Errorf("load finished movies: %w", err)
		}
	}

	finishedShows := map[int]bool{}
	for _, chunk := range chunks(showIDs) {
		rows, err := s.db.Query(fmt.Sprintf(`
			SELECT season.parent_id, COUNT(*),
				SUM(CASE WHEN COALESCE(p.is_finished, 0) <> 0 THEN 1 ELSE 0 END)
			FROM medias e
			JOIN medias season ON e.parent_id = season.id AND season.type = 'season'
			LEFT JOIN progressions p ON p.media_id = e.id AND p.user_id = ?
			WHERE e.type = 'episode' AND e.file_path IS NOT NULL AND e.file_path <> ''
			  AND season.parent_id IN (%s)
			GROUP BY season.parent_id`, placeholders(len(chunk))),
			append([]interface{}{viewerID}, intArgs(chunk)...)...)
		if err != nil {
			return nil, fmt.Errorf("load show progress: %w", err)
		}
		for rows.Next() {
			var id, available, finished int
			if err := rows.Scan(&id, &available, &finished); err != nil {
				rows.Close()
				return nil, fmt.Errorf("scan show progress: %w", err)
			}
			finishedShows[id] = available > 0 && finished >= available
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return nil, fmt.Errorf("load show progress: %w", err)
		}
	}

	for _, e := range entries {
		p := out[e.listID]
		p.onServer++
		watched := finishedMovies[e.next.MediaID]
		if e.isShow {
			watched = finishedShows[e.next.MediaID]
		}
		if watched {
			p.watched++
			if p.watchedItems == nil {
				p.watchedItems = map[int]bool{}
			}
			p.watchedItems[e.next.ID] = true
		} else if p.next == nil {
			next := e.next
			p.next = &next
		}
		out[e.listID] = p
	}
	return out, nil
}

// chunks découpe ids, sans doublon, en lots que SQLite accepte.
func chunks(ids []int) [][]int {
	seen := map[int]bool{}
	var unique []int
	for _, id := range ids {
		if !seen[id] {
			seen[id] = true
			unique = append(unique, id)
		}
	}
	var out [][]int
	for len(unique) > 0 {
		n := min(sqlChunk, len(unique))
		out = append(out, unique[:n])
		unique = unique[n:]
	}
	return out
}
