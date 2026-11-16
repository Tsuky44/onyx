package titleindex

import (
	"context"
	"errors"
	"log"
	"time"
)

const (
	// runStartDelay laisse le serveur démarrer avant le premier
	// téléchargement (environ 33 Mo).
	runStartDelay = 2 * time.Minute
	// runTick revérifie toutes les heures : l'export du jour arrive vers 8 h
	// UTC, et un échec se retente à la prochaine heure, pas en boucle.
	runTick = time.Hour
	// refreshTimeout borne un rafraîchissement : le client de téléchargement
	// n'a pas d'échéance à lui.
	refreshTimeout = 15 * time.Minute
)

// Run tient l'index à jour jusqu'à l'arrêt de ctx : au démarrage puis chaque
// heure, il télécharge l'export du jour s'il ne l'a pas déjà. enabled est
// relu à chaque fois : sans clé TMDB, le catalogue de demandes ne sert pas
// et il est inutile de télécharger quoi que ce soit.
func (r Refresher) Run(ctx context.Context, enabled func() bool) {
	timer := time.NewTimer(runStartDelay)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
		}
		if enabled() {
			r.refreshIfStale(ctx, time.Now())
		}
		timer.Reset(runTick)
	}
}

// refreshIfStale télécharge l'export du jour, ou celui de la veille s'il
// n'est pas encore publié, quand l'index ne l'a pas déjà.
func (r Refresher) refreshIfStale(ctx context.Context, now time.Time) {
	built, err := r.Index.BuiltFor(ctx)
	if err != nil {
		log.Printf("titleindex: %v", err)
		return
	}
	day := exportDay(now)
	for _, candidate := range []time.Time{day, day.AddDate(0, 0, -1)} {
		if candidate.Format("2006-01-02") <= built {
			return
		}
		refreshCtx, cancel := context.WithTimeout(ctx, refreshTimeout)
		started := time.Now()
		count, err := r.Refresh(refreshCtx, candidate)
		cancel()
		if errors.Is(err, errExportMissing) {
			continue
		}
		if err != nil {
			log.Printf("titleindex: export du %s: %v", candidate.Format("2006-01-02"), err)
			return
		}
		log.Printf("titleindex: %d titres de l'export du %s indexés en %s",
			count, candidate.Format("2006-01-02"), time.Since(started).Round(time.Second))
		return
	}
	log.Printf("titleindex: aucun export TMDB publié pour le %s ni la veille", day.Format("2006-01-02"))
}
