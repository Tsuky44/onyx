package streaming

import (
	"log"
	"sync"

	"project-player/server/safego"
	"project-player/server/streaming/capacity"
)

// Les changements du profil publié pendant que le serveur tourne : un retrait
// de recette (recipe_retire.go) et la correction apprise des sessions
// (session_feedback.go). Le profil ne change jamais en place : chacun en
// publie un nouveau et l'écrit dans le cache, pour qu'un redémarrage le
// reprenne.

var (
	// profileEdit sérialise les lectures-modifications-publications du profil :
	// deux sessions qui rapportent en même temps perdraient sinon l'une des
	// deux corrections, et un retrait pourrait effacer une correction.
	profileEdit sync.Mutex
	// savingProfile sérialise les écritures du cache.
	savingProfile sync.Mutex
)

// storeProfile publie un profil neuf (mesure, remesure, cache) sous le même
// verrou que les retouches.
func storeProfile(profile *capacity.Profile) {
	profileEdit.Lock()
	defer profileEdit.Unlock()
	currentProfile.Store(profile)
}

// editProfile applique change au profil publié, publie le résultat et l'écrit.
// change rend nil quand il n'y a rien à changer. Sans profil prêt, rien : la
// mesure en cours reprendra les verdicts du registre, et une correction
// apprise contre le banc d'un profil qui n'existe pas encore ne voudrait rien
// dire.
func editProfile(change func(*capacity.Profile) *capacity.Profile) {
	profileEdit.Lock()
	profile := capacityProfile()
	if profile == nil {
		profileEdit.Unlock()
		return
	}
	next := change(profile)
	if next == nil {
		profileEdit.Unlock()
		return
	}
	currentProfile.Store(next)
	profileEdit.Unlock()
	saveProfileInBackground(next)
}

// publishTrials publie le profil avec les verdicts du registre, et l'écrit.
func publishTrials() {
	editProfile(func(p *capacity.Profile) *capacity.Profile {
		return p.WithTrials(capacityTrials.Results())
	})
}

func saveProfileInBackground(profile *capacity.Profile) {
	profiler := activeProfiler.Load()
	if profiler == nil {
		return
	}
	go safego.Run("capacity-save", func() {
		savingProfile.Lock()
		defer savingProfile.Unlock()
		// Une écriture plus ancienne qui passerait après une plus récente
		// remettrait l'ancien profil dans le cache : seul le profil publié
		// s'écrit.
		if capacityProfile() != profile {
			return
		}
		if err := capacity.SaveProfile(profiler.Path, profile); err != nil {
			log.Printf("Streaming: profil matériel non écrit, le changement sera perdu au redémarrage : %v", err)
		}
	})
}
