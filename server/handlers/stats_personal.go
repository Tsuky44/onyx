package handlers

import (
	"database/sql"
	"fmt"
	"time"

	"project-player/server/database"
)

// « Mes stats » : ce qu'un compte a regardé, pour lui seul (GET /api/me/stats).
// Tout se lit dans playback_history, croisé avec la progression (« vu ») et le
// catalogue (épisodes, dates de sortie, genres). Ce que l'app peut déduire des
// séries déjà envoyées (jour record, séance moyenne, créneau préféré) n'est pas
// recalculé ici. Voir l'ADR 2026-11-26-tsuky-statistiques-personnelles.

// allTimeMaxDays borne « Depuis le début » : dix ans de jours à zéro restent
// une réponse de quelques dizaines de kilo-octets.
const allTimeMaxDays = 3650

// PersonalStats complète PlaybackStats pour le compte qui la demande.
type PersonalStats struct {
	AllTime   bool   `json:"all_time"`
	FirstPlay string `json:"first_play,omitempty"`
	// Previous est la période de même durée juste avant, pour comparer.
	// Absente sur « Depuis le début ».
	Previous *periodTotals `json:"previous,omitempty"`
	Streak   struct {
		Current int `json:"current"`
		Best    int `json:"best"`
	} `json:"streak"`
	// WeekdayHour : 7 lignes (lundi d'abord) de 24 heures, en secondes vues.
	WeekdayHour         [7][24]int        `json:"weekday_hour"`
	LongestPlay         *titledSeconds    `json:"longest_play,omitempty"`
	Marathon            *marathonStat     `json:"marathon,omitempty"`
	ShowsCount          int               `json:"shows_count"`
	ShowsFinished       int               `json:"shows_finished"`
	Shows               []showProgressRow `json:"shows"`
	UnfinishedMovies    []unfinishedMovie `json:"unfinished_movies"`
	AverageMovieSeconds int               `json:"average_movie_seconds"`
	Decades             []decadeStat      `json:"decades"`
	Genres              []genreStat       `json:"genres"`
	Devices             []statBucket      `json:"devices"`
	Lifetime            lifetimeStats     `json:"lifetime"`
}

type periodTotals struct {
	Plays   int `json:"plays"`
	Watched int `json:"watched_seconds"`
}

type titledSeconds struct {
	Title   string `json:"title"`
	Watched int    `json:"watched_seconds"`
}

type marathonStat struct {
	Title    string `json:"title"`
	Date     string `json:"date"`
	Episodes int    `json:"episodes"`
}

type lifetimeStats struct {
	Plays         int            `json:"plays"`
	Watched       int            `json:"watched_seconds"`
	LongestPlay   *titledSeconds `json:"longest_play,omitempty"`
	MostRewatched *rewatchStat   `json:"most_rewatched,omitempty"`
}

type rewatchStat struct {
	Title string `json:"title"`
	Times int    `json:"times"`
}

// personalQuery porte le filtre commun : ce compte, une lecture qui compte, et
// la période quand il y en a une.
type personalQuery struct {
	userID int
	window statsWindow
}

func (q personalQuery) where() (string, []any) {
	where := ` WHERE h.user_id = ? AND h.watched_seconds >= ? AND h.started_at >= ?`
	args := []any{q.userID, playbackMinSeconds, q.window.since}
	if q.window.until != "" {
		where += ` AND h.started_at < ?`
		args = append(args, q.window.until)
	}
	return where, args
}

func (q personalQuery) everWhere() (string, []any) {
	return ` WHERE h.user_id = ? AND h.watched_seconds >= ?`, []any{q.userID, playbackMinSeconds}
}

// daysSinceFirstPlay donne la durée de « Depuis le début » : du jour de la
// première lecture à aujourd'hui, au moins un jour.
func daysSinceFirstPlay(userID, offsetMinutes int, now time.Time) (int, error) {
	var first sql.NullString
	err := database.DB.QueryRow(`SELECT strftime('%Y-%m-%d', MIN(started_at), ?) FROM playback_history
		WHERE user_id = ? AND watched_seconds >= ?`, tzModifier(offsetMinutes), userID, playbackMinSeconds).Scan(&first)
	if err != nil {
		return 0, err
	}
	if !first.Valid || first.String == "" {
		return 30, nil
	}
	window := newStatsWindow(1, offsetMinutes, now)
	day, err := time.ParseInLocation("2006-01-02", first.String, window.today.Location())
	if err != nil {
		return 0, fmt.Errorf("parse first play %q: %w", first.String, err)
	}
	days := int(window.today.Sub(day).Hours()/24) + 1
	return max(1, min(days, allTimeMaxDays)), nil
}

func computePersonalStats(userID int, window statsWindow, allTime bool) (*PersonalStats, error) {
	q := personalQuery{userID: userID, window: window}
	p := &PersonalStats{AllTime: allTime}
	steps := []func(personalQuery, *PersonalStats) error{
		loadPrevious, loadStreaks, loadWeekdayHour, loadLongestPlays, loadMarathon,
		loadShowProgress, loadMovies, loadDecades, loadGenres, loadDevices, loadLifetime,
	}
	for _, step := range steps {
		if err := step(q, p); err != nil {
			return nil, err
		}
	}
	return p, nil
}

func loadPrevious(q personalQuery, p *PersonalStats) error {
	if p.AllTime {
		return nil
	}
	start := historyStamp(q.window.firstDay.AddDate(0, 0, -q.window.days))
	prev := &periodTotals{}
	err := database.DB.QueryRow(`SELECT COUNT(*), COALESCE(SUM(watched_seconds), 0) FROM playback_history
		WHERE user_id = ? AND watched_seconds >= ? AND started_at >= ? AND started_at < ?`,
		q.userID, playbackMinSeconds, start, q.window.since).Scan(&prev.Plays, &prev.Watched)
	if err != nil {
		return fmt.Errorf("previous period: %w", err)
	}
	p.Previous = prev
	return nil
}

// loadStreaks compte les jours d'affilée sur tout l'historique, pas seulement
// la période : un record ne dépend pas du filtre choisi.
func loadStreaks(q personalQuery, p *PersonalStats) error {
	where, args := q.everWhere()
	rows, err := database.DB.Query(`SELECT DISTINCT strftime('%Y-%m-%d', h.started_at, ?) FROM playback_history h`+where+` ORDER BY 1`,
		append([]any{q.window.modifier}, args...)...)
	if err != nil {
		return fmt.Errorf("streak days: %w", err)
	}
	defer rows.Close()
	var dates []string
	for rows.Next() {
		var d string
		if err := rows.Scan(&d); err != nil {
			return fmt.Errorf("scan streak day: %w", err)
		}
		dates = append(dates, d)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if len(dates) > 0 {
		p.FirstPlay = dates[0]
	}
	p.Streak.Current, p.Streak.Best = streaks(dates, q.window.today)
	return nil
}

// streaks lit des jours triés (AAAA-MM-JJ, sans doublon). La série en cours
// tient encore si le dernier jour est hier : on n'a pas forcément regardé
// quelque chose avant de consulter ses statistiques.
func streaks(dates []string, today time.Time) (current, best int) {
	var prev time.Time
	run := 0
	for _, d := range dates {
		day, err := time.ParseInLocation("2006-01-02", d, today.Location())
		if err != nil {
			continue
		}
		if !prev.IsZero() && day.Equal(prev.AddDate(0, 0, 1)) {
			run++
		} else {
			run = 1
		}
		best = max(best, run)
		prev = day
	}
	if !prev.IsZero() && (prev.Equal(today) || prev.Equal(today.AddDate(0, 0, -1))) {
		current = run
	}
	return current, best
}

func loadWeekdayHour(q personalQuery, p *PersonalStats) error {
	where, args := q.where()
	rows, err := database.DB.Query(`
		SELECT CAST(strftime('%w', h.started_at, ?) AS INTEGER), CAST(strftime('%H', h.started_at, ?) AS INTEGER),
		       COALESCE(SUM(h.watched_seconds), 0)
		FROM playback_history h`+where+` GROUP BY 1, 2`, append([]any{q.window.modifier, q.window.modifier}, args...)...)
	if err != nil {
		return fmt.Errorf("weekday hour: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var weekday, hour, watched int
		if err := rows.Scan(&weekday, &hour, &watched); err != nil {
			return fmt.Errorf("scan weekday hour: %w", err)
		}
		if weekday >= 0 && weekday < 7 && hour >= 0 && hour < 24 {
			// strftime('%w') commence le dimanche ; la grille, le lundi.
			p.WeekdayHour[(weekday+6)%7][hour] = watched
		}
	}
	return rows.Err()
}

// countsAsViewingSQL dit qu'une lecture compte pour une fois vu : au moins la
// moitié du film. Le plus revu de « Mes stats » et les « vu 3 fois » du Rétro
// comptent de la même façon.
const countsAsViewingSQL = `h.duration_seconds > 0 AND h.watched_seconds * 2 >= h.duration_seconds`

// displayTitleSQL nomme une lecture : la série pour un épisode, le titre sinon.
const displayTitleSQL = `CASE WHEN h.media_type = 'episode' AND COALESCE(h.show_title, '') != '' THEN h.show_title ELSE h.title END`

func longestPlay(where string, args []any) (*titledSeconds, error) {
	var t titledSeconds
	err := database.DB.QueryRow(`SELECT `+displayTitleSQL+`, h.watched_seconds FROM playback_history h`+where+`
		ORDER BY h.watched_seconds DESC LIMIT 1`, args...).Scan(&t.Title, &t.Watched)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func loadLongestPlays(q personalQuery, p *PersonalStats) error {
	where, args := q.where()
	var err error
	if p.LongestPlay, err = longestPlay(where, args); err != nil {
		return fmt.Errorf("longest play: %w", err)
	}
	where, args = q.everWhere()
	if p.Lifetime.LongestPlay, err = longestPlay(where, args); err != nil {
		return fmt.Errorf("longest play ever: %w", err)
	}
	return nil
}

// loadMarathon cherche le jour où l'on a vu le plus d'épisodes différents
// d'une même série. Deux épisodes au moins : un seul n'est pas un marathon.
func loadMarathon(q personalQuery, p *PersonalStats) error {
	where, args := q.where()
	var m marathonStat
	err := database.DB.QueryRow(`
		SELECT MAX(h.show_title), strftime('%Y-%m-%d', h.started_at, ?) AS day,
		       COUNT(DISTINCT COALESCE(CAST(h.media_id AS TEXT), h.title)) AS episodes
		FROM playback_history h`+where+` AND h.media_type = 'episode' AND COALESCE(h.show_title, '') != ''
		GROUP BY h.show_title, day
		HAVING episodes >= 2
		ORDER BY episodes DESC, SUM(h.watched_seconds) DESC LIMIT 1`,
		append([]any{q.window.modifier}, args...)...).Scan(&m.Title, &m.Date, &m.Episodes)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return fmt.Errorf("marathon: %w", err)
	}
	p.Marathon = &m
	return nil
}

func loadLifetime(q personalQuery, p *PersonalStats) error {
	where, args := q.everWhere()
	if err := database.DB.QueryRow(`SELECT COUNT(*), COALESCE(SUM(h.watched_seconds), 0) FROM playback_history h`+where, args...).
		Scan(&p.Lifetime.Plays, &p.Lifetime.Watched); err != nil {
		return fmt.Errorf("lifetime totals: %w", err)
	}
	var r rewatchStat
	err := database.DB.QueryRow(`
		SELECT MAX(h.title), COUNT(*) FROM playback_history h`+where+`
		  AND h.media_type = 'movie' AND h.media_id IS NOT NULL AND `+countsAsViewingSQL+`
		GROUP BY h.media_id HAVING COUNT(*) >= 2
		ORDER BY 2 DESC, MAX(h.started_at) DESC LIMIT 1`, args...).Scan(&r.Title, &r.Times)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return fmt.Errorf("most rewatched: %w", err)
	}
	p.Lifetime.MostRewatched = &r
	return nil
}
