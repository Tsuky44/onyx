package mediahub

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"project-player/server/ttlcache"
)

// Overseerr et Jellyseerr (ADR-0136). Les deux partagent l'API de Seerr, sous
// /api/v1 : une clé d'administrateur dans X-Api-Key, et X-Api-User pour agir
// au nom d'un de ses comptes. Seerr ne connaît pas les comptes d'Onyx : un
// compte Onyx agit comme le compte Seerr qui porte son nom, sinon comme celui
// de la clé.

// SeerrPath est la base de l'API d'Overseerr et de Jellyseerr.
const SeerrPath = "/api/v1"

// Les droits d'un compte Seerr, en bits (server/lib/permissions.ts chez eux).
const (
	seerrCanAdmin          = 2
	seerrCanManageRequests = 16
	seerrCanRequest        = 32
	seerrCanViewRequests   = 16384
	seerrCanRequestMovie   = 262144
	seerrCanRequestTV      = 524288
)

// L'état d'un titre (MediaStatus) et celui d'une demande (MediaRequestStatus).
// Jellyseerr ajoute des états de titre après « disponible » (bloqué,
// supprimé) et les états de demande « échouée » et « terminée ».
const (
	seerrMediaPending    = 2
	seerrMediaProcessing = 3
	seerrMediaPartial    = 4
	seerrMediaAvailable  = 5

	seerrRequestPending   = 1
	seerrRequestDeclined  = 3
	seerrRequestCompleted = 5
)

// seerrUser est un compte Seerr. Les noms absents arrivent en null.
type seerrUser struct {
	ID               int    `json:"id"`
	Email            string `json:"email"`
	Username         string `json:"username"`
	PlexUsername     string `json:"plexUsername"`
	JellyfinUsername string `json:"jellyfinUsername"`
	DisplayName      string `json:"displayName"`
	Permissions      int    `json:"permissions"`
}

// can dit si le compte a l'un de ces droits. L'administrateur les a tous.
func (u seerrUser) can(permissions ...int) bool {
	if u.Permissions&seerrCanAdmin != 0 {
		return true
	}
	for _, permission := range permissions {
		if u.Permissions&permission != 0 {
			return true
		}
	}
	return false
}

// name est le nom à montrer : celui que Seerr affiche lui-même.
func (u seerrUser) name() string {
	for _, name := range []string{u.DisplayName, u.Username, u.JellyfinUsername, u.PlexUsername, u.Email} {
		if strings.TrimSpace(name) != "" {
			return strings.TrimSpace(name)
		}
	}
	return ""
}

// named dit si le compte porte ce nom, sous l'une de ses formes : un compte
// importé de Plex ou de Jellyfin n'a souvent pas de nom local.
func (u seerrUser) named(name string) bool {
	for _, own := range []string{u.Username, u.DisplayName, u.JellyfinUsername, u.PlexUsername, u.Email} {
		if own = strings.TrimSpace(own); own != "" && strings.EqualFold(own, name) {
			return true
		}
	}
	return false
}

// seerrDirectory est ce qu'Onyx retient d'un Seerr : le compte de la clé, les
// comptes à rapprocher des siens, et ce que le ping de MediaHub disait.
type seerrDirectory struct {
	owner   seerrUser
	users   []seerrUser
	version string
	// partialRequests : Seerr laisse demander une partie des saisons.
	partialRequests bool
}

// seerrIdentity est le compte Seerr au nom duquel un compte Onyx agit.
type seerrIdentity struct {
	user seerrUser
	// linked : un compte Seerr porte le nom du compte Onyx. Sinon c'est le
	// compte de la clé, partagé avec les autres comptes sans homonyme.
	linked bool
}

func (d seerrDirectory) identity(as Account) seerrIdentity {
	if name := strings.TrimSpace(as.Username); name != "" {
		for _, user := range d.users {
			if user.named(name) {
				return seerrIdentity{user: user, linked: true}
			}
		}
	}
	return seerrIdentity{user: d.owner}
}

// Les comptes d'un Seerr changent rarement : cinq minutes évitent de relire la
// liste à chaque appel, et un compte créé pour porter le nom d'un compte Onyx
// se retrouve vite. Le test de liaison l'oublie tout de suite.
var seerrDirectories = newSeerrDirectories()

func newSeerrDirectories() *ttlcache.Cache[seerrDirectory] {
	return ttlcache.New[seerrDirectory](5*time.Minute, 8)
}

// seerrUserPages borne la lecture des comptes : mille comptes, c'est déjà
// plus qu'un serveur privé n'en porte.
const (
	seerrUserPageSize = 100
	seerrUserPages    = 10
)

func (c Client) seerrCacheKey() string { return c.base() + "\n" + c.key() }

func resetSeerr() {
	seerrDirectories = newSeerrDirectories()
	seerrDetailsCache = newSeerrDetailsCache()
	seerrTitles = newSeerrTitles()
}

// ForgetSeerrAccounts fait relire les comptes au prochain appel : le test de
// liaison vient souvent juste après la création d'un compte.
func (c Client) ForgetSeerrAccounts() { seerrDirectories.Delete(c.seerrCacheKey()) }

// seerr envoie un appel à l'API de Seerr. actAs > 0 fait agir la clé au nom de
// ce compte : Seerr applique alors ses droits et ses quotas. Un statut hors
// 2xx revient en *StatusError, dans la forme que l'app lit.
func (c Client) seerr(ctx context.Context, method, path string, actAs int, query url.Values, body []byte) ([]byte, error) {
	header := http.Header{}
	header.Set("X-Api-Key", c.key())
	if actAs > 0 {
		header.Set("X-Api-User", strconv.Itoa(actAs))
	}
	status, raw, err := c.roundTrip(ctx, method, SeerrPath+path, header, query, body)
	if err != nil {
		return nil, err
	}
	if status < 200 || status > 299 {
		return nil, c.seerrFailure(status, raw)
	}
	return raw, nil
}

// seerrFailure rend un refus de Seerr comme MediaHub rend les siens :
// { "error": … } en français, que l'app affiche tel quel. Seerr écrit
// { message } en anglais ; les refus qu'un compte rencontre vraiment sont
// traduits, le reste passe avec ses mots.
func (c Client) seerrFailure(status int, raw []byte) *StatusError {
	var answer struct {
		Message string `json:"message"`
		Error   string `json:"error"`
	}
	_ = json.Unmarshal(raw, &answer)
	said := answer.Message
	if said == "" {
		said = answer.Error
	}
	lower := strings.ToLower(said)
	label := c.Service.Label()

	message := said
	switch {
	case strings.Contains(lower, "quota"):
		message = fmt.Sprintf("Quota de demandes atteint chez %s.", label)
	case strings.Contains(lower, "already exists"):
		message = "Ce titre est déjà demandé."
	case strings.Contains(lower, "blacklist"), strings.Contains(lower, "blocklist"):
		message = fmt.Sprintf("Ce titre est bloqué chez %s.", label)
	case strings.Contains(lower, "only pending requests"):
		message = "Seule une demande en attente s'approuve ou se refuse."
	case strings.Contains(lower, "request not found"):
		message = fmt.Sprintf("Cette demande n'existe plus chez %s.", label)
	case status == http.StatusUnauthorized, strings.Contains(lower, "permission to access this endpoint"):
		message = fmt.Sprintf("%s refuse : la clé API est fausse, ou ce compte n'y a pas ce droit.", label)
	case strings.Contains(lower, "permission"):
		message = fmt.Sprintf("%s refuse : ce compte n'y a pas ce droit.", label)
	case message == "":
		message = fmt.Sprintf("Réponse inattendue de %s (HTTP %d).", label, status)
	}
	// Un 401 relayé tel quel se lirait dans l'app comme une session Onyx
	// expirée : c'est Seerr qui refuse, pas Onyx.
	if status == http.StatusUnauthorized {
		status = http.StatusForbidden
	}
	body, err := json.Marshal(struct {
		Error string `json:"error"`
	}{message})
	if err != nil {
		body = []byte(`{"error":"Réponse inattendue du service de demandes."}`)
	}
	return &StatusError{Status: status, Body: body}
}

// seerrDirectory lit, ou relit après cinq minutes, les comptes du Seerr.
func (c Client) seerrDirectory(ctx context.Context) (seerrDirectory, error) {
	if !c.Configured() {
		return seerrDirectory{}, ErrNotConfigured
	}
	key := c.seerrCacheKey()
	if directory, ok := seerrDirectories.Get(key); ok {
		return directory, nil
	}

	var directory seerrDirectory
	raw, err := c.seerr(ctx, http.MethodGet, "/auth/me", 0, nil, nil)
	if err != nil {
		return seerrDirectory{}, err
	}
	if err := json.Unmarshal(raw, &directory.owner); err != nil {
		return seerrDirectory{}, fmt.Errorf("mediahub: decode seerr account: %w", err)
	}
	if directory.owner.ID <= 0 {
		return seerrDirectory{}, errors.New("mediahub: seerr gave no account for this key")
	}

	for page := 0; page < seerrUserPages; page++ {
		query := url.Values{
			"take": {strconv.Itoa(seerrUserPageSize)},
			"skip": {strconv.Itoa(page * seerrUserPageSize)},
		}
		raw, err := c.seerr(ctx, http.MethodGet, "/user", 0, query, nil)
		if err != nil {
			return seerrDirectory{}, err
		}
		var list struct {
			Results []seerrUser `json:"results"`
		}
		if err := json.Unmarshal(raw, &list); err != nil {
			return seerrDirectory{}, fmt.Errorf("mediahub: decode seerr accounts: %w", err)
		}
		directory.users = append(directory.users, list.Results...)
		if len(list.Results) < seerrUserPageSize {
			break
		}
	}

	directory.version, directory.partialRequests = c.seerrAbout(ctx)
	seerrDirectories.Put(key, directory)
	return directory, nil
}

// seerrAbout lit la version et le réglage des demandes partielles. Ni l'un ni
// l'autre ne vaut de faire échouer un appel : sans réponse, la version reste
// vide et les saisons se choisissent, comme Seerr le fait par défaut.
func (c Client) seerrAbout(ctx context.Context) (version string, partialRequests bool) {
	partialRequests = true
	if raw, err := c.seerr(ctx, http.MethodGet, "/status", 0, nil, nil); err == nil {
		var status struct {
			Version string `json:"version"`
		}
		if json.Unmarshal(raw, &status) == nil {
			version = status.Version
		}
	}
	if raw, err := c.seerr(ctx, http.MethodGet, "/settings/public", 0, nil, nil); err == nil {
		var public struct {
			PartialRequestsEnabled *bool `json:"partialRequestsEnabled"`
		}
		if json.Unmarshal(raw, &public) == nil && public.PartialRequestsEnabled != nil {
			partialRequests = *public.PartialRequestsEnabled
		}
	}
	return version, partialRequests
}

// seerrIdentity rend le compte Seerr au nom duquel le compte Onyx agit.
func (c Client) seerrIdentity(ctx context.Context, as Account) (seerrIdentity, error) {
	directory, err := c.seerrDirectory(ctx)
	if err != nil {
		return seerrIdentity{}, err
	}
	return directory.identity(as), nil
}

// seerrAccess dit ce que le compte peut faire, d'après les droits du compte
// Seerr au nom duquel il agit.
func (c Client) seerrAccess(ctx context.Context, as Account) (Access, error) {
	directory, err := c.seerrDirectory(ctx)
	if err != nil {
		return Access{}, err
	}
	identity := directory.identity(as)
	user := identity.user
	return Access{
		Service: string(c.Service),
		Version: directory.version,
		Linked:  identity.linked,
		Can: Abilities{
			Read:            true,
			Request:         user.can(seerrCanRequest, seerrCanRequestMovie, seerrCanRequestTV),
			ReadAllRequests: user.can(seerrCanManageRequests, seerrCanViewRequests),
			Moderate:        user.can(seerrCanManageRequests),
			Delete:          user.can(seerrCanManageRequests),
		},
		SeasonChoice: directory.partialRequests,
	}, nil
}

// SeerrLink est ce qu'un test de liaison apprend d'un Seerr.
type SeerrLink struct {
	// Answered : l'adresse répond comme Overseerr ou Jellyseerr.
	Answered bool
	// KeyAccepted : la clé ouvre l'API.
	KeyAccepted bool
	Version     string
	// KeyAccount est le nom du compte de la clé.
	KeyAccount string
	// Linked : un compte Seerr porte le nom du compte qui teste.
	Linked bool
}

// IsSeerr dit si l'adresse répond comme Overseerr ou Jellyseerr : leur
// GET /status est public et rend leur version.
func (c Client) IsSeerr(ctx context.Context) (version string, ok bool, err error) {
	status, raw, err := c.roundTrip(ctx, http.MethodGet, SeerrPath+"/status", http.Header{}, nil, nil)
	if err != nil {
		return "", false, err
	}
	var answer struct {
		Version string `json:"version"`
	}
	if status != http.StatusOK || json.Unmarshal(raw, &answer) != nil || answer.Version == "" {
		return "", false, nil
	}
	return answer.Version, true, nil
}

// ProbeSeerr teste l'adresse et la clé, au nom du compte qui teste. L'erreur
// n'est rendue que pour une adresse muette.
func (c Client) ProbeSeerr(ctx context.Context, as Account) (SeerrLink, error) {
	version, ok, err := c.IsSeerr(ctx)
	if err != nil || !ok {
		return SeerrLink{}, err
	}
	link := SeerrLink{Answered: true, Version: version}

	c.ForgetSeerrAccounts()
	directory, err := c.seerrDirectory(ctx)
	if IsUnreachable(err) {
		return link, err
	}
	if err != nil {
		// Un refus, ou une réponse qui n'est pas celle d'un compte : la clé
		// n'ouvre pas l'API.
		return link, nil
	}
	link.KeyAccepted = true
	link.KeyAccount = directory.owner.name()
	link.Linked = directory.identity(as).linked
	return link, nil
}
