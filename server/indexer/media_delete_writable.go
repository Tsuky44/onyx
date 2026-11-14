package indexer

import (
	"errors"
	"os"
	"path/filepath"
	"sort"
)

// Effacer un fichier, c'est écrire dans son dossier. Un dossier de médias
// monté en lecture seule (`:ro` dans docker-compose) ou qui n'appartient pas
// au compte du serveur (PUID) faisait échouer os.Remove *après* que MediaHub
// avait retiré le titre de sorraa : le fichier restait sur le disque, plus
// suivi par personne. On le vérifie donc avant de toucher à quoi que ce soit,
// pour les seuls fichiers encore là : ceux que sorraa vient d'effacer
// (ADR-0128) ne demandent rien à Onyx.

// ErrNotWritable : Onyx ne peut pas écrire dans le dossier d'un fichier du
// média, donc pas l'effacer. errors.As sur *NotWritableError donne le dossier.
var ErrNotWritable = errors.New("indexer: media folder is not writable")

// NotWritableError nomme le dossier où Onyx ne peut pas écrire.
type NotWritableError struct {
	Dir string
	Err error
}

func (e *NotWritableError) Error() string {
	return "indexer: cannot write in " + e.Dir + ": " + e.Err.Error()
}

func (e *NotWritableError) Is(target error) bool { return target == ErrNotWritable }

func (e *NotWritableError) Unwrap() error { return e.Err }

// checkWritableDirs rend une *NotWritableError pour le premier dossier où
// Onyx ne peut pas écrire parmi ceux des fichiers encore sur le disque. Un
// fichier déjà absent ne bloque rien : il compte comme supprimé (voir
// DeleteMedia).
func checkWritableDirs(files []deletableFile) error {
	seen := map[string]bool{}
	dirs := make([]string, 0, len(files))
	for _, f := range files {
		if _, err := os.Lstat(f.path); os.IsNotExist(err) {
			continue
		}
		dir := filepath.Dir(f.path)
		if !seen[dir] {
			seen[dir] = true
			dirs = append(dirs, dir)
		}
	}
	sort.Strings(dirs)
	for _, dir := range dirs {
		if err := dirWritable(dir); err != nil && !os.IsNotExist(err) {
			return &NotWritableError{Dir: dir, Err: err}
		}
	}
	return nil
}
