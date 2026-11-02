package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"strings"

	"project-player/server/buildinfo"
	"project-player/server/config"
	"project-player/server/database"
	"project-player/server/mediahub"
	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

// Ce que MediaHub lit et écrit chez Onyx avec la seule clé d'intégration
// (ADR-0102) : les comptes à importer, la bibliothèque de « Ma médiathèque »
// et sa propre adresse. Il le faisait avant avec la session d'un
// administrateur Onyx gardée dans ses réglages, qui expirait et ouvrait tout
// le reste du serveur.

// RequireMediaHubKey ouvre une route au serveur MediaHub qui présente la clé
// d'intégration. Le handler reçoit l'utilisateur 0 : aucun compte n'appelle,
// donc aucune progression ni aucun droit propre ne s'y mêle.
func RequireMediaHubKey(next AuthenticatedHandle) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		if err := mediahub.VerifyKey(r.Header, config.MediaHubAPIKey()); err != nil {
			writeJSONError(w, http.StatusUnauthorized, "Clé d'intégration invalide")
			return
		}
		next(w, r, ps, 0)
	}
}

// integrationAccount est un compte tel que MediaHub l'importe : ni le gabarit
// d'invitation ni l'état OTP, dont il n'a pas l'usage.
type integrationAccount struct {
	ID          int                `json:"id"`
	Username    string             `json:"username"`
	IsOwner     bool               `json:"is_owner"`
	Permissions models.Permissions `json:"permissions"`
	Avatar      string             `json:"avatar"`
}

type integrationAccountsResponse struct {
	Users []integrationAccount `json:"users"`
}

// MediaHubAccounts rend les comptes du serveur
// (GET /api/integrations/mediahub/users).
func MediaHubAccounts(w http.ResponseWriter, _ *http.Request, _ httprouter.Params, _ int) {
	rows, err := database.DB.Query("SELECT " + userColumns + " FROM users ORDER BY id")
	if err != nil {
		log.Printf("MediaHubAccounts: query: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	resp := integrationAccountsResponse{Users: []integrationAccount{}}
	for rows.Next() {
		user, err := scanUser(rows)
		if err != nil {
			log.Printf("MediaHubAccounts: scan: %v", err)
			continue
		}
		resp.Users = append(resp.Users, integrationAccount{
			ID: user.ID, Username: user.Username, IsOwner: user.IsOwner,
			Permissions: user.Permissions, Avatar: user.Avatar,
		})
	}
	if err := rows.Err(); err != nil {
		log.Printf("MediaHubAccounts: rows: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(resp)
}

// mediaHubLinkState est ce qu'Onyx sait de MediaHub. La clé n'y figure que
// par ses derniers caractères : MediaHub, qui vient de la présenter, la
// connaît déjà.
type mediaHubLinkState struct {
	MediaHubURL   string `json:"mediahub_url"`
	APIKeyHint    string `json:"mediahub_api_key_hint"`
	ServerVersion string `json:"server_version"`
}

func currentMediaHubLink() mediaHubLinkState {
	snapshot := config.Snapshot()
	return mediaHubLinkState{
		MediaHubURL:   snapshot.MediaHubURL,
		APIKeyHint:    snapshot.MediaHubAPIKeyHint,
		ServerVersion: buildinfo.Version,
	}
}

// GetMediaHubLink rend l'état de la liaison
// (GET /api/integrations/mediahub/link).
func GetMediaHubLink(w http.ResponseWriter, _ *http.Request, _ httprouter.Params, _ int) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(currentMediaHubLink())
}

// mediaHubLinkUpdate : l'adresse de MediaHub, et une nouvelle clé quand
// MediaHub la change. Présenter l'ancienne suffit pour la remplacer, comme
// pour un mot de passe.
type mediaHubLinkUpdate struct {
	MediaHubURL *string `json:"mediahub_url"`
	APIKey      *string `json:"mediahub_api_key"`
}

// validMediaHubURL accepte une adresse http(s) absolue, sans chemin de
// requête ni fragment : Onyx y ajoute ses propres routes.
func validMediaHubURL(raw string) bool {
	parsed, err := url.Parse(raw)
	return err == nil && (parsed.Scheme == "http" || parsed.Scheme == "https") &&
		parsed.Host != "" && parsed.RawQuery == "" && parsed.Fragment == ""
}

// minMediaHubKeyLength : MediaHub tire 32 octets en hexadécimal. Une clé plus
// courte se devinerait, et c'est elle qui ouvre ces routes.
const minMediaHubKeyLength = 32

// UpdateMediaHubLink écrit l'adresse de MediaHub, et sa nouvelle clé s'il en
// donne une (PUT /api/integrations/mediahub/link).
func UpdateMediaHubLink(w http.ResponseWriter, r *http.Request, _ httprouter.Params, _ int) {
	var req mediaHubLinkUpdate
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	update := config.UpdateRequest{}
	if req.MediaHubURL != nil {
		address := strings.TrimRight(strings.TrimSpace(*req.MediaHubURL), "/")
		if !validMediaHubURL(address) {
			writeJSONError(w, http.StatusBadRequest, "Adresse de MediaHub invalide (http:// ou https://)")
			return
		}
		update.MediaHubURL = &address
	}
	if req.APIKey != nil {
		key := strings.TrimSpace(*req.APIKey)
		if len(key) < minMediaHubKeyLength {
			writeJSONError(w, http.StatusBadRequest, "Clé d'intégration trop courte")
			return
		}
		update.MediaHubAPIKey = &key
	}

	if _, err := config.ApplyUpdate(update); err != nil {
		log.Printf("UpdateMediaHubLink: %v", err)
		writeJSONError(w, http.StatusInternalServerError, "Failed to save settings")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(currentMediaHubLink())
}
