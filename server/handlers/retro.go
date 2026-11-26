package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"project-player/server/database"

	"github.com/julienschmidt/httprouter"
)

// Les routes du Rétro (ADR 2026-11-26-tsuky-retro-annuel). Chacune ne lit
// que le compte qui appelle ; seul retroServer parle des autres, en agrégats.

// RetroStatus est la réponse de GET /api/me/retro : ce dont l'accueil a
// besoin pour savoir s'il montre la diapo, l'anneau ou la carte « Revoir ».
type RetroStatus struct {
	Year     int    `json:"year"`
	Open     bool   `json:"open"`
	Eligible bool   `json:"eligible"`
	Seen     bool   `json:"seen"`
	EndsAt   string `json:"ends_at"` // RFC 3339, heure du serveur
}

// GetMyRetroStatus : GET /api/me/retro?tz_offset=<minutes>.
func GetMyRetroStatus(w http.ResponseWriter, r *http.Request, _ httprouter.Params, userID int) {
	season := retroCalendar(retroNow(), retroPreview())
	status := RetroStatus{Year: season.Year, Open: season.Open, EndsAt: season.EndsAt.Format(time.RFC3339)}
	if season.Open {
		offset := queryInt(r, "tz_offset", 0, -14*60, 14*60)
		report, err := computeRetro(userID, season.Year, offset)
		if err == nil {
			status.Eligible = report.Eligible
			status.Seen, err = retroSeen(userID, season.Year)
		}
		if err != nil {
			log.Printf("GetMyRetroStatus: %v", err)
			writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
			return
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

// GetMyRetro : GET /api/me/retro/:year?tz_offset=<minutes>. 404 hors saison,
// ou pour une autre année que celle qui se montre.
func GetMyRetro(w http.ResponseWriter, r *http.Request, ps httprouter.Params, userID int) {
	year, ok := openRetroYear(w, ps)
	if !ok {
		return
	}
	offset := queryInt(r, "tz_offset", 0, -14*60, 14*60)
	report, err := computeRetro(userID, year, offset)
	if err != nil {
		log.Printf("GetMyRetro: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(report)
}

// MarkMyRetroSeen : POST /api/me/retro/:year/seen. Retire la diapo et
// l'anneau de l'accueil, sur tous les appareils du compte.
func MarkMyRetroSeen(w http.ResponseWriter, _ *http.Request, ps httprouter.Params, userID int) {
	year, ok := openRetroYear(w, ps)
	if !ok {
		return
	}
	if _, err := database.DB.Exec(`INSERT OR IGNORE INTO retro_views (user_id, year) VALUES (?, ?)`, userID, year); err != nil {
		log.Printf("MarkMyRetroSeen: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// openRetroYear lit :year et répond à la place du handler quand il ne
// correspond pas au Rétro visible.
func openRetroYear(w http.ResponseWriter, ps httprouter.Params) (int, bool) {
	year, err := strconv.Atoi(ps.ByName("year"))
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "Requête invalide")
		return 0, false
	}
	season := retroCalendar(retroNow(), retroPreview())
	if !season.Open || year != season.Year {
		writeJSONError(w, http.StatusNotFound, "Rétro indisponible")
		return 0, false
	}
	return year, true
}

func retroSeen(userID, year int) (bool, error) {
	var seen bool
	err := database.DB.QueryRow(`SELECT EXISTS (SELECT 1 FROM retro_views WHERE user_id = ? AND year = ?)`, userID, year).Scan(&seen)
	return seen, err
}
