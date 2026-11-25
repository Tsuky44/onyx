package capacity

import (
	"math"
	"sync"
)

// Le budget par ressource : ce que les sessions vivantes ont réservé.
//
// Avant lui, le serveur comptait des sessions (MAX_TRANSCODES, ADR-0033) : une
// recopie qui ne coûte rien pesait autant qu'un 4K Dolby Vision qui prend tous
// les cœurs d'un petit serveur. Chaque session réserve maintenant le coût
// prévu de sa recette, par ressource, et le planificateur décide la suivante
// contre ce qui reste.
//
// La réservation est le coût à la vitesse de lecture (Pipeline.Cost). Une
// session va plus vite tant qu'elle prend son avance, puis le bridage la
// ramène à 1× en moyenne (32 s d'avance, streaming/session.go) : c'est cette
// moyenne qui occupe la machine pendant toute la lecture.

// Budget tient les réservations, par session. Sûr entre goroutines ; un Budget
// nil ne réserve rien et rend une charge nulle, pour les tests qui posent des
// sessions sans gestionnaire complet.
type Budget struct {
	mu   sync.Mutex
	held map[string]reservation
}

type reservation struct {
	owner string
	cost  Cost
}

// NewBudget rend un budget vide.
func NewBudget() *Budget {
	return &Budget{held: map[string]reservation{}}
}

// Reserve pose (ou remplace) la réservation de la session id. owner est ce qui
// regroupe les sessions d'un même lecteur (le ticket) : Load peut l'exclure.
func (b *Budget) Reserve(id, owner string, cost Cost) {
	if b == nil {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	b.held[id] = reservation{owner: owner, cost: cost}
}

// Release rend la réservation de la session id. Sans effet si elle n'en a
// pas : une session se rend à la fois quand elle est gelée, quand FFmpeg sort
// et quand elle est détruite, et seul le premier compte.
func (b *Budget) Release(id string) bool {
	if b == nil {
		return false
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	_, ok := b.held[id]
	delete(b.held, id)
	return ok
}

// Load est la charge réservée par toutes les sessions, sauf celles de
// exceptOwner : un lecteur qui demande une nouvelle session va remplacer les
// siennes, et un changement de qualité ne doit pas être jugé contre la
// session qu'il remplace. exceptOwner vide n'exclut rien.
func (b *Budget) Load(exceptOwner string) Load {
	if b == nil {
		return Load{}
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	var used Cost
	for _, r := range b.held {
		if exceptOwner != "" && r.owner == exceptOwner {
			continue
		}
		used = used.Plus(r.cost)
	}
	return Load{Used: used}
}

// Held est le nombre de réservations en cours.
func (b *Budget) Held() int {
	if b == nil {
		return 0
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.held)
}

// Margin est ce qui reste libre de chaque ressource de cette machine, sauf
// les sessions de exceptOwner, jamais négatif. C'est l'accès des phases 4 et 5
// (tenue des barreaux, suggested_quality) : la marge du moment, sans refaire
// le compte des sessions. Nil sans profil.
func (b *Budget) Margin(profile *Profile, exceptOwner string) (Cost, bool) {
	if profile == nil {
		return Cost{}, false
	}
	total := CapacityOf(profile)
	used := b.Load(exceptOwner).Used
	free := func(r Resource) float64 { return math.Max(total.Of(r)-used.Of(r), 0) }
	return Cost{
		CPU:     free(ResourceCPU),
		Decode:  free(ResourceDecode),
		Encode:  free(ResourceEncode),
		Compute: free(ResourceCompute),
	}, true
}

// CapacityOf est ce que la machine a de chaque ressource : ses cœurs, et un
// moteur plein (1) pour chaque moteur du circuit.
func CapacityOf(profile *Profile) Cost {
	return Cost{CPU: float64(max(profile.Inventory.Cores, 1)), Decode: 1, Encode: 1, Compute: 1}
}

// SpeedUnder est la vitesse que tiendrait un travail de ce coût sous cette
// charge : sur chaque ressource, la part libre divisée par le coût, et le
// minimum sur toutes. Un coût nul tient sans limite (math.Inf).
func SpeedUnder(cost Cost, profile *Profile, load Load) float64 {
	speed := math.Inf(1)
	if profile == nil {
		return speed
	}
	total := CapacityOf(profile)
	for _, r := range Resources {
		need := cost.Of(r)
		if need <= 0 {
			continue
		}
		speed = math.Min(speed, math.Max(total.Of(r)-load.Used.Of(r), 0)/need)
	}
	return speed
}
