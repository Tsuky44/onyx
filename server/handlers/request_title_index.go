package handlers

import (
	"context"
	"log"
	"path/filepath"

	"project-player/server/config"
	"project-player/server/httpx"
	"project-player/server/safego"
	"project-player/server/titleindex"
)

// titleIndexFile est le fichier de l'index des titres connus, à côté de la
// base du serveur (ADR-0135).
const titleIndexFile = "title-index.db"

// StartRequestTitleIndex ouvre l'index des titres connus dans dataDir, le
// branche sur la recherche des demandes et le tient à jour jusqu'à l'arrêt de
// ctx. Un index qui ne s'ouvre pas laisse la recherche à TMDB seul : le
// serveur démarre quand même.
func StartRequestTitleIndex(ctx context.Context, dataDir string) {
	ix, err := titleindex.Open(filepath.Join(dataDir, titleIndexFile))
	if err != nil {
		log.Printf("titleindex: index indisponible, recherche TMDB seule: %v", err)
		return
	}
	UseTitleIndex(ix)
	refresher := titleindex.Refresher{Index: ix, Client: httpx.Download}
	go safego.Forever("titleindex.Run", func() {
		refresher.Run(ctx, func() bool { return config.TMDBAPIKey() != "" })
	})
}
