package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

func inviteKey(b byte) [32]byte {
	var k [32]byte
	k[0] = b
	return k
}

func TestWatchPartyInviteRefusesSomeoneWithoutTheAppOpen(t *testing.T) {
	store := newWatchPartyInviteStore()
	now := time.Unix(1_000_000, 0)
	if _, err := store.invite("ABC123", 1, "alex", 2, now); err != errInviteeOffline {
		t.Fatalf("never seen: err = %v, want errInviteeOffline", err)
	}
	store.touch(inviteKey(2), 2, now)
	later := now.Add(appPresenceStaleAfter + time.Second)
	if _, err := store.invite("ABC123", 1, "alex", 2, later); err != errInviteeOffline {
		t.Fatalf("stopped polling: err = %v, want errInviteeOffline", err)
	}
	if _, err := store.invite("ABC123", 1, "alex", 1, now); err != errInviteeSelf {
		t.Fatalf("self: err = %v, want errInviteeSelf", err)
	}
}

func TestWatchPartyInviteWakesTheInboxOfEveryDevice(t *testing.T) {
	store := newWatchPartyInviteStore()
	now := time.Unix(1_000_000, 0)
	store.touch(inviteKey(2), 2, now)
	version, wait, invites := store.snapshot(2, now)
	if len(invites) != 0 {
		t.Fatalf("empty inbox holds %d invites", len(invites))
	}
	if _, err := store.invite("ABC123", 1, "alex", 2, now); err != nil {
		t.Fatal(err)
	}
	select {
	case <-wait:
	default:
		t.Fatal("an invite must wake the inbox's waiting polls")
	}
	next, _, invites := store.snapshot(2, now)
	if next <= version || len(invites) != 1 || invites[0].FromName != "alex" {
		t.Fatalf("after invite: version %d → %d, invites %+v", version, next, invites)
	}
}

func TestWatchPartyReinviteReplacesTheInviteWithANewOne(t *testing.T) {
	store := newWatchPartyInviteStore()
	now := time.Unix(1_000_000, 0)
	store.touch(inviteKey(2), 2, now)
	first, _ := store.invite("ABC123", 1, "alex", 2, now)
	second, err := store.invite("ABC123", 1, "alex", 2, now.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	_, _, invites := store.snapshot(2, now.Add(time.Second))
	if len(invites) != 1 || invites[0].ID != second.ID || second.ID == first.ID {
		t.Fatalf("re-invite must replace with a fresh id, got %+v", invites)
	}
}

func TestWatchPartyDeclineIsSeenByTheHost(t *testing.T) {
	store := newWatchPartyInviteStore()
	now := time.Unix(1_000_000, 0)
	store.touch(inviteKey(2), 2, now)
	inv, _ := store.invite("ABC123", 1, "alex", 2, now)
	if got := store.statusFor("ABC123", 2, now); got != "pending" {
		t.Fatalf("status = %q, want pending", got)
	}
	if err := store.decline(3, inv.ID, now); err != errInviteNotFound {
		t.Fatalf("another account declining: err = %v", err)
	}
	if err := store.decline(2, inv.ID, now); err != nil {
		t.Fatal(err)
	}
	if got := store.statusFor("ABC123", 2, now); got != "declined" {
		t.Fatalf("status = %q, want declined", got)
	}
	if _, _, invites := store.snapshot(2, now); len(invites) != 0 {
		t.Fatalf("declined invite still in the inbox: %+v", invites)
	}
	if got := store.statusFor("ABC123", 2, now.Add(watchPartyDeclineMemory+time.Second)); got != "" {
		t.Fatalf("old decline still reported: %q", got)
	}
}

func TestWatchPartyInviteExpiresAndGoesWithItsParty(t *testing.T) {
	store := newWatchPartyInviteStore()
	now := time.Unix(1_000_000, 0)
	store.touch(inviteKey(2), 2, now)
	store.invite("ABC123", 1, "alex", 2, now)
	store.invite("XYZ789", 1, "alex", 2, now)
	if _, _, invites := store.snapshot(2, now.Add(watchPartyInviteLifetime)); len(invites) != 0 {
		t.Fatalf("expired invites still shown: %+v", invites)
	}

	store.touch(inviteKey(2), 2, now)
	store.reap(now, func(code string) bool { return code == "XYZ789" })
	_, _, invites := store.snapshot(2, now)
	if len(invites) != 1 || invites[0].Code != "XYZ789" {
		t.Fatalf("an ended party's invite must go, got %+v", invites)
	}

	store.clear(2, "XYZ789")
	if _, _, invites := store.snapshot(2, now); len(invites) != 0 {
		t.Fatalf("joining must clear the invite, got %+v", invites)
	}
}

func TestWatchPartyInviteesAreOnlyAccountsWithTheAppOpen(t *testing.T) {
	setupAuthDB(t)
	host := createTestUser(t, "alex", true, models.Permissions{})
	online := createTestUser(t, "sam", false, models.Permissions{})
	createTestUser(t, "lou", false, models.Permissions{}) // jamais ouvert
	member := createTestUser(t, "kim", false, models.Permissions{})

	parties, invites := watchParties, watchPartyInvites
	watchParties, watchPartyInvites = newTestWatchPartyStore(), newWatchPartyInviteStore()
	t.Cleanup(func() { watchParties, watchPartyInvites = parties, invites })

	now := time.Now()
	party, err := watchParties.create(&watchPartyMember{ID: "a", UserID: host, Username: "alex"}, 42, 0, false, now)
	if err != nil {
		t.Fatal(err)
	}
	if err := watchParties.join(party.Code, &watchPartyMember{ID: "k", UserID: member}, now); err != nil {
		t.Fatal(err)
	}
	for i, id := range []int{host, online, member} {
		watchPartyInvites.touch(inviteKey(byte(i+1)), id, now)
	}

	list := func() []watchPartyInviteeView {
		req := httptest.NewRequest(http.MethodGet, "/api/watch-parties/"+party.Code+"/invitees?member=a", nil)
		rec := httptest.NewRecorder()
		ListWatchPartyInvitees(rec, req, httprouter.Params{{Key: "code", Value: party.Code}}, host)
		if rec.Code != http.StatusOK {
			t.Fatalf("status %d: %s", rec.Code, rec.Body)
		}
		var out watchPartyInviteesResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		return out.Invitees
	}
	got := list()
	if len(got) != 1 || got[0].UserID != online || got[0].Username != "sam" || got[0].InviteStatus != "" {
		t.Fatalf("invitees = %+v, want only sam (online, not in the party, not the host)", got)
	}

	if _, err := watchPartyInvites.invite(party.Code, host, "alex", online, now); err != nil {
		t.Fatal(err)
	}
	if got := list(); got[0].InviteStatus != "pending" {
		t.Fatalf("after invite: %+v", got)
	}

	// Un compte hors de la séance ne voit pas qui l'on pourrait inviter.
	req := httptest.NewRequest(http.MethodGet, "/api/watch-parties/"+party.Code+"/invitees?member=a", nil)
	rec := httptest.NewRecorder()
	ListWatchPartyInvitees(rec, req, httprouter.Params{{Key: "code", Value: party.Code}}, online)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("outsider: status %d, want 403", rec.Code)
	}
}
