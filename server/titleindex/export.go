package titleindex

import (
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Les exports quotidiens de TMDB : un objet JSON par ligne, sans clé
// (https://developer.themoviedb.org/docs/daily-id-exports). Générés vers 7 h
// UTC, disponibles vers 8 h, gardés trois mois.
const exportBaseURL = "https://files.tmdb.org/p/exports/"

// export décrit un des deux fichiers lus : le nom, le champ du titre et le
// seuil de popularité sous lequel un titre n'est pas gardé.
//
// Seuils choisis sur l'export du 15/11/2026 (1,45 million de titres) : un
// film à 1 (« Les Visiteurs » 4,3, « Itinéraire d'un enfant gâté » 1,8 ;
// en dessous, surtout des films que personne ne cherche), une série à 2,
// leur échelle étant plus haute (« Pride and Prejudice », BBC 1995, est à
// 2,1). Reste environ 42 000 films et 51 000 séries. Un titre sous le seuil
// reste trouvable par la recherche de TMDB, tapé en mots entiers.
type export struct {
	name          string
	mediaType     string
	titleField    string
	minPopularity float64
}

var exports = []export{
	{name: "movie_ids", mediaType: "movie", titleField: "original_title", minPopularity: 1},
	{name: "tv_series_ids", mediaType: "tv", titleField: "original_name", minPopularity: 2},
}

// exportLine est une ligne d'un export : les deux champs de titre, l'un ou
// l'autre selon le fichier.
type exportLine struct {
	ID            int     `json:"id"`
	OriginalTitle string  `json:"original_title"`
	OriginalName  string  `json:"original_name"`
	Popularity    float64 `json:"popularity"`
	Adult         bool    `json:"adult"`
	Video         bool    `json:"video"`
}

// exportDay est le jour du dernier export qu'on peut espérer trouver à now :
// celui du jour passé 9 h UTC, celui de la veille avant.
func exportDay(now time.Time) time.Time {
	day := now.UTC().Add(-9 * time.Hour)
	return time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, time.UTC)
}

func exportURL(base, name string, day time.Time) string {
	return fmt.Sprintf("%s%s_%s.json.gz", base, name, day.Format("01_02_2006"))
}

// errExportMissing dit qu'un export n'est pas (encore) publié.
var errExportMissing = errors.New("export TMDB absent")

// readExport lit un export gzip de r et passe à add chaque titre au-dessus du
// seuil de e. Ni film pour adultes ni simple vidéo (bande-annonce, bonus).
func readExport(r io.Reader, e export, add func(Hit) error) error {
	gz, err := gzip.NewReader(r)
	if err != nil {
		return fmt.Errorf("%s: gzip: %w", e.name, err)
	}
	defer gz.Close()
	dec := json.NewDecoder(gz)
	for {
		var line exportLine
		err := dec.Decode(&line)
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("%s: ligne illisible: %w", e.name, err)
		}
		if line.Adult || line.Video || line.Popularity < e.minPopularity || line.ID <= 0 {
			continue
		}
		title := line.OriginalTitle
		if e.titleField == "original_name" {
			title = line.OriginalName
		}
		if title == "" {
			continue
		}
		if err := add(Hit{ID: line.ID, MediaType: e.mediaType, Title: title, Popularity: line.Popularity}); err != nil {
			return err
		}
	}
}

// Refresher télécharge les exports et remplit l'index.
type Refresher struct {
	Index  *Index
	Client *http.Client
	// BaseURL remplace exportBaseURL dans les tests.
	BaseURL string
}

// Refresh remplit l'index avec les exports de day. Les deux fichiers entrent
// dans la même transaction : il n'y a jamais les films d'un jour sans ses
// séries. Rend errExportMissing si l'un n'est pas publié.
func (r Refresher) Refresh(ctx context.Context, day time.Time) (int, error) {
	base := r.BaseURL
	if base == "" {
		base = exportBaseURL
	}
	return r.Index.replace(ctx, day.Format("2006-01-02"), func(add func(Hit) error) error {
		for _, e := range exports {
			if err := r.download(ctx, exportURL(base, e.name, day), e, add); err != nil {
				return err
			}
		}
		return nil
	})
}

func (r Refresher) download(ctx context.Context, url string, e export, add func(Hit) error) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("%s: requête: %w", e.name, err)
	}
	resp, err := r.Client.Do(req)
	if err != nil {
		return fmt.Errorf("%s: téléchargement: %w", e.name, err)
	}
	defer resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusForbidden:
		// files.tmdb.org rend 403 pour un fichier qui n'existe pas encore.
		return fmt.Errorf("%s: %w", e.name, errExportMissing)
	case resp.StatusCode != http.StatusOK:
		return fmt.Errorf("%s: statut %d", e.name, resp.StatusCode)
	}
	return readExport(resp.Body, e, add)
}
