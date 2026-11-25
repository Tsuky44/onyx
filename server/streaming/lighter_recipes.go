package streaming

import (
	"log"
	"math"
	"strconv"
	"time"

	"project-player/server/streaming/capacity"
	"project-player/server/ttlcache"
)

// La recette suivante d'un fichier, après une session trop lente (critère 2
// du plan docs/transcodage-adaptatif.md).
//
// Une session qui passe 20 s sous 1× ne se corrige pas en cours de route :
// FFmpeg ne change pas de preset. Mais le spectateur rouvre une session au
// moindre saut, changement de piste ou suggestion de l'Auto, et celle-là doit
// être plus légère.
//
// Ce que la session lente a appris tient en un chiffre : ce fichier coûte
// `slowdown` fois ce que le planificateur prévoyait (la vitesse prévue sur la
// vitesse vue). Le planificateur multiplie ses coûts par ce facteur pour ce
// fichier (capacity.Job.Slowdown), et sa règle fait le reste, dans l'ordre que
// le plan demande :
//
//  1. le preset de libx264 plus rapide, au même barreau, s'il tient : la
//     règle élimine ce qui ne tient pas 1,5× et garde la meilleure image de
//     ce qui reste ;
//  2. sinon, au plus rapide ou sur le circuit, le barreau : sa vitesse prévue
//     passe sous 1,3×, et l'Auto (auto=1) descend à l'admission ; un choix
//     manuel est servi tel quel, avec capacity_warning: too_heavy.
//
// La correction du profil (session_feedback.go) apprend la même chose par
// classe de recette, lentement et pour tous les fichiers ; cette mémoire est
// immédiate, pour ce fichier seulement, et courte : la charge qui l'a rendue
// lente aura changé.

const (
	// lighterMemoryTTL : le temps d'une soirée de visionnage, sauts et reprises
	// compris. Plus long, un serveur libéré refuserait encore son 4K au
	// spectateur suivant.
	lighterMemoryTTL = 20 * time.Minute
	// lighterMemoryMax borne la mémoire (ADR-0050) : bien plus de fichiers
	// lents en vingt minutes qu'un serveur n'a de spectateurs.
	lighterMemoryMax = 256
	// maxSlowdown borne ce qu'un fichier peut coûter de plus que prévu. À
	// quatre fois, même un 4K Dolby Vision prévu à 2× tombe sous 1,3× : au-delà,
	// le facteur ne change plus aucune décision et ne ferait que garder un
	// fichier cassé au fond de l'échelle.
	maxSlowdown = 4.0
)

// lighterRecipe est ce qu'un fichier doit prendre de plus léger.
type lighterRecipe struct {
	// slowdown multiplie les coûts prévus de ce fichier ; 0 ou 1 : rien.
	slowdown float64
}

var lighterRecipes = ttlcache.New[lighterRecipe](lighterMemoryTTL, lighterMemoryMax)

func lighterKey(mediaID int) string { return strconv.Itoa(mediaID) }

// lighterRecipeFor est ce que ce fichier doit prendre de plus léger, s'il a
// eu une session lente récemment.
func lighterRecipeFor(mediaID int) lighterRecipe {
	r, _ := lighterRecipes.Get(lighterKey(mediaID))
	return r
}

// noteSlowSession retient qu'une session de ce fichier, avec la recette plan,
// tient speed là où le planificateur prévoyait predicted.
func noteSlowSession(mediaID int, plan *capacity.Pipeline, predicted, speed float64) {
	if plan == nil {
		// Une recopie lente n'est pas un encodeur lent : c'est le disque ou
		// le réseau, qu'aucune recette ne soulage.
		return
	}
	next, ok := slowdownAfter(plan.Slowdown, predicted, speed)
	if !ok {
		return
	}
	lighterRecipes.Put(lighterKey(mediaID), lighterRecipe{slowdown: next})
	log.Printf("Streaming: media %d : %.2f× vu pour %.2f× prévu, ses prochaines recettes comptent ×%.2f pendant %s",
		mediaID, speed, predicted, next, lighterMemoryTTL)
}

// slowdownAfter est le facteur du fichier après une session lente : celui que
// sa recette portait déjà, fois l'erreur de la prévision. ok est faux quand la
// prévision n'était pas meilleure que ce qu'on a vu : la charge explique la
// lenteur, et le fichier n'y est pour rien.
func slowdownAfter(current, predicted, speed float64) (float64, bool) {
	if speed <= 0 || predicted <= speed || math.IsInf(predicted, 1) {
		return 0, false
	}
	current = math.Max(current, 1)
	return math.Min(current*predicted/speed, maxSlowdown), true
}
