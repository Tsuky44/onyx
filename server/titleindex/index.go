// Package titleindex complète les titres connus de TMDB à partir de ce qu'on
// commence à taper (ADR-0135).
//
// La recherche de TMDB cherche des mots entiers : « bat » ne trouve pas
// Batman, même parmi ses 10 000 résultats. TMDB publie chaque jour, sans clé,
// la liste de tous ses films et séries avec leur popularité ; le serveur en
// garde les titres un minimum connus dans une base SQLite à part, indexée par
// début de mot, et y cherche les titres qui commencent par la requête.
package titleindex

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"

	_ "modernc.org/sqlite"
)

// Hit est un titre de l'index : l'identifiant TMDB, le type (movie ou tv),
// le titre original et la popularité du jour de l'export.
type Hit struct {
	ID         int
	MediaType  string
	Title      string
	Popularity float64
}

// Index est la base des titres connus. Elle vit dans son propre fichier, à
// côté de la base du serveur : c'est un cache refait chaque jour, qui n'a rien
// à faire dans les sauvegardes et qu'on peut supprimer sans rien perdre.
type Index struct {
	db *sql.DB
}

// schema range le titre passé par Fold dans la colonne indexée (FTS5, préfixes
// de 2 et 3 lettres précalculés pour les premières frappes). Le reste est
// stocké sans index.
const schema = `
CREATE VIRTUAL TABLE IF NOT EXISTS titles USING fts5(
	folded,
	title UNINDEXED,
	media_type UNINDEXED,
	tmdb_id UNINDEXED,
	popularity UNINDEXED,
	tokenize = 'unicode61',
	prefix = '2 3'
);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
`

// Open ouvre (ou crée) l'index au chemin path.
func Open(path string) (*Index, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=synchronous(NORMAL)")
	if err != nil {
		return nil, fmt.Errorf("titleindex: ouverture %s: %w", path, err)
	}
	db.SetMaxOpenConns(2)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("titleindex: schéma: %w", err)
	}
	return &Index{db: db}, nil
}

// Close ferme la base.
func (ix *Index) Close() error { return ix.db.Close() }

// tvPopularityScale ramène la popularité d'une série à l'échelle des films.
// Mesuré sur l'export du 15/11/2026 : autant de films ont une popularité d'au
// moins 1 que de séries d'au moins 3 (environ 40 000), et The Office (série)
// est à 1 740 quand The Dark Knight est à 83. Sans ce facteur, « Batang
// Quiapo » (série, 57) passait devant tous les films Batman.
const tvPopularityScale = 3.0

// NormalizedPopularity est la popularité de TMDB, ramenée à l'échelle des
// films pour une série.
func NormalizedPopularity(mediaType string, popularity float64) float64 {
	popularity = max(popularity, 0)
	if mediaType == "tv" {
		return popularity / tvPopularityScale
	}
	return popularity
}

// suggestCandidates borne les titres lus pour une requête avant de les
// reclasser : les plus populaires d'abord, une première lettre peut en
// toucher des dizaines de milliers.
const suggestCandidates = 300

// Suggest rend au plus limit titres de l'index qui correspondent à query,
// du plus pertinent au moins pertinent. mediaType limite à "movie" ou "tv" ;
// vide, les deux. Un index encore vide ne rend rien.
func (ix *Index) Suggest(ctx context.Context, query, mediaType string, limit int) ([]Hit, error) {
	folded := Fold(query)
	match := ftsPrefixQuery(folded)
	if match == "" || limit <= 0 {
		return nil, nil
	}
	sqlQuery := `SELECT tmdb_id, media_type, title, popularity FROM titles WHERE titles MATCH ?`
	args := []any{match}
	if mediaType == "movie" || mediaType == "tv" {
		sqlQuery += ` AND media_type = ?`
		args = append(args, mediaType)
	}
	sqlQuery += fmt.Sprintf(` ORDER BY CASE media_type WHEN 'tv' THEN popularity / %g ELSE popularity END DESC LIMIT %d`,
		tvPopularityScale, suggestCandidates)

	rows, err := ix.db.QueryContext(ctx, sqlQuery, args...)
	if err != nil {
		return nil, fmt.Errorf("titleindex: suggestion %q: %w", query, err)
	}
	defer rows.Close()
	var hits []Hit
	for rows.Next() {
		var h Hit
		if err := rows.Scan(&h.ID, &h.MediaType, &h.Title, &h.Popularity); err != nil {
			return nil, fmt.Errorf("titleindex: lecture: %w", err)
		}
		hits = append(hits, h)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("titleindex: lecture: %w", err)
	}

	score := func(h Hit) float64 {
		return MatchWeight(folded, h.Title) * (1 + math.Log1p(NormalizedPopularity(h.MediaType, h.Popularity)))
	}
	sort.SliceStable(hits, func(a, b int) bool { return score(hits[a]) > score(hits[b]) })
	return hits[:min(limit, len(hits))], nil
}

// ftsPrefixQuery change la requête pliée en requête FTS5 où chaque mot est un
// début de mot : « dark kni » → `"dark"* "kni"*`. Fold ne laisse que des
// lettres, des chiffres et des espaces : les guillemets ne peuvent pas être
// cassés. Un mot d'une lettre (« l » de « l'empire ») toucherait presque tout
// l'index : il ne compte que s'il est seul et la requête est alors trop
// courte pour suggérer quoi que ce soit.
func ftsPrefixQuery(folded string) string {
	var terms []string
	for _, word := range strings.Fields(folded) {
		if len([]rune(word)) < 2 {
			continue
		}
		terms = append(terms, `"`+word+`"*`)
	}
	return strings.Join(terms, " ")
}

// BuiltFor rend le jour de l'export (AAAA-MM-JJ) que l'index contient, ou ""
// s'il n'a jamais été rempli.
func (ix *Index) BuiltFor(ctx context.Context) (string, error) {
	var day string
	err := ix.db.QueryRowContext(ctx, `SELECT value FROM meta WHERE key = 'built_for'`).Scan(&day)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("titleindex: date de l'index: %w", err)
	}
	return day, nil
}

// replace remplace tout l'index par les titres que fill écrit avec add, en
// une transaction : un téléchargement coupé laisse l'index de la veille.
func (ix *Index) replace(ctx context.Context, day string, fill func(add func(Hit) error) error) (int, error) {
	tx, err := ix.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("titleindex: transaction: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx, `DELETE FROM titles`); err != nil {
		return 0, fmt.Errorf("titleindex: vidage: %w", err)
	}
	insert, err := tx.PrepareContext(ctx,
		`INSERT INTO titles (folded, title, media_type, tmdb_id, popularity) VALUES (?, ?, ?, ?, ?)`)
	if err != nil {
		return 0, fmt.Errorf("titleindex: préparation: %w", err)
	}
	defer insert.Close()

	count := 0
	err = fill(func(h Hit) error {
		folded := Fold(h.Title)
		if folded == "" {
			return nil
		}
		if _, err := insert.ExecContext(ctx, folded, h.Title, h.MediaType, h.ID, h.Popularity); err != nil {
			return fmt.Errorf("titleindex: ajout de %d: %w", h.ID, err)
		}
		count++
		return nil
	})
	if err != nil {
		return 0, err
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO meta (key, value) VALUES ('built_for', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value`, day); err != nil {
		return 0, fmt.Errorf("titleindex: date de l'index: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return 0, fmt.Errorf("titleindex: validation: %w", err)
	}
	// Les pages libérées par la veille servent au lendemain ; on rend
	// seulement le journal WAL, qui a grossi de tout l'index.
	if _, err := ix.db.ExecContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		return count, fmt.Errorf("titleindex: checkpoint: %w", err)
	}
	return count, nil
}
