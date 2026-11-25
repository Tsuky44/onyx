package capacity

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"time"
)

// Profiler construit le profil : il lit l'inventaire, fait les essais du
// registre, mesure les étapes, et écrit le cache.
type Profiler struct {
	// Path est le fichier du cache (CacheFileName dans le dossier de données).
	Path string
	// Server est la version du serveur, dans l'empreinte : une mise à jour de
	// l'image peut changer les pilotes sans changer FFmpeg.
	Server string
	// Forcings sont les variables qui forcent un choix (VIDEO_ENCODER…) : en
	// changer une invalide le cache.
	Forcings map[string]string
	// Root et Run lisent l'inventaire (SystemRoot, RunFFmpeg en production).
	Root fs.FS
	Run  Runner
	// Registry porte les essais, que streaming a enregistrés.
	Registry *Registry
	// Describe dit, d'après les verdicts, quels encodeurs sont candidats et
	// quoi mesurer. Le banc lance ainsi les commandes des sessions.
	Describe func(inv Inventory, results []TrialResult) ([]EncoderCandidate, BenchInput)
	// Measure lance une mesure ; nil : bench.MeasureBackground.
	Measure Measurer
}

// Inventory lit l'inventaire et son empreinte.
func (p *Profiler) Inventory(ctx context.Context) (Inventory, Fingerprint) {
	inv := ReadInventory(ctx, p.Root, p.Run)
	return inv, FingerprintOf(inv, p.Server, p.Forcings)
}

// Cached rend le profil en cache s'il décrit cette machine, et remet ses
// verdicts dans le registre : aucun essai ne sera relancé (critère 6).
func (p *Profiler) Cached(fp Fingerprint) (*Profile, bool) {
	profile, err := LoadProfile(p.Path, fp)
	switch {
	case err == nil:
		p.Registry.Restore(profile.Trials)
		return profile, true
	case errors.Is(err, os.ErrNotExist):
		log.Println("Streaming: pas encore de profil matériel, mesure en arrière-plan")
	case errors.Is(err, ErrStale):
		log.Println("Streaming: la machine a changé depuis le profil matériel, nouvelle mesure en arrière-plan")
	default:
		log.Printf("Streaming: profil matériel ignoré, nouvelle mesure en arrière-plan : %v", err)
	}
	return nil, false
}

// Build fait les essais (tous si fresh, sinon ceux qui n'ont pas encore de
// verdict), mesure, et écrit le cache. L'erreur ne concerne que l'écriture
// du cache : le profil rendu est utilisable.
func (p *Profiler) Build(ctx context.Context, inv Inventory, fp Fingerprint, fresh bool) (*Profile, error) {
	started := time.Now()
	p.Registry.Run(ctx, fresh)
	results := p.Registry.Results()
	encoders, input := p.Describe(inv, results)

	dir, err := os.MkdirTemp("", "onyx-capacity-*")
	if err != nil {
		return nil, fmt.Errorf("capacity: dossier des sources du banc: %w", err)
	}
	defer os.RemoveAll(dir)
	input.Dir = dir
	costs := MeasureCosts(ctx, input, p.Measure)
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}

	profile := &Profile{
		Fingerprint:    fp,
		MeasuredAt:     started.UTC(),
		MeasureSeconds: time.Since(started).Round(100 * time.Millisecond).Seconds(),
		Inventory:      inv,
		Trials:         results,
		Encoders:       encoders,
		Costs:          costs,
	}
	if err := SaveProfile(p.Path, profile); err != nil {
		return profile, err
	}
	return profile, nil
}
