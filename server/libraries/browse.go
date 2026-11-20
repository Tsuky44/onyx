package libraries

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"project-player/server/safego"
)

// L'explorateur de dossiers du premier lancement (ADR-0164).
//
// SuggestFolders (ADR-0155) ne propose que les dossiers du premier niveau de
// /media. Un serveur dont les médias sont rangés plus profond
// (/media/Films/Action) obligeait encore à taper le chemin. Browse laisse
// descendre dossier par dossier, mais JAMAIS au-dessus de la racine : le
// serveur ne montre à personne le reste du disque du conteneur.

// Les bornes du comptage de vidéos. Il sert à rassurer (« ce dossier contient
// bien des films »), pas à compter : sur un partage réseau lent, le chiffre
// exact ne vaut pas l'attente.
const (
	// countMaxDepth : Séries/Une série/Saison 1/fichier est à quatre niveaux.
	countMaxDepth = 4
	// countMaxEntries borne les entrées lues par dossier proposé.
	countMaxEntries = 2000
	// countFolderBudget borne le temps d'un dossier, countTotalBudget celui de
	// toute la liste : passé l'un ou l'autre, le chiffre est dit coupé.
	countFolderBudget = 400 * time.Millisecond
	countTotalBudget  = 2 * time.Second
	// countWorkers : les dossiers se comptent en parallèle, sans saturer un
	// disque en veille ou un partage lent.
	countWorkers = 4
	// maxBrowseFolders borne la liste d'un dossier : au-delà, ce n'est plus un
	// choix de dossier mais un dossier de films.
	maxBrowseFolders = 500
)

var (
	// ErrOutsideRoot : le chemin demandé n'est pas sous la racine (ou tente
	// d'en sortir par « .. »).
	ErrOutsideRoot = errors.New("libraries: path is outside the media root")
	// ErrFolderNotFound : le dossier demandé n'existe pas (ou n'en est pas un).
	ErrFolderNotFound = errors.New("libraries: folder not found")
)

// Crumb est un maillon du fil d'Ariane : de la racine au dossier courant.
type Crumb struct {
	Name string `json:"name"`
	Path string `json:"path"`
}

// BrowsedFolder est un sous-dossier du dossier parcouru.
type BrowsedFolder struct {
	Name string `json:"name"`
	Path string `json:"path"`
	Kind Kind   `json:"kind"`
	// Covered : une bibliothèque couvre déjà ce dossier, ou un dossier qui le
	// contient. Le choisir compterait ses fichiers deux fois.
	Covered bool `json:"covered"`
	// VideoCount est borné ; VideoCountCapped dit que le comptage a été coupé
	// (profondeur, nombre d'entrées ou délai) et que le dossier en contient
	// donc au moins autant.
	VideoCount       int  `json:"video_count"`
	VideoCountCapped bool `json:"video_count_capped"`
}

// Listing est ce que rend Browse.
type Listing struct {
	// Root est le dossier au-dessus duquel on ne monte pas.
	Root string `json:"root"`
	Path string `json:"path"`
	// Parent est nil à la racine.
	Parent     *string         `json:"parent"`
	Breadcrumb []Crumb         `json:"breadcrumb"`
	Folders    []BrowsedFolder `json:"folders"`
	// Readable est faux quand le dossier existe mais que le serveur ne sait
	// pas le lire (droits, partage tombé).
	Readable bool `json:"readable"`
	// EmptyRoot : la racine est absente, illisible ou sans aucun sous-dossier.
	// C'est le cas d'un docker-compose où le dossier de médias n'est pas monté.
	EmptyRoot bool `json:"empty_root"`
}

// Browse liste les sous-dossiers de requested, sous root. requested vide est
// la racine. isVideo dit si un nom de fichier est une vidéo (l'indexeur la
// définit ; il importe ce paquet, qui ne peut donc pas l'importer).
//
// Le confinement est lexical : le chemin nettoyé doit rester sous root, et un
// segment « .. » est refusé tel quel, avant tout nettoyage. Les liens
// symboliques de dossiers sont suivis, comme SuggestFolders le fait : un
// partage monté par un lien sous /media reste un dossier de médias, et ses
// chemins restent ceux de /media.
func Browse(ctx context.Context, root, requested string, libs []Library, isVideo func(string) bool) (Listing, error) {
	root = filepath.Clean(root)
	path, err := confine(root, requested)
	if err != nil {
		return Listing{}, err
	}

	listing := Listing{
		Root:       root,
		Path:       path,
		Breadcrumb: breadcrumb(root, path),
		Folders:    []BrowsedFolder{},
	}
	if path != root {
		parent := filepath.Dir(path)
		listing.Parent = &parent
	}

	entries, readErr := os.ReadDir(path)
	if readErr == nil {
		listing.Readable = true
	} else {
		info, statErr := os.Stat(path)
		if (errors.Is(statErr, fs.ErrNotExist) && path != root) || (statErr == nil && !info.IsDir()) {
			return Listing{}, ErrFolderNotFound
		}
		// Sinon : une racine absente, ou un dossier qui existe mais ne se lit
		// pas (droits, partage tombé, boucle de liens). Ce n'est pas une
		// erreur : l'assistant doit pouvoir décrire cet état (readable,
		// empty_root).
	}

	if listing.Readable {
		listing.Folders = browsedFolders(path, entries, libs)
	}

	// La racine se juge sur elle-même, où que l'on soit.
	switch {
	case path == root:
		listing.EmptyRoot = !listing.Readable || !hasFolder(path, entries)
	default:
		rootEntries, rootErr := os.ReadDir(root)
		listing.EmptyRoot = rootErr != nil || !hasFolder(root, rootEntries)
	}

	countVideos(ctx, listing.Folders, isVideo)
	return listing, nil
}

// confine rend le chemin nettoyé de requested, ou ErrOutsideRoot.
func confine(root, requested string) (string, error) {
	requested = strings.TrimSpace(requested)
	if requested == "" {
		return root, nil
	}
	if strings.ContainsRune(requested, 0) {
		return "", ErrOutsideRoot
	}
	// « .. » est refusé avant le nettoyage : « /media/../etc » se nettoierait
	// en « /etc », et « /media/Films/../Séries » en un chemin légitime que
	// personne n'a de raison d'écrire ainsi.
	for _, segment := range strings.FieldsFunc(requested, func(r rune) bool { return r == '/' || r == '\\' }) {
		if segment == ".." {
			return "", ErrOutsideRoot
		}
	}
	// Les chemins de l'API sont ceux du conteneur, en « / » ; sous Windows
	// (essais en local), filepath.Clean les écrit en « \ ».
	path := filepath.Clean(filepath.FromSlash(requested))
	if !within(root, path) {
		return "", ErrOutsideRoot
	}
	return path, nil
}

// within dit si path est root ou un dossier sous root, par composants entiers :
// « /media-autre » n'est pas sous « /media ».
func within(root, path string) bool {
	if path == root {
		return true
	}
	prefix := root
	if !strings.HasSuffix(prefix, string(filepath.Separator)) {
		prefix += string(filepath.Separator)
	}
	return strings.HasPrefix(path, prefix)
}

func breadcrumb(root, path string) []Crumb {
	crumbs := []Crumb{{Name: filepath.Base(root), Path: root}}
	if path == root {
		return crumbs
	}
	current := root
	rel := strings.TrimPrefix(path, root)
	for _, segment := range strings.Split(strings.Trim(rel, string(filepath.Separator)), string(filepath.Separator)) {
		if segment == "" {
			continue
		}
		current = filepath.Join(current, segment)
		crumbs = append(crumbs, Crumb{Name: segment, Path: current})
	}
	return crumbs
}

func hasFolder(dir string, entries []fs.DirEntry) bool {
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), ".") && isFolder(entry, filepath.Join(dir, entry.Name())) {
			return true
		}
	}
	return false
}

func browsedFolders(dir string, entries []fs.DirEntry, libs []Library) []BrowsedFolder {
	folders := []BrowsedFolder{}
	for _, entry := range entries {
		name := entry.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		path := filepath.Join(dir, name)
		if !isFolder(entry, path) {
			continue
		}
		folders = append(folders, BrowsedFolder{
			Name:    name,
			Path:    path,
			Kind:    GuessKind(name),
			Covered: covers(libs, path),
		})
	}
	sort.SliceStable(folders, func(i, j int) bool {
		return strings.ToLower(folders[i].Name) < strings.ToLower(folders[j].Name)
	})
	if len(folders) > maxBrowseFolders {
		folders = folders[:maxBrowseFolders]
	}
	return folders
}

// countVideos remplit VideoCount de chaque dossier, en parallèle et dans le
// délai total : un dossier que le délai a coupé est dit coupé, pas vide.
func countVideos(ctx context.Context, folders []BrowsedFolder, isVideo func(string) bool) {
	if len(folders) == 0 || isVideo == nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, countTotalBudget)
	defer cancel()

	var wg sync.WaitGroup
	slots := make(chan struct{}, countWorkers)
	for i := range folders {
		wg.Add(1)
		slots <- struct{}{}
		folder := &folders[i]
		go safego.Run("libraries.countVideos", func() {
			defer wg.Done()
			defer func() { <-slots }()
			folderCtx, folderCancel := context.WithTimeout(ctx, countFolderBudget)
			defer folderCancel()
			folder.VideoCount, folder.VideoCountCapped = countFolderVideos(folderCtx, folder.Path, isVideo)
		})
	}
	wg.Wait()
}

// countFolderVideos compte les vidéos de dir : en largeur, jusqu'à
// countMaxDepth niveaux et countMaxEntries entrées. Le second résultat est vrai
// quand une borne a coupé le parcours. Les dossiers cachés sont ignorés, et un
// lien de dossier est suivi : la profondeur borne aussi une boucle de liens.
func countFolderVideos(ctx context.Context, dir string, isVideo func(string) bool) (count int, capped bool) {
	type level struct {
		path  string
		depth int
	}
	queue := []level{{dir, 1}}
	seen := 0
	for len(queue) > 0 {
		current := queue[0]
		queue = queue[1:]
		if ctx.Err() != nil {
			return count, true
		}
		entries, err := os.ReadDir(current.path)
		if err != nil {
			// Un sous-dossier illisible ne compte rien ; il ne coupe pas le
			// comptage des autres.
			continue
		}
		for _, entry := range entries {
			name := entry.Name()
			if strings.HasPrefix(name, ".") {
				continue
			}
			seen++
			if seen > countMaxEntries {
				return count, true
			}
			path := filepath.Join(current.path, name)
			if isFolder(entry, path) {
				if current.depth >= countMaxDepth {
					capped = true
					continue
				}
				queue = append(queue, level{path, current.depth + 1})
				continue
			}
			if isVideo(name) {
				count++
			}
		}
	}
	return count, capped
}

// covers dit si une bibliothèque de libs est ce dossier ou le contient.
func covers(libs []Library, path string) bool {
	for _, lib := range libs {
		taken := filepath.Clean(lib.Path)
		// Le dossier d'une bibliothèque, ou un dossier dans le sien : ses
		// fichiers seraient comptés deux fois.
		if path == taken || strings.HasPrefix(path, taken+string(filepath.Separator)) {
			return true
		}
	}
	return false
}
