package libraries

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Les dossiers que l'app propose quand on crée une bibliothèque (ADR-0155).
//
// Le docker-compose monte les médias de l'hôte sous un seul dossier du
// conteneur, /media. Taper « /media/Films » à la main demandait de savoir ce
// que le conteneur voit, et une faute de frappe ne se disait qu'au moment
// d'enregistrer : le serveur liste donc ce qu'il trouve là, et l'app
// préremplit le formulaire avec.

// DefaultMediaRoot est le dossier où le docker-compose monte les médias.
const DefaultMediaRoot = "/media"

// maxFolders borne la liste : au-delà, ce n'est plus un dossier de
// bibliothèques mais un dossier de films, et le choix se tape à la main.
const maxFolders = 50

// MediaRoot est le dossier dont les sous-dossiers sont proposés :
// MEDIA_ROOT, sinon [DefaultMediaRoot].
func MediaRoot() string {
	if root := strings.TrimSpace(os.Getenv("MEDIA_ROOT")); root != "" {
		return filepath.Clean(root)
	}
	return DefaultMediaRoot
}

// Folder est un dossier proposé, et le type que son nom laisse deviner.
type Folder struct {
	Path string `json:"path"`
	Name string `json:"name"`
	Kind Kind   `json:"kind"`
}

// SuggestFolders liste les dossiers de root qu'aucune bibliothèque de libs ne
// couvre encore : les films d'abord, puis les séries, puis le reste, chacun par
// ordre alphabétique. Un root sans sous-dossier est lui-même proposé : c'est
// alors un seul dossier de médias, monté tel quel.
//
// Un root absent n'est pas une erreur : un serveur lancé hors de Docker n'a
// pas de /media, et le formulaire reste à remplir à la main.
func SuggestFolders(root string, libs []Library) ([]Folder, error) {
	root = filepath.Clean(root)
	entries, err := os.ReadDir(root)
	if errors.Is(err, fs.ErrNotExist) {
		return []Folder{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("libraries: read %s: %w", root, err)
	}

	covered := func(path string) bool { return covers(libs, path) }

	folders := []Folder{}
	sawFolder := false
	for _, entry := range entries {
		name := entry.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		path := filepath.Join(root, name)
		if !isFolder(entry, path) {
			continue
		}
		sawFolder = true
		if covered(path) {
			continue
		}
		folders = append(folders, Folder{Path: path, Name: name, Kind: GuessKind(name)})
	}
	if !sawFolder && !covered(root) {
		folders = append(folders, Folder{Path: root, Name: filepath.Base(root), Kind: GuessKind(filepath.Base(root))})
	}

	sort.SliceStable(folders, func(i, j int) bool {
		if a, b := kindRank(folders[i].Kind), kindRank(folders[j].Kind); a != b {
			return a < b
		}
		return strings.ToLower(folders[i].Name) < strings.ToLower(folders[j].Name)
	})
	if len(folders) > maxFolders {
		folders = folders[:maxFolders]
	}
	return folders, nil
}

// isFolder suit un lien symbolique : un partage monté par un lien reste un
// dossier de médias.
func isFolder(entry fs.DirEntry, path string) bool {
	if entry.IsDir() {
		return true
	}
	if entry.Type()&fs.ModeSymlink == 0 {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func kindRank(kind Kind) int {
	switch kind {
	case KindMovies:
		return 0
	case KindShows:
		return 1
	}
	return 2
}

var accentFold = strings.NewReplacer(
	"é", "e", "è", "e", "ê", "e", "ë", "e",
	"à", "a", "â", "a", "î", "i", "ï", "i",
	"ô", "o", "û", "u", "ù", "u", "ç", "c",
)

// GuessKind lit le type d'un dossier dans son nom : « Films », « Movies »,
// « Cinéma » sont des films ; « Séries », « TV Shows », « TV » des séries. Le
// reste est « Autre », que l'administrateur corrige d'un geste.
func GuessKind(name string) Kind {
	n := accentFold.Replace(strings.ToLower(strings.TrimSpace(name)))
	switch {
	case strings.Contains(n, "film") || strings.Contains(n, "movie") || strings.Contains(n, "cinema"):
		return KindMovies
	case strings.Contains(n, "serie") || strings.Contains(n, "show") ||
		n == "tv" || strings.HasPrefix(n, "tv ") || strings.HasSuffix(n, " tv"):
		return KindShows
	}
	return KindOther
}
