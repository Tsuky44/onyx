package libraries

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func mkdirs(t *testing.T, root string, names ...string) {
	t.Helper()
	for _, name := range names {
		if err := os.MkdirAll(filepath.Join(root, name), 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", name, err)
		}
	}
}

func TestGuessKindReadsTheFolderName(t *testing.T) {
	for _, tc := range []struct {
		name string
		want Kind
	}{
		{"Films", KindMovies},
		{"films 4K", KindMovies},
		{"Movies", KindMovies},
		{"Cinéma", KindMovies},
		{"Séries", KindShows},
		{"Series", KindShows},
		{"TV Shows", KindShows},
		{"TV", KindShows},
		{"Animés TV", KindShows},
		{"Concerts", KindOther},
		{"Vidéos de famille", KindOther},
		{"TVA", KindOther},
	} {
		if got := GuessKind(tc.name); got != tc.want {
			t.Errorf("GuessKind(%q) = %q, want %q", tc.name, got, tc.want)
		}
	}
}

// Les films d'abord, puis les séries, puis le reste : la première proposition
// est celle que l'app préremplit, et un serveur neuf crée ses films avant ses
// séries.
func TestSuggestFoldersPutsMoviesThenShowsThenTheRest(t *testing.T) {
	root := t.TempDir()
	mkdirs(t, root, "Concerts", "Séries", "Films", ".Trash", "Animes")
	if err := os.WriteFile(filepath.Join(root, "lisez-moi.txt"), nil, 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := SuggestFolders(root, nil)
	if err != nil {
		t.Fatal(err)
	}
	want := []Folder{
		{Path: filepath.Join(root, "Films"), Name: "Films", Kind: KindMovies},
		{Path: filepath.Join(root, "Séries"), Name: "Séries", Kind: KindShows},
		{Path: filepath.Join(root, "Animes"), Name: "Animes", Kind: KindOther},
		{Path: filepath.Join(root, "Concerts"), Name: "Concerts", Kind: KindOther},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("SuggestFolders = %+v, want %+v (ni fichier ni dossier caché)", got, want)
	}
}

// Un dossier déjà pris, ou dans un dossier pris, compterait ses fichiers deux
// fois.
func TestSuggestFoldersSkipsWhatALibraryCovers(t *testing.T) {
	root := t.TempDir()
	mkdirs(t, root, "Films", "Séries", "Séries/Animés")
	libs := []Library{{Name: "Films", Kind: KindMovies, Path: filepath.Join(root, "Films")}}

	got, err := SuggestFolders(root, libs)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Name != "Séries" {
		t.Fatalf("SuggestFolders = %+v, want Séries only", got)
	}

	libs = append(libs, Library{Name: "Séries", Kind: KindShows, Path: filepath.Join(root, "Séries")})
	if got, _ := SuggestFolders(root, libs); len(got) != 0 {
		t.Fatalf("SuggestFolders = %+v, want nothing left", got)
	}
}

// Un seul dossier monté tel quel sur /media : c'est lui qu'on propose.
func TestSuggestFoldersOffersTheRootWhenItHoldsNoFolder(t *testing.T) {
	parent := t.TempDir()
	mkdirs(t, parent, "Films")
	root := filepath.Join(parent, "Films")

	got, err := SuggestFolders(root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Path != root || got[0].Kind != KindMovies {
		t.Fatalf("SuggestFolders = %+v, want the root itself", got)
	}
	if got, _ := SuggestFolders(root, []Library{{Path: root}}); len(got) != 0 {
		t.Fatalf("SuggestFolders = %+v, want nothing once the root is a library", got)
	}
}

// Hors de Docker, /media n'existe pas : rien à proposer, sans erreur.
func TestSuggestFoldersWithoutRootIsEmpty(t *testing.T) {
	got, err := SuggestFolders(filepath.Join(t.TempDir(), "absent"), nil)
	if err != nil || got == nil || len(got) != 0 {
		t.Fatalf("SuggestFolders = %+v, %v; want an empty list", got, err)
	}
}

func TestMediaRootFollowsTheEnvironment(t *testing.T) {
	t.Setenv("MEDIA_ROOT", "")
	if got := MediaRoot(); got != DefaultMediaRoot {
		t.Fatalf("MediaRoot() = %q, want %q", got, DefaultMediaRoot)
	}
	t.Setenv("MEDIA_ROOT", "/mnt/medias/")
	if got := MediaRoot(); got != "/mnt/medias" {
		t.Fatalf("MediaRoot() = %q, want /mnt/medias", got)
	}
}
