package libraries

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
)

func isMKV(name string) bool { return strings.HasSuffix(strings.ToLower(name), ".mkv") }

func touch(t *testing.T, paths ...string) {
	t.Helper()
	for _, path := range paths {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func browse(t *testing.T, root, requested string, libs ...Library) Listing {
	t.Helper()
	listing, err := Browse(context.Background(), root, requested, libs, isMKV)
	if err != nil {
		t.Fatalf("Browse(%q): %v", requested, err)
	}
	return listing
}

// Le garde essentiel de l'explorateur : aucune demande ne sort de la racine,
// quelle que soit la forme du chemin.
func TestBrowseNeverLeavesTheRoot(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "media")
	// Un voisin dont le nom commence comme la racine : un contrôle par
	// préfixe de chaîne le laisserait passer.
	mkdirs(t, parent, "media", "media-autre", "secret")

	for name, requested := range map[string]string{
		"parent par ..":             root + "/..",
		"échappée au milieu":        root + "/Films/../../secret",
		"échappée par le début":     "../secret",
		"segment .. relatif":        "Films/../..",
		"antislash":                 root + `\..\secret`,
		"voisin au même préfixe":    filepath.Join(parent, "media-autre"),
		"autre dossier du disque":   parent,
		"dossier absolu quelconque": "/etc",
		"chemin relatif":            "Films",
		"octet nul":                 root + "/Films\x00/..",
	} {
		t.Run(name, func(t *testing.T) {
			listing, err := Browse(context.Background(), root, requested, nil, isMKV)
			if !errors.Is(err, ErrOutsideRoot) {
				t.Fatalf("Browse(%q) = %+v, %v; want ErrOutsideRoot", requested, listing, err)
			}
		})
	}
}

// Un lien symbolique de dossier se suit, comme le fait SuggestFolders : un
// partage monté par un lien sous /media reste un dossier de médias. Ses chemins
// restent ceux de la racine, jamais ceux de sa cible.
func TestBrowseFollowsFolderSymlinksWithoutExposingTheirTarget(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "media")
	nas := filepath.Join(parent, "nas")
	mkdirs(t, parent, "media", "nas/Action")
	touch(t, filepath.Join(nas, "Action", "a.mkv"))
	if err := os.Symlink(nas, filepath.Join(root, "Partage")); err != nil {
		t.Skipf("pas de lien symbolique ici : %v", err)
	}

	top := browse(t, root, "")
	if len(top.Folders) != 1 || top.Folders[0].Path != filepath.Join(root, "Partage") || top.Folders[0].VideoCount != 1 {
		t.Fatalf("racine = %+v, want le lien Partage comme dossier, avec sa vidéo", top.Folders)
	}

	inside := browse(t, root, filepath.Join(root, "Partage"))
	if len(inside.Folders) != 1 || inside.Folders[0].Path != filepath.Join(root, "Partage", "Action") {
		t.Fatalf("dans le lien = %+v, want Action sous le chemin du lien", inside.Folders)
	}
	if inside.Parent == nil || *inside.Parent != root {
		t.Fatalf("parent = %v, want la racine (jamais le dossier cible)", inside.Parent)
	}
	for _, crumb := range inside.Breadcrumb {
		if strings.Contains(crumb.Path, "nas") {
			t.Fatalf("fil d'Ariane %+v : il laisse voir la cible du lien", inside.Breadcrumb)
		}
	}

	// Le chemin de la cible, lui, est hors racine.
	if _, err := Browse(context.Background(), root, nas, nil, isMKV); !errors.Is(err, ErrOutsideRoot) {
		t.Fatalf("Browse(cible du lien) = %v, want ErrOutsideRoot", err)
	}
}

func TestBrowseListsTheRootThenAFolderWithItsBreadcrumb(t *testing.T) {
	root := filepath.Join(t.TempDir(), "media")
	mkdirs(t, root, "Séries", "Films/Action", "Films/Drame", "Concerts", ".Trash")
	touch(t, filepath.Join(root, "lisez-moi.txt"))

	top := browse(t, root, "")
	if top.Root != root || top.Path != root || top.Parent != nil || !top.Readable || top.EmptyRoot {
		t.Fatalf("racine = %+v", top)
	}
	if want := []Crumb{{Name: "media", Path: root}}; !reflect.DeepEqual(top.Breadcrumb, want) {
		t.Fatalf("fil d'Ariane = %+v, want %+v", top.Breadcrumb, want)
	}
	var names []string
	kinds := map[string]Kind{}
	for _, folder := range top.Folders {
		names = append(names, folder.Name)
		kinds[folder.Name] = folder.Kind
	}
	// Par ordre alphabétique, sans fichier ni dossier caché.
	if want := []string{"Concerts", "Films", "Séries"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("dossiers = %v, want %v", names, want)
	}
	if kinds["Films"] != KindMovies || kinds["Séries"] != KindShows || kinds["Concerts"] != KindOther {
		t.Fatalf("types = %v", kinds)
	}

	films := browse(t, root, filepath.Join(root, "Films"))
	if films.Parent == nil || *films.Parent != root {
		t.Fatalf("parent = %v, want %s", films.Parent, root)
	}
	wantCrumbs := []Crumb{{Name: "media", Path: root}, {Name: "Films", Path: filepath.Join(root, "Films")}}
	if !reflect.DeepEqual(films.Breadcrumb, wantCrumbs) {
		t.Fatalf("fil d'Ariane = %+v, want %+v", films.Breadcrumb, wantCrumbs)
	}
	if len(films.Folders) != 2 || films.Folders[0].Name != "Action" || films.EmptyRoot {
		t.Fatalf("Films = %+v", films)
	}

	// Un chemin avec une barre finale ou un « . » se nettoie sans sortir.
	if again := browse(t, root, filepath.Join(root, "Films")+"/./"); again.Path != films.Path {
		t.Fatalf("chemin nettoyé = %q, want %q", again.Path, films.Path)
	}
}

func TestBrowseMarksWhatALibraryAlreadyCovers(t *testing.T) {
	root := filepath.Join(t.TempDir(), "media")
	mkdirs(t, root, "Films/Action", "Séries", "Concerts")
	libs := []Library{
		{Path: filepath.Join(root, "Films")},
		{Path: filepath.Join(root, "Séries", "Anime")},
	}

	covered := func(listing Listing) map[string]bool {
		out := map[string]bool{}
		for _, folder := range listing.Folders {
			out[folder.Name] = folder.Covered
		}
		return out
	}
	top := covered(browse(t, root, "", libs...))
	if !top["Films"] || top["Séries"] || top["Concerts"] {
		t.Fatalf("couverts à la racine = %v, want Films seul (Séries ne contient qu'une bibliothèque)", top)
	}
	// Dans une bibliothèque, tout est couvert.
	if inside := covered(browse(t, root, filepath.Join(root, "Films"), libs...)); !inside["Action"] {
		t.Fatalf("couverts dans Films = %v, want Action couvert", inside)
	}
}

func TestBrowseNotFound(t *testing.T) {
	root := filepath.Join(t.TempDir(), "media")
	mkdirs(t, root, "Films")
	touch(t, filepath.Join(root, "Films", "a.mkv"))

	for name, requested := range map[string]string{
		"dossier absent":      filepath.Join(root, "Absent"),
		"un fichier":          filepath.Join(root, "Films", "a.mkv"),
		"absent plus profond": filepath.Join(root, "Absent", "Plus", "Loin"),
	} {
		if _, err := Browse(context.Background(), root, requested, nil, isMKV); !errors.Is(err, ErrFolderNotFound) {
			t.Errorf("%s : Browse = %v, want ErrFolderNotFound", name, err)
		}
	}
}

// La racine absente n'est pas une erreur : c'est le diagnostic « montez votre
// dossier dans le compose ».
func TestBrowseDiagnosesAnEmptyOrMissingRoot(t *testing.T) {
	parent := t.TempDir()

	missing := browse(t, filepath.Join(parent, "absente"), "")
	if missing.Readable || !missing.EmptyRoot || len(missing.Folders) != 0 || missing.Parent != nil {
		t.Fatalf("racine absente = %+v", missing)
	}

	empty := filepath.Join(parent, "vide")
	mkdirs(t, parent, "vide")
	if listing := browse(t, empty, ""); !listing.Readable || !listing.EmptyRoot {
		t.Fatalf("racine vide = %+v", listing)
	}

	// Des fichiers sans dossier : rien à choisir, c'est encore une racine vide.
	filesOnly := filepath.Join(parent, "fichiers")
	touch(t, filepath.Join(filesOnly, "a.mkv"))
	if listing := browse(t, filesOnly, ""); !listing.EmptyRoot {
		t.Fatalf("racine sans dossier = %+v", listing)
	}

	// Un dossier caché n'est pas un dossier à choisir.
	hiddenOnly := filepath.Join(parent, "cache")
	mkdirs(t, hiddenOnly, ".Trash")
	if listing := browse(t, hiddenOnly, ""); !listing.EmptyRoot {
		t.Fatalf("racine à dossier caché = %+v", listing)
	}
}

func TestBrowseCountsVideosWithinItsLimits(t *testing.T) {
	root := filepath.Join(t.TempDir(), "media")
	touch(t,
		filepath.Join(root, "Films", "Un (2020)", "un.mkv"),
		filepath.Join(root, "Films", "Deux.MKV"),
		filepath.Join(root, "Films", "notes.txt"),
		filepath.Join(root, "Films", ".cache", "caché.mkv"),
		// Séries/Série/Saison/épisode : le niveau le plus profond d'une série.
		filepath.Join(root, "Séries", "S", "Saison 1", "e1.mkv"),
		filepath.Join(root, "Profond", "a", "b", "c", "d", "trop-loin.mkv"),
		filepath.Join(root, "Profond", "a", "b", "proche.mkv"),
	)
	mkdirs(t, root, "Vide")

	got := map[string]BrowsedFolder{}
	for _, folder := range browse(t, root, "").Folders {
		got[folder.Name] = folder
	}
	for name, want := range map[string]struct {
		count  int
		capped bool
	}{
		"Films":   {2, false},
		"Séries":  {1, false},
		"Vide":    {0, false},
		"Profond": {1, true},
	} {
		if folder := got[name]; folder.VideoCount != want.count || folder.VideoCountCapped != want.capped {
			t.Errorf("%s : %d vidéo(s), coupé %v ; want %d, %v", name, folder.VideoCount, folder.VideoCountCapped, want.count, want.capped)
		}
	}
}

func TestBrowseCapsTheNumberOfEntriesItReads(t *testing.T) {
	root := filepath.Join(t.TempDir(), "media")
	dir := filepath.Join(root, "Gros")
	mkdirs(t, root, "Gros")
	for i := 0; i < countMaxEntries+5; i++ {
		touch(t, filepath.Join(dir, "f"+strconv.Itoa(i)+".mkv"))
	}
	folder := browse(t, root, "").Folders[0]
	if !folder.VideoCountCapped || folder.VideoCount != countMaxEntries {
		t.Fatalf("Gros = %d vidéos, coupé %v ; want %d et coupé", folder.VideoCount, folder.VideoCountCapped, countMaxEntries)
	}
}

// Un délai dépassé dit « coupé », pas « vide » : l'utilisateur ne doit pas
// croire qu'un dossier plein est vide.
func TestBrowseSaysCappedWhenTheTimeIsUp(t *testing.T) {
	root := filepath.Join(t.TempDir(), "media")
	touch(t, filepath.Join(root, "Films", "a.mkv"))

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	listing, err := Browse(ctx, root, "", nil, isMKV)
	if err != nil {
		t.Fatal(err)
	}
	if folder := listing.Folders[0]; !folder.VideoCountCapped {
		t.Fatalf("Films = %+v, want un comptage coupé", folder)
	}
}

// Une boucle de liens (un lien qui remonte vers son parent) ne fait pas tourner
// le comptage : la profondeur le borne.
func TestBrowseCountStopsOnASymlinkLoop(t *testing.T) {
	root := filepath.Join(t.TempDir(), "media")
	touch(t, filepath.Join(root, "Films", "a.mkv"))
	if err := os.Symlink(filepath.Join(root, "Films"), filepath.Join(root, "Films", "boucle")); err != nil {
		t.Skipf("pas de lien symbolique ici : %v", err)
	}
	folder := browse(t, root, "").Folders[0]
	if !folder.VideoCountCapped || folder.VideoCount < 1 {
		t.Fatalf("Films = %+v, want un comptage borné par la profondeur", folder)
	}
}
