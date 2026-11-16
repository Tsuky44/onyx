package handlers

import (
	"fmt"
	"log"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"sync"
	"unicode"

	"project-player/server/safego"
)

// La recherche du catalogue de demandes, rangée par pertinence (ADR-0134).
//
// TMDB range une recherche surtout par la correspondance du texte : « bat »
// sortait « Bat Masterson » (un mot exact) devant « Batman », qu'on cherche
// presque toujours. On garde la liste de TMDB, mais on la reclasse : la
// correspondance du titre (la même échelle que `searchMatchRank` dans l'app)
// pèse, la notoriété du titre (popularité et nombre de votes) départage.

// searchRankPoolPages est le nombre de pages TMDB reclassées ensemble. Trois
// pages (60 titres) suffisent pour que le titre connu remonte même quand TMDB
// le met en deuxième page, et coûtent trois appels en parallèle, en cache dix
// minutes comme les autres pages du catalogue. Au-delà, les pages de TMDB
// passent telles quelles : on ne cherche plus si loin le titre voulu.
const searchRankPoolPages = 3

// searchMatchWeights donne le poids de chaque rang de correspondance de
// searchMatchRank, du titre exact (0) à la requête sans espaces (5).
var searchMatchWeights = [...]float64{1.0, 0.85, 0.7, 0.6, 0.4, 0.35}

// searchNoMatchWeight vaut pour un titre que TMDB a trouvé par ailleurs (un
// titre alternatif, une traduction) : il reste, mais derrière.
const searchNoMatchWeight = 0.3

// searchCatalog rend la page page de la recherche query sur path
// (/search/multi, /search/movie ou /search/tv). Les pages 1 à
// searchRankPoolPages découpent les mêmes titres reclassés, sans doublon
// entre elles ; les suivantes sont celles de TMDB.
func searchCatalog(client *http.Client, path, lang string, page int, query string) (tmdbCatalogResponse, error) {
	pageURL := func(p int) string {
		return fmt.Sprintf("%s?language=%s&page=%d&query=%s", path, lang, p, url.QueryEscape(query))
	}
	if page > searchRankPoolPages {
		return cachedTMDBCatalogPage(client, pageURL(page))
	}

	// Les trois pages partent ensemble, sans attendre que la première dise
	// combien il y en a : la page 1 attendait sinon deux allers-retours TMDB
	// l'un après l'autre. Une page au-delà de la dernière revient vide de
	// TMDB et n'est pas comptée.
	pages := make([]tmdbCatalogResponse, searchRankPoolPages)
	errs := make([]error, searchRankPoolPages)
	var wg sync.WaitGroup
	for i := range pages {
		wg.Add(1)
		go func(i int) {
			defer safego.Recover("handlers/request_search_rank.go:searchCatalog")
			defer wg.Done()
			pages[i], errs[i] = cachedTMDBCatalogPage(client, pageURL(i+1))
		}(i)
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
		rows = append(rows, p.Results...)
		fetched++
	}

	ranked := rankSearchRows(query, dedupeSearchRows(rows))
	if page > fetched {
		return tmdbCatalogResponse{Page: page, TotalPages: first.TotalPages, Results: []tmdbCatalogRow{}}, nil
	}
	per := (len(ranked) + fetched - 1) / fetched
	start := min((page-1)*per, len(ranked))
	end := min(start+per, len(ranked))
	return tmdbCatalogResponse{Page: page, TotalPages: first.TotalPages, Results: ranked[start:end]}, nil
}

// dedupeSearchRows rend une copie de rows sans les personnes (que le
// catalogue ne montre pas) ni les titres déjà vus : TMDB peut glisser un
// titre d'une page à l'autre entre deux appels.
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

// rankSearchRows range rows (que la fonction réordonne) du plus pertinent
// au moins pertinent pour query. À score égal, l'ordre de TMDB reste.
func rankSearchRows(query string, rows []tmdbCatalogRow) []tmdbCatalogRow {
	q := foldSearchText(query)
	scores := make(map[int]float64, len(rows))
	for i, row := range rows {
		scores[i] = searchRowScore(q, row)
	}
	order := make([]int, len(rows))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(a, b int) bool { return scores[order[a]] > scores[order[b]] })
	out := make([]tmdbCatalogRow, len(rows))
	for i, idx := range order {
		out[i] = rows[idx]
	}
	return out
}

// searchRowScore multiplie le poids de la meilleure correspondance (titre
// traduit ou original) par la notoriété. Le logarithme tasse les écarts :
// un titre cent fois plus populaire ne gagne pas cent fois, et un titre
// exact peu connu passe encore devant un titre connu qui ne correspond pas.
// Les votes, qui s'accumulent sur des années, retiennent un classique que la
// popularité du moment (une mesure de la semaine) a oublié.
func searchRowScore(foldedQuery string, row tmdbCatalogRow) float64 {
	weight := searchNoMatchWeight
	for _, title := range []string{row.Title, row.Name, row.OriginalTitle, row.OriginalName} {
		if rank, ok := searchMatchRank(foldSearchText(title), foldedQuery); ok {
			weight = max(weight, searchMatchWeights[rank])
		}
	}
	notoriety := math.Log1p(max(row.Popularity, 0)) + 0.3*math.Log1p(max(float64(row.VoteCount), 0))
	return weight * (1 + notoriety)
}

// searchMatchRank est le rang de la correspondance entre un titre et une
// requête, tous deux passés par foldSearchText : plus petit, plus pertinent.
// La même échelle que `searchMatchRank` de l'app (utils/search_match.dart).
func searchMatchRank(t, q string) (int, bool) {
	if q == "" || t == "" {
		return 0, false
	}
	if t == q {
		return 0, true
	}
	if strings.HasPrefix(t, q) {
		return 1, true
	}
	if strings.Contains(" "+t, " "+q) {
		return 2, true
	}
	titleWords := strings.Fields(t)
	allWords := true
	for _, word := range strings.Fields(q) {
		found := false
		for _, tw := range titleWords {
			if strings.HasPrefix(tw, word) {
				found = true
				break
			}
		}
		if !found {
			allWords = false
			break
		}
	}
	if allWords {
		return 3, true
	}
	if strings.Contains(t, q) {
		return 4, true
	}
	if strings.Contains(strings.ReplaceAll(t, " ", ""), strings.ReplaceAll(q, " ", "")) {
		return 5, true
	}
	return 0, false
}

// searchFolds ramène les lettres accentuées et les ligatures à leur forme de
// base, comme `_folds` de l'app : « amelie » trouve « Amélie ».
var searchFolds = map[rune]string{
	'à': "a", 'á': "a", 'â': "a", 'ã': "a", 'ä': "a", 'å': "a", 'ā': "a", 'æ': "ae",
	'ç': "c", 'ć': "c", 'č': "c",
	'è': "e", 'é': "e", 'ê': "e", 'ë': "e", 'ē': "e", 'ę': "e", 'ě': "e",
	'ì': "i", 'í': "i", 'î': "i", 'ï': "i", 'ī': "i",
	'ñ': "n", 'ń': "n", 'ň': "n",
	'ò': "o", 'ó': "o", 'ô': "o", 'õ': "o", 'ö': "o", 'ø': "o", 'ō': "o", 'œ': "oe",
	'ß': "ss", 'š': "s", 'ś': "s",
	'ù': "u", 'ú': "u", 'û': "u", 'ü': "u", 'ū': "u", 'ů': "u",
	'ý': "y", 'ÿ': "y", 'ž': "z", 'ź': "z", 'ż': "z", 'ł': "l",
}

// foldSearchText met text en minuscules, sans accents, la ponctuation
// changée en espace et les espaces réduits à un seul, comme `foldForSearch`
// de l'app : « L’Empire » se trouve par « empire ».
func foldSearchText(text string) string {
	var b strings.Builder
	pendingSpace := false
	for _, r := range strings.ToLower(text) {
		folded, ok := searchFolds[r]
		if !ok {
			folded = string(r)
		}
		if unicode.IsLetter(r) || unicode.IsNumber(r) {
			if pendingSpace && b.Len() > 0 {
				b.WriteByte(' ')
			}
			pendingSpace = false
			b.WriteString(folded)
		} else {
			pendingSpace = true
		}
	}
	return b.String()
}
