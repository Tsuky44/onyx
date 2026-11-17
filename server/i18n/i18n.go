// Package i18n traduit les messages que le serveur renvoie à l'app.
//
// Même principe que l'app (ADR-0047) : la clé est le texte français, écrit
// tel quel dans le code, et chaque autre langue est un dictionnaire
// français → langue. Une clé absente d'un dictionnaire rend le français : un
// message jamais traduit reste lisible, il ne devient pas une clé technique.
// Les valeurs variables s'écrivent {0}, {1}… dans la phrase et se passent en
// arguments, pour que la traduction place la valeur où sa grammaire la veut.
//
// Ajouter une langue : un fichier `<code>.go` qui déclare sa map, puis une
// ligne dans dictionaries. Voir ADR-0137.
package i18n

import (
	"fmt"
	"net/http"
	"strings"
)

// Default est la langue des clés : celle dans laquelle le code est écrit.
const Default = "fr"

// dictionaries porte, par code de langue, le dictionnaire français → langue.
// Le français n'y figure pas : c'est la clé.
var dictionaries = map[string]map[string]string{
	"en": en,
}

// Supported dit si le serveur parle cette langue.
func Supported(code string) bool {
	if code == Default {
		return true
	}
	_, ok := dictionaries[code]
	return ok
}

// Languages liste les langues que le serveur parle, le français d'abord.
func Languages() []string {
	out := []string{Default}
	for code := range dictionaries {
		out = append(out, code)
	}
	return out
}

func primarySubtag(tag string) string {
	tag = strings.TrimSpace(tag)
	if i := strings.IndexAny(tag, "-_;"); i >= 0 {
		tag = tag[:i]
	}
	return strings.ToLower(strings.TrimSpace(tag))
}

// FromHeader lit la langue d'un en-tête Accept-Language : la première que le
// serveur parle l'emporte, comme pour les fiches (medialang.FromHeader). Pas
// d'en-tête, ou aucune langue connue, donne le français : une app d'avant ce
// réglage reçoit les messages qu'elle recevait.
//
// C'est volontairement la langue des messages, pas celle des fiches : un
// serveur dont les métadonnées sont en anglais n'a pas pour autant à répondre
// ses erreurs en anglais à une app qui ne l'a pas demandé.
func FromHeader(acceptLanguage string) string {
	for _, tag := range strings.Split(acceptLanguage, ",") {
		if code := primarySubtag(tag); code != "" && Supported(code) {
			return code
		}
	}
	return Default
}

// FromRequest est la langue que l'app annonce sur la requête.
func FromRequest(r *http.Request) string {
	return FromHeader(r.Header.Get("Accept-Language"))
}

// Key marque un texte français destiné à être traduit plus tard, quand il
// est rangé dans une variable ou rendu par une fonction avant d'arriver à
// T ou à writeJSONError. Il rend son argument tel quel : son rôle est de
// laisser le test de couverture (codeguard) lire le littéral.
func Key(fr string) string { return fr }

// T rend la phrase fr dans la langue lang, avec ses valeurs.
func T(lang, fr string, args ...any) string {
	text := fr
	if dict, ok := dictionaries[lang]; ok {
		if translated, ok := dict[fr]; ok {
			text = translated
		}
	}
	return fill(text, args)
}

// fill remplace {0}, {1}… par les arguments. Une valeur sans emplacement est
// ignorée, un emplacement sans valeur reste visible : l'oubli se voit.
func fill(text string, args []any) string {
	if len(args) == 0 || !strings.Contains(text, "{") {
		return text
	}
	pairs := make([]string, 0, 2*len(args))
	for i, a := range args {
		pairs = append(pairs, fmt.Sprintf("{%d}", i), fmt.Sprint(a))
	}
	return strings.NewReplacer(pairs...).Replace(text)
}

// Error est une erreur dont le message se traduit : un service ou un
// validateur la rend, le handler la met dans la langue de la requête avec
// writeJSONFailure. Error() reste en français, pour les journaux et les
// comparaisons existantes.
type Error struct {
	Key  string
	Args []any
}

// Errorf rend une *Error. fr est la phrase française, avec {0}, {1}… pour
// les valeurs.
func Errorf(fr string, args ...any) error { return &Error{Key: fr, Args: args} }

func (e *Error) Error() string { return fill(e.Key, e.Args) }
