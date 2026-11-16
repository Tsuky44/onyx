package handlers

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func titlesOf(rows []tmdbCatalogRow) []string {
	out := make([]string, len(rows))
	for i, row := range rows {
		out[i] = row.Title + row.Name
	}
	return out
}

func indexOfTitle(rows []tmdbCatalogRow, title string) int {
	for i, row := range rows {
		if row.Title+row.Name == title {
			return i
		}
	}
	return -1
}

// Le cas qui a lancé le reclassement : « bat » sortait « Bat Masterson »
// avant Batman, dans l'ordre de TMDB.
func TestSearchRanksWellKnownTitlesAboveObscureWordMatches(t *testing.T) {
	rows := []tmdbCatalogRow{
		{ID: 1, MediaType: "tv", Name: "Bat Masterson", Popularity: 4, VoteCount: 25},
		{ID: 2, MediaType: "movie", Title: "Bat", Popularity: 0.6, VoteCount: 1},
		{ID: 3, MediaType: "movie", Title: "Batman", Popularity: 30, VoteCount: 8000},
		{ID: 4, MediaType: "movie", Title: "The Batman", Popularity: 90, VoteCount: 10000},
	}
	got := rankSearchRows("bat", rows)
	masterson := indexOfTitle(got, "Bat Masterson")
	for _, batman := range []string{"Batman", "The Batman"} {
		if indexOfTitle(got, batman) > masterson {
			t.Fatalf("%q doit passer devant « Bat Masterson » : %v", batman, titlesOf(got))
		}
	}
	if got[0].Title != "Batman" {
		t.Fatalf("« Batman » commence par la requête et est connu : premier attendu, %v", titlesOf(got))
	}
}

// La notoriété départage, elle n'écrase pas le texte : le titre exact passe
// devant une suite à peine plus populaire, et un titre connu qui ne
// correspond pas reste derrière.
func TestSearchKeepsExactTitleFirstAmongComparablyKnownTitles(t *testing.T) {
	rows := []tmdbCatalogRow{
		{ID: 1, MediaType: "movie", Title: "Dune : Deuxième partie", Popularity: 120, VoteCount: 6000},
		{ID: 2, MediaType: "tv", Name: "Les Enfants de Dune", Popularity: 10, VoteCount: 200},
		{ID: 3, MediaType: "movie", Title: "Dune", Popularity: 80, VoteCount: 12000},
	}
	got := rankSearchRows("dune", rows)
	want := []string{"Dune", "Dune : Deuxième partie", "Les Enfants de Dune"}
	if strings.Join(titlesOf(got), "|") != strings.Join(want, "|") {
		t.Fatalf("ordre %v, attendu %v", titlesOf(got), want)
	}
}

// Le titre est traduit (language=fr-FR) : on cherche aussi dans le titre
// original, et sans accents.
func TestSearchMatchesOriginalTitleAndIgnoresAccents(t *testing.T) {
	rows := []tmdbCatalogRow{
		{ID: 1, MediaType: "movie", Title: "Sans rapport", Popularity: 50, VoteCount: 500},
		{ID: 2, MediaType: "movie", Title: "Le Chevalier noir", OriginalTitle: "The Dark Knight", Popularity: 40, VoteCount: 30000},
		{ID: 3, MediaType: "movie", Title: "Le Fabuleux Destin d'Amélie Poulain", Popularity: 20, VoteCount: 10000},
	}
	if got := rankSearchRows("dark knight", rows); got[0].ID != 2 {
		t.Fatalf("le titre original doit compter : %v", titlesOf(got))
	}
	if got := rankSearchRows("amelie", rows); got[0].ID != 3 {
		t.Fatalf("« amelie » doit trouver « Amélie » : %v", titlesOf(got))
	}
}

// pagedTMDB rend une page de recherche par numéro, et sert la page 4 telle
// quelle pour vérifier que l'au-delà du reclassement vient de TMDB.
type pagedTMDB struct{}

func (pagedTMDB) RoundTrip(r *http.Request) (*http.Response, error) {
	page := r.URL.Query().Get("page")
	var results []string
	for i := 0; i < 4; i++ {
		id := fmt.Sprintf("%s%d", page, i)
		// La page 3 est la plus connue : elle doit remonter en tête.
		pop := 1
		if page == "3" {
			pop = 500
		}
		results = append(results, fmt.Sprintf(`{"id":%s,"media_type":"movie","title":"Film %s","popularity":%d}`, id, id, pop))
	}
	results = append(results, `{"id":99,"media_type":"person","name":"Film Personne"}`)
	// Un titre qui glisse d'une page à l'autre ne doit sortir qu'une fois.
	results = append(results, `{"id":7,"media_type":"movie","title":"Film doublon"}`)
	body := fmt.Sprintf(`{"page":%s,"total_pages":5,"results":[%s]}`, page, strings.Join(results, ","))
	return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header), Request: r}, nil
}

func TestSearchPagesServeEachPooledTitleOnceThenTMDBPages(t *testing.T) {
	t.Setenv("TMDB_API_KEY", "test-key")
	tmdbCatalogPages = newCatalogPageCacheForTest(t)
	client := &http.Client{Transport: pagedTMDB{}}

	seen := map[int]int{}
	var firstPage []tmdbCatalogRow
	for page := 1; page <= searchRankPoolPages; page++ {
		got, err := searchCatalog(client, "/search/multi", "fr-FR", page, "film")
		if err != nil {
			t.Fatalf("page %d : %v", page, err)
		}
		if got.Page != page || got.TotalPages != 5 {
			t.Fatalf("page %d : en-tête inattendu %+v", page, got)
		}
		if page == 1 {
			firstPage = got.Results
		}
		for _, row := range got.Results {
			seen[row.ID]++
		}
	}
	// 3 pages × 4 films, plus le doublon une seule fois ; jamais la personne.
	if len(seen) != 13 {
		t.Fatalf("%d titres distincts sur les pages reclassées, attendu 13 : %v", len(seen), seen)
	}
	for id, n := range seen {
		if n != 1 {
			t.Fatalf("titre %d servi %d fois", id, n)
		}
		if id == 99 {
			t.Fatal("une personne ne doit pas sortir dans le catalogue")
		}
	}
	if len(firstPage) == 0 || firstPage[0].ID/10 != 3 {
		t.Fatalf("les titres connus de la page 3 de TMDB doivent ouvrir la page 1 : %v", titlesOf(firstPage))
	}

	fourth, err := searchCatalog(client, "/search/multi", "fr-FR", 4, "film")
	if err != nil {
		t.Fatalf("page 4 : %v", err)
	}
	if fourth.Page != 4 || len(fourth.Results) == 0 || fourth.Results[0].ID != 40 {
		t.Fatalf("la page 4 doit être celle de TMDB, telle quelle : %+v", fourth)
	}
}

// concurrentTMDB ne répond à la page 1 qu'une fois les pages 2 et 3
// demandées : si searchCatalog attendait la page 1 pour lancer les autres, la
// page 1 tomberait en délai dépassé. La recherche n'a qu'une page.
type concurrentTMDB struct {
	others chan struct{}
}

func (c concurrentTMDB) RoundTrip(r *http.Request) (*http.Response, error) {
	page := r.URL.Query().Get("page")
	status, body := http.StatusOK, `{"page":1,"total_pages":1,"results":[{"id":1,"media_type":"movie","title":"Seul"}]}`
	if page == "1" {
		for range 2 {
			select {
			case <-c.others:
			case <-time.After(2 * time.Second):
				return nil, errors.New("pages 2 et 3 pas demandées en même temps que la page 1")
			}
		}
	} else {
		c.others <- struct{}{}
		// Au-delà de la dernière page : même un échec ne doit pas compter.
		status, body = http.StatusUnprocessableEntity, `{}`
	}
	return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header), Request: r}, nil
}

func TestSearchAsksTheThreePoolPagesAtOnce(t *testing.T) {
	t.Setenv("TMDB_API_KEY", "test-key")
	tmdbCatalogPages = newCatalogPageCacheForTest(t)
	client := &http.Client{Transport: concurrentTMDB{others: make(chan struct{}, 2)}}

	got, err := searchCatalog(client, "/search/multi", "fr-FR", 1, "seul")
	if err != nil {
		t.Fatalf("page 1 : %v", err)
	}
	if len(got.Results) != 1 || got.Results[0].ID != 1 || got.TotalPages != 1 {
		t.Fatalf("une recherche d'une page doit rendre sa page seule : %+v", got)
	}
}

func TestFoldSearchTextMatchesTheApp(t *testing.T) {
	cases := map[string]string{
		"L’Empire contre-attaque": "l empire contre attaque",
		"Amélie":                  "amelie",
		"WALL·E":                  "wall e",
		"  Spider-Man  ":          "spider man",
		"Œdipe":                   "oedipe",
	}
	for in, want := range cases {
		if got := foldSearchText(in); got != want {
			t.Errorf("foldSearchText(%q) = %q, attendu %q", in, got, want)
		}
	}
}
