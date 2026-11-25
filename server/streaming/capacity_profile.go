package streaming

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"

	"project-player/server/safego"
	"project-player/server/streaming/capacity"
)

// Le profil matériel du serveur (docs/transcodage-adaptatif.md, phase 1).
//
// Les trois choix que fytroz faisait au démarrage — l'encodeur, la chaîne
// VAAPI, le périphérique de libplacebo — deviennent des essais d'un seul
// registre (capacity.Registry). Leurs commandes restent ici, dans leurs
// fichiers ; leurs verdicts vont dans le profil, avec le coût de chaque étape
// mesuré par le banc, et le profil est écrit dans le dossier de données.
//
// Au démarrage :
//   - un cache qui décrit cette machine alimente les choix tout de suite,
//     sans relancer aucun essai (critère 6) ;
//   - sinon, les trois choix se font comme avant, de façon synchrone, puis la
//     mesure tourne en arrière-plan. Tant qu'elle n'a pas fini, le serveur se
//     comporte exactement comme avant le profil ; ensuite, le planificateur
//     choisit la recette de chaque session.

var (
	// currentProfile est le profil publié, nil tant qu'il n'est pas prêt. Il
	// ne change jamais en place : un retrait ou une remesure en publie un autre.
	currentProfile atomic.Pointer[capacity.Profile]
	// capacityTrials est le registre des essais du serveur.
	capacityTrials = capacity.NewRegistry()
	// activeProfiler est le profileur lancé par StartCapacity, pour Remeasure.
	activeProfiler atomic.Pointer[capacity.Profiler]
	// measuring empêche deux mesures en même temps.
	measuring sync.Mutex
)

// capacityProfile est le profil prêt, ou nil.
func capacityProfile() *capacity.Profile { return currentProfile.Load() }

// forcingVariables sont les variables qui forcent un choix du profil. En
// changer une change l'empreinte : le cache est remesuré.
var forcingVariables = []string{"VIDEO_ENCODER", "HARDWARE_FILTERS", "VULKAN_DEVICE", "VAAPI_DEVICE"}

func capacityForcings() map[string]string {
	forcings := map[string]string{}
	for _, name := range forcingVariables {
		forcings[name] = os.Getenv(name)
	}
	return forcings
}

// StartCapacity lit le profil en cache, ou fait les choix d'avant le profil
// et lance la mesure en arrière-plan. À appeler une fois, au démarrage, avant
// de servir : dataDir est le dossier de la base, serverVersion la version du
// serveur.
func (h *Handler) StartCapacity(dataDir, serverVersion string) {
	profiler := &capacity.Profiler{
		Path:     filepath.Join(dataDir, capacity.CacheFileName),
		Server:   serverVersion,
		Forcings: capacityForcings(),
		Root:     capacity.SystemRoot(),
		Run:      capacity.RunFFmpeg,
		Registry: capacityTrials,
		Describe: describeCapacity,
	}
	activeProfiler.Store(profiler)
	ctx := context.Background()
	inv, fp := profiler.Inventory(ctx)
	registerTrials(capacityTrials, inv)

	if profile, ok := profiler.Cached(fp); ok {
		applyProfile(profile)
		log.Printf("Streaming: profil matériel lu du cache (mesuré le %s), aucun essai relancé",
			profile.MeasuredAt.Format("2006-01-02 15:04"))
		return
	}

	// Le comportement d'avant le profil, à l'identique : ces trois choix
	// lancent FFmpeg, et leur verdict doit être au journal avant la première
	// lecture.
	recordLegacyChoices(capacityTrials)

	busy := func() bool { return h.manager.LiveCountExcept([32]byte{}) > 0 }
	go safego.Run("capacity-profile", func() { measureProfile(ctx, profiler, inv, fp, busy, false) })
}

// Remeasure refait tous les essais et toutes les mesures, en arrière-plan,
// et publie le nouveau profil : pour la page d'administration (phase 7), ou
// après un changement de matériel que l'empreinte ne voit pas. Faux si aucun
// profileur n'a été lancé.
//
// Le planificateur, le périphérique Vulkan et libplacebo suivent le nouveau
// profil dès sa publication. Les choix d'avant le profil (encodeur et chaîne
// VAAPI d'un VIDEO_ENCODER forcé), résolus une fois par processus, le suivent
// au prochain démarrage, qui lit le nouveau cache.
func (h *Handler) Remeasure() bool {
	profiler := activeProfiler.Load()
	if profiler == nil {
		return false
	}
	busy := func() bool { return h.manager.LiveCountExcept([32]byte{}) > 0 }
	go safego.Run("capacity-remeasure", func() {
		inv, fp := profiler.Inventory(context.Background())
		measureProfile(context.Background(), profiler, inv, fp, busy, true)
	})
	return true
}

// measureProfile construit, publie et écrit le profil.
func measureProfile(ctx context.Context, profiler *capacity.Profiler, inv capacity.Inventory,
	fp capacity.Fingerprint, busy func() bool, fresh bool) {
	measuring.Lock()
	defer measuring.Unlock()
	describe := profiler.Describe
	p := *profiler
	p.Describe = func(inv capacity.Inventory, results []capacity.TrialResult) ([]capacity.EncoderCandidate, capacity.BenchInput) {
		encoders, input := describe(inv, results)
		input.Busy = busy
		return encoders, input
	}
	profile, err := p.Build(ctx, inv, fp, fresh)
	if profile == nil {
		log.Printf("Streaming: profil matériel non mesuré, le serveur garde ses choix de démarrage : %v", err)
		return
	}
	if err != nil {
		log.Printf("Streaming: profil matériel non écrit, il sera remesuré au prochain démarrage : %v", err)
	}
	if fresh {
		hardwareFiltersOff.Store(false)
		if choice, ok := vulkanChoiceOf(profile); ok {
			vulkanChosen.Store(&choice)
		}
	}
	currentProfile.Store(profile)
	log.Printf("Streaming: profil matériel prêt en %.1f s (%d cœurs, %s, FFmpeg %s) : %s",
		profile.MeasureSeconds, inv.Cores, orUnknown(inv.CPUModel), orUnknown(inv.FFmpeg.Version), encoderNames(profile))
}

// startupChoices sont les choix d'avant le profil, tels qu'un profil en cache
// les a gardés.
type startupChoices struct {
	encoder        VideoEncoder
	hevc           VideoEncoder
	hevcOK         bool
	hevcKnown      bool
	hardwareFilter bool
	libplacebo     bool
	vulkan         *vulkanChoice
}

// choicesFromProfile relit les choix de démarrage dans un profil : l'encodeur
// que VIDEO_ENCODER avait retenu, son HEVC, la chaîne sur le circuit (pas
// retirée), libplacebo et son périphérique.
func choicesFromProfile(profile *capacity.Profile) startupChoices {
	c := startupChoices{encoder: softwareEncoder}
	if t, ok := profile.Trial(capacity.TrialSelectedEncoder); ok {
		if enc, found := encoderByName(t.Choice); found {
			c.encoder = enc
		}
	}
	if t, ok := profile.Trial(capacity.TrialSelectedHEVC); ok {
		c.hevcKnown = true
		enc, found := encoderByName(t.Choice)
		c.hevc, c.hevcOK = enc, found && t.Works
	}
	c.hardwareFilter = profile.HardwareFilters(c.encoder.surface)
	c.libplacebo, _ = profile.Libplacebo()
	if choice, ok := vulkanChoiceOf(profile); ok {
		c.vulkan = &choice
	}
	return c
}

// applyProfile alimente les choix de démarrage depuis un profil en cache, sans
// rien essayer, puis le publie.
func applyProfile(profile *capacity.Profile) {
	c := choicesFromProfile(profile)
	videoEncoderOnce.Do(func() {
		resolvedEncoder = c.encoder
		log.Printf("Streaming: video encoder %s (hardware=%v), from the hardware profile", c.encoder.Name, c.encoder.Hardware)
	})
	if c.hevcKnown {
		hevcEncoderOnce.Do(func() { resolvedHEVCEncoder, hevcEncoderOK = c.hevc, c.hevcOK })
	}
	hardwareFiltersOnce.Do(func() { hardwareFiltersOK = c.hardwareFilter })
	libplaceboOnce.Do(func() { libplaceboOK = c.libplacebo })
	if c.vulkan != nil {
		vulkanChosen.Store(c.vulkan)
		log.Printf("Streaming: libplacebo renders on %s (gpu=%v), from the hardware profile", c.vulkan.Spec, c.vulkan.GPU)
	}
	currentProfile.Store(profile)
}

// vulkanChoiceOf relit le choix du périphérique Vulkan dans le profil.
func vulkanChoiceOf(profile *capacity.Profile) (vulkanChoice, bool) {
	t, ok := profile.Trial(capacity.TrialVulkan)
	if !ok || !t.Works || t.Choice == "" {
		return vulkanChoice{}, false
	}
	return vulkanChoice{Spec: t.Choice, GPU: t.GPU, Fallback: t.Fallback}, true
}

// recordLegacyChoices fait les trois choix comme avant le profil, et en donne
// les verdicts au registre : la mesure en arrière-plan ne les refera pas.
func recordLegacyChoices(reg *capacity.Registry) {
	selected := SelectedVideoEncoder()
	reg.Record(capacity.TrialResult{
		Name: capacity.TrialSelectedEncoder, Works: true, Choice: selected.Name, GPU: selected.Hardware,
		Forced: forcedValue("VIDEO_ENCODER"),
	})
	filtersOK := HardwareFiltersUsable()
	if selected.surface != "" {
		reg.Record(capacity.TrialResult{
			Name: capacity.TrialFiltersPrefix + selected.surface, Works: filtersOK,
			Forced: forcedValue("HARDWARE_FILTERS"),
		})
	}
	ResolveToneMapping()
	vulkan := capacity.TrialResult{Name: capacity.TrialVulkan, Works: libplaceboOK, Forced: forcedValue("VULKAN_DEVICE")}
	if choice := vulkanChosen.Load(); choice != nil && libplaceboOK {
		vulkan.Choice, vulkan.GPU, vulkan.Fallback = choice.Spec, choice.GPU, choice.Fallback
	}
	reg.Record(vulkan)
}

func forcedValue(name string) string {
	if v := strings.TrimSpace(os.Getenv(name)); v != "" {
		return name + "=" + v
	}
	return ""
}

// registerTrials enregistre les essais du serveur, dans l'ordre où ils
// dépendent les uns des autres.
//
// Décision §0.1 du plan : la mesure décide de l'encodeur. Sans VIDEO_ENCODER,
// libx264 et chaque encodeur du circuit que ce FFmpeg connaît sont essayés,
// et tous ceux qui tournent deviennent des candidats du planificateur. Avec
// VIDEO_ENCODER (libx264 et auto compris), seul l'encodeur forcé l'est : le
// forçage passe avant la mesure.
func registerTrials(reg *capacity.Registry, inv capacity.Inventory) {
	reg.Register(capacity.Trial{
		Name: capacity.TrialSelectedEncoder, Forced: forcedValue("VIDEO_ENCODER"),
		Run: func(context.Context) capacity.TrialResult {
			enc := detectVideoEncoder(encoderWorks)
			return capacity.TrialResult{Works: true, Choice: enc.Name, GPU: enc.Hardware}
		},
	})
	reg.Register(capacity.Trial{
		Name: capacity.TrialSelectedHEVC,
		Run: func(context.Context) capacity.TrialResult {
			h264 := softwareEncoder
			if t, ok := reg.Result(capacity.TrialSelectedEncoder); ok {
				if enc, found := encoderByName(t.Choice); found {
					h264 = enc
				}
			}
			enc, ok := hevcEncoderFor(h264, encoderRuns)
			return capacity.TrialResult{Works: ok, Choice: enc.Name, GPU: enc.Hardware}
		},
	})
	if forcedValue("VIDEO_ENCODER") == "" {
		for _, enc := range measuredEncoders(inv) {
			enc := enc
			reg.Register(capacity.Trial{
				Name: capacity.TrialEncoderPrefix + enc.Name,
				Run: func(context.Context) capacity.TrialResult {
					if enc.isHEVC() {
						// Le HEVC d'un circuit n'est essayé que si son H.264 tourne.
						if h264, ok := reg.Result(capacity.TrialEncoderPrefix + h264SiblingName(enc.Name)); ok && !h264.Works {
							return capacity.TrialResult{Note: "le H.264 du même circuit ne tourne pas"}
						}
					}
					return capacity.TrialResult{Works: encoderRuns(enc), Choice: enc.Name, GPU: enc.Hardware}
				},
			})
		}
	}
	for _, enc := range hardwareEncoders {
		if enc.surface == "" {
			continue
		}
		enc := enc
		reg.Register(capacity.Trial{
			Name: capacity.TrialFiltersPrefix + enc.surface, Forced: forcedValue("HARDWARE_FILTERS"),
			Run: func(context.Context) capacity.TrialResult {
				if !encoderUsable(reg, enc.Name) {
					return capacity.TrialResult{Note: enc.Name + " n'est pas un encodeur de ce serveur"}
				}
				return capacity.TrialResult{Works: resolveHardwareFilters(enc), Choice: enc.surface, GPU: true}
			},
		})
	}
	reg.Register(capacity.Trial{
		Name: capacity.TrialVulkan, Forced: forcedValue("VULKAN_DEVICE"),
		Run: func(context.Context) capacity.TrialResult {
			if !ffmpegHasFilter("libplacebo") {
				return capacity.TrialResult{Note: "ce FFmpeg n'a pas libplacebo"}
			}
			choice, ok := measureVulkanDevice()
			return capacity.TrialResult{Works: ok, Choice: choice.Spec, GPU: choice.GPU, Fallback: choice.Fallback}
		},
	})
}

// encoderUsable dit qu'un encodeur est celui que VIDEO_ENCODER a retenu, ou
// un candidat qui a passé son essai.
func encoderUsable(reg *capacity.Registry, name string) bool {
	if t, ok := reg.Result(capacity.TrialSelectedEncoder); ok && t.Choice == name {
		return true
	}
	t, ok := reg.Result(capacity.TrialEncoderPrefix + name)
	return ok && t.Works
}

// measuredEncoders sont les encodeurs à essayer sans VIDEO_ENCODER : libx264
// et libx265, puis chaque encodeur du circuit que ce FFmpeg a compilé et dont
// le périphérique existe, suivi de son HEVC. Rien n'est essayé de ce qui ne
// peut pas tourner : c'est autant de FFmpeg en moins au premier démarrage.
func measuredEncoders(inv capacity.Inventory) []VideoEncoder {
	out := []VideoEncoder{softwareEncoder, softwareHEVCEncoder}
	for _, enc := range hardwareEncoders {
		if !inv.FFmpeg.HasEncoder(enc.Name) || !deviceFor(enc.Name, inv) {
			continue
		}
		out = append(out, enc)
		if sibling, ok := hevcSiblingOf(enc); ok && inv.FFmpeg.HasEncoder(sibling.Name) {
			out = append(out, sibling)
		}
	}
	return out
}

// deviceFor dit que la machine a le périphérique de cet encodeur.
func deviceFor(name string, inv capacity.Inventory) bool {
	switch {
	case strings.HasSuffix(name, "_videotoolbox"):
		return runtime.GOOS == "darwin"
	case strings.HasSuffix(name, "_nvenc"):
		return len(inv.NvidiaNodes) > 0
	case strings.HasSuffix(name, "_vaapi"), strings.HasSuffix(name, "_qsv"):
		return len(inv.RenderNodes) > 0
	}
	return true
}

// h264SiblingName est le H.264 du même circuit qu'un HEVC.
func h264SiblingName(hevc string) string {
	for h264, sibling := range hevcSiblings {
		if sibling.Name == hevc {
			return h264
		}
	}
	return ""
}

// encoderByName retrouve un encodeur que ce serveur sait lancer.
func encoderByName(name string) (VideoEncoder, bool) {
	switch name {
	case softwareEncoder.Name:
		return softwareEncoder, true
	case softwareHEVCEncoder.Name:
		return softwareHEVCEncoder, true
	}
	for _, enc := range hardwareEncoders {
		if enc.Name == name {
			return enc, true
		}
		if sibling, ok := hevcSiblingOf(enc); ok && sibling.Name == name {
			return sibling, true
		}
	}
	return VideoEncoder{}, false
}

func orUnknown(s string) string {
	if s == "" {
		return "inconnu"
	}
	return s
}

func encoderNames(profile *capacity.Profile) string {
	var names []string
	for _, c := range profile.Encoders {
		if !c.Fallback {
			names = append(names, c.Name)
		}
	}
	return "encodeurs candidats " + strings.Join(names, ", ")
}
