package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"project-player/server/calendar"

	"github.com/julienschmidt/httprouter"
)

// Les routes du calendrier « À venir » (ADR
// 2026-11-27-tsuky-calendrier-sorties-serveur). Elles ne lisent et
// n'écrivent que le compte qui appelle.

const (
	// calendarDefaultPast / calendarDefaultAhead : la fenêtre quand l'app
	// n'en donne pas, de quoi remplir le mois affiché et les suivants.
	calendarDefaultPast  = 31
	calendarDefaultAhead = 180
	// calendarMaxSpan borne une fenêtre demandée : au-delà d'un an, TMDB n'a
	// de toute façon plus de dates d'épisodes.
	calendarMaxSpan = 400
	// calendarScheduleBudget : ce qu'un calendrier attend TMDB au premier
	// chargement. Les programmes en retard arrivent au chargement suivant.
	calendarScheduleBudget = 6 * time.Second
)

// CalendarResponse est la réponse de GET /api/calendar.
type CalendarResponse struct {
	From     string                  `json:"from"`
	To       string                  `json:"to"`
	Today    string                  `json:"today"`
	Entries  []calendar.Entry        `json:"entries"`
	Followed []calendar.FollowedShow `json:"followed"`
}

// GetCalendar : GET /api/calendar?from=AAAA-MM-JJ&to=AAAA-MM-JJ&today=AAAA-MM-JJ.
// today est le jour de l'appareil, qui peut ne pas être celui du serveur
// autour de minuit ; il sert au « prochain épisode » des séries suivies.
func GetCalendar(w http.ResponseWriter, r *http.Request, _ httprouter.Params, userID int) {
	now := time.Now()
	today, ok := calendarDay(r, "today", now)
	if !ok {
		writeJSONError(w, http.StatusBadRequest, "Date invalide")
		return
	}
	from, okFrom := calendarDay(r, "from", today.AddDate(0, 0, -calendarDefaultPast))
	to, okTo := calendarDay(r, "to", today.AddDate(0, 0, calendarDefaultAhead))
	if !okFrom || !okTo || to.Before(from) || to.Sub(from) > calendarMaxSpan*24*time.Hour {
		writeJSONError(w, http.StatusBadRequest, "Période invalide")
		return
	}

	interests, err := calendarInterests(r, userID, now)
	if err != nil {
		log.Printf("GetCalendar: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
		return
	}
	lang := languageOf(r)
	if err := enrichCalendarFromLibrary(interests, lang); err != nil {
		log.Printf("GetCalendar: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
		return
	}
	presence, err := calendarPresence(interests)
	if err != nil {
		log.Printf("GetCalendar: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
		return
	}
	shows, movies := calendarSchedules(interests, lang, today, calendarScheduleBudget)

	const day = "2006-01-02"
	resp := CalendarResponse{
		From:     from.Format(day),
		To:       to.Format(day),
		Today:    today.Format(day),
		Entries:  calendar.Build(interests, shows, movies, presence, from.Format(day), to.Format(day)),
		Followed: calendar.Followed(interests, shows, today.Format(day)),
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// calendarInterests réunit les raisons qu'a le compte de voir un titre, puis
// applique ses choix.
func calendarInterests(r *http.Request, userID int, now time.Time) ([]calendar.Interest, error) {
	watching, err := calendarWatchingShows(userID, now)
	if err != nil {
		return nil, err
	}
	server, err := calendarServerShows(now)
	if err != nil {
		return nil, err
	}
	choices, err := calendarChoices(userID)
	if err != nil {
		return nil, err
	}
	candidates := append(watching, calendarRequested(r.Context(), userID)...)
	candidates = append(candidates, server...)
	return calendar.Merge(candidates, choices), nil
}

func calendarDay(r *http.Request, name string, fallback time.Time) (time.Time, bool) {
	raw := r.URL.Query().Get(name)
	if raw == "" {
		y, m, d := fallback.Date()
		return time.Date(y, m, d, 0, 0, 0, 0, time.UTC), true
	}
	parsed, err := time.Parse("2006-01-02", raw)
	return parsed, err == nil
}

// FollowCalendarShow : PUT /api/calendar/follows/:tmdbId. Suit une série,
// ou la remet dans le calendrier après un retrait.
func FollowCalendarShow(w http.ResponseWriter, _ *http.Request, ps httprouter.Params, userID int) {
	writeCalendarChoice(w, ps, userID, true)
}

// UnfollowCalendarShow : DELETE /api/calendar/follows/:tmdbId. Retire une
// série du calendrier, y compris quand elle y entrait d'elle-même : elle ne
// revient pas toute seule au prochain épisode regardé.
func UnfollowCalendarShow(w http.ResponseWriter, _ *http.Request, ps httprouter.Params, userID int) {
	writeCalendarChoice(w, ps, userID, false)
}

func writeCalendarChoice(w http.ResponseWriter, ps httprouter.Params, userID int, follow bool) {
	tmdbID, err := strconv.Atoi(ps.ByName("tmdbId"))
	if err != nil || tmdbID <= 0 {
		writeJSONError(w, http.StatusBadRequest, "Identifiant TMDB invalide")
		return
	}
	if err := setCalendarChoice(userID, tmdbID, follow); err != nil {
		log.Printf("writeCalendarChoice: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Erreur interne du serveur")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
