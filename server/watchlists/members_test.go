package watchlists

import (
	"errors"
	"testing"

	"project-player/server/models"
)

const carol = 3

// newTeamStore ajoute un troisième compte à la base de newTestStore.
func newTeamStore(t *testing.T) *Store {
	t.Helper()
	s := newTestStore(t)
	if _, err := s.db.Exec(`INSERT INTO users (id, username, password_hash, avatar) VALUES (3, 'carol', 'x', 'preset:fox')`); err != nil {
		t.Fatal(err)
	}
	return s
}

func mustInvite(t *testing.T, s *Store, owner, listID, user int) []models.WatchListMember {
	t.Helper()
	members, err := s.AddMember(owner, listID, user)
	if err != nil {
		t.Fatalf("AddMember(%d→%d): %v", owner, user, err)
	}
	return members
}

// Un invité remplit la liste d'un autre, même privée ; un compte qui n'est
// pas invité, lui, ne le peut toujours pas.
func TestAnInvitedAccountAddsAndRemovesTitlesInAPrivateList(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Soirée ciné", false)

	if _, err := s.Get(bob, list.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("private list before the invitation: %v, want ErrNotFound", err)
	}
	mustInvite(t, s, alice, list.ID, bob)

	item, err := s.AddServerMedia(bob, list.ID, 10)
	if err != nil {
		t.Fatalf("invited account adds: %v", err)
	}
	detail, err := s.Get(bob, list.ID)
	if err != nil {
		t.Fatalf("invited account reads a private list: %v", err)
	}
	if !detail.CanEdit || detail.IsMine || len(detail.Items) != 1 {
		t.Fatalf("detail for the invited account = %+v, want editable, not hers, one item", detail.WatchList)
	}
	if err := s.RemoveItem(bob, list.ID, item.ID); err != nil {
		t.Fatalf("invited account removes: %v", err)
	}

	if _, err := s.AddServerMedia(carol, list.ID, 10); !errors.Is(err, ErrNotFound) {
		t.Fatalf("uninvited account writes to a private list: %v, want ErrNotFound", err)
	}
}

// Une liste partagée avec tous reste en lecture seule pour qui n'est pas
// invité : l'invitation est ce qui ouvre l'écriture.
func TestSharedListStaysReadOnlyForUninvitedAccounts(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Recos", true)
	mustInvite(t, s, alice, list.ID, bob)

	if _, err := s.AddServerMedia(bob, list.ID, 10); err != nil {
		t.Fatalf("invited: %v", err)
	}
	if _, err := s.AddServerMedia(carol, list.ID, 10); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("uninvited on a shared list: %v, want ErrNotOwner", err)
	}
}

// Les invités ne gèrent pas la liste : seul le propriétaire la renomme, la
// supprime ou invite.
func TestInvitedAccountsCannotManageTheList(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Soirée ciné", false)
	mustInvite(t, s, alice, list.ID, bob)

	if _, err := s.Update(bob, list.ID, ListParams{Name: "Autre", IsShared: true}); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("invited renames: %v, want ErrNotOwner", err)
	}
	if err := s.Delete(bob, list.ID); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("invited deletes: %v, want ErrNotOwner", err)
	}
	if _, err := s.AddMember(bob, list.ID, carol); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("invited invites: %v, want ErrNotOwner", err)
	}
	if err := s.RemoveMember(bob, list.ID, carol); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("invited removes someone else: %v, want ErrNotOwner", err)
	}
}

// Une liste où l'on est invité apparaît parmi celles des autres, privée ou
// non, avec le droit de la remplir.
func TestInvitedListsAppearWithTheRightToEdit(t *testing.T) {
	s := newTeamStore(t)
	private := mustCreate(t, s, alice, "Privée", false)
	shared := mustCreate(t, s, alice, "Ouverte", true)
	mustCreate(t, s, alice, "Fermée", false)
	mustInvite(t, s, alice, private.ID, bob)

	lists, err := s.Lists(bob, &Probe{MediaID: 10})
	if err != nil {
		t.Fatal(err)
	}
	if len(lists.Shared) != 2 {
		t.Fatalf("bob sees %d lists of others, want 2: %+v", len(lists.Shared), lists.Shared)
	}
	for _, l := range lists.Shared {
		switch l.ID {
		case private.ID:
			if !l.CanEdit || l.MemberCount != 1 || l.ContainsItemID == nil {
				t.Fatalf("invited list = %+v, want editable, one member, probed", l)
			}
		case shared.ID:
			if l.CanEdit {
				t.Fatalf("a list shared with everyone is not editable by everyone: %+v", l)
			}
		default:
			t.Fatalf("unexpected list %d", l.ID)
		}
	}
	owned, err := s.Lists(alice, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range owned.Mine {
		if !l.CanEdit {
			t.Fatalf("the owner always edits her own list: %+v", l)
		}
	}
}

func TestInvitingIsIdempotentAndBounded(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Soirée ciné", false)
	mustInvite(t, s, alice, list.ID, bob)
	members := mustInvite(t, s, alice, list.ID, bob)
	if len(members) != 1 || members[0].Username != "bob" {
		t.Fatalf("members = %+v, want bob once", members)
	}

	later := watchLaterOf(t, s, alice)
	if _, err := s.AddMember(alice, later.ID, bob); !errors.Is(err, ErrInvalid) {
		t.Fatalf("invite to watch later: %v, want ErrInvalid", err)
	}
	if _, err := s.AddMember(alice, list.ID, alice); !errors.Is(err, ErrInvalid) {
		t.Fatalf("invite oneself: %v, want ErrInvalid", err)
	}
	if _, err := s.AddMember(alice, list.ID, 999); !errors.Is(err, ErrInvalid) {
		t.Fatalf("invite an unknown account: %v, want ErrInvalid", err)
	}

	for i := 0; i < MaxMembersPerList; i++ {
		id := 100 + i
		if _, err := s.db.Exec(`INSERT INTO users (id, username, password_hash) VALUES (?, ?, 'x')`, id, "u"+string(rune('a'+i%26))+string(rune('a'+i/26))); err != nil {
			t.Fatal(err)
		}
		if i < MaxMembersPerList-1 {
			mustInvite(t, s, alice, list.ID, id)
		}
	}
	if _, err := s.AddMember(alice, list.ID, 100+MaxMembersPerList-1); !errors.Is(err, ErrTooMany) {
		t.Fatalf("past the bound: %v, want ErrTooMany", err)
	}
}

// Le propriétaire retire qui il veut ; un invité se retire lui-même, et perd
// alors l'accès à une liste privée.
func TestMembersLeaveAndOwnersRemove(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Soirée ciné", false)
	mustInvite(t, s, alice, list.ID, bob)
	mustInvite(t, s, alice, list.ID, carol)

	if err := s.RemoveMember(bob, list.ID, bob); err != nil {
		t.Fatalf("bob leaves: %v", err)
	}
	if _, err := s.Get(bob, list.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob after leaving a private list: %v, want ErrNotFound", err)
	}
	if err := s.RemoveMember(alice, list.ID, carol); err != nil {
		t.Fatalf("owner removes carol: %v", err)
	}
	if err := s.RemoveMember(alice, list.ID, carol); !errors.Is(err, ErrNotFound) {
		t.Fatalf("removing twice: %v, want ErrNotFound", err)
	}
	if err := s.RemoveMember(carol, list.ID, carol); !errors.Is(err, ErrNotFound) {
		t.Fatalf("stranger leaving a private list: %v, want ErrNotFound", err)
	}
}

func TestDeletingTheListOrTheAccountClearsTheInvitations(t *testing.T) {
	s := newTeamStore(t)
	list := mustCreate(t, s, alice, "Soirée ciné", false)
	mustInvite(t, s, alice, list.ID, bob)
	if _, err := s.db.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`DELETE FROM users WHERE id = ?`, bob); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM watch_list_members`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("members after deleting the account = %d, want 0", n)
	}
}

func TestPeopleListsTheOtherAccountsWithTheirAvatar(t *testing.T) {
	s := newTeamStore(t)
	people, err := s.People(alice)
	if err != nil {
		t.Fatal(err)
	}
	if len(people) != 2 || people[0].Username != "bob" || people[1].Username != "carol" || people[1].Avatar != "preset:fox" {
		t.Fatalf("people = %+v, want bob and carol", people)
	}
}
