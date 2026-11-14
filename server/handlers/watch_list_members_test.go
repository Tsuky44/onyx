package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"project-player/server/models"

	"github.com/julienschmidt/httprouter"
)

// Le corps {"role": "viewer"} invite à voir seulement (ADR-0129) ; sans corps,
// l'invité remplit la liste, comme pour les apps d'avant les rôles.
func TestInvitingWithARoleThroughTheRoute(t *testing.T) {
	setupAuthDB(t)
	alice := createTestUser(t, "alice", false, models.Permissions{})
	bob := createTestUser(t, "bob", false, models.Permissions{})
	carol := createTestUser(t, "carol", false, models.Permissions{})
	list := createList(t, alice, `{"name":"Soirée ciné"}`)
	body := `{"tmdb_id":1,"media_type":"movie","title":"X"}`

	invite := func(target int, payload string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPut, "/api/lists/x/members/y", strings.NewReader(payload))
		AddWatchListMember(rec, req,
			listParams(list.ID, httprouter.Param{Key: "user", Value: strconv.Itoa(target)}), alice)
		return rec
	}
	if rec := invite(bob, ""); rec.Code != http.StatusOK {
		t.Fatalf("invite without a body: %d %s", rec.Code, rec.Body.String())
	}
	rec := invite(carol, `{"role":"viewer"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("invite a viewer: %d %s", rec.Code, rec.Body.String())
	}
	var members []models.WatchListMember
	if err := json.NewDecoder(rec.Body).Decode(&members); err != nil || len(members) != 2 {
		t.Fatalf("members = %+v (%v), want two", members, err)
	}
	if members[0].Role != models.WatchListRoleEditor || members[1].Role != models.WatchListRoleViewer {
		t.Fatalf("roles = %q, %q, want editor then viewer", members[0].Role, members[1].Role)
	}

	if rec := addToList(t, bob, list.ID, body); rec.Code != http.StatusOK {
		t.Fatalf("editor adds: %d %s", rec.Code, rec.Body.String())
	}
	if rec := addToList(t, carol, list.ID, body); rec.Code != http.StatusForbidden {
		t.Fatalf("viewer adds: %d, want 403", rec.Code)
	}
	rec = httptest.NewRecorder()
	GetWatchList(rec, httptest.NewRequest(http.MethodGet, "/api/lists/x", nil), listParams(list.ID), carol)
	if rec.Code != http.StatusOK {
		t.Fatalf("viewer reads the private list: %d %s", rec.Code, rec.Body.String())
	}

	if rec := invite(carol, `{"role":"owner"}`); rec.Code != http.StatusBadRequest {
		t.Fatalf("unknown role: %d, want 400", rec.Code)
	}
	if rec := invite(carol, `{`); rec.Code != http.StatusBadRequest {
		t.Fatalf("unreadable body: %d, want 400", rec.Code)
	}
}
