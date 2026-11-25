// Package capacity sait ce que la machine du serveur tient, et en déduit la
// recette de chaque transcodage.
//
// Trois morceaux, chacun derrière une interface étroite (voir
// docs/transcodage-adaptatif.md §3) :
//
//   - l'inventaire (ReadInventory) : cœurs, mémoire, circuits, FFmpeg, sans
//     rien lancer de lourd ;
//   - le profil (Profile) : les verdicts des essais (Registry), les encodeurs
//     candidats et le coût de chaque étape, mesuré par le banc
//     (MeasureCosts). Il est persisté avec une empreinte de la machine, pour
//     qu'un démarrage ordinaire ne relance rien ;
//   - le planificateur (PlanPipeline) : la recette d'une session, son coût
//     prévu par ressource et sa vitesse prévue.
//
// Le paquet n'importe pas streaming : c'est streaming qui lui décrit ses
// encodeurs et ses filtres, et qui rend la recette en arguments FFmpeg.
package capacity

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// ProfileVersion change quand la forme du profil ou la façon de mesurer
// change : un cache d'une autre version est remesuré.
const ProfileVersion = 1

// CacheFileName est le nom du cache, dans le dossier de données du serveur.
const CacheFileName = "capacity-profile.json"

// Fingerprint est ce qui, s'il change, rend le profil faux : une autre
// machine, un autre quota, un circuit en plus ou en moins, un autre FFmpeg,
// une autre version du serveur (ses pilotes viennent avec l'image), ou un
// forçage que l'opérateur a changé.
type Fingerprint struct {
	Version     int               `json:"version"`
	Server      string            `json:"server"`
	CPUModel    string            `json:"cpu_model"`
	Arch        string            `json:"arch"`
	Cores       int               `json:"cores"`
	MemoryBytes int64             `json:"memory_bytes"`
	Devices     []string          `json:"devices"`
	FFmpeg      string            `json:"ffmpeg"`
	Forcings    map[string]string `json:"forcings,omitempty"`
}

// FingerprintOf est l'empreinte d'un inventaire, pour cette version du
// serveur et ces forçages. Un forçage vide n'est pas retenu.
func FingerprintOf(inv Inventory, server string, forcings map[string]string) Fingerprint {
	fp := Fingerprint{
		Version:     ProfileVersion,
		Server:      server,
		CPUModel:    inv.CPUModel,
		Arch:        inv.Arch,
		Cores:       inv.Cores,
		MemoryBytes: inv.MemoryBytes,
		FFmpeg:      inv.FFmpeg.Version,
	}
	fp.Devices = append(append([]string{}, inv.RenderNodes...), inv.NvidiaNodes...)
	sort.Strings(fp.Devices)
	for k, v := range forcings {
		if v = strings.TrimSpace(v); v != "" {
			if fp.Forcings == nil {
				fp.Forcings = map[string]string{}
			}
			fp.Forcings[k] = v
		}
	}
	return fp
}

// Same dit que deux empreintes décrivent la même machine.
func (f Fingerprint) Same(o Fingerprint) bool {
	a, errA := json.Marshal(f)
	b, errB := json.Marshal(o)
	return errA == nil && errB == nil && string(a) == string(b)
}

// EncoderCandidate est un encodeur que le planificateur peut prendre.
// streaming le décrit ; capacity n'en connaît que ce qui change la recette.
type EncoderCandidate struct {
	Name string `json:"name"`
	// Codec vaut `h264` ou `hevc` (le HDR gardé, ADR-0106).
	Codec    string `json:"codec"`
	Hardware bool   `json:"hardware,omitempty"`
	// Surface nomme les images du circuit (`vaapi`) quand le même circuit
	// décode et met à l'échelle : la chaîne de fytroz peut alors garder
	// l'image dessus de bout en bout.
	Surface string `json:"surface,omitempty"`
	// Upload dit que l'encodeur ne prend que des images du périphérique : la
	// commande ouvre ce périphérique, et elle ne peut pas en ouvrir un second
	// pour libplacebo (voir TranscodeOptions.encoder()).
	Upload bool `json:"upload,omitempty"`
	// Fallback n'est pris que si aucun autre candidat ne donne de recette :
	// libx264 derrière un encodeur forcé qui ne sait pas faire ce cas.
	Fallback bool `json:"fallback,omitempty"`
}

// Profile est ce que la machine sait faire, et à quel prix.
type Profile struct {
	Fingerprint Fingerprint `json:"fingerprint"`
	MeasuredAt  time.Time   `json:"measured_at"`
	// MeasureSeconds est la durée de la mesure (critère 6 : moins de 20 s).
	MeasureSeconds float64            `json:"measure_seconds"`
	Inventory      Inventory          `json:"inventory"`
	Trials         []TrialResult      `json:"trials"`
	Encoders       []EncoderCandidate `json:"encoders"`
	Costs          []StageCost        `json:"costs"`
}

// Trial rend le verdict d'un essai.
func (p *Profile) Trial(name string) (TrialResult, bool) {
	for _, t := range p.Trials {
		if t.Name == name {
			return t, true
		}
	}
	return TrialResult{}, false
}

// WithTrials rend une copie du profil avec ces verdicts : le profil publié ne
// change jamais en place, un retrait en publie un nouveau.
func (p *Profile) WithTrials(results []TrialResult) *Profile {
	next := *p
	next.Trials = append([]TrialResult(nil), results...)
	return &next
}

// Candidates rend les encodeurs de ce codec qui n'ont pas été retirés.
func (p *Profile) Candidates(codec string) []EncoderCandidate {
	var out []EncoderCandidate
	for _, c := range p.Encoders {
		if c.Codec != codec {
			continue
		}
		if t, ok := p.Trial(TrialEncoderPrefix + c.Name); ok && !t.Usable() {
			continue
		}
		out = append(out, c)
	}
	return out
}

// HardwareFilters dit que la chaîne de cette surface garde l'image sur le
// circuit, essai passé et pas retirée.
func (p *Profile) HardwareFilters(surface string) bool {
	if surface == "" {
		return false
	}
	t, ok := p.Trial(TrialFiltersPrefix + surface)
	return ok && t.Usable()
}

// Libplacebo dit si libplacebo tourne, et s'il tourne sur un circuit.
func (p *Profile) Libplacebo() (usable, gpu bool) {
	t, ok := p.Trial(TrialVulkan)
	return ok && t.Works, ok && t.Works && t.GPU
}

// Zscale dit que ce FFmpeg sait tone mapper par zscale.
func (p *Profile) Zscale() bool {
	return p.Inventory.FFmpeg.HasFilter("zscale") && p.Inventory.FFmpeg.HasFilter("tonemap")
}

// StageCost rend le coût par mégapixel·image d'une variante : la mesure si le
// banc l'a faite, sinon la référence, dont la part CPU est ramenée à la
// vitesse mesurée des cœurs de cette machine. ok est faux pour une variante
// que rien ne décrit.
func (p *Profile) StageCost(stage Stage, variant string, hardware bool) (StageCost, bool) {
	for _, c := range p.Costs {
		if c.Stage == stage && c.Variant == variant {
			return c, true
		}
	}
	ref, ok := referenceCost(stage, variant, hardware)
	if !ok {
		return StageCost{}, false
	}
	ref.CPU *= p.cpuRatio()
	return StageCost{Stage: stage, Variant: variant, Cost: ref, Estimated: true}, true
}

// cpuRatio est la vitesse des cœurs de cette machine rapportée à la machine
// de référence, par l'étalon (x264 veryfast) ; 1 sans mesure.
func (p *Profile) cpuRatio() float64 {
	ref, _ := referenceCost(StageEncode, anchorVariant, false)
	for _, c := range p.Costs {
		if c.Stage == StageEncode && c.Variant == anchorVariant && !c.Estimated && c.Cost.CPU > 0 {
			return c.Cost.CPU / ref.CPU
		}
	}
	return 1
}

// ErrStale dit que le cache décrit une autre machine, ou une autre version.
var ErrStale = errors.New("capacity: le profil en cache ne correspond plus à cette machine")

// LoadProfile lit le profil en cache, s'il décrit bien cette machine.
func LoadProfile(path string, want Fingerprint) (*Profile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var p Profile
	if err := json.Unmarshal(data, &p); err != nil {
		return nil, fmt.Errorf("capacity: cache illisible %s: %w", path, err)
	}
	if !p.Fingerprint.Same(want) {
		return nil, ErrStale
	}
	return &p, nil
}

// SaveProfile écrit le profil, par un fichier temporaire renommé : un arrêt
// au milieu de l'écriture ne laisse pas un cache tronqué.
func SaveProfile(path string, p *Profile) error {
	data, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		return fmt.Errorf("capacity: encodage du profil: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("capacity: dossier du cache: %w", err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return fmt.Errorf("capacity: écriture du cache: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		return fmt.Errorf("capacity: remplacement du cache: %w", err)
	}
	return nil
}
