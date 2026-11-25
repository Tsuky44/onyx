package capacity

import (
	"context"
	"log"
	"sort"
	"strings"
	"sync"
	"time"
)

// Le registre unique des essais.
//
// Avant lui, trois choix faits au démarrage avaient chacun sa façon de
// faire : l'encodeur (`encoderRuns`), la chaîne VAAPI (`detectHardwareFilters`)
// et le périphérique de libplacebo (`chooseVulkanDevice`). Le dernier, écrit
// par fytroz, a posé le contrat que tous suivent ici :
//
//  1. un essai de fonctionnement ;
//  2. une course ou un banc quand plusieurs chemins marchent ;
//  3. le choix ;
//  4. le retrait de la recette quand une session meurt avec elle ;
//  5. le forçage par une variable, qui passe avant la mesure ;
//  6. une ligne de journal qui dit le choix.
//
// Les essais restent écrits là où sont leurs commandes (streaming), qui les
// enregistre ici. Le registre les lance, garde leur verdict, le met dans le
// profil (et donc dans le cache : un démarrage avec un cache valide ne relance
// aucun essai) et applique les retraits.

// Trial est un essai.
type Trial struct {
	// Name est la clé du verdict, stable d'une version à l'autre : elle est
	// écrite dans le cache. Voir les constantes Trial*.
	Name string
	// Forced est la variable qui force ce choix, telle que l'opérateur l'a
	// posée (`VIDEO_ENCODER=h264_vaapi`), ou vide.
	Forced string
	// Run fait l'essai, et la course s'il y en a une, et rend le verdict.
	Run func(ctx context.Context) TrialResult
}

// Les noms d'essais que streaming enregistre. Un encodeur essayé pour le
// planificateur s'appelle TrialEncoderPrefix + son nom.
const (
	// TrialSelectedEncoder est la résolution de VIDEO_ENCODER (libx264 quand
	// la variable est absente) : l'encodeur des sessions tant que le profil
	// n'est pas prêt, et le seul candidat quand la variable est posée.
	TrialSelectedEncoder = "encoder"
	// TrialSelectedHEVC est l'encodeur HEVC qui va avec.
	TrialSelectedHEVC = "hevc"
	// TrialEncoderPrefix précède le nom d'un encodeur essayé pour le
	// planificateur (`encoder/h264_vaapi`, `encoder/hevc_vaapi`).
	TrialEncoderPrefix = "encoder/"
	// TrialFiltersPrefix précède la surface d'une chaîne de filtres sur le
	// circuit (`filters/vaapi`).
	TrialFiltersPrefix = "filters/"
	// TrialVulkan est le périphérique de libplacebo.
	TrialVulkan = "vulkan"
)

// TrialResult est le verdict d'un essai. Ses champs servent à tous : chaque
// essai remplit ceux qui le concernent.
type TrialResult struct {
	Name  string `json:"name"`
	Works bool   `json:"works"`
	// Forced reprend Trial.Forced : le verdict vient de l'opérateur, pas de
	// la mesure.
	Forced string `json:"forced,omitempty"`
	// Choice est ce qui a été retenu : le nom d'un encodeur, la spec d'un
	// périphérique Vulkan (`vulkan:1`), une surface.
	Choice string `json:"choice,omitempty"`
	// GPU dit que Choice est un circuit (et pas un rendu logiciel).
	GPU bool `json:"gpu,omitempty"`
	// Fallback est le choix à reprendre si le circuit lâche une session.
	Fallback string `json:"fallback,omitempty"`
	// Note est la ligne de journal du verdict, ou ce que FFmpeg a dit en
	// échouant.
	Note string `json:"note,omitempty"`
	// Retired est la raison du retrait (l'erreur de FFmpeg d'une session
	// morte avant son premier segment), vide tant que la recette tient.
	Retired string `json:"retired,omitempty"`
	// Withdrawals gardent chaque recette retirée de cet essai, avec sa
	// raison : la chaîne VAAPI (qui rend l'essai inutilisable, Retired), ou le
	// circuit de libplacebo (qui revient au rendu logiciel, l'essai reste
	// bon). C'est ce que la page d'administration montrera (phase 7).
	Withdrawals []Withdrawal `json:"withdrawals,omitempty"`
}

// Withdrawal est une recette retirée parce qu'une session est morte avec elle
// avant son premier segment.
type Withdrawal struct {
	// Recipe nomme ce qui a été retiré (`filters/vaapi`, `vulkan:1`).
	Recipe string `json:"recipe"`
	// Reason est la ligne d'erreur de FFmpeg.
	Reason string    `json:"reason"`
	At     time.Time `json:"at"`
}

// Usable dit que la recette marche et n'a pas été retirée.
func (r TrialResult) Usable() bool { return r.Works && r.Retired == "" }

// Registry garde les essais et leurs verdicts.
type Registry struct {
	mu      sync.Mutex
	trials  []Trial
	results map[string]TrialResult
}

// NewRegistry rend un registre vide.
func NewRegistry() *Registry { return &Registry{results: map[string]TrialResult{}} }

// Register ajoute un essai. Un essai du même nom remplace le précédent.
func (r *Registry) Register(t Trial) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := range r.trials {
		if r.trials[i].Name == t.Name {
			r.trials[i] = t
			return
		}
	}
	r.trials = append(r.trials, t)
}

// Record retient un verdict obtenu ailleurs : au premier démarrage, les trois
// choix d'avant le profil tournent encore de façon synchrone (le comportement
// d'aujourd'hui), et le profil reprend leurs verdicts au lieu de refaire
// leurs essais.
func (r *Registry) Record(result TrialResult) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.results[result.Name] = result
}

// Run lance, dans l'ordre d'enregistrement, chaque essai qui n'a pas encore
// de verdict (tous quand fresh), et journalise chaque verdict.
func (r *Registry) Run(ctx context.Context, fresh bool) {
	r.mu.Lock()
	trials := append([]Trial(nil), r.trials...)
	r.mu.Unlock()
	for _, t := range trials {
		if ctx.Err() != nil {
			return
		}
		r.mu.Lock()
		_, known := r.results[t.Name]
		r.mu.Unlock()
		if known && !fresh {
			continue
		}
		result := t.Run(ctx)
		result.Name, result.Forced = t.Name, t.Forced
		logTrial(result)
		r.Record(result)
	}
}

// Result rend le verdict d'un essai.
func (r *Registry) Result(name string) (TrialResult, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	result, ok := r.results[name]
	return result, ok
}

// Results rend tous les verdicts, triés par nom.
func (r *Registry) Results() []TrialResult {
	r.mu.Lock()
	defer r.mu.Unlock()
	return sortedResults(r.results)
}

// Restore remplace les verdicts par ceux d'un profil en cache.
func (r *Registry) Restore(results []TrialResult) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.results = map[string]TrialResult{}
	for _, result := range results {
		r.results[result.Name] = result
	}
}

// Update modifie un verdict sous le verrou ; faux si l'essai n'en a pas.
// C'est le retrait de fytroz pour Vulkan, qui ne retire pas tout mais revient
// au rendu logiciel.
func (r *Registry) Update(name string, change func(*TrialResult)) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	result, ok := r.results[name]
	if !ok {
		return false
	}
	change(&result)
	r.results[name] = result
	return true
}

// Retire retire une recette, avec la raison ; faux si elle l'était déjà.
// L'essai devient inutilisable (Usable).
func (r *Registry) Retire(name, reason string) bool {
	return r.Withdraw(name, name, reason, time.Now(), func(result *TrialResult, line string) bool {
		if result.Retired != "" {
			return false
		}
		result.Retired = line
		return true
	})
}

// Withdraw est le seul chemin d'un retrait : change applique ce qui reste de
// l'essai une fois la recette retirée (rien pour une chaîne, le rendu
// logiciel pour Vulkan) et dit faux si c'était déjà fait. La raison, réduite
// à la ligne d'erreur de FFmpeg, est gardée dans Withdrawals. Faux si l'essai
// n'a pas de verdict ou si change n'a rien changé.
func (r *Registry) Withdraw(name, recipe, reason string, at time.Time, change func(result *TrialResult, line string) bool) bool {
	line := errorLine(reason)
	if line == "" {
		line = "session morte avant son premier segment"
	}
	withdrawn := false
	r.Update(name, func(result *TrialResult) {
		if !change(result, line) {
			return
		}
		result.Withdrawals = append(append([]Withdrawal(nil), result.Withdrawals...),
			Withdrawal{Recipe: recipe, Reason: line, At: at.UTC()})
		withdrawn = true
	})
	return withdrawn
}

func logTrial(result TrialResult) {
	verdict := "ne marche pas"
	if result.Works {
		verdict = "marche"
	}
	line := "Streaming: essai " + result.Name + " : " + verdict
	if result.Choice != "" {
		line += ", retenu " + result.Choice
	}
	if result.Forced != "" {
		line += " (forcé par " + result.Forced + ")"
	}
	if result.Note != "" {
		line += " — " + errorLine(result.Note)
	}
	log.Print(line)
}

// errorLine résume une sortie de FFmpeg à sa dernière ligne utile, celle qui
// dit l'erreur.
func errorLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if line := strings.TrimSpace(lines[i]); line != "" {
			if len(line) > 300 {
				line = line[:300]
			}
			return line
		}
	}
	return ""
}

func sortedResults(results map[string]TrialResult) []TrialResult {
	out := make([]TrialResult, 0, len(results))
	for _, r := range results {
		out = append(out, r)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}
