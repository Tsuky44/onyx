package bench

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"
)

// FFmpeg est le binaire que le banc lance.
var FFmpeg = "ffmpeg"

// Result est ce que coûte une commande FFmpeg.
type Result struct {
	// Elapsed est le temps écoulé, démarrage du processus compris.
	Elapsed time.Duration
	// CPU est le temps processeur (utilisateur et système) de FFmpeg, sur tous
	// ses threads.
	CPU time.Duration
	// Frames est le nombre d'images que FFmpeg a écrites en sortie.
	Frames int
}

// Measure lance FFmpeg avec ces arguments et rend ce que la commande a coûté.
// La commande doit écrire une sortie (`-f null -` suffit) : les images se
// comptent par le rapport de progression que Measure demande lui-même.
func Measure(args []string) (Result, error) {
	return MeasureContext(context.Background(), args)
}

// MeasureContext est Measure, annulable.
func MeasureContext(ctx context.Context, args []string) (Result, error) {
	return measure(ctx, args, false)
}

// MeasureBackground est MeasureContext en priorité basse : le profil du
// serveur mesure pendant que le serveur sert, et ne doit prendre que le
// processeur que personne n'utilise. Le temps processeur compté ne change
// pas ; seul le temps écoulé peut s'allonger si la machine est occupée.
func MeasureBackground(ctx context.Context, args []string) (Result, error) {
	return measure(ctx, args, true)
}

func measure(ctx context.Context, args []string, background bool) (Result, error) {
	cmd := exec.CommandContext(ctx, FFmpeg, progressArgs(args)...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr

	start := time.Now()
	err := cmd.Start()
	if err == nil {
		if background {
			lowerPriority(cmd.Process.Pid)
		}
		err = cmd.Wait()
	}
	elapsed := time.Since(start)
	if err != nil {
		return Result{}, fmt.Errorf("ffmpeg %s: %w: %s", strings.Join(args, " "), err, lastLine(stderr.String()))
	}
	return Result{
		Elapsed: elapsed,
		CPU:     cpuTime(cmd.ProcessState),
		Frames:  parseProgressFrames(stdout.String()),
	}, nil
}

// MeasureMedian lance la commande runs fois et rend la mesure médiane selon le
// temps processeur : une seule passe est trop sensible au bruit de la machine
// (un autre processus, la fréquence qui monte) pour qu'une soustraction en soit
// fiable.
func MeasureMedian(ctx context.Context, args []string, runs int) (Result, error) {
	if runs < 1 {
		runs = 1
	}
	results := make([]Result, 0, runs)
	for i := 0; i < runs; i++ {
		r, err := MeasureContext(ctx, args)
		if err != nil {
			return Result{}, err
		}
		results = append(results, r)
	}
	return medianByCPU(results), nil
}

// medianByCPU est la mesure du milieu quand on les trie par temps processeur
// (la plus haute des deux du milieu pour un nombre pair).
func medianByCPU(results []Result) Result {
	if len(results) == 0 {
		return Result{}
	}
	sorted := append([]Result(nil), results...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].CPU < sorted[j].CPU })
	return sorted[len(sorted)/2]
}

// progressArgs ajoute le rapport de progression lisible par une machine, sur la
// sortie standard, devant les arguments de la commande.
func progressArgs(args []string) []string {
	return append([]string{"-nostats", "-progress", "pipe:1"}, args...)
}

// parseProgressFrames lit la dernière ligne `frame=N` du rapport de
// progression : le nombre d'images écrites quand FFmpeg a fini. 0 sans rapport.
func parseProgressFrames(report string) int {
	frames := 0
	for _, line := range strings.Split(report, "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok || key != "frame" {
			continue
		}
		if n, err := strconv.Atoi(strings.TrimSpace(value)); err == nil {
			frames = n
		}
	}
	return frames
}

// cpuTime est le temps processeur d'un processus terminé.
func cpuTime(state *os.ProcessState) time.Duration {
	if state == nil {
		return 0
	}
	return state.UserTime() + state.SystemTime()
}

// lastLine est la dernière ligne non vide, pour résumer la sortie d'erreur de
// FFmpeg dans un message.
func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	return strings.TrimSpace(lines[len(lines)-1])
}
