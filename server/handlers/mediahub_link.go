package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"project-player/server/config"
	"project-player/server/httpx"
	"project-player/server/i18n"
	"project-player/server/mediahub"

	"github.com/julienschmidt/httprouter"
)

// Le test de la liaison avec le compagnon de demandes (ADR-0072, 0087, 0136).
//
// Seul le serveur peut dire s'il joint OnyxHub : l'app ou le navigateur de
// l'admin ne sont pas sur le même réseau, et une adresse qui marche depuis un
// téléphone (un domaine public) peut être injoignable depuis un conteneur, et
// inversement (un nom Docker). Avant ce test, une adresse fausse ne se
// remarquait qu'à la première demande refusée.

type mediaHubLinkRequest struct {
	// Les valeurs du formulaire, pas encore enregistrées. Absentes ou vides :
	// celles des réglages.
	MediaHubURL    *string `json:"mediahub_url"`
	MediaHubAPIKey *string `json:"mediahub_api_key"`
	// RequestService : le service choisi dans le formulaire (ADR-0136).
	RequestService *string `json:"request_service"`
}

type mediaHubLinkResult struct {
	OK      bool   `json:"ok"`
	Message string `json:"message"`
	// Service vaut "onyxhub", "mediahub", "overseerr" ou "jellyseerr" quand
	// l'adresse a répondu comme l'un d'eux.
	Service string `json:"service,omitempty"`
	Version string `json:"version,omitempty"`
	// Notes sont les réserves d'une liaison qui marche, prêtes à afficher :
	// le compte de l'administrateur absent du compagnon, les notifications
	// de MediaHub sans adresse.
	Notes []string `json:"notes,omitempty"`
}

type integrationPing struct {
	Status  string `json:"status"`
	Service string `json:"service"`
	Version string `json:"version"`
}

// probeMediaHub essaie d'abord le ping de l'API v1 de MediaHub, qui vérifie
// la clé et dit ce que vaut le compte de l'administrateur. Un 404 dit un
// compagnon plus ancien : on retombe sur la sonde d'OnyxHub.
func probeMediaHub(lang, baseURL, apiKey string, as mediahub.Account, client *http.Client) mediaHubLinkResult {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	apiKey = strings.TrimSpace(apiKey)
	if baseURL == "" {
		return mediaHubLinkResult{Message: i18n.T(lang, "Aucune adresse MediaHub n'est enregistrée.")}
	}
	if apiKey == "" {
		return mediaHubLinkResult{Message: i18n.T(lang, "Aucune clé d'intégration n'est enregistrée.")}
	}

	hub := mediahub.Client{BaseURL: baseURL, APIKey: apiKey, HTTP: client}
	ping, err := hub.Ping(context.Background(), as)
	var status *mediahub.StatusError
	switch {
	case err == nil && ping.Status == "ok":
		hub.Remember(mediahub.DialectV1)
		return mediaHubV1LinkResult(lang, ping, as)
	case errors.As(err, &status) && (status.Status == http.StatusUnauthorized || status.Status == http.StatusForbidden):
		hub.Remember(mediahub.DialectV1)
		return mediaHubLinkResult{Message: i18n.T(lang, "MediaHub répond, mais refuse cette clé."), Service: "mediahub"}
	case errors.As(err, &status) && (status.Status == http.StatusNotFound || status.Status == http.StatusMethodNotAllowed):
		result := probeOnyxHub(lang, baseURL, apiKey, client)
		if result.OK {
			hub.Remember(mediahub.DialectOnyxHub)
		}
		return result
	case errors.As(err, &status):
		return mediaHubLinkResult{Message: i18n.T(lang, "Réponse inattendue de cette adresse (HTTP {0}).", status.Status)}
	case err == nil:
		return mediaHubLinkResult{Message: i18n.T(lang, "Cette adresse répond, mais pas comme MediaHub.")}
	default:
		return mediaHubLinkResult{Message: i18n.T(lang, "Le serveur ne joint pas cette adresse.")}
	}
}

// mediaHubV1LinkResult dit ce qui marche, puis ce qui manque encore.
func mediaHubV1LinkResult(lang string, ping mediahub.Ping, as mediahub.Account) mediaHubLinkResult {
	message := i18n.T(lang, "MediaHub répond et accepte la clé.")
	if ping.Version != "" {
		message = i18n.T(lang, "MediaHub {0} répond et accepte la clé.", ping.Version)
	}
	var notes []string
	if as.Username != "" && (ping.User == nil || !ping.User.Linked) {
		notes = append(notes, i18n.T(lang, "Aucun compte MediaHub ne s'appelle « {0} » : MediaHub retrouve chaque compte "+
			"d'Onyx par son nom, et un nom inconnu peut demander sans retrouver ses demandes.", as.Username))
	}
	if !ping.WebhookConfigured {
		notes = append(notes, i18n.T(lang, "MediaHub n'envoie pas ses évènements à Onyx : réglez ONYX_WEBHOOK_URL sur "+
			"l'adresse d'Onyx suivie de /api/integrations/mediahub/events pour que les imports s'indexent tout de suite."))
	}
	return mediaHubLinkResult{OK: true, Message: message, Service: ping.Service, Version: ping.Version, Notes: notes}
}

// probeOnyxHub interroge GET /api/integration/ping, la route d'OnyxHub qui
// n'accepte que la clé d'intégration. MediaHub ne l'a pas : sur un 404, sa
// route de disponibilité (qu'il servait sans clé) dit au moins que l'adresse
// est la bonne.
func probeOnyxHub(lang, baseURL, apiKey string, client *http.Client) mediaHubLinkResult {
	status, body, err := getWithKey(client, baseURL+"/api/integration/ping", apiKey)
	if err != nil {
		return mediaHubLinkResult{Message: i18n.T(lang, "Le serveur ne joint pas cette adresse.")}
	}
	switch {
	case status == http.StatusOK:
		var ping integrationPing
		if json.Unmarshal(body, &ping) != nil || ping.Status != "ok" {
			return mediaHubLinkResult{Message: i18n.T(lang, "Cette adresse répond, mais pas comme OnyxHub.")}
		}
		message := i18n.T(lang, "OnyxHub répond et accepte la clé.")
		if ping.Version != "" {
			message = i18n.T(lang, "OnyxHub {0} répond et accepte la clé.", ping.Version)
		}
		return mediaHubLinkResult{OK: true, Message: message, Service: ping.Service, Version: ping.Version}
	case status == http.StatusUnauthorized || status == http.StatusForbidden:
		return mediaHubLinkResult{Message: i18n.T(lang, "OnyxHub répond, mais refuse cette clé."), Service: "onyxhub"}
	case status == http.StatusNotFound:
		legacy, _, err := getWithKey(client, baseURL+"/api/media/availability/550?type=movie", apiKey)
		if err == nil && legacy == http.StatusOK {
			return mediaHubLinkResult{OK: true, Message: i18n.T(lang, "MediaHub répond (il ne permet pas de vérifier la clé)."), Service: "mediahub"}
		}
		// Le service choisi n'est pas le bon : le dire évite de chercher la
		// panne du côté de l'adresse ou de la clé.
		seerr := mediahub.Client{BaseURL: baseURL, APIKey: apiKey, HTTP: client}
		if _, ok, err := seerr.IsSeerr(context.Background()); err == nil && ok {
			return mediaHubLinkResult{Message: i18n.T(lang, "Cette adresse répond comme Overseerr ou Jellyseerr : choisissez ce service, puis testez à nouveau.")}
		}
		return mediaHubLinkResult{Message: i18n.T(lang, "Cette adresse répond, mais ni comme OnyxHub ni comme MediaHub.")}
	default:
		return mediaHubLinkResult{Message: i18n.T(lang, "Réponse inattendue de cette adresse (HTTP {0}).", status)}
	}
}

// probeSeerr teste Overseerr ou Jellyseerr : l'adresse par leur GET /status,
// public, puis la clé par le compte qu'elle ouvre. La réserve dit comment le
// compte de l'administrateur y agira (ADR-0136).
func probeSeerr(lang, baseURL, apiKey string, service mediahub.Service, as mediahub.Account, client *http.Client) mediaHubLinkResult {
	label := service.Label()
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	apiKey = strings.TrimSpace(apiKey)
	if baseURL == "" {
		return mediaHubLinkResult{Message: i18n.T(lang, "Aucune adresse {0} n'est enregistrée.", label)}
	}
	if apiKey == "" {
		return mediaHubLinkResult{Message: i18n.T(lang, "Aucune clé API n'est enregistrée.")}
	}

	seerr := mediahub.Client{BaseURL: baseURL, APIKey: apiKey, HTTP: client, Service: service}
	link, err := seerr.ProbeSeerr(context.Background(), as)
	switch {
	case err != nil:
		return mediaHubLinkResult{Message: i18n.T(lang, "Le serveur ne joint pas cette adresse.")}
	case !link.Answered:
		return mediaHubLinkResult{Message: i18n.T(lang, "Cette adresse répond, mais pas comme {0}.", label)}
	case !link.KeyAccepted:
		return mediaHubLinkResult{Message: i18n.T(lang, "{0} répond, mais refuse cette clé.", label), Service: string(service), Version: link.Version}
	}

	result := mediaHubLinkResult{
		OK:      true,
		Message: i18n.T(lang, "{0} {1} répond et accepte la clé.", label, link.Version),
		Service: string(service),
		Version: link.Version,
	}
	if as.Username != "" && !link.Linked {
		result.Notes = append(result.Notes, i18n.T(lang, "Aucun compte {0} ne s'appelle « {1} » : ce compte, comme tout compte "+
			"d'Onyx sans homonyme, agit par le compte de la clé (« {2} »), dont il partage les demandes et les droits.",
			label, as.Username, link.KeyAccount))
	}
	return result
}

func getWithKey(client *http.Client, target, apiKey string) (int, []byte, error) {
	req, err := http.NewRequest(http.MethodGet, target, nil)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	resp, err := client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return 0, nil, err
	}
	return resp.StatusCode, body, nil
}

// TestMediaHubLink teste la liaison avec le compagnon (POST /api/settings/mediahub/test),
// au nom de l'administrateur qui la teste. Le résultat du test n'est pas une
// erreur HTTP : la réponse est 200 avec ok à false et le message à montrer.
func TestMediaHubLink(w http.ResponseWriter, r *http.Request, _ httprouter.Params, userID int) {
	var req mediaHubLinkRequest
	r.Body = http.MaxBytesReader(w, r.Body, 8<<10)
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		writeJSONError(w, http.StatusBadRequest, "Corps de requête invalide")
		return
	}

	baseURL := config.MediaHubURL()
	if req.MediaHubURL != nil && strings.TrimSpace(*req.MediaHubURL) != "" {
		baseURL = *req.MediaHubURL
	}
	apiKey := config.MediaHubAPIKey()
	if req.MediaHubAPIKey != nil && strings.TrimSpace(*req.MediaHubAPIKey) != "" {
		apiKey = *req.MediaHubAPIKey
	}

	service := config.RequestService()
	if req.RequestService != nil {
		var ok bool
		if service, ok = mediahub.ParseService(*req.RequestService); !ok {
			writeJSONError(w, http.StatusBadRequest, "Service de demandes inconnu")
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	// Sans compte lisible, le test vaut quand même pour l'adresse et la clé.
	account, _ := mediaHubAccount(userID)
	lang := i18n.FromRequest(r)
	if service.Seerr() {
		_ = json.NewEncoder(w).Encode(probeSeerr(lang, baseURL, apiKey, service, account, httpx.Standard))
		return
	}
	_ = json.NewEncoder(w).Encode(probeMediaHub(lang, baseURL, apiKey, account, httpx.Standard))
}
