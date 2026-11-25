package streaming

import (
	"context"
	"log"
	"time"

	"project-player/server/streaming/capacity"
)

// La passe de fond des aperçus cède au budget des sessions.
//
// Phase 3 du plan docs/transcodage-adaptatif.md. La passe tourne déjà en
// priorité basse, sur un cœur et un thread, et sur le même périphérique
// Vulkan que les sessions (fytroz). La priorité basse ne suffit pas sur une
// petite machine : un cœur pris à une session qui tient 1,1× la fait passer
// sous 1×. La passe n'extrait donc une image que si le budget laisse ce cœur
// libre, et se met en pause entre deux images dès qu'une session le réserve.
// Une image prend 40 à 170 ms : la pause arrive sans attendre.
//
// Sans profil prêt, rien ne change : la passe tourne comme avant.

// previewWarmCost est ce que la passe de fond demande de libre : un cœur
// (previewArgs avec un thread, plus le décodage).
var previewWarmCost = capacity.Cost{CPU: 1}

// previewBudgetPoll est l'intervalle auquel une passe en pause regarde si le
// budget s'est libéré.
var previewBudgetPoll = 2 * time.Second

// previewsMayRun dit si le budget laisse tourner la passe de fond.
func previewsMayRun(profile *capacity.Profile, budget *capacity.Budget) bool {
	if profile == nil {
		return true
	}
	return capacity.SpeedUnder(previewWarmCost, profile, budget.Load("")) >= 1
}

// waitForBudget attend que la passe puisse extraire l'image suivante. Faux si
// elle doit s'arrêter entre-temps : contexte annulé ou ticket fermé.
func (g *previewGenerator) waitForBudget(ctx context.Context, set *previewSet, ticket [32]byte) bool {
	if g.mayRun == nil || g.mayRun() {
		return true
	}
	log.Printf("previews: media %d: en pause, le budget des sessions prend le processeur", set.mediaID)
	ticker := time.NewTicker(previewBudgetPoll)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return false
		case <-ticker.C:
		}
		if g.tickets != nil && !g.tickets.IsLive(ticket, set.mediaID) {
			return false
		}
		if g.mayRun() {
			log.Printf("previews: media %d: reprise", set.mediaID)
			return true
		}
	}
}
