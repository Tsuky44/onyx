package handlers

import (
	"fmt"
	"sort"

	"project-player/server/database"
)

// Le volet « titres » de « Mes stats » : séries suivies, films, décennies,
// genres et appareils. Voir stats_personal.go.

// showsShown borne la liste des séries ; les comptes portent sur toutes.
const showsShown = 6

type showProgressRow struct {
	ShowID        int    `json:"show_id"`
	Title         string `json:"title"`
	PosterURL     string `json:"poster_url,omitempty"`
	Watched       int    `json:"watched_seconds"`
	EpisodesSeen  int    `json:"episodes_seen"`
	EpisodesTotal int    `json:"episodes_total"`
	Finished      bool   `json:"finished"`
}

type unfinishedMovie struct {
	MediaID   int    `json:"media_id"`
	Title     string `json:"title"`
	PosterURL string `json:"poster_url,omitempty"`
	Percent   int    `json:"percent"`
}

type decadeStat struct {
	Decade  int `json:"decade"`
	Titles  int `json:"titles"`
	Watched int `json:"watched_seconds"`
}

type genreStat struct {
	GenreID int `json:"genre_id"`
	Titles  int `json:"titles"`
	Watched int `json:"watched_seconds"`
}

// titleIDSQL : le titre d'une lecture dans le catalogue, la série pour un
// épisode, le film sinon.
const titleIDSQL = `CASE WHEN h.media_type = 'episode' THEN h.show_id ELSE h.media_id END`

// loadShowProgress : les séries regardées sur la période, avec leur
// avancement selon le serveur (épisodes marqués vus sur épisodes présents).
// Les épisodes spéciaux (saison 0) ne comptent pas : ils empêcheraient une
// série vue en entier d'être « terminée ».
func loadShowProgress(q personalQuery, p *PersonalStats) error {
	where, args := q.where()
	rows, err := database.DB.Query(`
		WITH watched AS (
			SELECT h.show_id AS id, MAX(h.show_title) AS title, SUM(h.watched_seconds) AS secs, MAX(h.started_at) AS last
			FROM playback_history h`+where+` AND h.media_type = 'episode' AND h.show_id IS NOT NULL
			GROUP BY h.show_id
		),
		episodes AS (
			SELECT e.id, CASE WHEN parent.type = 'show' THEN parent.id ELSE parent.parent_id END AS show_id
			FROM medias e JOIN medias parent ON parent.id = e.parent_id
			WHERE e.type = 'episode' AND COALESCE(e.season_number, 0) != 0
		)
		SELECT w.id, COALESCE(NULLIF(s.title, ''), w.title), COALESCE(s.poster_url, ''), w.secs,
		       (SELECT COUNT(*) FROM episodes e JOIN progressions pr ON pr.media_id = e.id
		         WHERE e.show_id = w.id AND pr.user_id = ? AND pr.is_finished = 1),
		       (SELECT COUNT(*) FROM episodes e WHERE e.show_id = w.id)
		FROM watched w LEFT JOIN medias s ON s.id = w.id
		ORDER BY w.secs DESC, w.last DESC`, append(args, q.userID)...)
	if err != nil {
		return fmt.Errorf("show progress: %w", err)
	}
	defer rows.Close()
	p.Shows = []showProgressRow{}
	for rows.Next() {
		var s showProgressRow
		if err := rows.Scan(&s.ShowID, &s.Title, &s.PosterURL, &s.Watched, &s.EpisodesSeen, &s.EpisodesTotal); err != nil {
			return fmt.Errorf("scan show progress: %w", err)
		}
		s.Finished = s.EpisodesTotal > 0 && s.EpisodesSeen >= s.EpisodesTotal
		p.ShowsCount++
		if s.Finished {
			p.ShowsFinished++
		}
		if len(p.Shows) < showsShown {
			p.Shows = append(p.Shows, s)
		}
	}
	return rows.Err()
}

// loadMovies : les films commencés sur la période et pas finis (« à finir »),
// et la durée moyenne des films regardés.
func loadMovies(q personalQuery, p *PersonalStats) error {
	where, args := q.where()
	rows, err := database.DB.Query(`
		SELECT h.media_id, MAX(h.title), COALESCE(MAX(m.poster_url), ''),
		       MAX(pr.current_position_seconds) * 100 / MAX(h.duration_seconds)
		FROM playback_history h
		JOIN progressions pr ON pr.media_id = h.media_id AND pr.user_id = h.user_id
		LEFT JOIN medias m ON m.id = h.media_id`+where+`
		  AND h.media_type = 'movie' AND pr.is_finished = 0 AND pr.current_position_seconds >= 60
		  AND h.duration_seconds > 0
		GROUP BY h.media_id
		ORDER BY MAX(h.started_at) DESC LIMIT 5`, args...)
	if err != nil {
		return fmt.Errorf("unfinished movies: %w", err)
	}
	defer rows.Close()
	p.UnfinishedMovies = []unfinishedMovie{}
	for rows.Next() {
		var m unfinishedMovie
		if err := rows.Scan(&m.MediaID, &m.Title, &m.PosterURL, &m.Percent); err != nil {
			return fmt.Errorf("scan unfinished movie: %w", err)
		}
		m.Percent = max(1, min(m.Percent, 99))
		p.UnfinishedMovies = append(p.UnfinishedMovies, m)
	}
	if err := rows.Err(); err != nil {
		return err
	}

	if err := database.DB.QueryRow(`
		SELECT COALESCE(CAST(AVG(d) AS INTEGER), 0) FROM (
			SELECT MAX(h.duration_seconds) AS d FROM playback_history h`+where+`
			  AND h.media_type = 'movie' AND h.media_id IS NOT NULL
			GROUP BY h.media_id
		) WHERE d > 0`, args...).Scan(&p.AverageMovieSeconds); err != nil {
		return fmt.Errorf("average movie: %w", err)
	}
	return nil
}

// loadDecades range les titres regardés (un film, une série) selon l'année de
// sortie que le catalogue connaît.
func loadDecades(q personalQuery, p *PersonalStats) error {
	where, args := q.where()
	rows, err := database.DB.Query(`
		SELECT CAST(substr(t.release_date, 1, 3) AS INTEGER) * 10, COUNT(DISTINCT t.id), SUM(h.watched_seconds)
		FROM playback_history h JOIN medias t ON t.id = `+titleIDSQL+where+`
		  AND t.release_date GLOB '[12][0-9][0-9][0-9]*'
		GROUP BY 1 ORDER BY 1`, args...)
	if err != nil {
		return fmt.Errorf("decades: %w", err)
	}
	defer rows.Close()
	p.Decades = []decadeStat{}
	for rows.Next() {
		var d decadeStat
		if err := rows.Scan(&d.Decade, &d.Titles, &d.Watched); err != nil {
			return fmt.Errorf("scan decade: %w", err)
		}
		p.Decades = append(p.Decades, d)
	}
	return rows.Err()
}

// tvGenreFold ramène les genres doubles des séries TMDB à ceux des films, pour
// qu'un film et une série de science-fiction tombent dans le même genre.
var tvGenreFold = map[int][]int{
	10759: {28, 12},  // Action & Adventure → Action, Aventure
	10765: {878, 14}, // Sci-Fi & Fantasy → Science-Fiction, Fantastique
	10768: {10752},   // War & Politics → Guerre
	10762: {10751},   // Kids → Familial
}

func loadGenres(q personalQuery, p *PersonalStats) error {
	where, args := q.where()
	rows, err := database.DB.Query(`
		SELECT t.id, g.genre_id, SUM(h.watched_seconds)
		FROM playback_history h JOIN medias t ON t.id = `+titleIDSQL+`
		JOIN media_genres g ON g.media_id = t.id`+where+`
		GROUP BY t.id, g.genre_id`, args...)
	if err != nil {
		return fmt.Errorf("genres: %w", err)
	}
	defer rows.Close()
	type acc struct {
		titles  map[int]bool
		watched map[int]int // par titre : un titre compté deux fois par le repli ne double pas son temps
	}
	byGenre := map[int]*acc{}
	for rows.Next() {
		var titleID, genreID, watched int
		if err := rows.Scan(&titleID, &genreID, &watched); err != nil {
			return fmt.Errorf("scan genre: %w", err)
		}
		targets, folded := tvGenreFold[genreID]
		if !folded {
			targets = []int{genreID}
		}
		for _, id := range targets {
			a := byGenre[id]
			if a == nil {
				a = &acc{titles: map[int]bool{}, watched: map[int]int{}}
				byGenre[id] = a
			}
			a.titles[titleID] = true
			a.watched[titleID] = watched
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	p.Genres = make([]genreStat, 0, len(byGenre))
	for id, a := range byGenre {
		g := genreStat{GenreID: id, Titles: len(a.titles)}
		for _, w := range a.watched {
			g.Watched += w
		}
		p.Genres = append(p.Genres, g)
	}
	sort.Slice(p.Genres, func(i, j int) bool {
		if p.Genres[i].Watched != p.Genres[j].Watched {
			return p.Genres[i].Watched > p.Genres[j].Watched
		}
		return p.Genres[i].GenreID < p.Genres[j].GenreID
	})
	if len(p.Genres) > 8 {
		p.Genres = p.Genres[:8]
	}
	return nil
}

// loadDevices : où l'on regarde, par nom d'appareil (« Salon ») plutôt que
// par application ; Secondary porte l'application, d'où l'app tire l'icône.
// Un appareil sans nom a une clé vide, que l'app nomme elle-même.
func loadDevices(q personalQuery, p *PersonalStats) error {
	where, args := q.where()
	rows, err := database.DB.Query(`
		SELECT COALESCE(NULLIF(h.device_name, ''), ''), COALESCE(MAX(h.client), ''), COUNT(*), SUM(h.watched_seconds)
		FROM playback_history h`+where+`
		GROUP BY 1 ORDER BY 4 DESC LIMIT 6`, args...)
	if err != nil {
		return fmt.Errorf("devices: %w", err)
	}
	defer rows.Close()
	p.Devices = []statBucket{}
	for rows.Next() {
		var b statBucket
		if err := rows.Scan(&b.Key, &b.Secondary, &b.Plays, &b.Watched); err != nil {
			return fmt.Errorf("scan device: %w", err)
		}
		b.Label = b.Key
		p.Devices = append(p.Devices, b)
	}
	return rows.Err()
}
