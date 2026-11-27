package streaming

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

// Le périphérique Vulkan de libplacebo.
//
// Le tone mapping d'un Dolby Vision profil 5 passe par libplacebo (ADR-0060),
// et libplacebo par Vulkan. L'image n'avait que le Vulkan logiciel de Mesa
// (lavapipe), choisi pour l'hôte sans GPU : la commande demandait `vulkan`
// tout court, et tombait dessus même sur une machine dont le circuit vidéo
// était passé au conteneur.
//
// Mesuré sur un i7-10700K, un épisode 4K profil 5 vers 1080p : « encodé à
// 0.6× la vitesse de lecture », seize threads `llvmpipe` au travail, 100 °C.
// Reproduit sur 4 cœurs : 9,1 cœur-secondes par seconde de film, contre 3,4
// pour un HDR10 tone mappé par zscale. C'est le rendu logiciel qui coûte.
//
// D'où ce choix au démarrage, fait par la machine et pas pour elle : les
// périphériques sont listés, chacun fait tourner le filtre d'une session, et
// quand plusieurs y arrivent ils sont chronométrés sur les mêmes images. Le
// plus rapide est retenu. Un serveur sans circuit garde donc le rendu logiciel
// et tous ses cœurs, comme avant ; un serveur dont le circuit va plus vite que
// ses cœurs prend le circuit ; et un serveur à beaucoup de cœurs dont le
// circuit serait plus lent garde ses cœurs. Le pilote Vulkan d'Intel est dans
// l'image pour cela (Dockerfile). Rien n'a tourné sur un vrai circuit avant
// d'être écrit : si une session y meurt avant son premier segment, le serveur
// revient au rendu logiciel.

// vulkanDevice est un périphérique que FFmpeg a listé.
type vulkanDevice struct {
	Index int
	Name  string
	// Kind est le mot de FFmpeg : integrated, discrete, virtual, software.
	Kind string
}

func (d vulkanDevice) software() bool { return d.Kind == "software" }

// vulkanChoice est ce que le démarrage a retenu.
type vulkanChoice struct {
	// Spec est la valeur de -init_hw_device.
	Spec string
	// GPU dit que Spec n'est pas le rendu logiciel.
	GPU bool
	// Fallback est le rendu logiciel à reprendre si le circuit lâche une
	// session ; vide quand il n'y en a pas, ou que Spec l'est déjà.
	Fallback string
}

// legacyVulkanSpec laisse FFmpeg prendre le premier périphérique : ce que le
// serveur demandait avant, et ce qu'il demande encore quand la liste des
// périphériques n'a pas pu être lue.
const legacyVulkanSpec = "vulkan"

var vulkanChosen atomic.Pointer[vulkanChoice]

// vulkanInitArgs ouvre le périphérique Vulkan d'une commande à libplacebo.
func vulkanInitArgs() []string {
	if choice := vulkanChosen.Load(); choice != nil {
		return []string{"-init_hw_device", choice.Spec}
	}
	return []string{"-init_hw_device", legacyVulkanSpec}
}

// vulkanOnGPU dit que libplacebo tourne sur un vrai circuit.
func vulkanOnGPU() bool {
	choice := vulkanChosen.Load()
	return choice != nil && choice.GPU
}

// vulkanListLine reconnaît une ligne de la liste de FFmpeg, écrite en
// `verbose` à l'ouverture du périphérique :
//
//	[AVHWDeviceContext @ 0x…]     0: Intel(R) UHD Graphics 630 (CML GT2) (integrated) (0x9bc5)
var vulkanListLine = regexp.MustCompile(
	`(?m)^(?:\[[^\]]*\])?\s*(\d+): (.+) \((integrated|discrete|virtual|software|unknown)\) \(0x[0-9a-fA-F]+\)\s*$`)

// parseVulkanDevices lit la liste des périphériques dans la sortie de FFmpeg.
func parseVulkanDevices(output string) []vulkanDevice {
	var devices []vulkanDevice
	for _, match := range vulkanListLine.FindAllStringSubmatch(output, -1) {
		index, err := strconv.Atoi(match[1])
		if err != nil {
			continue
		}
		devices = append(devices, vulkanDevice{Index: index, Name: match[2], Kind: match[3]})
	}
	return devices
}

// chooseVulkanDevice retient le périphérique de libplacebo.
//
// works dit si le filtre d'une session tourne sur un périphérique ; race le
// chronomètre sur une charge plus lourde. Un seul périphérique qui marche est
// pris sans course : c'est le cas de tout serveur sans circuit, et il n'a pas
// à payer une seconde de rendu logiciel de plus à chaque démarrage. À temps
// égal le circuit l'emporte, puisqu'il laisse les cœurs au décodage et à
// l'encodage de la même session.
//
// forced est VULKAN_DEVICE : l'opérateur nomme le périphérique (un index, ou
// un morceau de son nom, `llvmpipe` pour le rendu logiciel) et rien d'autre
// n'est essayé.
func chooseVulkanDevice(
	devices []vulkanDevice,
	forced string,
	works func(spec string) error,
	race func(spec string) (time.Duration, error),
) (vulkanChoice, bool) {
	if forced != "" {
		spec := legacyVulkanSpec + ":" + forced
		if err := works(spec); err != nil {
			log.Printf("Streaming: VULKAN_DEVICE=%s cannot run libplacebo: %v", forced, err)
			return vulkanChoice{}, false
		}
		log.Printf("Streaming: libplacebo renders on VULKAN_DEVICE=%s", forced)
		return vulkanChoice{Spec: spec, GPU: !strings.Contains(strings.ToLower(forced), "llvmpipe")}, true
	}
	if len(devices) == 0 {
		// Pas de liste : un FFmpeg qui ne l'écrit pas, ou aucun pilote. L'essai
		// d'avant tranche, sur le périphérique que FFmpeg prend de lui-même.
		if err := works(legacyVulkanSpec); err != nil {
			return vulkanChoice{}, false
		}
		log.Println("Streaming: libplacebo renders on the default Vulkan device")
		return vulkanChoice{Spec: legacyVulkanSpec}, true
	}

	type candidate struct {
		device vulkanDevice
		spec   string
		took   time.Duration
	}
	var usable []candidate
	for _, device := range devices {
		spec := fmt.Sprintf("%s:%d", legacyVulkanSpec, device.Index)
		if err := works(spec); err != nil {
			log.Printf("Streaming: libplacebo does not run on %s (%s): %v", device.Name, device.Kind, err)
			continue
		}
		usable = append(usable, candidate{device: device, spec: spec})
	}
	if len(usable) == 0 {
		return vulkanChoice{}, false
	}

	if len(usable) > 1 {
		raced := usable[:0]
		for _, c := range usable {
			took, err := race(c.spec)
			if err != nil {
				log.Printf("Streaming: libplacebo failed its timed run on %s (%s): %v", c.device.Name, c.device.Kind, err)
				continue
			}
			log.Printf("Streaming: libplacebo on %s (%s): %s for the timed run",
				c.device.Name, c.device.Kind, took.Round(time.Millisecond))
			c.took = took
			raced = append(raced, c)
		}
		if len(raced) == 0 {
			return vulkanChoice{}, false
		}
		usable = raced
		sort.SliceStable(usable, func(i, j int) bool {
			if usable[i].took != usable[j].took {
				return usable[i].took < usable[j].took
			}
			return !usable[i].device.software() && usable[j].device.software()
		})
	}

	best := usable[0]
	choice := vulkanChoice{Spec: best.spec, GPU: !best.device.software()}
	if choice.GPU {
		for _, c := range usable[1:] {
			if c.device.software() {
				choice.Fallback = c.spec
				break
			}
		}
		log.Printf("Streaming: libplacebo renders on %s (%s)", best.device.Name, best.device.Kind)
	} else {
		log.Printf("Streaming: libplacebo renders on %s (software): tone mapping a Dolby Vision "+
			"profile 5 source will keep every core busy", best.device.Name)
	}
	return choice, true
}

// resolveVulkanDevice liste les périphériques, choisit, et retient le choix.
func resolveVulkanDevice() bool {
	forced := strings.TrimSpace(os.Getenv("VULKAN_DEVICE"))
	var devices []vulkanDevice
	if forced == "" {
		devices = listVulkanDevices()
		// La liste entière, pas seulement le choix : c'est elle qui dit si
		// la carte ou le circuit que l'opérateur a passés au conteneur y
		// sont visibles par Vulkan.
		log.Printf("Streaming: Vulkan devices seen: %s", describeVulkanDevices(devices))
	}
	choice, ok := chooseVulkanDevice(devices, forced, libplaceboRunsOn, libplaceboRace)
	if ok {
		vulkanChosen.Store(&choice)
	}
	return ok
}

// describeVulkanDevices écrit la liste pour le journal.
func describeVulkanDevices(devices []vulkanDevice) string {
	if len(devices) == 0 {
		return "none listed"
	}
	parts := make([]string, 0, len(devices))
	for _, device := range devices {
		parts = append(parts, fmt.Sprintf("%d: %s (%s)", device.Index, device.Name, device.Kind))
	}
	return strings.Join(parts, ", ")
}

// listVulkanDevices demande à FFmpeg d'ouvrir un périphérique Vulkan en
// `verbose` : il écrit la liste avant de choisir, même s'il échoue ensuite.
func listVulkanDevices() []vulkanDevice {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	// L'erreur ne dit rien ici : sans aucun pilote la liste est vide, et c'est
	// l'essai du filtre qui décide.
	output, _ := exec.CommandContext(ctx, "ffmpeg",
		"-hide_banner", "-loglevel", "verbose", "-nostdin",
		"-init_hw_device", legacyVulkanSpec,
		"-f", "lavfi", "-i", "color=c=black:s=16x16",
		"-frames:v", "1", "-f", "null", "-",
	).CombinedOutput()
	return parseVulkanDevices(string(output))
}

// libplaceboProbeArgs fait passer des images 10 bits par le filtre d'une
// session, sur le périphérique donné.
func libplaceboProbeArgs(spec, size string, frames int) []string {
	return []string{
		"-hide_banner", "-loglevel", "error", "-nostdin",
		"-init_hw_device", spec,
		"-f", "lavfi", "-i", "testsrc2=size=" + size + ":rate=24,format=yuv420p10le",
		"-frames:v", strconv.Itoa(frames),
		"-vf", doviToSDRFilter,
		"-f", "null", "-",
	}
}

// libplaceboRunsOn dit si le filtre d'une session tourne sur ce périphérique.
func libplaceboRunsOn(spec string) error {
	_, err := runLibplaceboProbe(libplaceboProbeArgs(spec, "320x240", 2))
	return err
}

// libplaceboRace chronomètre une seconde de 720p sur ce périphérique. Assez
// d'images pour que le rendu pèse plus que l'ouverture du périphérique et la
// compilation de ses shaders, assez peu pour que le rendu logiciel d'un petit
// serveur ne retarde pas le démarrage de plus de quelques secondes.
func libplaceboRace(spec string) (time.Duration, error) {
	return runLibplaceboProbe(libplaceboProbeArgs(spec, "1280x720", 24))
}

func runLibplaceboProbe(args []string) (time.Duration, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	started := time.Now()
	output, err := exec.CommandContext(ctx, "ffmpeg", args...).CombinedOutput()
	if err != nil {
		return 0, fmt.Errorf("%w %s", err, strings.TrimSpace(string(output)))
	}
	return time.Since(started), nil
}

// noteVulkanSessionDied ramène libplacebo sur le rendu logiciel : une session
// vient de mourir sur le circuit avant son premier segment. L'essai du
// démarrage n'a vu qu'une image de synthèse, pas la couche RPU d'un film.
func noteVulkanSessionDied(sessionID, stderr string) {
	choice := vulkanChosen.Load()
	if choice == nil || !choice.GPU || choice.Fallback == "" {
		return
	}
	software := vulkanChoice{Spec: choice.Fallback}
	if vulkanChosen.CompareAndSwap(choice, &software) {
		log.Printf("Streaming: session %s died with libplacebo on the GPU before its first segment, "+
			"software Vulkan from now on: %s", sessionID, strings.TrimSpace(stderr))
	}
}
