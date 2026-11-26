package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sort"
	"strings"
	"time"

	"project-player/server/database"

	"github.com/julienschmidt/httprouter"
)

// ==================== Statistics ====================

type statBucket struct {
	Key       string `json:"key"`
	Label     string `json:"label"`
	Secondary string `json:"secondary,omitempty"`
	PosterURL string `json:"poster_url,omitempty"`
	MediaType string `json:"media_type,omitempty"`
	Plays     int    `json:"plays"`
	Watched   int    `json:"watched_seconds"`
}

type dailyStat struct {
	Date    string `json:"date"`
	Plays   int    `json:"plays"`
	Watched int    `json:"watched_seconds"`
}

// PlaybackStats summarises a period of viewing.
type PlaybackStats struct {
	Days   int `json:"days"`
	Totals struct {
		Plays       int `json:"plays"`
		Watched     int `json:"watched_seconds"`
		ActiveUsers int `json:"active_users"`
		Movies      int `json:"movies"`
		Episodes    int `json:"episodes"`
	} `json:"totals"`
	Daily       []dailyStat  `json:"daily"`
	HourOfDay   []int        `json:"hour_of_day"`
	TopUsers    []statBucket `json:"top_users,omitempty"`
	TopMedia    []statBucket `json:"top_media"`
	Clients     []statBucket `json:"clients"`
	PlayMethods []statBucket `json:"play_methods"`
	// Personal n'existe que dans GET /api/me/stats (stats_personal.go).
	Personal *PersonalStats `json:"personal,omitempty"`
}

// tzModifier renders a UTC offset as a SQLite date modifier.
func tzModifier(offsetMinutes int) string {
	return fmt.Sprintf("%+d minutes", offsetMinutes)
}

// statsWindow est la période d'une statistique : des jours entiers, découpés
// dans le fuseau de l'appareil qui la demande.
type statsWindow struct {
	days     int
	today    time.Time // minuit d'aujourd'hui, heure de l'appareil
	firstDay time.Time // minuit du premier jour de la période
	since    string    // firstDay, au format de playback_history
	// until ferme la période (exclue), au format de playback_history. Vide
	// pour « Mes stats », qui va jusqu'à maintenant ; posé par le Rétro, qui
	// s'arrête au 30 novembre (retro_calendar.go).
	until    string
	modifier string // le décalage du fuseau pour strftime
}

func newStatsWindow(days, offsetMinutes int, now time.Time) statsWindow {
	zone := time.FixedZone("client", offsetMinutes*60)
	localNow := now.In(zone)
	today := time.Date(localNow.Year(), localNow.Month(), localNow.Day(), 0, 0, 0, 0, zone)
	firstDay := today.AddDate(0, 0, -(days - 1))
	return statsWindow{
		days:     days,
		today:    today,
		firstDay: firstDay,
		since:    historyStamp(firstDay),
		modifier: tzModifier(offsetMinutes),
	}
}

func computePlaybackStats(userID, days, offsetMinutes int, now time.Time, includeUsers bool) (*PlaybackStats, error) {
	stats := &PlaybackStats{Days: days, Daily: []dailyStat{}, HourOfDay: make([]int, 24)}
	window := newStatsWindow(days, offsetMinutes, now)
	firstDay, since, modifier := window.firstDay, window.since, window.modifier

	where := ` WHERE h.started_at >= ? AND h.watched_seconds >= ?`
	args := []any{since, playbackMinSeconds}
	if userID > 0 {
		where += ` AND h.user_id = ?`
		args = append(args, userID)
	}

	err := database.DB.QueryRow(`
		SELECT COUNT(*), COALESCE(SUM(h.watched_seconds), 0), COUNT(DISTINCT h.user_id),
		       COUNT(DISTINCT CASE WHEN h.media_type = 'movie' THEN COALESCE(h.media_id, h.title) END),
		       COUNT(DISTINCT CASE WHEN h.media_type = 'episode' THEN COALESCE(h.media_id, h.title) END)
		FROM playback_history h`+where, args...,
	).Scan(&stats.Totals.Plays, &stats.Totals.Watched, &stats.Totals.ActiveUsers, &stats.Totals.Movies, &stats.Totals.Episodes)
	if err != nil {
		return nil, err
	}

	// Daily series, zero-filled so the chart has one bar per day.
	byDay := map[string]dailyStat{}
	rows, err := database.DB.Query(`
		SELECT strftime('%Y-%m-%d', h.started_at, ?), COUNT(*), COALESCE(SUM(h.watched_seconds), 0)
		FROM playback_history h`+where+` GROUP BY 1`, append([]any{modifier}, args...)...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var d dailyStat
		if err := rows.Scan(&d.Date, &d.Plays, &d.Watched); err != nil {
			rows.Close()
			return nil, err
		}
		byDay[d.Date] = d
	}
	rows.Close()
	for i := 0; i < days; i++ {
		date := firstDay.AddDate(0, 0, i).Format("2006-01-02")
		day := byDay[date]
		day.Date = date
		stats.Daily = append(stats.Daily, day)
	}

	rows, err = database.DB.Query(`
		SELECT CAST(strftime('%H', h.started_at, ?) AS INTEGER), COALESCE(SUM(h.watched_seconds), 0)
		FROM playback_history h`+where+` GROUP BY 1`, append([]any{modifier}, args...)...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var hour, watched int
		if err := rows.Scan(&hour, &watched); err != nil {
			rows.Close()
			return nil, err
		}
		if hour >= 0 && hour < 24 {
			stats.HourOfDay[hour] = watched
		}
	}
	rows.Close()

	bucketQuery := func(selectKey, selectLabel, selectSecondary, selectPoster, selectType, joins string, limit int) ([]statBucket, error) {
		rows, err := database.DB.Query(`
			SELECT `+selectKey+`, `+selectLabel+`, `+selectSecondary+`, `+selectPoster+`, `+selectType+`,
			       COUNT(*), COALESCE(SUM(h.watched_seconds), 0)
			FROM playback_history h `+joins+where+`
			GROUP BY 1 ORDER BY 7 DESC, 6 DESC LIMIT ?`, append(args, limit)...)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		buckets := []statBucket{}
		for rows.Next() {
			var b statBucket
			if err := rows.Scan(&b.Key, &b.Label, &b.Secondary, &b.PosterURL, &b.MediaType, &b.Plays, &b.Watched); err != nil {
				return nil, err
			}
			buckets = append(buckets, b)
		}
		return buckets, rows.Err()
	}

	if includeUsers {
		stats.TopUsers, err = bucketQuery(`CAST(h.user_id AS TEXT)`, `COALESCE(MAX(u.username), '')`, `''`, `''`, `''`,
			`LEFT JOIN users u ON u.id = h.user_id`, 10)
		if err != nil {
			return nil, err
		}
	}

	// Episodes count towards their show: "Severance, 14 lectures" says more
	// than fourteen separate episode lines.
	stats.TopMedia, err = bucketQuery(
		`CASE WHEN h.media_type = 'episode' AND COALESCE(h.show_title, '') != '' THEN 'show:' || h.show_title
		      ELSE 'media:' || COALESCE(CAST(h.media_id AS TEXT), h.title) END`,
		`CASE WHEN h.media_type = 'episode' AND COALESCE(h.show_title, '') != '' THEN MAX(h.show_title) ELSE MAX(h.title) END`,
		`CASE WHEN h.media_type = 'episode' THEN COUNT(DISTINCT COALESCE(h.media_id, h.title)) || ' épisode(s)' ELSE '' END`,
		`COALESCE(MAX(NULLIF(show.poster_url, '')), MAX(NULLIF(m.poster_url, '')), '')`,
		`CASE WHEN h.media_type = 'episode' AND COALESCE(h.show_title, '') != '' THEN 'show' ELSE MAX(h.media_type) END`,
		`LEFT JOIN medias m ON m.id = h.media_id LEFT JOIN medias show ON show.id = h.show_id`, 10)
	if err != nil {
		return nil, err
	}

	stats.Clients, err = bucketQuery(`COALESCE(NULLIF(h.client, ''), 'Inconnu')`, `COALESCE(NULLIF(h.client, ''), 'Inconnu')`,
		`''`, `''`, `''`, ``, 8)
	if err != nil {
		return nil, err
	}
	stats.PlayMethods, err = bucketQuery(`COALESCE(NULLIF(h.play_method, ''), 'direct')`, `COALESCE(NULLIF(h.play_method, ''), 'direct')`,
		`''`, `''`, `''`, ``, 4)
	if err != nil {
		return nil, err
	}
	// Clients report "Android TV 1.4.2": grouping by the full label would split
	// one platform across every release, so the version is folded here.
	stats.Clients = foldClientVersions(stats.Clients)
	return stats, nil
}

func foldClientVersions(buckets []statBucket) []statBucket {
	merged := map[string]*statBucket{}
	var order []string
	for _, b := range buckets {
		label := b.Label
		if fields := strings.Fields(label); len(fields) > 1 {
			last := fields[len(fields)-1]
			if last != "" && (last[0] >= '0' && last[0] <= '9') {
				label = strings.Join(fields[:len(fields)-1], " ")
			}
		}
		if existing, ok := merged[label]; ok {
			existing.Plays += b.Plays
			existing.Watched += b.Watched
			continue
		}
		folded := b
		folded.Key = label
		folded.Label = label
		merged[label] = &folded
		order = append(order, label)
	}
	out := make([]statBucket, 0, len(order))
	for _, label := range order {
		out = append(out, *merged[label])
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Watched > out[j].Watched })
	return out
}

func writeStats(w http.ResponseWriter, r *http.Request, userID int, includeUsers bool) {
	days := queryInt(r, "days", 30, 1, 365)
	offset := queryInt(r, "tz_offset", 0, -14*60, 14*60)
	stats, err := computePlaybackStats(userID, days, offset, time.Now(), includeUsers)
	if err != nil {
		log.Printf("PlaybackStats: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

// GetPlaybackStats covers the whole server (GET /api/admin/stats, manage_users).
func GetPlaybackStats(w http.ResponseWriter, r *http.Request, _ httprouter.Params, _ int) {
	writeStats(w, r, queryInt(r, "user_id", 0, 0, 1<<31-1), true)
}

// GetMyPlaybackStats covers the caller's own viewing (GET /api/me/stats).
// Elle ajoute le détail de « Mes stats » (personal) ; all=1 couvre tout
// l'historique du compte au lieu de days.
func GetMyPlaybackStats(w http.ResponseWriter, r *http.Request, _ httprouter.Params, userID int) {
	offset := queryInt(r, "tz_offset", 0, -14*60, 14*60)
	now := time.Now()
	allTime := r.URL.Query().Get("all") == "1"
	days := queryInt(r, "days", 30, 1, 365)
	if allTime {
		var err error
		if days, err = daysSinceFirstPlay(userID, offset, now); err != nil {
			log.Printf("GetMyPlaybackStats: first play: %v", err)
			writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
			return
		}
	}
	stats, err := computePlaybackStats(userID, days, offset, now, false)
	if err == nil {
		stats.Personal, err = computePersonalStats(userID, newStatsWindow(days, offset, now), allTime)
	}
	if err != nil {
		log.Printf("GetMyPlaybackStats: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}
