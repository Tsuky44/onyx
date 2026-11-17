package handlers

import (
	"context"
	"fmt"
	"log"
	"math"
	"net/http"
	"net/url"
	"sort"
	"sync"
	"time"

	"project-player/server/safego"
	"project-player/server/titleindex"
	"project-player/server/ttlcache"
)

// La recherche du catalogue de demandes, rangée par pertinence (ADR-0134) et
// complétée par les titres connus qui commencent par la requête (ADR-0135).
//
// TMDB range une recherche surtout par la correspondance du texte, et sur des
// mots entiers : « bat » sortait « Bat Masterson » et jamais Batman. On garde
// la liste de TMDB, on y ajoute les titres connus de l'index (titleindex), et
// on reclasse le tout : la correspondance du titre pèse, la notoriété
// départage.

// searchRankPoolPages est le nombre de pages TMDB reclassées ensemble. Trois
// pages (60 titres) suffisent pour que le titre connu remonte même quand TMDB
// le met en deuxième page, et coûtent trois appels en parallèle, en cache dix
// minutes comme les autres pages du catalogue. Au-delà, les pages de TMDB
// passent telles quelles : on ne cherche plus si loin le titre voulu.
const searchRankPoolPages = 3

// searchSuggestionLimit est le nombre de titres de l'index ajoutés à une
// recherche : chacun coûte un appel de fiche TMDB (titre français, affiche),
// en cache un jour.
const searchSuggestionLimit = 10

// titleSuggester est l'index des titres connus, vu de la recherche.
type titleSuggester interface {
	Suggest(ctx context.Context, query, mediaType string, limit int) ([]titleindex.Hit, error)
}

// requestTitles est nil tant que main n'a pas ouvert l'index : la recherche
// se fait alors avec TMDB seul.
var requestTitles titleSuggester

// UseTitleIndex branche l'index des titres connus sur la recherche du
// catalogue de demandes. À appeler au démarrage, avant de servir.
func UseTitleIndex(s titleSuggester) { requestTitles = s }

// Les fiches des titres suggérés, un jour en cache : un titre et son affiche
// ne bougent pas plus vite, et les mêmes reviennent à chaque lettre tapée.
var tmdbTitleRows = ttlcache.New[tmdbCatalogRow](24*time.Hour, 2048)

// searchCatalog rend la page page de la recherche query, sur les films
// (kind "movie"), les séries ("tv") ou les deux (""). Les pages 1 à
// searchRankPoolPages découpent les mêmes titres reclassés, sans doublon
// entre elles ; les suivantes sont celles de TMDB.
func searchCatalog(client *http.Client, kind, lang string, page int, query string) (tmdbCatalogResponse, error) {
	path := "/search/multi"
	if kind == "movie" || kind == "tv" {
		path = "/search/" + kind
	}
	pageURL := func(p int) string {
		return fmt.Sprintf("%s?language=%s&page=%d&query=%s", path, lang, p, url.QueryEscape(query))
	}
	if page > searchRankPoolPages {
		return cachedTMDBCatalogPage(client, pageURL(page))
	}

	// Les trois pages et les fiches des titres suggérés partent ensemble,
	// sans attendre que la première page dise combien il y en a. Une page
	// au-delà de la dernière revient vide de TMDB et n'est pas comptée.
	pages := make([]tmdbCatalogResponse, searchRankPoolPages)
	errs := make([]error, searchRankPoolPages)
	hits := suggestTitles(query, kind)
	suggested := make([]*tmdbCatalogRow, len(hits))
	var wg sync.WaitGroup
	for i := range pages {
		wg.Add(1)
		go func(i int) {
			defer safego.Recover("handlers/request_search_rank.go:searchCatalog page")
			defer wg.Done()
			pages[i], errs[i] = cachedTMDBCatalogPage(client, pageURL(i+1))
		}(i)
	}
	for i, hit := range hits {
		wg.Add(1)
		go func(i int, hit titleindex.Hit) {
			defer safego.Recover("handlers/request_search_rank.go:searchCatalog fiche")
			defer wg.Done()
			row, err := cachedTMDBTitleRow(client, hit, lang)
			if err != nil {
				// Une fiche en échec retire seulement cette suggestion.
				log.Printf("searchCatalog: fiche %s %d: %v", hit.MediaType, hit.ID, err)
				return
			}
			suggested[i] = &row
		}(i, hit)
	}
	wg.Wait()

	if errs[0] != nil {
		return tmdbCatalogResponse{}, fmt.Errorf("recherche %q page 1: %w", query, errs[0])
	}
	first := pages[0]
	pooled := max(min(searchRankPoolPages, first.TotalPages), 1)

	// Une page suivante en échec ne prive pas de la première : on reclasse
	// ce qui est arrivé, jusqu'au premier trou pour ne pas sauter de titres.
	var rows []tmdbCatalogRow
	fetched := 0
	for i, p := range pages[:pooled] {
		if errs[i] != nil {
			log.Printf("searchCatalog: page %d de %q: %v", i+1, query, errs[i])
			break
		}
		for _, row := range p.Results {
			// /search/movie et /search/tv ne disent pas le type : on le pose
			// pour reconnaître le même titre venu de l'index.
			if row.MediaType == "" && (kind == "movie" || kind == "tv") {
				row.MediaType = kind
			}
			rows = append(rows, row)
		}
		fetched++
	}
	for _, row := range suggested {
		if row != nil {
			rows = append(rows, *row)
		}
	}

	ranked := rankSearchRows(query, dedupeSearchRows(rows))
	totalPages := max(first.TotalPages, 1)
	if page > fetched {
		return tmdbCatalogResponse{Page: page, TotalPages: totalPages, Results: []tmdbCatalogRow{}}, nil
	}
	per := (len(ranked) + fetched - 1) / fetched
	start := min((page-1)*per, len(ranked))
	end := min(start+per, len(ranked))
	return tmdbCatalogResponse{Page: page, TotalPages: totalPages, Results: ranked[start:end]}, nil
}

// suggestTitles rend les titres connus de l'index qui commencent par query,
// ou rien sans index. Un index en panne ne prive pas de la recherche TMDB.
func suggestTitles(query, kind string) []titleindex.Hit {
	if requestTitles == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	hits, err := requestTitles.Suggest(ctx, query, kind, searchSuggestionLimit)
	if err != nil {
		log.Printf("searchCatalog: index des titres: %v", err)
		return nil
	}
	return hits
}

// cachedTMDBTitleRow rend la fiche TMDB d'un titre suggéré, dans la langue
// lang, sous la forme d'une ligne de recherche.
func cachedTMDBTitleRow(client *http.Client, hit titleindex.Hit, lang string) (tmdbCatalogRow, error) {
	key := fmt.Sprintf("/%s/%d?language=%s", hit.MediaType, hit.ID, lang)
	if row, ok := tmdbTitleRows.Get(key); ok {
		return row, nil
	}
	var row tmdbCatalogRow
	if err := fetchTMDBCatalogPage(client, key, &row); err != nil {
		return tmdbCatalogRow{}, err
	}
	row.MediaType = hit.MediaType
	tmdbTitleRows.Put(key, row)
	return row, nil
}

// dedupeSearchRows rend une copie de rows sans les personnes (que le
// catalogue ne montre pas) ni les titres déjà vus : TMDB peut glisser un
// titre d'une page à l'autre entre deux appels, et l'index suggère souvent
// un titre que TMDB a aussi trouvé.
func dedupeSearchRows(rows []tmdbCatalogRow) []tmdbCatalogRow {
	seen := make(map[string]bool, len(rows))
	out := make([]tmdbCatalogRow, 0, len(rows))
	for _, row := range rows {
		if row.MediaType != "" && row.MediaType != "movie" && row.MediaType != "tv" {
			continue
		}
		key := fmt.Sprintf("%s:%d", row.MediaType, row.ID)
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, row)
	}
	return out
}

// Le seuil de notoriété d'un titre exact pour passer en tête (ADR-0134) :
// assez de votes, ou assez de popularité pour un titre qui sort et n'a pas
// encore de votes. Sans seuil, le film « Bat » (1 vote) repasserait devant
// Batman sur « bat » ; avec, « ava » ouvre sur Ava (2020, environ 2 000 votes)
// avant Avatar.
const (
	exactTitleMinVotes      = 100
	exactTitleMinPopularity = 10.0
)

// rankSearchRows range rows du plus pertinent au moins pertinent pour query,
// dans une nouvelle liste : d'abord les titres exacts assez connus, puis le
// reste, chacun par score. À rang égal, l'ordre reçu reste.
func rankSearchRows(query string, rows []tmdbCatalogRow) []tmdbCatalogRow {
	q := titleindex.Fold(query)
	scores := make([]float64, len(rows))
	leads := make([]bool, len(rows))
	for i, row := range rows {
		scores[i] = searchRowScore(q, row)
		leads[i] = isKnownExactTitle(q, row)
	}
	order := make([]int, len(rows))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(a, b int) bool {
		if leads[order[a]] != leads[order[b]] {
			return leads[order[a]]
		}
		return scores[order[a]] > scores[order[b]]
	})
	out := make([]tmdbCatalogRow, len(rows))
	for i, idx := range order {
		out[i] = rows[idx]
	}
	return out
}

// isKnownExactTitle dit si row porte exactement le titre cherché (traduit ou
// original) et passe le seuil de notoriété. Le score seul ne suffisait pas :
// le titre exact n'y pèse que 15 % de plus qu'un début de titre, et un titre
// deux ou trois fois plus connu effaçait cet écart (« ava » sortait toute la
// saga Avatar avant Ava).
func isKnownExactTitle(foldedQuery string, row tmdbCatalogRow) bool {
	if !titleindex.IsExactTitle(foldedQuery, row.Title, row.Name, row.OriginalTitle, row.OriginalName) {
		return false
	}
	return row.VoteCount >= exactTitleMinVotes ||
		titleindex.NormalizedPopularity(row.MediaType, row.Popularity) >= exactTitleMinPopularity
}

// searchRowScore multiplie le poids de la meilleure correspondance (titre
// traduit ou original) par la notoriété. Le logarithme tasse les écarts :
// un titre cent fois plus populaire ne gagne pas cent fois, et un titre
// exact peu connu passe encore devant un titre connu qui ne correspond pas.
// Les votes, qui s'accumulent sur des années, retiennent un classique que la
// popularité du moment (une mesure de la semaine) a oublié ; la popularité
// d'une série est ramenée à l'échelle des films (titleindex).
func searchRowScore(foldedQuery string, row tmdbCatalogRow) float64 {
	weight := titleindex.MatchWeight(foldedQuery, row.Title, row.Name, row.OriginalTitle, row.OriginalName)
	popularity := titleindex.NormalizedPopularity(row.MediaType, row.Popularity)
	notoriety := math.Log1p(popularity) + 0.3*math.Log1p(max(float64(row.VoteCount), 0))
	return weight * (1 + notoriety)
}
