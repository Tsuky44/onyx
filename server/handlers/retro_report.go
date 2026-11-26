package handlers

import (
	"database/sql"
	"fmt"
	"time"

	"project-player/server/database"
	"project-player/server/ttlcache"
)

// Le Rétro d'un compte : ce qu'il a regardé du 1er janvier au 30 novembre.
// Il réutilise les chargeurs de « Mes stats » (grille jour × heure, marathon,
// appareils) sur une fenêtre fermée, et ajoute ce qui n'appartient qu'à lui :
// top 5, mois, moments, part de lecture directe, place sur le serveur.

// retroMinSeconds est le seuil du Rétro : sous 5 h dans l'année, rien ne
// s'affiche. Une story bâtie sur trois films serait vide d'un écran à l'autre.
const retroMinSeconds = 5 * 3600

// retroTopTitles est la longueur du classement de l'écran « Ton top 5 ».
const retroTopTitles = 5

// retroReports garde un Rétro calculé une heure : la fenêtre est fermée, les
// chiffres ne changent plus, et chaque ouverture de la story n'a pas à relire
// toute une année d'historique. 500 comptes × trois fuseaux, au plus.
var retroReports = ttlcache.New[*RetroReport](time.Hour, 500)

// RetroReport est la réponse de GET /api/me/retro/:year.
type RetroReport struct {
	Year     int  `json:"year"`
	Eligible bool `json:"eligible"`
	// Les chiffres qui suivent sont vides quand Eligible est faux.
	WatchedSeconds int           `json:"watched_seconds"`
	Plays          int           `json:"plays"`
	Titles         int           `json:"titles"`
	MovieSeconds   int           `json:"movie_seconds"`
	Top            []retroTitle  `json:"top"`
	Months         []int         `json:"months"`   // 12 totaux, janvier d'abord
	Hours          []int         `json:"hours"`    // 24 totaux, heure de l'appareil
	Weekdays       []int         `json:"weekdays"` // 7 totaux, lundi d'abord
	Marathon       *marathonStat `json:"marathon,omitempty"`
	FirstPlay      *retroMoment  `json:"first_play,omitempty"`
	LatestNight    *retroMoment  `json:"latest_night,omitempty"`
	Devices        []statBucket  `json:"devices"`
	// DirectPercent est la part du temps lue telle quelle, sans conversion.
	// Seul chiffre technique du Rétro, présenté comme une nouvelle du serveur.
	DirectPercent int         `json:"direct_percent"`
	Archetype     string      `json:"archetype"`
	Server        retroServer `json:"server"`
}

type retroTitle struct {
	MediaID   int    `json:"media_id"`
	Title     string `json:"title"`
	MediaType string `json:"media_type"` // "show" ou "movie"
	PosterURL string `json:"poster_url"`
	Watched   int    `json:"watched_seconds"`
	Episodes  int    `json:"episodes"` // épisodes différents, pour une série
	Times     int    `json:"times"`    // fois vu, pour un film
}

// retroMoment est une séance datée, à l'heure de l'appareil
// (AAAA-MM-JJTHH:MM, sans fuseau : l'app l'affiche telle quelle).
type retroMoment struct {
	Title string `json:"title"`
	At    string `json:"at"`
}

// retroServer ne nomme personne : un total, un rang, le titre le plus partagé.
type retroServer struct {
	Members         int    `json:"members"`
	WatchedSeconds  int    `json:"watched_seconds"`
	Rank            int    `json:"rank"`
	TopTitle        string `json:"top_title"`
	TopTitleViewers int    `json:"top_title_viewers"`
}

// titleKeySQL regroupe une lecture sous ce qu'elle raconte : la série pour un
// épisode, le film sinon. Même clé que le classement de l'administration.
const titleKeySQL = `CASE WHEN h.media_type = 'episode' AND COALESCE(h.show_title, '') != '' THEN 'show:' || h.show_title
	ELSE 'media:' || COALESCE(CAST(h.media_id AS TEXT), h.title) END`

func computeRetro(userID, year, offsetMinutes int) (*RetroReport, error) {
	key := fmt.Sprintf("%d:%d:%d", userID, year, offsetMinutes)
	if cached, ok := retroReports.Get(key); ok {
		return cached, nil
	}
	q := personalQuery{userID: userID, window: newRetroWindow(year, offsetMinutes)}
	r := &RetroReport{Year: year, Top: []retroTitle{}, Months: []int{}, Hours: []int{}, Weekdays: []int{}, Devices: []statBucket{}}
	if err := loadRetroTotals(q, r); err != nil {
		return nil, err
	}
	r.Eligible = r.WatchedSeconds >= retroMinSeconds
	if r.Eligible {
		steps := []func(personalQuery, *RetroReport) error{
			loadRetroTop, loadRetroMonths, loadRetroHabits, loadRetroMoments, loadRetroDirect, loadRetroServer,
		}
		for _, step := range steps {
			if err := step(q, r); err != nil {
				return nil, err
			}
		}
		r.Archetype = chooseArchetype(r)
	} else {
		// Sous le seuil, la réponse ne dit que cela.
		*r = RetroReport{Year: year, Top: []retroTitle{}, Months: []int{}, Hours: []int{}, Weekdays: []int{}, Devices: []statBucket{}}
	}
	retroReports.Put(key, r)
	return r, nil
}

func loadRetroTotals(q personalQuery, r *RetroReport) error {
	where, args := q.where()
	err := database.DB.QueryRow(`
		SELECT COUNT(*), COALESCE(SUM(h.watched_seconds), 0), COUNT(DISTINCT `+titleKeySQL+`),
		       COALESCE(SUM(CASE WHEN h.media_type = 'movie' THEN h.watched_seconds ELSE 0 END), 0)
		FROM playback_history h`+where, args...).Scan(&r.Plays, &r.WatchedSeconds, &r.Titles, &r.MovieSeconds)
	if err != nil {
		return fmt.Errorf("retro totals: %w", err)
	}
	return nil
}

func loadRetroTop(q personalQuery, r *RetroReport) error {
	where, args := q.where()
	rows, err := database.DB.Query(`
		SELECT CASE WHEN h.media_type = 'episode' AND COALESCE(h.show_title, '') != '' THEN COALESCE(MAX(h.show_id), 0)
		            ELSE COALESCE(MAX(h.media_id), 0) END,
		       MAX(`+displayTitleSQL+`),
		       CASE WHEN h.media_type = 'episode' AND COALESCE(h.show_title, '') != '' THEN 'show' ELSE 'movie' END,
		       COALESCE(MAX(NULLIF(show.poster_url, '')), MAX(NULLIF(m.poster_url, '')), ''),
		       SUM(h.watched_seconds),
		       COUNT(DISTINCT CASE WHEN h.media_type = 'episode' THEN COALESCE(CAST(h.media_id AS TEXT), h.title) END),
		       SUM(CASE WHEN h.media_type = 'movie' AND `+countsAsViewingSQL+` THEN 1 ELSE 0 END)
		FROM playback_history h
		LEFT JOIN medias m ON m.id = h.media_id LEFT JOIN medias show ON show.id = h.show_id`+where+`
		GROUP BY `+titleKeySQL+`
		ORDER BY 5 DESC LIMIT ?`, append(args, retroTopTitles)...)
	if err != nil {
		return fmt.Errorf("retro top: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var t retroTitle
		if err := rows.Scan(&t.MediaID, &t.Title, &t.MediaType, &t.PosterURL, &t.Watched, &t.Episodes, &t.Times); err != nil {
			return fmt.Errorf("scan retro top: %w", err)
		}
		r.Top = append(r.Top, t)
	}
	return rows.Err()
}

func loadRetroMonths(q personalQuery, r *RetroReport) error {
	where, args := q.where()
	rows, err := database.DB.Query(`
		SELECT CAST(strftime('%m', h.started_at, ?) AS INTEGER), SUM(h.watched_seconds)
		FROM playback_history h`+where+` GROUP BY 1`, append([]any{q.window.modifier}, args...)...)
	if err != nil {
		return fmt.Errorf("retro months: %w", err)
	}
	defer rows.Close()
	r.Months = make([]int, 12)
	for rows.Next() {
		var month, watched int
		if err := rows.Scan(&month, &watched); err != nil {
			return fmt.Errorf("scan retro month: %w", err)
		}
		if month >= 1 && month <= 12 {
			r.Months[month-1] = watched
		}
	}
	return rows.Err()
}

// loadRetroHabits reprend trois chargeurs de « Mes stats » : la grille jour ×
// heure (repliée en heures et en jours), le marathon et les appareils.
func loadRetroHabits(q personalQuery, r *RetroReport) error {
	p := &PersonalStats{}
	for _, step := range []func(personalQuery, *PersonalStats) error{loadWeekdayHour, loadMarathon, loadDevices} {
		if err := step(q, p); err != nil {
			return err
		}
	}
	r.Hours, r.Weekdays = make([]int, 24), make([]int, 7)
	for day, hours := range p.WeekdayHour {
		for hour, seconds := range hours {
			r.Hours[hour] += seconds
			r.Weekdays[day] += seconds
		}
	}
	r.Marathon, r.Devices = p.Marathon, p.Devices
	return nil
}

// loadRetroMoments trouve la première séance de l'année et la plus tardive :
// celle qui commence le plus tard entre minuit et 5 h.
func loadRetroMoments(q personalQuery, r *RetroReport) error {
	where, args := q.where()
	moment := func(query string, args []any) (*retroMoment, error) {
		var m retroMoment
		err := database.DB.QueryRow(query, args...).Scan(&m.Title, &m.At)
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return &m, err
	}
	var err error
	r.FirstPlay, err = moment(`SELECT `+displayTitleSQL+`, strftime('%Y-%m-%dT%H:%M', h.started_at, ?)
		FROM playback_history h`+where+` ORDER BY h.started_at LIMIT 1`, append([]any{q.window.modifier}, args...))
	if err != nil {
		return fmt.Errorf("retro first play: %w", err)
	}
	m := q.window.modifier
	nightArgs := append(append([]any{m}, args...), m, m)
	r.LatestNight, err = moment(`SELECT `+displayTitleSQL+`, strftime('%Y-%m-%dT%H:%M', h.started_at, ?)
		FROM playback_history h`+where+` AND CAST(strftime('%H', h.started_at, ?) AS INTEGER) < 5
		ORDER BY strftime('%H:%M:%S', h.started_at, ?) DESC LIMIT 1`, nightArgs)
	if err != nil {
		return fmt.Errorf("retro latest night: %w", err)
	}
	return nil
}

// loadRetroDirect : une lecture sans méthode connue est directe, comme dans
// les statistiques du serveur ; une lecture hors ligne (« local ») n'a rien
// demandé au serveur non plus.
func loadRetroDirect(q personalQuery, r *RetroReport) error {
	where, args := q.where()
	var direct int
	err := database.DB.QueryRow(`
		SELECT COALESCE(SUM(CASE WHEN COALESCE(NULLIF(h.play_method, ''), 'direct') IN ('direct', 'local')
		                    THEN h.watched_seconds ELSE 0 END), 0)
		FROM playback_history h`+where, args...).Scan(&direct)
	if err != nil {
		return fmt.Errorf("retro direct: %w", err)
	}
	if r.WatchedSeconds > 0 {
		r.DirectPercent = direct * 100 / r.WatchedSeconds
	}
	return nil
}

// loadRetroServer place le compte parmi ceux qui ont regardé quelque chose
// sur la même période. Rien n'y nomme un autre compte.
func loadRetroServer(q personalQuery, r *RetroReport) error {
	where := ` WHERE h.watched_seconds >= ? AND h.started_at >= ? AND h.started_at < ?`
	args := []any{playbackMinSeconds, q.window.since, q.window.until}
	rows, err := database.DB.Query(`SELECT h.user_id, SUM(h.watched_seconds) FROM playback_history h`+where+`
		GROUP BY 1 ORDER BY 2 DESC, 1`, args...)
	if err != nil {
		return fmt.Errorf("retro server ranking: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var userID, watched int
		if err := rows.Scan(&userID, &watched); err != nil {
			return fmt.Errorf("scan retro ranking: %w", err)
		}
		r.Server.Members++
		r.Server.WatchedSeconds += watched
		if userID == q.userID {
			r.Server.Rank = r.Server.Members
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	err = database.DB.QueryRow(`SELECT MAX(`+displayTitleSQL+`), COUNT(DISTINCT h.user_id) FROM playback_history h`+where+`
		GROUP BY `+titleKeySQL+` ORDER BY 2 DESC, SUM(h.watched_seconds) DESC LIMIT 1`, args...).
		Scan(&r.Server.TopTitle, &r.Server.TopTitleViewers)
	if err != nil && err != sql.ErrNoRows {
		return fmt.Errorf("retro server top title: %w", err)
	}
	return nil
}
