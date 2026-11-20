package watchlists

import (
	"testing"

	"project-player/server/models"
)

// seedShow range une série de deux épisodes présents sur le disque et d'un
// emplacement TMDB sans fichier : seuls les deux premiers comptent.
func seedShow(t *testing.T, s *Store) {
	t.Helper()
	for _, stmt := range []string{
		`INSERT INTO medias (id, type, title, tmdb_id, poster_url) VALUES (20, 'show', 'Dark', 70523, '/posters/dark.jpg')`,
		`INSERT INTO medias (id, type, title, parent_id) VALUES (21, 'season', 'Saison 1', 20)`,
		`INSERT INTO medias (id, type, title, parent_id, file_path) VALUES (22, 'episode', 'E1', 21, '/d1.mkv')`,
		`INSERT INTO medias (id, type, title, parent_id, file_path) VALUES (23, 'episode', 'E2', 21, '/d2.mkv')`,
		`INSERT INTO medias (id, type, title, parent_id, file_path) VALUES (24, 'episode', 'E3 manquant', 21, '')`,
	} {
		if _, err := s.db.Exec(stmt); err != nil {
			t.Fatalf("seed show: %v", err)
		}
	}
}

func finish(t *testing.T, s *Store, user, media int) {
	t.Helper()
	if _, err := s.db.Exec(`INSERT INTO progressions (user_id, media_id, current_position_seconds, is_finished, updated_at)
		VALUES (?, ?, 100, 1, 1)`, user, media); err != nil {
		t.Fatalf("finish: %v", err)
	}
}

func listByID(t *testing.T, s *Store, viewer, id int) (found bool, watched, onServer int, next int) {
	t.Helper()
	lists, err := s.Lists(viewer, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range append(lists.Mine, lists.Shared...) {
		if l.ID == id {
			if l.NextItem != nil {
				next = l.NextItem.MediaID
			}
			return true, l.WatchedCount, l.OnServerCount, next
		}
	}
	return false, 0, 0, 0
}

// « Vu » est une décision du serveur : un film est vu quand sa progression est
// terminée, une série quand tous ses épisodes présents le sont, et le prochain
// titre est le premier non vu dans l'ordre d'ajout (ADR-0159).
func TestListProgressCountsWatchedTitlesAndPicksTheNextOne(t *testing.T) {
	s := newTestStore(t)
	seedShow(t, s)
	list := mustCreate(t, s, alice, "Ce soir", true)
	for _, id := range []int{10, 20, 11} {
		if _, err := s.AddServerMedia(alice, list.ID, id); err != nil {
			t.Fatalf("add %d: %v", id, err)
		}
	}
	// Un titre que le serveur n'a pas : il compte dans la liste, pas dans
	// « sur le serveur ».
	if _, err := s.AddCatalogTitle(alice, list.ID, CatalogTitle{MediaType: "movie", TMDBID: 999, Title: "Absent"}); err != nil {
		t.Fatal(err)
	}

	_, watched, onServer, next := listByID(t, s, alice, list.ID)
	if watched != 0 || onServer != 3 || next != 10 {
		t.Fatalf("nothing seen: watched=%d onServer=%d next=%d, want 0/3/10", watched, onServer, next)
	}

	finish(t, s, alice, 10)
	// Un seul des deux épisodes : la série n'est pas vue.
	finish(t, s, alice, 22)
	_, watched, _, next = listByID(t, s, alice, list.ID)
	if watched != 1 || next != 20 {
		t.Fatalf("one movie seen: watched=%d next=%d, want 1/20", watched, next)
	}

	// Le second épisode terminé, l'emplacement sans fichier ne retient pas la
	// série ; le prochain devient le film suivant.
	finish(t, s, alice, 23)
	_, watched, _, next = listByID(t, s, alice, list.ID)
	if watched != 2 || next != 11 {
		t.Fatalf("show seen: watched=%d next=%d, want 2/11", watched, next)
	}

	// Tout vu : plus de prochain titre.
	finish(t, s, alice, 11)
	_, watched, onServer, next = listByID(t, s, alice, list.ID)
	if watched != 3 || onServer != 3 || next != 0 {
		t.Fatalf("all seen: watched=%d onServer=%d next=%d, want 3/3/0", watched, onServer, next)
	}
}

// La progression est celle du compte qui lit, pas celle du propriétaire.
func TestListProgressIsThatOfTheReadingAccount(t *testing.T) {
	s := newTestStore(t)
	list := mustCreate(t, s, alice, "Recos", true)
	if _, err := s.AddServerMedia(alice, list.ID, 10); err != nil {
		t.Fatal(err)
	}
	finish(t, s, alice, 10)

	_, watched, _, _ := listByID(t, s, alice, list.ID)
	if watched != 1 {
		t.Fatalf("owner watched = %d, want 1", watched)
	}
	_, watched, onServer, next := listByID(t, s, bob, list.ID)
	if watched != 0 || onServer != 1 || next != 10 {
		t.Fatalf("guest: watched=%d onServer=%d next=%d, want 0/1/10", watched, onServer, next)
	}
}

func TestEmptyListHasNoProgress(t *testing.T) {
	s := newTestStore(t)
	list := mustCreate(t, s, alice, "Vide", false)
	_, watched, onServer, next := listByID(t, s, alice, list.ID)
	if watched != 0 || onServer != 0 || next != 0 {
		t.Fatalf("empty list: %d/%d/%d, want 0/0/0", watched, onServer, next)
	}
}

// Le détail d'une liste dit, titre par titre, ce que le compte a vu : c'est ce
// que lisent les onglets À voir / Vus, sans que l'app recalcule « vu ».
func TestListDetailFlagsEachWatchedItem(t *testing.T) {
	s := newTestStore(t)
	seedShow(t, s)
	list := mustCreate(t, s, alice, "Ce soir", true)
	for _, id := range []int{10, 20} {
		if _, err := s.AddServerMedia(alice, list.ID, id); err != nil {
			t.Fatalf("add %d: %v", id, err)
		}
	}
	if _, err := s.AddCatalogTitle(alice, list.ID, CatalogTitle{MediaType: "movie", TMDBID: 999, Title: "Absent"}); err != nil {
		t.Fatal(err)
	}
	finish(t, s, alice, 10)

	watchedByMedia := func(viewer int) map[int]bool {
		detail, err := s.Get(viewer, list.ID)
		if err != nil {
			t.Fatal(err)
		}
		out := map[int]bool{}
		for _, it := range detail.Items {
			out[it.MediaID] = it.Watched
		}
		return out
	}
	got := watchedByMedia(alice)
	if !got[10] || got[20] || got[0] {
		t.Fatalf("owner flags = %v, want only media 10 watched", got)
	}
	if got := watchedByMedia(bob); got[10] {
		t.Fatalf("guest sees the owner's progress: %v", got)
	}
}

// Le détail d'une liste dit où le compte en est d'une série : épisodes terminés
// sur épisodes présents (l'emplacement sans fichier ne compte pas) et le
// premier qui reste à voir (ADR-0162).
func TestListDetailTellsHowFarTheAccountIsInAShow(t *testing.T) {
	s := newTestStore(t)
	seedShow(t, s)
	for id, episode := range map[int]int{22: 1, 23: 2} {
		if _, err := s.db.Exec(`UPDATE medias SET season_number = 1, episode_number = ? WHERE id = ?`, episode, id); err != nil {
			t.Fatal(err)
		}
	}
	list := mustCreate(t, s, alice, "Séries", true)
	for _, id := range []int{10, 20} {
		if _, err := s.AddServerMedia(alice, list.ID, id); err != nil {
			t.Fatalf("add %d: %v", id, err)
		}
	}
	show := func(viewer int) models.WatchListItem {
		detail, err := s.Get(viewer, list.ID)
		if err != nil {
			t.Fatal(err)
		}
		for _, it := range detail.Items {
			if it.MediaID == 20 {
				return it
			}
			if it.MediaID == 10 && it.EpisodesTotal != 0 {
				t.Fatalf("a movie carries episode counts: %+v", it)
			}
		}
		t.Fatal("show missing from the list")
		return models.WatchListItem{}
	}

	got := show(alice)
	if got.EpisodesTotal != 2 || got.EpisodesWatched != 0 || got.NextEpisodeSeason != 1 || got.NextEpisodeNumber != 1 {
		t.Fatalf("not started: %+v, want 0/2 next S1E1", got)
	}
	finish(t, s, alice, 22)
	got = show(alice)
	if got.EpisodesWatched != 1 || got.NextEpisodeSeason != 1 || got.NextEpisodeNumber != 2 || got.Watched {
		t.Fatalf("half way: %+v, want 1/2 next S1E2", got)
	}
	// Un autre compte repart de zéro.
	if other := show(bob); other.EpisodesWatched != 0 || other.NextEpisodeNumber != 1 {
		t.Fatalf("guest sees the owner's progress: %+v", other)
	}
	finish(t, s, alice, 23)
	got = show(alice)
	if got.EpisodesWatched != 2 || got.NextEpisodeSeason != 0 || got.NextEpisodeNumber != 0 || !got.Watched {
		t.Fatalf("finished: %+v, want 2/2 and no next episode", got)
	}
}
