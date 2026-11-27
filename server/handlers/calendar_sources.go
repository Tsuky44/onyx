package handlers

import (
	"context"
	"fmt"
	"log"
	"time"

	"project-player/server/calendar"
	"project-player/server/database"
	"project-player/server/httpx"
	"project-player/server/mediahub"
)

// Ce que le calendrier « À venir » sait d'un compte et de la bibliothèque
// (ADR 2026-11-27-tsuky-calendrier-sorties-serveur). Chaque source est
// bornée : le calendrier ne doit jamais devenir « toutes les sorties du
// monde », ni lancer des centaines d'appels TMDB pour une vieille série
// regardée il y a des années.
const (
	// calendarWatchingWindow : une série dont on n'a rien lancé depuis un an
	// n'est plus « en cours ».
	calendarWatchingWindow = 365 * 24 * time.Hour
	calendarWatchingMax    = 100
	// calendarServerWindow : une série de la bibliothèque qui a reçu un
	// épisode ces six derniers mois est sans doute encore diffusée. Celles
	// qui n'ont rien reçu depuis sont des séries terminées ou en pause
	// longue ; leur reprise passera par un suivi ou une demande.
	calendarServerWindow = 180 * 24 * time.Hour
	calendarServerMax    = 60
	// calendarRequestsBudget : le compagnon de demandes peut être lent ; le
	// calendrier s'affiche sans lui plutôt que de l'attendre.
	calendarRequestsBudget = 4 * time.Second
)

// calendarWatchingShows : les séries de la bibliothèque dont le compte a
// lancé un épisode dans l'année, la plus récente d'abord.
func calendarWatchingShows(userID int, now time.Time) ([]calendar.Interest, error) {
	cutoff := now.Add(-calendarWatchingWindow).UTC().Format("2006-01-02")
	rows, err := database.DB.Query(`
		SELECT show.id, show.tmdb_id, show.title, COALESCE(show.poster_url, '')
		FROM progressions p
		JOIN medias ep ON ep.id = p.media_id AND ep.type = 'episode'
		JOIN medias season ON season.id = ep.parent_id AND season.type = 'season'
		JOIN medias show ON show.id = season.parent_id AND show.type = 'show'
		WHERE p.user_id = ? AND p.updated_at >= ? AND COALESCE(show.tmdb_id, 0) > 0
		GROUP BY show.id
		ORDER BY MAX(p.updated_at) DESC
		LIMIT ?`, userID, cutoff, calendarWatchingMax)
	if err != nil {
		return nil, fmt.Errorf("séries en cours: %w", err)
	}
	return scanCalendarShows(rows, calendar.SourceWatching)
}

// calendarServerShows : les séries de la bibliothèque qui ont reçu un
// épisode récemment, la plus récente d'abord.
func calendarServerShows(now time.Time) ([]calendar.Interest, error) {
	cutoff := now.Add(-calendarServerWindow).UTC().Format("2006-01-02")
	rows, err := database.DB.Query(`
		SELECT show.id, show.tmdb_id, show.title, COALESCE(show.poster_url, '')
		FROM medias show
		JOIN medias season ON season.parent_id = show.id AND season.type = 'season'
		JOIN medias ep ON ep.parent_id = season.id AND ep.type = 'episode'
		WHERE show.type = 'show' AND COALESCE(show.tmdb_id, 0) > 0 AND ep.created_at >= ?
		GROUP BY show.id
		ORDER BY MAX(ep.created_at) DESC
		LIMIT ?`, cutoff, calendarServerMax)
	if err != nil {
		return nil, fmt.Errorf("séries du serveur: %w", err)
	}
	return scanCalendarShows(rows, calendar.SourceServer)
}

type calendarRows interface {
	Next() bool
	Scan(dest ...any) error
	Err() error
	Close() error
}

func scanCalendarShows(rows calendarRows, source calendar.Source) ([]calendar.Interest, error) {
	defer rows.Close()
	var out []calendar.Interest
	for rows.Next() {
		it := calendar.Interest{Kind: calendar.KindShow, Source: source}
		if err := rows.Scan(&it.MediaID, &it.TMDBID, &it.Title, &it.PosterURL); err != nil {
			return nil, fmt.Errorf("lecture d'une série: %w", err)
		}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("lecture des séries: %w", err)
	}
	return out, nil
}

// calendarRequested : les demandes du compte auprès du compagnon (MediaHub,
// Overseerr, Jellyseerr), refus exclus. Sans compagnon réglé, ou s'il ne
// répond pas à temps, rien : les demandes manquent, le reste du calendrier
// s'affiche.
func calendarRequested(ctx context.Context, userID int) []calendar.Interest {
	hub := mediaHubClient(httpx.Standard)
	if !hub.Configured() {
		return nil
	}
	account, err := mediaHubAccount(userID)
	if err != nil {
		log.Printf("calendar: compte %d pour les demandes: %v", userID, err)
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, calendarRequestsBudget)
	defer cancel()
	lots, err := hub.Requests(ctx, account, mediahub.ScopeMine)
	if err != nil {
		log.Printf("calendar: demandes du compte %d: %v", userID, err)
		return nil
	}
	var out []calendar.Interest
	for _, lot := range lots {
		if lot.Status == "declined" || lot.TMDBID <= 0 {
			continue
		}
		kind := calendar.KindMovie
		if lot.MediaType == "tv" {
			kind = calendar.KindShow
		}
		poster := ""
		if lot.PosterPath != nil {
			poster = calendar.TMDBImage(*lot.PosterPath, "w342")
		}
		out = append(out, calendar.Interest{
			Kind: kind, TMDBID: lot.TMDBID, Source: calendar.SourceRequest,
			Title: lot.Title, PosterURL: poster,
		})
	}
	return out
}

// calendarChoices : les suivis et retraits explicites du compte.
func calendarChoices(userID int) (map[int]calendar.Choice, error) {
	rows, err := database.DB.Query(`SELECT tmdb_id, followed FROM calendar_follows WHERE user_id = ?`, userID)
	if err != nil {
		return nil, fmt.Errorf("suivis du calendrier: %w", err)
	}
	defer rows.Close()
	choices := map[int]calendar.Choice{}
	for rows.Next() {
		var id int
		var followed bool
		if err := rows.Scan(&id, &followed); err != nil {
			return nil, fmt.Errorf("lecture d'un suivi: %w", err)
		}
		choices[id] = calendar.Choice(followed)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("lecture des suivis: %w", err)
	}
	return choices, nil
}

// setCalendarChoice enregistre « suivre » (true) ou « retirer » (false).
func setCalendarChoice(userID, tmdbID int, follow bool) error {
	_, err := database.DB.Exec(`
		INSERT INTO calendar_follows (user_id, tmdb_id, followed, updated_at)
		VALUES (?, ?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(user_id, tmdb_id) DO UPDATE SET followed = excluded.followed, updated_at = excluded.updated_at`,
		userID, tmdbID, follow)
	if err != nil {
		return fmt.Errorf("suivi %d du compte %d: %w", tmdbID, userID, err)
	}
	return nil
}

// enrichCalendarFromLibrary relie à la bibliothèque les séries et films
// venus d'une demande ou d'un suivi : leur fiche, leur titre local et leur
// affiche, pour qu'un toucher ouvre la fiche du serveur. Les titres passent
// dans la langue de la requête.
func enrichCalendarFromLibrary(interests []calendar.Interest, lang mediaLanguage) error {
	var showIDs, movieIDs []int
	for _, it := range interests {
		if it.Kind == calendar.KindShow {
			showIDs = append(showIDs, it.TMDBID)
		} else {
			movieIDs = append(movieIDs, it.TMDBID)
		}
	}
	type local struct {
		id            int
		title, poster string
	}
	found := map[calendar.Kind]map[int]local{calendar.KindShow: {}, calendar.KindMovie: {}}
	for kind, ids := range map[calendar.Kind][]int{calendar.KindShow: showIDs, calendar.KindMovie: movieIDs} {
		if len(ids) == 0 {
			continue
		}
		args := []any{string(kind)}
		for _, id := range ids {
			args = append(args, id)
		}
		rows, err := database.DB.Query(fmt.Sprintf(`
			SELECT MIN(id), tmdb_id, title, COALESCE(poster_url, '')
			FROM medias WHERE type = ? AND tmdb_id IN (%s)
			GROUP BY tmdb_id`, sqlPlaceholders(len(ids))), args...)
		if err != nil {
			return fmt.Errorf("titres de la bibliothèque: %w", err)
		}
		for rows.Next() {
			var l local
			var tmdbID int
			if err := rows.Scan(&l.id, &tmdbID, &l.title, &l.poster); err != nil {
				rows.Close()
				return fmt.Errorf("lecture d'un titre: %w", err)
			}
			found[kind][tmdbID] = l
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return fmt.Errorf("lecture des titres: %w", err)
		}
	}

	mediaIDs := []int{}
	for i := range interests {
		it := &interests[i]
		l, ok := found[it.Kind][it.TMDBID]
		if !ok {
			continue
		}
		it.MediaID = l.id
		it.Title = l.title
		if l.poster != "" {
			it.PosterURL = l.poster
		}
		mediaIDs = append(mediaIDs, l.id)
	}
	texts := lang.texts(mediaIDs)
	for i := range interests {
		if text, ok := texts[interests[i].MediaID]; ok && text.Title != "" {
			interests[i].Title = text.Title
		}
	}
	return nil
}

// calendarPresence : ce que la bibliothèque détient déjà des séries et films
// du calendrier, pour « Disponible » et la lecture directe.
func calendarPresence(interests []calendar.Interest) (calendar.Presence, error) {
	presence := calendar.Presence{Episodes: map[int]map[[2]int]int{}, Movies: map[int]int{}}
	var showIDs, movieIDs []any
	for _, it := range interests {
		if it.Kind == calendar.KindShow {
			showIDs = append(showIDs, it.TMDBID)
		} else {
			movieIDs = append(movieIDs, it.TMDBID)
		}
	}
	if len(showIDs) > 0 {
		rows, err := database.DB.Query(fmt.Sprintf(`
			SELECT show.tmdb_id, season.season_number, ep.episode_number, MIN(ep.id)
			FROM medias show
			JOIN medias season ON season.parent_id = show.id AND season.type = 'season'
			JOIN medias ep ON ep.parent_id = season.id AND ep.type = 'episode'
			WHERE show.type = 'show' AND show.tmdb_id IN (%s)
			  AND ep.episode_number > 0 AND COALESCE(ep.file_path, '') <> ''
			GROUP BY show.tmdb_id, season.season_number, ep.episode_number`, sqlPlaceholders(len(showIDs))), showIDs...)
		if err != nil {
			return presence, fmt.Errorf("épisodes présents: %w", err)
		}
		for rows.Next() {
			var tmdbID, season, episode, mediaID int
			if err := rows.Scan(&tmdbID, &season, &episode, &mediaID); err != nil {
				rows.Close()
				return presence, fmt.Errorf("lecture d'un épisode présent: %w", err)
			}
			if presence.Episodes[tmdbID] == nil {
				presence.Episodes[tmdbID] = map[[2]int]int{}
			}
			presence.Episodes[tmdbID][[2]int{season, episode}] = mediaID
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return presence, fmt.Errorf("lecture des épisodes présents: %w", err)
		}
	}
	if len(movieIDs) > 0 {
		rows, err := database.DB.Query(fmt.Sprintf(`
			SELECT tmdb_id, MIN(id) FROM medias
			WHERE type = 'movie' AND tmdb_id IN (%s) AND COALESCE(file_path, '') <> ''
			GROUP BY tmdb_id`, sqlPlaceholders(len(movieIDs))), movieIDs...)
		if err != nil {
			return presence, fmt.Errorf("films présents: %w", err)
		}
		for rows.Next() {
			var tmdbID, mediaID int
			if err := rows.Scan(&tmdbID, &mediaID); err != nil {
				rows.Close()
				return presence, fmt.Errorf("lecture d'un film présent: %w", err)
			}
			presence.Movies[tmdbID] = mediaID
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return presence, fmt.Errorf("lecture des films présents: %w", err)
		}
	}
	return presence, nil
}
