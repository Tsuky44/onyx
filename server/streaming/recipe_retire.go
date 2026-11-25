package streaming

import (
	"log"
	"strings"
	"time"

	"project-player/server/streaming/capacity"
)

// Le retrait d'une recette qui tue ses sessions (phase 5 du plan
// docs/transcodage-adaptatif.md).
//
// Fytroz a posé la règle pour ses deux chemins du circuit : une session morte
// avant son premier segment condamne la recette pour tout le serveur, parce
// que l'essai du démarrage n'a vu qu'une source de synthèse. La chaîne VAAPI
// est coupée (noteHardwareSessionDied), libplacebo revient au rendu logiciel
// (noteVulkanSessionDied). Ces deux retraits avaient chacun sa bascule, son
// journal et sa façon d'écrire le profil ; ils passent maintenant par un seul
// retireRecipe, qui garde la raison (l'erreur de FFmpeg) dans le profil pour
// la page d'administration (capacity.Withdrawal).
//
// La règle vaut aussi pour un encodeur du circuit que la mesure a choisi
// (sans VIDEO_ENCODER) : il sort des candidats du planificateur, qui reprend
// libx264 ou un autre circuit. Un encodeur forcé par l'opérateur n'a pas
// d'essai à son nom dans le registre : il n'est jamais retiré, comme avant.

// recipeKind est ce qu'une session morte fait retirer.
type recipeKind int

const (
	recipeNone recipeKind = iota
	// recipeHardwareFilters : la chaîne qui garde l'image sur le circuit.
	recipeHardwareFilters
	// recipeVulkanGPU : libplacebo sur un vrai circuit.
	recipeVulkanGPU
	// recipeHardwareEncoder : un encodeur du circuit choisi par la mesure.
	recipeHardwareEncoder
)

// recipeAtFault est la recette que la mort de cette session condamne : la plus
// précise de celles qu'elle utilisait. La chaîne VAAPI d'abord, puis le
// circuit de libplacebo (les deux règles de fytroz, telles quelles) ; l'encodeur
// du circuit seulement quand ni l'une ni l'autre ne tournait, pour ne pas
// retirer deux recettes pour une seule mort.
func (s *TranscodeSession) recipeAtFault() (recipeKind, string) {
	switch {
	case s.hardwareFilters:
		return recipeHardwareFilters, ""
	case s.vulkanGPU:
		return recipeVulkanGPU, ""
	case s.hardwareEncoder != "":
		return recipeHardwareEncoder, s.hardwareEncoder
	}
	return recipeNone, ""
}

// retireRecipe retire la recette pour tout le serveur, en mémoire et dans le
// profil, avec la raison. Faux si elle l'était déjà : deux sessions mortes en
// même temps ne la retirent qu'une fois, et ne l'écrivent qu'une fois au
// journal.
func retireRecipe(kind recipeKind, encoder, sessionID, stderr string) bool {
	reason := strings.TrimSpace(stderr)
	now := time.Now()
	switch kind {
	case recipeHardwareFilters:
		if !hardwareFiltersOff.CompareAndSwap(false, true) {
			return false
		}
		log.Printf("Streaming: session %s died with hardware filters before its first segment, "+
			"software filters from now on: %s", sessionID, reason)
		// Retirée du profil aussi : le planificateur ne la propose plus, et un
		// démarrage avec le cache ne la remet pas.
		changed := false
		for _, r := range capacityTrials.Results() {
			if strings.HasPrefix(r.Name, capacity.TrialFiltersPrefix) && r.Usable() {
				changed = capacityTrials.Retire(r.Name, stderr) || changed
			}
		}
		if changed {
			publishTrials()
		}
		return true

	case recipeVulkanGPU:
		choice := vulkanChosen.Load()
		if choice == nil || !choice.GPU || choice.Fallback == "" {
			return false
		}
		software := vulkanChoice{Spec: choice.Fallback}
		if !vulkanChosen.CompareAndSwap(choice, &software) {
			return false
		}
		log.Printf("Streaming: session %s died with libplacebo on the GPU before its first segment, "+
			"software Vulkan from now on: %s", sessionID, reason)
		// Le profil le garde : un démarrage avec le cache ne relance pas la
		// course qui remettrait le circuit en tête.
		if capacityTrials.Withdraw(capacity.TrialVulkan, choice.Spec, stderr, now,
			func(r *capacity.TrialResult, line string) bool {
				r.Choice, r.GPU, r.Fallback = software.Spec, false, ""
				r.Retired = ""
				r.Note = "retour au rendu logiciel après une session morte sur le circuit : " + line
				return true
			}) {
			publishTrials()
		}
		return true

	case recipeHardwareEncoder:
		if !capacityTrials.Retire(capacity.TrialEncoderPrefix+encoder, stderr) {
			return false
		}
		log.Printf("Streaming: session %s died with %s before its first segment, "+
			"the planner no longer offers it: %s", sessionID, encoder, reason)
		publishTrials()
		return true
	}
	return false
}

// noteHardwareSessionDied retire la chaîne matérielle pour tout le serveur :
// une session vient de mourir avec elle avant son premier segment. Les
// suivantes, et la nouvelle tentative du lecteur, reprennent la chaîne
// logicielle.
func noteHardwareSessionDied(sessionID, stderr string) {
	retireRecipe(recipeHardwareFilters, "", sessionID, stderr)
}

// noteVulkanSessionDied ramène libplacebo sur le rendu logiciel : une session
// vient de mourir sur le circuit avant son premier segment. L'essai du
// démarrage n'a vu qu'une image de synthèse, pas la couche RPU d'un film.
func noteVulkanSessionDied(sessionID, stderr string) {
	retireRecipe(recipeVulkanGPU, "", sessionID, stderr)
}
