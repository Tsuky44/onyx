//go:build linux || darwin

package indexer

import "golang.org/x/sys/unix"

// dirWritable demande au noyau si le serveur peut créer et effacer dans dir.
// access(2) voit aussi bien un montage en lecture seule (EROFS) que des droits
// manquants (EACCES), sans rien écrire sur le disque.
func dirWritable(dir string) error {
	return unix.Access(dir, unix.W_OK|unix.X_OK)
}
