// Package tmdb est le seul endroit du serveur qui parle à l'API de TMDB.
//
// TMDB v3 s'authentifie par un paramètre d'URL, `api_key`. Tant que chaque
// appelant écrivait son URL lui-même, la clé voyageait avec elle : une erreur
// réseau de net/http cite l'URL entière (`Get "https://…?api_key=…": dial
// tcp…`), et ces erreurs partaient telles quelles dans le journal du serveur.
// Ici l'appelant ne donne que le chemin ; la clé est posée au dernier moment,
// et retirée de toute erreur avant qu'elle ne remonte.
//
// Le client HTTP reste celui de l'appelant (httpx.Fast, Standard, Catalog) :
// c'est lui qui porte l'échéance, et le rejeu sur 429.
package tmdb

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"project-player/server/config"
)

const baseURL = "https://api.themoviedb.org/3"

// ErrNoKey : aucune clé TMDB n'est réglée sur ce serveur.
var ErrNoKey = errors.New("tmdb: no API key configured")

// Get lit une ressource de TMDB. pathAndQuery est relatif à la racine de
// l'API, paramètres compris : "/tv/1399?language=fr-FR".
//
// Comme http.Client.Get, une réponse qui n'est pas 200 n'est pas une erreur :
// l'appelant lit resp.StatusCode et ferme resp.Body.
func Get(client *http.Client, pathAndQuery string) (*http.Response, error) {
	return GetContext(context.Background(), client, pathAndQuery)
}

// GetContext est Get, abandonné quand ctx se termine.
func GetContext(ctx context.Context, client *http.Client, pathAndQuery string) (*http.Response, error) {
	return getWithKey(ctx, client, config.TMDBAPIKey(), pathAndQuery)
}

// ErrInvalidKey : TMDB a refusé la clé (401).
var ErrInvalidKey = errors.New("tmdb: API key rejected")

// CheckKey demande à TMDB si key est une clé valide, par sa route de
// configuration, la plus légère. C'est le seul appel du paquet qui prend une
// clé explicite : l'assistant du premier lancement teste celle qu'on vient de
// saisir, avant de l'enregistrer (ADR-0164).
//
// Rend nil pour une clé acceptée, ErrNoKey pour une clé vide, ErrInvalidKey
// quand TMDB la refuse, et toute autre erreur (réseau, DNS, délai, 5xx) pour
// un TMDB qu'on ne joint pas. Aucune de ces erreurs ne cite la clé.
func CheckKey(ctx context.Context, client *http.Client, key string) error {
	key = strings.TrimSpace(key)
	resp, err := getWithKey(ctx, client, key, "/configuration")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusOK:
		return nil
	case resp.StatusCode == http.StatusUnauthorized:
		return ErrInvalidKey
	}
	return fmt.Errorf("tmdb: GET /configuration: HTTP %d", resp.StatusCode)
}

func getWithKey(ctx context.Context, client *http.Client, key, pathAndQuery string) (*http.Response, error) {
	if key == "" {
		return nil, ErrNoKey
	}
	path, query, _ := strings.Cut(pathAndQuery, "?")
	target := baseURL + path + "?api_key=" + url.QueryEscape(key)
	if query != "" {
		target += "&" + query
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, fmt.Errorf("tmdb: GET %s: invalid request", path)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("tmdb: GET %s: %w", path, withoutURL(err))
	}
	return resp, nil
}

// withoutURL rend la cause d'une erreur de net/http sans l'URL qu'elle cite.
// La cause reste enveloppée : errors.Is(err, context.DeadlineExceeded) et
// consorts répondent comme avant.
func withoutURL(err error) error {
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		return urlErr.Err
	}
	return err
}
