package titleindex

import (
	"strings"
	"unicode"
)

// La correspondance entre un titre et ce qu'on tape pour le trouver, la même
// que celle de l'app (`foldForSearch` et `searchMatchRank` dans
// app/lib/utils/search_match.dart) : un changement d'un côté se reporte de
// l'autre.

// matchWeights donne le poids de chaque rang de MatchRank, du titre exact (0)
// à la requête sans espaces (5). Voir ADR-0134.
var matchWeights = [...]float64{1.0, 0.85, 0.7, 0.6, 0.4, 0.35}

// NoMatchWeight vaut pour un titre que TMDB a trouvé autrement (un titre
// alternatif, une traduction) : il reste, mais derrière.
const NoMatchWeight = 0.3

// MatchWeight est le poids de la meilleure correspondance de foldedQuery
// (passée par Fold) parmi titles, ou NoMatchWeight.
func MatchWeight(foldedQuery string, titles ...string) float64 {
	weight := NoMatchWeight
	for _, title := range titles {
		if rank, ok := MatchRank(Fold(title), foldedQuery); ok {
			weight = max(weight, matchWeights[rank])
		}
	}
	return weight
}

// IsExactTitle dit si l'un des titles, passé par Fold, est exactement
// foldedQuery (passée par Fold), article de tête ignoré : « batman » est le
// titre exact de « The Batman ».
func IsExactTitle(foldedQuery string, titles ...string) bool {
	for _, title := range titles {
		if rank, ok := MatchRank(Fold(title), foldedQuery); ok && rank == 0 {
			return true
		}
	}
	return false
}

// leadingArticles sont ignorés en tête d'un titre pour juger s'il commence
// par la requête : « The Batman » commence par « bat » autant que
// « Batman », comme le rangement A → Z de l'app ignore ces articles.
var leadingArticles = []string{"the ", "a ", "an ", "le ", "la ", "les ", "l ", "un ", "une "}

// MatchRank est le rang de la correspondance entre un titre et une requête,
// tous deux passés par Fold : plus petit, plus pertinent. Dans l'ordre : le
// titre exact, un titre qui commence par la requête, un mot du titre qui
// commence par elle, tous les mots de la requête en début de mots du titre,
// la requête n'importe où, la requête sans ses espaces dans le titre sans les
// siens (« spiderman » trouve « Spider-Man »).
func MatchRank(t, q string) (int, bool) {
	best, found := matchRank(t, q)
	for _, article := range leadingArticles {
		if rest, ok := strings.CutPrefix(t, article); ok {
			if rank, ok := matchRank(rest, q); ok && (!found || rank < best) {
				best, found = rank, true
			}
			break
		}
	}
	return best, found
}

func matchRank(t, q string) (int, bool) {
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
	if everyWordStartsAWord(strings.Fields(q), strings.Fields(t)) {
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

func everyWordStartsAWord(queryWords, titleWords []string) bool {
	for _, word := range queryWords {
		found := false
		for _, tw := range titleWords {
			if strings.HasPrefix(tw, word) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}

// folds ramène les lettres accentuées et les ligatures à leur forme de base,
// comme `_folds` de l'app : « amelie » trouve « Amélie ».
var folds = map[rune]string{
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

// Fold met text en minuscules, sans accents, la ponctuation changée en espace
// et les espaces réduits à un seul : « L’Empire » se trouve par « empire »,
// ce qu'il ne ferait pas collé en « lempire ».
func Fold(text string) string {
	var b strings.Builder
	pendingSpace := false
	for _, r := range strings.ToLower(text) {
		if !isWordRune(r) {
			pendingSpace = true
			continue
		}
		if pendingSpace && b.Len() > 0 {
			b.WriteByte(' ')
		}
		pendingSpace = false
		if folded, ok := folds[r]; ok {
			b.WriteString(folded)
		} else {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func isWordRune(r rune) bool {
	return unicode.IsLetter(r) || unicode.IsNumber(r)
}
