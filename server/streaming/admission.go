package streaming

import (
	"fmt"
	"math"

	"project-player/server/streaming/capacity"
)

// L'admission d'une session, contre le budget par ressource.
//
// Phase 3 du plan docs/transcodage-adaptatif.md, décision §0.5. Le
// planificateur a déjà pris, au barreau demandé, la recette la moins chère
// quand la meilleure ne tenait pas (capacity.PlanPipeline). Si même elle ne
// tient pas admitSpeed avec la charge du moment :
//
//   - l'Auto (le client envoie auto=1) descend de barreau, jusqu'au plus haut
//     qui tient, et la réponse le dit (capacity_warning: degraded) ;
//   - un choix manuel, ou un client qui ne connaît pas auto=1, est servi tel
//     quel, avec capacity_warning: too_heavy. Un client déjà installé ne voit
//     jamais sa qualité baisser ;
//   - le 503 server_busy ne sert qu'à la limite dure : aucun barreau ne tient
//     la lecture (hardLimitSpeed). Ouvrir quand même ferait saccader toutes
//     les sessions en cours, pas seulement la nouvelle.
//
// Sans profil prêt, rien de tout cela ne joue : la vitesse prévue est infinie,
// le barreau demandé est servi, et seul le plafond de sessions d'avant compte.

// Les avertissements de /start (StartResponse.CapacityWarning).
const (
	// CapacityDegraded : l'Auto a demandé plus que ce que le serveur tient ;
	// le barreau servi est plus bas (StartResponse.RequestedQuality dit
	// lequel était demandé).
	CapacityDegraded = "degraded"
	// CapacityTooHeavy : le barreau servi est celui demandé, mais le serveur
	// prévoit qu'il ne tiendra pas admitSpeed. Le lecteur peut saccader.
	CapacityTooHeavy = "too_heavy"
)

// admitSpeed est la vitesse prévue qu'une session doit tenir pour être admise
// sans avertissement : le critère 1 du plan. Sous le 1,5× que vise le
// planificateur pour choisir sa recette : une session admise à 1,3× prend
// encore son avance, plus lentement après un saut.
const admitSpeed = 1.3

// hardLimitSpeed est la limite dure : sous 1×, aucune session ne suit la
// lecture, et celles qui tournent déjà perdent leur part.
const hardLimitSpeed = 1.0

// copyCost est ce que réserve une image recopiée : presque rien (*estimé* :
// démultiplexer et réécrire les paquets, moins de 0,1 cœur au §7 du plan).
var copyCost = capacity.Cost{CPU: 0.05}

// audioRenditionCPU est ce que coûte une piste audio publiée, en cœurs :
// décoder la source (TrueHD, DTS-HD) et l'encoder en AAC. *Estimé* : « quelques
// dixièmes de cœur » pour huit pistes TrueHD (§7 du plan).
const audioRenditionCPU = 0.04

// audioCost est ce que coûtent n pistes audio publiées.
func audioCost(n int) capacity.Cost { return capacity.Cost{CPU: audioRenditionCPU * float64(n)} }

// rungOption est un barreau essayé : ses options, ce que la session réservera,
// et la vitesse que le planificateur prévoit sous la charge du moment.
type rungOption struct {
	options TranscodeOptions
	cost    capacity.Cost
	speed   float64
}

// admission est la décision de /start.
type admission struct {
	served rungOption
	// requested est le barreau que le client a demandé.
	requested string
	// warning vaut "", CapacityDegraded ou CapacityTooHeavy.
	warning string
	// refused est la raison lisible du 503, vide quand la session est admise.
	refused string
}

// admit décide quel barreau servir. try planifie un barreau sous la charge
// du moment ; below liste, du plus haut au plus bas, les barreaux que l'Auto
// peut prendre à la place de requested (rungsBelow).
func admit(requested string, auto bool, below []string, try func(quality string) rungOption) admission {
	first := try(requested)
	if first.speed >= admitSpeed {
		return admission{served: first, requested: requested}
	}
	if !auto && first.speed >= hardLimitSpeed {
		return admission{served: first, requested: requested, warning: CapacityTooHeavy}
	}
	// Le barreau le plus rapide de tous ceux essayés, au cas où aucun ne tient
	// admitSpeed. À vitesse égale, le plus haut (essayé le premier).
	fastest := first
	for _, quality := range below {
		option := try(quality)
		if auto && option.speed >= admitSpeed {
			return admission{served: option, requested: requested, warning: CapacityDegraded}
		}
		if option.speed > fastest.speed {
			fastest = option
		}
		// En manuel, il suffit de savoir qu'un barreau tient la lecture : le
		// demandé sera servi tel quel.
		if !auto && option.speed >= hardLimitSpeed {
			break
		}
	}
	if fastest.speed < hardLimitSpeed {
		return admission{served: first, requested: requested, refused: busyReason(first, fastest)}
	}
	if !auto {
		return admission{served: first, requested: requested, warning: CapacityTooHeavy}
	}
	warning := CapacityDegraded
	if fastest.options.Quality == requested {
		warning = CapacityTooHeavy
	}
	return admission{served: fastest, requested: requested, warning: warning}
}

// busyReason est la raison du 503, pour le journal et le corps de la réponse.
func busyReason(first, fastest rungOption) string {
	return fmt.Sprintf("le serveur est saturé : %s tiendrait %.2f× la lecture, et même %s seulement %.2f×",
		first.options.Quality, finiteSpeed(first.speed), fastest.options.Quality, finiteSpeed(fastest.speed))
}

func finiteSpeed(speed float64) float64 {
	if math.IsInf(speed, 1) {
		return 99
	}
	return speed
}

// rungsBelow sont les barreaux de cette source sous requested, dans l'ordre
// du menu (le débit décroissant, ADR-0022) : la descente de l'Auto ne demande
// jamais plus à la ligne que ce que l'Auto avait choisi. Le premier qui tient
// est le plus haut qui tient.
func rungsBelow(requested string, sourceHeight int) []string {
	ladder := QualityLadderFor(sourceHeight)
	for i, tier := range ladder {
		if tier.Key == requested {
			keys := make([]string, 0, len(ladder)-i-1)
			for _, t := range ladder[i+1:] {
				keys = append(keys, t.Key)
			}
			return keys
		}
	}
	// Un barreau hors du menu de cette source (inconnu, ou au-dessus d'elle) :
	// tout ce qui demande moins à la ligne.
	limit := EstimateBandwidth(requested)
	var keys []string
	for _, t := range ladder {
		if t.BitrateBps < limit {
			keys = append(keys, t.Key)
		}
	}
	return keys
}

// planRung planifie un barreau sous la charge load : la décision de recopie,
// puis la recette, et ce que la session réservera. audioCount est le nombre de
// pistes audio publiées, qui coûtent en plus de l'image.
//
// La charge passée au planificateur compte aussi l'audio de la session : il
// tourne dans le même FFmpeg, sur les mêmes cœurs.
func planRung(options TranscodeOptions, profile *capacity.Profile, load capacity.Load, audioCount int) rungOption {
	if profile == nil {
		return rungOption{options: options, speed: math.Inf(1)}
	}
	audio := audioCost(audioCount)
	if options.Video.Copy {
		cost := copyCost.Plus(audio)
		return rungOption{options: options, cost: cost, speed: capacity.SpeedUnder(cost, profile, load)}
	}
	planned, ok := planPipeline(options, profile, capacity.Load{Used: load.Used.Plus(audio)})
	if !ok || planned.Pipeline == nil {
		// Aucun encodeur du profil ne sait faire ce travail : il part comme
		// avant le profil, sans prévision. Il réserve un cœur, pour ne pas être
		// invisible aux sessions suivantes.
		return rungOption{options: planned, cost: capacity.Cost{CPU: 1}.Plus(audio), speed: math.Inf(1)}
	}
	return rungOption{options: planned, cost: planned.Pipeline.Cost.Plus(audio), speed: planned.Pipeline.Speed}
}
