package capacity

import (
	"bufio"
	"context"
	"io/fs"
	"os"
	"os/exec"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"
)

// L'inventaire de la machine : ce qu'on sait sans rien lancer de lourd.
//
// Tout se lit dans des fichiers (cgroup, /proc, /dev) ou dans quatre questions
// rapides à FFmpeg. Les fichiers passent par un fs.FS : os.DirFS("/") en
// production, une table de contenus fictifs dans les tests, pour décrire un
// Raspberry Pi ou un conteneur bridé sans en avoir un.

// Inventory est ce que la machine a.
type Inventory struct {
	// Cores est GOMAXPROCS(0) : les cœurs que le quota du conteneur laisse,
	// et non ceux de l'hôte (voir streaming/cores.go).
	Cores int `json:"cores"`
	// MemoryBytes est la mémoire utilisable : la limite du cgroup quand elle
	// est plus basse que la mémoire de la machine. 0 : inconnue.
	MemoryBytes int64  `json:"memory_bytes,omitempty"`
	Arch        string `json:"arch"`
	CPUModel    string `json:"cpu_model,omitempty"`
	// RenderNodes sont les nœuds `/dev/dri/renderD*` : un circuit que VAAPI
	// et Vulkan peuvent ouvrir.
	RenderNodes []string `json:"render_nodes,omitempty"`
	// NvidiaNodes sont les nœuds `/dev/nvidia*` passés au conteneur.
	NvidiaNodes []string        `json:"nvidia_nodes,omitempty"`
	FFmpeg      FFmpegInventory `json:"ffmpeg"`
}

// FFmpegInventory est ce que le FFmpeg de la machine dit de lui-même. Ce qui
// est compilé n'est pas ce qui marche (ADR-0023 §2) : ces listes ne servent
// qu'à ne pas essayer ce qui n'existe pas.
type FFmpegInventory struct {
	Version  string   `json:"version,omitempty"`
	Encoders []string `json:"encoders,omitempty"`
	Filters  []string `json:"filters,omitempty"`
	HWAccels []string `json:"hwaccels,omitempty"`
}

// HasEncoder dit que ce FFmpeg a été compilé avec cet encodeur.
func (f FFmpegInventory) HasEncoder(name string) bool { return contains(f.Encoders, name) }

// HasFilter dit que ce FFmpeg a ce filtre.
func (f FFmpegInventory) HasFilter(name string) bool { return contains(f.Filters, name) }

func contains(list []string, name string) bool {
	i := sort.SearchStrings(list, name)
	return i < len(list) && list[i] == name
}

// Runner lance FFmpeg et rend sa sortie standard. Remplacé dans les tests.
type Runner func(ctx context.Context, args ...string) (string, error)

// RunFFmpeg est le Runner de production.
func RunFFmpeg(ctx context.Context, args ...string) (string, error) {
	out, err := exec.CommandContext(ctx, "ffmpeg", args...).Output()
	return string(out), err
}

// SystemRoot est la racine des fichiers lus en production.
func SystemRoot() fs.FS { return os.DirFS("/") }

// ReadInventory lit l'inventaire. root contient les chemins sans leur « / »
// de tête (`proc/meminfo`). Une lecture qui échoue laisse son champ vide :
// une machine sans /proc (Windows, macOS en développement) a un inventaire
// pauvre, pas une erreur.
func ReadInventory(ctx context.Context, root fs.FS, run Runner) Inventory {
	inv := Inventory{
		Cores:    runtime.GOMAXPROCS(0),
		Arch:     runtime.GOARCH,
		CPUModel: cpuModel(readFile(root, "proc/cpuinfo")),
		MemoryBytes: usableMemory(
			readFile(root, "sys/fs/cgroup/memory.max"),
			readFile(root, "sys/fs/cgroup/memory/memory.limit_in_bytes"),
			readFile(root, "proc/meminfo"),
		),
		RenderNodes: deviceNodes(root, "dev/dri", "renderD"),
		NvidiaNodes: deviceNodes(root, "dev", "nvidia"),
	}
	if run != nil {
		inv.FFmpeg = readFFmpeg(ctx, run)
	}
	return inv
}

func readFile(root fs.FS, name string) string {
	data, err := fs.ReadFile(root, name)
	if err != nil {
		return ""
	}
	return string(data)
}

// cpuModel lit le modèle du processeur dans /proc/cpuinfo : `model name` sur
// x86, `Model` sur un Raspberry Pi, `Hardware` sur d'autres ARM.
func cpuModel(cpuinfo string) string {
	found := map[string]string{}
	scanner := bufio.NewScanner(strings.NewReader(cpuinfo))
	for scanner.Scan() {
		key, value, ok := strings.Cut(scanner.Text(), ":")
		if !ok {
			continue
		}
		key, value = strings.TrimSpace(key), strings.TrimSpace(value)
		if _, seen := found[key]; !seen && value != "" {
			found[key] = value
		}
	}
	for _, key := range []string{"model name", "Model", "Hardware", "cpu model", "Processor"} {
		if v := found[key]; v != "" {
			return v
		}
	}
	return ""
}

// unlimitedCgroup sépare une vraie limite de l'absence de limite : un cgroup
// v1 sans limite écrit le plus grand multiple de page sous 2^63. Tout ce qui
// dépasse un exaoctet est traité de même.
const unlimitedCgroup = int64(1) << 60

// usableMemory est la plus basse des limites connues : cgroup v2
// (`memory.max`), cgroup v1 (`memory.limit_in_bytes`), puis MemTotal.
func usableMemory(cgroupV2, cgroupV1, meminfo string) int64 {
	var best int64
	take := func(v int64) {
		if v > 0 && v < unlimitedCgroup && (best == 0 || v < best) {
			best = v
		}
	}
	if v := strings.TrimSpace(cgroupV2); v != "" && v != "max" {
		n, _ := strconv.ParseInt(v, 10, 64)
		take(n)
	}
	if v := strings.TrimSpace(cgroupV1); v != "" {
		n, _ := strconv.ParseInt(v, 10, 64)
		take(n)
	}
	take(memTotal(meminfo))
	return best
}

// memTotal lit `MemTotal: 16318432 kB` dans /proc/meminfo, en octets.
func memTotal(meminfo string) int64 {
	for _, line := range strings.Split(meminfo, "\n") {
		key, value, ok := strings.Cut(line, ":")
		if !ok || strings.TrimSpace(key) != "MemTotal" {
			continue
		}
		fields := strings.Fields(value)
		if len(fields) == 0 {
			return 0
		}
		n, err := strconv.ParseInt(fields[0], 10, 64)
		if err != nil {
			return 0
		}
		if len(fields) > 1 && strings.EqualFold(fields[1], "kB") {
			n *= 1024
		}
		return n
	}
	return 0
}

// deviceNodes liste les entrées de dir qui commencent par prefix, en chemins
// absolus triés.
func deviceNodes(root fs.FS, dir, prefix string) []string {
	entries, err := fs.ReadDir(root, dir)
	if err != nil {
		return nil
	}
	var nodes []string
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), prefix) {
			nodes = append(nodes, "/"+dir+"/"+entry.Name())
		}
	}
	sort.Strings(nodes)
	return nodes
}

// readFFmpeg pose les quatre questions. Chacune rend en quelques
// millisecondes ; une qui échoue laisse sa liste vide.
func readFFmpeg(ctx context.Context, run Runner) FFmpegInventory {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	ask := func(args ...string) string {
		out, err := run(ctx, append([]string{"-hide_banner"}, args...)...)
		if err != nil {
			return ""
		}
		return out
	}
	return FFmpegInventory{
		Version:  parseFFmpegVersion(ask("-version")),
		Encoders: parseCodecList(ask("-encoders")),
		Filters:  parseFilterList(ask("-filters")),
		HWAccels: parseHWAccels(ask("-hwaccels")),
	}
}

// parseFFmpegVersion lit `ffmpeg version 6.1.1 Copyright …`.
func parseFFmpegVersion(out string) string {
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && fields[0] == "ffmpeg" && fields[1] == "version" {
			return fields[2]
		}
	}
	return ""
}

// parseCodecList lit la sortie de `-encoders` : la légende d'abord, puis une
// ligne de tirets, puis ` V....D libx264  libx264 H.264 …`.
func parseCodecList(out string) []string {
	var names []string
	started := false
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if !started {
			started = len(fields) == 1 && strings.HasPrefix(fields[0], "---")
			continue
		}
		if len(fields) >= 2 {
			names = append(names, fields[1])
		}
	}
	sort.Strings(names)
	return names
}

// parseFilterList lit la sortie de `-filters` : ` T.C zscale  V->V  …`. Les
// lignes de la légende (` T.. = Timeline support`) n'ont pas de flèche.
func parseFilterList(out string) []string {
	var names []string
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && strings.Contains(fields[2], "->") {
			names = append(names, fields[1])
		}
	}
	sort.Strings(names)
	return names
}

// parseHWAccels lit la sortie de `-hwaccels` : un titre, puis un nom par ligne.
func parseHWAccels(out string) []string {
	var names []string
	for _, line := range strings.Split(out, "\n") {
		name := strings.TrimSpace(line)
		if name == "" || strings.HasSuffix(name, ":") || strings.Contains(name, " ") {
			continue
		}
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
