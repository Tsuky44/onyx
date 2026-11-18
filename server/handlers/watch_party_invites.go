package handlers

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"project-player/server/database"
	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

// Inviter à une séance « Regarder ensemble » (ADR-0148).
//
// En plus du code, un participant peut inviter une personne qui a Onyx ouvert
// en ce moment. « Ouvert » se lit sur la boîte d'invitations : tant que l'app
// est au premier plan, elle attend en long-polling GET
// /api/me/watch-party-invites, et cette attente sert de signe de présence,
// comme celle d'une séance sert de signe de vie (ADR-0029). Une app fermée, en
// arrière-plan ou hors réseau cesse d'attendre et disparaît de la liste au bout
// de [appPresenceStaleAfter] : on ne peut pas inviter quelqu'un qui ne verrait
// pas l'invitation.
//
// Tout vit en mémoire, comme les séances : une invitation ne vaut que tant que
// sa séance existe, et pour [watchPartyInviteLifetime].

const (
	// Durée maximale d'une attente de la boîte : celle d'une séance, sous le
	// délai de réception de 30 s du client Dio partagé.
	watchPartyInboxWindow = 20 * time.Second
	// Un appareil qui n'attend plus sa boîte depuis ce délai n'a plus l'app
	// ouverte : la fenêtre d'une attente, plus la reprise après une coupure.
	appPresenceStaleAfter = 45 * time.Second
	// Une invitation à laquelle personne n'a répondu ne reste pas en suspens :
	// la séance a avancé, et revenir plus tard sur l'accueil ne doit pas
	// proposer une soirée finie.
	watchPartyInviteLifetime = 2 * time.Minute
	// Un refus se retient un moment, pour que l'hôte le voie dans sa liste.
	watchPartyDeclineMemory = 10 * time.Minute
	// Assez pour plusieurs séances à la fois, pas assez pour inonder un
	// compte d'invitations.
	watchPartyMaxInvitesPerUser = 8
)

var (
	errInviteeOffline = errors.New("invitee does not have the app open")
	errInviteeSelf    = errors.New("cannot invite yourself")
	errInviteeMember  = errors.New("invitee already in the watch party")
	errInviteeFlooded = errors.New("too many pending invites for this account")
	errInviteNotFound = errors.New("invite not found")
)

type watchPartyInvite struct {
	ID         string
	Code       string
	FromUserID int
	FromName   string
	ToUserID   int
	Created    time.Time
	Expires    time.Time
}

// appPresence est un appareil dont l'app attend sa boîte d'invitations.
type appPresence struct {
	UserID int
	Seen   time.Time
}

// watchPartyInbox est la boîte d'un compte : toutes ses sessions la voient, et
// la première qui répond la vide pour les autres.
type watchPartyInbox struct {
	invites []*watchPartyInvite
	version int64
	// Fermé puis remplacé à chaque changement : c'est ce qui réveille les
	// attentes en cours, comme pour une séance.
	changed chan struct{}
}

type watchPartyDecline struct {
	code   string
	userID int
}

type watchPartyInviteStore struct {
	mu sync.Mutex
	// Un seul compteur pour toutes les boîtes : un numéro ne revient jamais
	// en arrière, même pour une boîte recréée.
	seq      int64
	presence map[[32]byte]appPresence
	inboxes  map[int]*watchPartyInbox
	declined map[watchPartyDecline]time.Time
}

func newWatchPartyInviteStore() *watchPartyInviteStore {
	return &watchPartyInviteStore{
		presence: make(map[[32]byte]appPresence),
		inboxes:  make(map[int]*watchPartyInbox),
		declined: make(map[watchPartyDecline]time.Time),
	}
}

var watchPartyInvites = newWatchPartyInviteStore()

// inboxLocked rend la boîte du compte, créée au besoin. s.mu doit être tenu.
func (s *watchPartyInviteStore) inboxLocked(userID int) *watchPartyInbox {
	box := s.inboxes[userID]
	if box == nil {
		s.seq++
		box = &watchPartyInbox{version: s.seq, changed: make(chan struct{})}
		s.inboxes[userID] = box
	}
	return box
}

// bump réveille les attentes de la boîte. s.mu doit être tenu.
func (s *watchPartyInviteStore) bump(b *watchPartyInbox) {
	s.seq++
	b.version = s.seq
	close(b.changed)
	b.changed = make(chan struct{})
}

// touch note que cette session a l'app ouverte.
func (s *watchPartyInviteStore) touch(key [32]byte, userID int, now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.presence[key] = appPresence{UserID: userID, Seen: now}
}

// online rend les comptes dont au moins un appareil a l'app ouverte.
func (s *watchPartyInviteStore) online(now time.Time) map[int]bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make(map[int]bool)
	for _, p := range s.presence {
		if now.Sub(p.Seen) <= appPresenceStaleAfter {
			out[p.UserID] = true
		}
	}
	return out
}

func (s *watchPartyInviteStore) isOnlineLocked(userID int, now time.Time) bool {
	for _, p := range s.presence {
		if p.UserID == userID && now.Sub(p.Seen) <= appPresenceStaleAfter {
			return true
		}
	}
	return false
}

// invite dépose une invitation dans la boîte de [toUserID]. Réinviter la même
// personne à la même séance remplace l'invitation d'avant par une nouvelle :
// l'app la montre de nouveau, même si elle avait laissé filer la première.
func (s *watchPartyInviteStore) invite(code string, fromUserID int, fromName string, toUserID int, now time.Time) (*watchPartyInvite, error) {
	if toUserID == fromUserID {
		return nil, errInviteeSelf
	}
	id, err := newWatchPartyMemberID()
	if err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.isOnlineLocked(toUserID, now) {
		return nil, errInviteeOffline
	}
	box := s.inboxLocked(toUserID)
	kept := box.invites[:0]
	for _, inv := range box.invites {
		if inv.Code != code && now.Before(inv.Expires) {
			kept = append(kept, inv)
		}
	}
	box.invites = kept
	if len(box.invites) >= watchPartyMaxInvitesPerUser {
		return nil, errInviteeFlooded
	}
	inv := &watchPartyInvite{
		ID:         id,
		Code:       code,
		FromUserID: fromUserID,
		FromName:   fromName,
		ToUserID:   toUserID,
		Created:    now,
		Expires:    now.Add(watchPartyInviteLifetime),
	}
	box.invites = append(box.invites, inv)
	delete(s.declined, watchPartyDecline{code: code, userID: toUserID})
	s.bump(box)
	return inv, nil
}

// decline retire une invitation de la boîte du compte, sur tous ses appareils,
// et retient le refus pour la liste de l'hôte.
func (s *watchPartyInviteStore) decline(userID int, id string, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	box := s.inboxes[userID]
	if box == nil {
		return errInviteNotFound
	}
	for i, inv := range box.invites {
		if inv.ID != id {
			continue
		}
		box.invites = append(box.invites[:i], box.invites[i+1:]...)
		s.declined[watchPartyDecline{code: inv.Code, userID: userID}] = now
		s.bump(box)
		return nil
	}
	return errInviteNotFound
}

// clear retire les invitations du compte à cette séance : il vient de la
// rejoindre, par l'invitation ou par le code.
func (s *watchPartyInviteStore) clear(userID int, code string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	box := s.inboxes[userID]
	if box == nil {
		return
	}
	kept := box.invites[:0]
	for _, inv := range box.invites {
		if inv.Code != code {
			kept = append(kept, inv)
		}
	}
	if len(kept) == len(box.invites) {
		return
	}
	box.invites = kept
	s.bump(box)
}

// statusFor dit où en est l'invitation de [userID] à la séance [code] :
// « pending », « declined » ou rien.
func (s *watchPartyInviteStore) statusFor(code string, userID int, now time.Time) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if box := s.inboxes[userID]; box != nil {
		for _, inv := range box.invites {
			if inv.Code == code && now.Before(inv.Expires) {
				return "pending"
			}
		}
	}
	if at, ok := s.declined[watchPartyDecline{code: code, userID: userID}]; ok && now.Sub(at) <= watchPartyDeclineMemory {
		return "declined"
	}
	return ""
}

// snapshot rend la boîte du compte : sa version, de quoi attendre le
// changement suivant, et les invitations encore valables.
func (s *watchPartyInviteStore) snapshot(userID int, now time.Time) (int64, <-chan struct{}, []watchPartyInvite) {
	s.mu.Lock()
	defer s.mu.Unlock()
	box := s.inboxLocked(userID)
	out := make([]watchPartyInvite, 0, len(box.invites))
	for _, inv := range box.invites {
		if now.Before(inv.Expires) {
			out = append(out, *inv)
		}
	}
	return box.version, box.changed, out
}

// reap oublie les appareils partis, les refus anciens et les invitations
// expirées ou dont la séance est finie. [alive] dit si une séance existe
// encore ; il est appelé hors du verrou de la boîte, pour ne jamais tenir les
// deux verrous à la fois.
func (s *watchPartyInviteStore) reap(now time.Time, alive func(code string) bool) {
	s.mu.Lock()
	codes := make(map[string]bool)
	for key, p := range s.presence {
		if now.Sub(p.Seen) > appPresenceStaleAfter {
			delete(s.presence, key)
		}
	}
	for key, at := range s.declined {
		if now.Sub(at) > watchPartyDeclineMemory {
			delete(s.declined, key)
		}
	}
	for _, box := range s.inboxes {
		for _, inv := range box.invites {
			codes[inv.Code] = true
		}
	}
	s.mu.Unlock()

	for code := range codes {
		codes[code] = alive(code)
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	for _, box := range s.inboxes {
		kept := box.invites[:0]
		for _, inv := range box.invites {
			if now.Before(inv.Expires) && codes[inv.Code] {
				kept = append(kept, inv)
			}
		}
		if len(kept) != len(box.invites) {
			box.invites = kept
			s.bump(box)
		}
	}
}

// mediaOf rend le média que lit la séance [code], et si elle existe.
func (s *watchPartyStore) mediaOf(code string) (int, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	party, ok := s.parties[code]
	if !ok {
		return 0, false
	}
	return party.MediaID, true
}

// --- Réponses -------------------------------------------------------------

type watchPartyInviteView struct {
	ID      string                `json:"id"`
	Code    string                `json:"code"`
	From    string                `json:"from"`
	MediaID int                   `json:"media_id"`
	Media   *models.HomeMediaItem `json:"media,omitempty"`
	Expires int                   `json:"expires_in_seconds"`
}

type watchPartyInvitesResponse struct {
	Version int64                  `json:"version"`
	Invites []watchPartyInviteView `json:"invites"`
}

type watchPartyInviteeView struct {
	UserID   int    `json:"user_id"`
	Username string `json:"username"`
	Avatar   string `json:"avatar"`
	// « pending » : invitée, sans réponse ; « declined » : elle a refusé ;
	// vide : pas encore invitée.
	InviteStatus string `json:"invite_status"`
}

type watchPartyInviteesResponse struct {
	Invitees []watchPartyInviteeView `json:"invitees"`
}

func writeWatchPartyInviteError(w http.ResponseWriter, err error) {
	switch err {
	case errInviteeOffline:
		writeJSONError(w, http.StatusConflict, "Cette personne n’a plus Onyx ouvert")
	case errInviteeSelf:
		writeJSONError(w, http.StatusBadRequest, "Vous ne pouvez pas vous inviter vous-même")
	case errInviteeMember:
		writeJSONError(w, http.StatusConflict, "Cette personne est déjà dans la séance")
	case errInviteeFlooded:
		writeJSONError(w, http.StatusTooManyRequests, "Cette personne a déjà trop d’invitations en attente")
	case errInviteNotFound:
		writeJSONError(w, http.StatusNotFound, "Invitation introuvable ou expirée")
	default:
		writeWatchPartyError(w, err)
	}
}

// inviteViews met en forme les invitations du compte : le média tel qu'il le
// voit, celui que la séance lit maintenant et non celui de l'invitation. Une
// séance finie ou un média qu'il ne peut pas lire ne s'annonce pas.
func inviteViews(userID int, invites []watchPartyInvite, now time.Time) []watchPartyInviteView {
	out := make([]watchPartyInviteView, 0, len(invites))
	for _, inv := range invites {
		mediaID, ok := watchParties.mediaOf(inv.Code)
		if !ok {
			continue
		}
		media, err := loadWatchPartyMedia(userID, mediaID)
		if err != nil {
			if err != sql.ErrNoRows {
				log.Printf("WatchPartyInvite: media %d: %v", mediaID, err)
			}
			continue
		}
		left := int(inv.Expires.Sub(now).Seconds())
		if left < 1 {
			left = 1
		}
		out = append(out, watchPartyInviteView{
			ID:      inv.ID,
			Code:    inv.Code,
			From:    inv.FromName,
			MediaID: mediaID,
			Media:   media,
			Expires: left,
		})
	}
	return out
}

// --- Routes ---------------------------------------------------------------

// PollWatchPartyInvites attend la prochaine invitation du compte
// (GET /api/me/watch-party-invites?since=N), et tient l'appareil pour présent
// tant qu'il attend.
func PollWatchPartyInvites(w http.ResponseWriter, r *http.Request, _ httprouter.Params, userID int) {
	key := sessionKey(bearerToken(r))
	since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
	watchPartyInvites.touch(key, userID, time.Now())

	version, changed, _ := watchPartyInvites.snapshot(userID, time.Now())
	if since >= version {
		timer := time.NewTimer(watchPartyInboxWindow)
		select {
		case <-changed:
		case <-timer.C:
		case <-r.Context().Done():
			timer.Stop()
			return
		}
		timer.Stop()
	}

	now := time.Now()
	watchPartyInvites.touch(key, userID, now)
	version, _, invites := watchPartyInvites.snapshot(userID, now)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	json.NewEncoder(w).Encode(watchPartyInvitesResponse{
		Version: version,
		Invites: inviteViews(userID, invites, now),
	})
}

// DeclineWatchPartyInvite refuse une invitation
// (POST /api/me/watch-party-invites/:id/decline).
func DeclineWatchPartyInvite(w http.ResponseWriter, r *http.Request, ps httprouter.Params, userID int) {
	if err := watchPartyInvites.decline(userID, ps.ByName("id"), time.Now()); err != nil {
		writeWatchPartyInviteError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// partyMemberUsers vérifie que [memberID] appartient au compte et rend les
// comptes déjà dans la séance, avec le nom du participant qui appelle.
func partyMemberUsers(code, memberID string, userID int) (map[int]bool, string, error) {
	watchParties.mu.Lock()
	defer watchParties.mu.Unlock()
	party, m, err := watchParties.member(code, memberID, userID)
	if err != nil {
		return nil, "", err
	}
	in := make(map[int]bool, len(party.Members))
	for _, other := range party.Members {
		in[other.UserID] = true
	}
	return in, m.Username, nil
}

// ListWatchPartyInvitees liste les personnes qu'un participant peut inviter :
// les comptes qui ont Onyx ouvert maintenant, hors lui-même et hors ceux déjà
// dans la séance (GET /api/watch-parties/:code/invitees?member=ID).
func ListWatchPartyInvitees(w http.ResponseWriter, r *http.Request, ps httprouter.Params, userID int) {
	code := normalizeUserCode(ps.ByName("code"))
	inParty, _, err := partyMemberUsers(code, r.URL.Query().Get("member"), userID)
	if err != nil {
		writeWatchPartyError(w, err)
		return
	}
	now := time.Now()
	ids := make([]any, 0)
	for id := range watchPartyInvites.online(now) {
		if id != userID && !inParty[id] {
			ids = append(ids, id)
		}
	}
	out := watchPartyInviteesResponse{Invitees: []watchPartyInviteeView{}}
	if len(ids) > 0 {
		rows, err := database.DB.Query(
			`SELECT id, username, avatar FROM users WHERE id IN (`+sqlPlaceholders(len(ids))+`)`, ids...)
		if err != nil {
			log.Printf("ListWatchPartyInvitees: %v", err)
			writeWatchPartyError(w, err)
			return
		}
		defer rows.Close()
		for rows.Next() {
			var v watchPartyInviteeView
			if err := rows.Scan(&v.UserID, &v.Username, &v.Avatar); err != nil {
				log.Printf("ListWatchPartyInvitees: scan: %v", err)
				continue
			}
			v.InviteStatus = watchPartyInvites.statusFor(code, v.UserID, now)
			out.Invitees = append(out.Invitees, v)
		}
		if err := rows.Err(); err != nil {
			log.Printf("ListWatchPartyInvitees: rows: %v", err)
		}
	}
	sort.Slice(out.Invitees, func(i, j int) bool {
		return strings.ToLower(out.Invitees[i].Username) < strings.ToLower(out.Invitees[j].Username)
	})
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	json.NewEncoder(w).Encode(out)
}

// InviteToWatchParty invite une personne qui a Onyx ouvert
// (POST /api/watch-parties/:code/invite).
func InviteToWatchParty(w http.ResponseWriter, r *http.Request, ps httprouter.Params, userID int) {
	var body struct {
		MemberID string `json:"member_id"`
		UserID   int    `json:"user_id"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024)).Decode(&body) != nil || body.UserID <= 0 {
		writeJSONError(w, http.StatusBadRequest, "Invitation invalide")
		return
	}
	code := normalizeUserCode(ps.ByName("code"))
	inParty, name, err := partyMemberUsers(code, body.MemberID, userID)
	if err != nil {
		writeWatchPartyError(w, err)
		return
	}
	if inParty[body.UserID] {
		writeWatchPartyInviteError(w, errInviteeMember)
		return
	}
	if _, err := watchPartyInvites.invite(code, userID, name, body.UserID, time.Now()); err != nil {
		writeWatchPartyInviteError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
