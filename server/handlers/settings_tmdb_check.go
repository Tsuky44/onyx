package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"project-player/server/config"
	"project-player/server/httpx"
	"project-player/server/i18n"
	"project-player/server/tmdb"

	"github.com/julienschmidt/httprouter"
)

// Le test de la clé TMDB (ADR-0164), calqué sur celui de la liaison avec le
// compagnon de demandes (mediahub_link.go).
//
// Seul le serveur peut dire si TMDB lui répond : le conteneur n'a peut-être pas
// accès à Internet, et une clé fausse ne se remarquait qu'au premier écran de
// demandes resté vide. Le résultat n'est pas une erreur HTTP : la réponse est
// 200, avec ok à false et le message à montrer.

// Les raisons d'un test de clé TMDB, lues telles quelles par l'app.
const (
	tmdbReasonOK          = "ok"
	tmdbReasonInvalidKey  = "invalid_key"
	tmdbReasonUnreachable = "unreachable"
	tmdbReasonNoKey       = "no_key"
)

// tmdbKeyTimeout borne le test : plus long, l'administrateur croirait le
// bouton figé.
const tmdbKeyTimeout = 8 * time.Second

type tmdbKeyTestRequest struct {
	// TMDBAPIKey est la clé du formulaire, pas encore enregistrée. Absente ou
	// vide : celle des réglages (ou de l'environnement).
	TMDBAPIKey *string `json:"tmdb_api_key"`
}

type tmdbKeyTestResult struct {
	OK     bool   `json:"ok"`
	Reason string `json:"reason"`
	// Message est prêt à afficher, dans la langue de la requête.
	Message string `json:"message"`
}

// tmdbKeyClient est le client du test. Une variable pour que les tests y
// mettent un faux TMDB.
var tmdbKeyClient = httpx.Standard

// TestTMDBKey teste une clé TMDB (POST /api/settings/tmdb/test). La clé n'est
// jamais renvoyée ni journalisée : le paquet tmdb la retire des erreurs.
func TestTMDBKey(w http.ResponseWriter, r *http.Request, _ httprouter.Params, _ int) {
	var req tmdbKeyTestRequest
	r.Body = http.MaxBytesReader(w, r.Body, 4<<10)
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		writeJSONError(w, http.StatusBadRequest, "Corps de requête invalide")
		return
	}

	key := config.TMDBAPIKey()
	if req.TMDBAPIKey != nil && strings.TrimSpace(*req.TMDBAPIKey) != "" {
		key = *req.TMDBAPIKey
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(checkTMDBKey(r.Context(), i18n.FromRequest(r), key))
}

func checkTMDBKey(ctx context.Context, lang, key string) tmdbKeyTestResult {
	ctx, cancel := context.WithTimeout(ctx, tmdbKeyTimeout)
	defer cancel()

	err := tmdb.CheckKey(ctx, tmdbKeyClient, key)
	switch {
	case err == nil:
		return tmdbKeyTestResult{OK: true, Reason: tmdbReasonOK, Message: i18n.T(lang, "La clé TMDB est valide.")}
	case errors.Is(err, tmdb.ErrNoKey):
		return tmdbKeyTestResult{Reason: tmdbReasonNoKey, Message: i18n.T(lang, "Aucune clé TMDB n'est enregistrée.")}
	case errors.Is(err, tmdb.ErrInvalidKey):
		return tmdbKeyTestResult{Reason: tmdbReasonInvalidKey,
			Message: i18n.T(lang, "TMDB refuse cette clé : vérifiez-la dans votre compte TMDB.")}
	}
	// Réseau, DNS, délai, ou TMDB en panne : le serveur n'a pas pu juger la
	// clé. L'erreur ne cite pas la clé (paquet tmdb).
	log.Printf("TestTMDBKey: %v", err)
	return tmdbKeyTestResult{Reason: tmdbReasonUnreachable,
		Message: i18n.T(lang, "Le serveur ne joint pas TMDB : vérifiez que le conteneur a accès à Internet, puis réessayez.")}
}
