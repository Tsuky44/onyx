package indexer

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	"project-player/server/database"
)

func TestGenreFillerReadsEachTitleOnceAndRetriesFailures(t *testing.T) {
	if _, err := database.InitDB(filepath.Join(t.TempDir(), "genres.db")); err != nil {
		t.Fatalf("InitDB: %v", err)
	}
	insert := func(mediaType string, tmdbID int) int {
		t.Helper()
		res, err := database.DB.Exec(`INSERT INTO medias (type, title, tmdb_id) VALUES (?, 'x', ?)`, mediaType, tmdbID)
		if err != nil {
			t.Fatalf("insert media: %v", err)
		}
		id, _ := res.LastInsertId()
		return int(id)
	}
	movie := insert("movie", 438631)
	show := insert("show", 95396)
	gone := insert("movie", 1)
	flaky := insert("movie", 2)
	insert("episode", 3) // un épisode n'a pas de genre à lui
	insert("movie", 0)   // un film que TMDB ne connaît pas

	var asked []string
	failFlaky := true
	saved := fetchGenreIDs
	t.Cleanup(func() { fetchGenreIDs = saved })
	fetchGenreIDs = func(_ context.Context, kind string, tmdbID int) ([]int, error) {
		asked = append(asked, kind)
		switch tmdbID {
		case 438631:
			return []int{878, 12}, nil
		case 95396:
			return []int{10765, 18}, nil
		case 1:
			return nil, errGenreNotFound
		case 2:
			if failFlaky {
				return nil, errors.New("réseau coupé")
			}
			return []int{35}, nil
		}
		t.Fatalf("fiche inattendue %s/%d", kind, tmdbID)
		return nil, nil
	}

	done, err := FillMissingGenres(context.Background(), 10)
	if err != nil || done != 3 {
		t.Fatalf("première passe : %d, %v", done, err)
	}
	if len(asked) != 4 || asked[1] != "tv" {
		t.Fatalf("demandes = %v", asked)
	}
	genres := func(id int) []int {
		t.Helper()
		rows, err := database.DB.Query(`SELECT genre_id FROM media_genres WHERE media_id = ? ORDER BY genre_id`, id)
		if err != nil {
			t.Fatal(err)
		}
		defer rows.Close()
		var out []int
		for rows.Next() {
			var g int
			if err := rows.Scan(&g); err != nil {
				t.Fatal(err)
			}
			out = append(out, g)
		}
		return out
	}
	if g := genres(movie); len(g) != 2 || g[0] != 12 || g[1] != 878 {
		t.Fatalf("genres du film = %v", g)
	}
	if g := genres(show); len(g) != 2 {
		t.Fatalf("genres de la série = %v", g)
	}
	if g := genres(gone); len(g) != 0 {
		t.Fatalf("une fiche disparue n'a pas de genre : %v", g)
	}

	// Seule la fiche qui a échoué est redemandée.
	asked, failFlaky = nil, false
	done, err = FillMissingGenres(context.Background(), 10)
	if err != nil || done != 1 || len(asked) != 1 {
		t.Fatalf("deuxième passe : %d, %v, %v", done, err, asked)
	}
	if g := genres(flaky); len(g) != 1 || g[0] != 35 {
		t.Fatalf("genres après la reprise = %v", g)
	}
	asked = nil
	if done, _ := FillMissingGenres(context.Background(), 10); done != 0 || len(asked) != 0 {
		t.Fatalf("troisième passe : %d, %v", done, asked)
	}
}
