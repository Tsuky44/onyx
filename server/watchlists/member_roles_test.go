package watchlists

import (
	"errors"
	"testing"

	"project-player/server/models"
)

// Voir ADR-0129 : un invité peut seulement voir une liste.

func mustInviteAs(t *testing.T, s *Store, owner, listID, user int, role string) []models.WatchListMember {
	t.Helper()
	members, err := s.AddMember(owner, listID, user, role)
	if err != nil {
		t.Fatalf("AddMember(%d→%d, %s): %v", owner, user, role, err)
	}
	return members
}

// Un invité à voir lit une liste privée, la trouve parmi celles des autres,
// et ne peut pas y écrire ; un compte sans invitation ne la voit toujours pas.
func TestAViewerReadsAPrivateListWithoutEditingIt(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Soirée ciné", false)
	mustInviteAs(t, s, alice, list.ID, bob, models.WatchListRoleViewer)

	detail, err := s.Get(bob, list.ID)
	if err != nil {
		t.Fatalf("viewer reads a private list: %v", err)
	}
	if detail.CanEdit || !detail.IsMember || detail.IsMine {
		t.Fatalf("viewer detail = %+v, want read-only member", detail.WatchList)
	}
	if _, err := s.AddServerMedia(bob, list.ID, 10); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("viewer adds: %v, want ErrNotOwner", err)
	}
	lists, err := s.Lists(bob, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(lists.Shared) != 1 || lists.Shared[0].ID != list.ID || lists.Shared[0].CanEdit || !lists.Shared[0].IsMember {
		t.Fatalf("bob's lists of others = %+v, want the list, read-only", lists.Shared)
	}
	if _, err := s.Get(carol, list.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("uninvited account reads a private list: %v, want ErrNotFound", err)
	}
}

// Réinviter change le rôle sans doubler l'invité : de « voir » à
// « ajouter », puis retour.
func TestInvitingAgainChangesTheRole(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Soirée ciné", false)
	mustInviteAs(t, s, alice, list.ID, bob, models.WatchListRoleViewer)

	members := mustInviteAs(t, s, alice, list.ID, bob, models.WatchListRoleEditor)
	if len(members) != 1 || members[0].Role != models.WatchListRoleEditor {
		t.Fatalf("members = %+v, want bob once, editor", members)
	}
	if _, err := s.AddServerMedia(bob, list.ID, 10); err != nil {
		t.Fatalf("promoted viewer adds: %v", err)
	}

	members = mustInviteAs(t, s, alice, list.ID, bob, models.WatchListRoleViewer)
	if len(members) != 1 || members[0].Role != models.WatchListRoleViewer {
		t.Fatalf("members = %+v, want bob once, viewer", members)
	}
	if _, err := s.AddServerMedia(bob, list.ID, 11); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("demoted editor adds: %v, want ErrNotOwner", err)
	}
	if _, err := s.AddMember(alice, list.ID, bob, "admin"); !errors.Is(err, ErrInvalid) {
		t.Fatalf("unknown role: %v, want ErrInvalid", err)
	}
}

// Deux comptes remplissent, un troisième voit, et tout le serveur lit :
// la liste partagée avec tous garde ses éditeurs.
func TestEditorsAndViewersMixOnAListSharedWithEveryone(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Noël", true)
	mustInviteAs(t, s, alice, list.ID, bob, models.WatchListRoleEditor)
	members := mustInviteAs(t, s, alice, list.ID, carol, models.WatchListRoleViewer)
	if len(members) != 2 || members[0].Role != models.WatchListRoleEditor || members[1].Role != models.WatchListRoleViewer {
		t.Fatalf("members = %+v, want bob editor then carol viewer", members)
	}
	if _, err := s.AddServerMedia(bob, list.ID, 10); err != nil {
		t.Fatalf("editor adds: %v", err)
	}
	if _, err := s.AddServerMedia(carol, list.ID, 10); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("viewer adds: %v, want ErrNotOwner", err)
	}
	summary, err := s.summary(alice, list.ID)
	if err != nil {
		t.Fatal(err)
	}
	if summary.MemberCount != 2 {
		t.Fatalf("member count = %d, want 2", summary.MemberCount)
	}
}

// Un invité à voir peut quitter la liste, comme un invité qui la remplit.
func TestAViewerLeavesTheList(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Soirée ciné", false)
	mustInviteAs(t, s, alice, list.ID, bob, models.WatchListRoleViewer)
	if err := s.RemoveMember(bob, list.ID, bob); err != nil {
		t.Fatalf("viewer leaves: %v", err)
	}
	if _, err := s.Get(bob, list.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("after leaving: %v, want ErrNotFound", err)
	}
}
