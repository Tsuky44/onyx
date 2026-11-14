//go:build !linux && !darwin

package indexer

// dirWritable ne vérifie rien hors Linux et macOS : sous Windows, les droits
// d'un dossier passent par des ACL qu'access(2) ne sait pas lire. L'échec
// éventuel de l'effacement le dira, comme avant.
func dirWritable(string) error { return nil }
