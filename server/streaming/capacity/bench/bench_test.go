package bench

import (
	"context"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestSourceGenerateArgs(t *testing.T) {
	tests := []struct {
		spec    SourceSpec
		want    []string
		wantNot []string
	}{
		{
			SDRH264,
			[]string{
				"-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24",
				"-frames:v", "48", "-c:v", "libx264", "-pix_fmt", "yuv420p", "out.mkv",
			},
			[]string{"-x265-params", "setparams"},
		},
		{
			HEVC10,
			[]string{
				"-i", "testsrc2=size=1920x1080:rate=24",
				"-c:v", "libx265", "-pix_fmt", "yuv420p10le", "-x265-params", "log-level=error",
			},
			[]string{"colorprim"},
		},
		{
			HDR10,
			[]string{
				"-i", "testsrc2=size=1920x1080:rate=24," + hdr10Marks,
				"-c:v", "libx265", "-pix_fmt", "yuv420p10le",
				"-x265-params", "log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc",
			},
			nil,
		},
	}
	for _, tt := range tests {
		t.Run(tt.spec.Name, func(t *testing.T) {
			args := tt.spec.GenerateArgs("out.mkv", 2)
			joined := " " + strings.Join(args, " ") + " "
			if !containsRun(args, tt.want) {
				t.Errorf("args %v ne contiennent pas, dans l'ordre, %v", args, tt.want)
			}
			for _, bad := range tt.wantNot {
				if strings.Contains(joined, bad) {
					t.Errorf("args %v contiennent %q", args, bad)
				}
			}
			if args[len(args)-1] != "out.mkv" {
				t.Errorf("la sortie est le dernier argument : %v", args)
			}
		})
	}
}

// containsRun dit que chaque élément de want est dans args, dans cet ordre.
func containsRun(args, want []string) bool {
	next := 0
	for _, a := range args {
		if next < len(want) && a == want[next] {
			next++
		}
	}
	return next == len(want)
}

func TestSources_TheThreePlanSourcesAreDistinct(t *testing.T) {
	names := map[string]bool{}
	for _, s := range Sources() {
		if names[s.Name] {
			t.Errorf("source %s en double", s.Name)
		}
		names[s.Name] = true
		if s.Width != 1920 || s.Height != 1080 {
			t.Errorf("%s : le plan veut du 1080p, pas %dx%d", s.Name, s.Width, s.Height)
		}
	}
	if len(names) != 3 {
		t.Errorf("%d sources, le plan en veut 3", len(names))
	}
	if !HDR10.HDR10 || HEVC10.HDR10 || SDRH264.HDR10 {
		t.Error("seule la source HDR10 est marquée BT.2020 PQ")
	}
}

func TestMegapixels(t *testing.T) {
	tests := []struct {
		w, h int
		want float64
	}{{1920, 1080, 2.0736}, {3840, 2160, 8.2944}, {1280, 720, 0.9216}, {0, 1080, 0}}
	for _, tt := range tests {
		if got := Megapixels(tt.w, tt.h); math.Abs(got-tt.want) > 1e-9 {
			t.Errorf("Megapixels(%d,%d) = %v, veut %v", tt.w, tt.h, got, tt.want)
		}
	}
}

// La ligne de base est la même commande sans l'étape : tout le reste égal.
func TestStepArgs_BaselineDiffersOnlyByTheStep(t *testing.T) {
	input := SDRH264.LavfiInput()
	step := Step{
		Name:   "encodage",
		Filter: "format=yuv420p",
		Codec:  []string{"-c:v", "libx264", "-preset", "veryfast"},
	}
	measured := step.MeasuredArgs(input, 48)
	baseline := step.BaselineArgs(input, 48)

	wantMeasured := []string{
		"-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24",
		"-vf", "format=yuv420p", "-frames:v", "48",
		"-c:v", "libx264", "-preset", "veryfast", "-f", "null", "-",
	}
	wantBaseline := []string{
		"-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24",
		"-frames:v", "48",
		"-c:v", "rawvideo", "-f", "null", "-",
	}
	if !reflect.DeepEqual(measured, wantMeasured) {
		t.Errorf("mesure\n got %v\nwant %v", measured, wantMeasured)
	}
	if !reflect.DeepEqual(baseline, wantBaseline) {
		t.Errorf("ligne de base\n got %v\nwant %v", baseline, wantBaseline)
	}
}

func TestStepArgs_AFilterOnlyStepKeepsTheBaselineCodec(t *testing.T) {
	step := Step{Name: "échelle", Filter: "scale=1280:720"}
	got := step.MeasuredArgs(FileInput("in.mkv"), 24)
	if !containsRun(got, []string{"-i", "in.mkv", "-vf", "scale=1280:720", "-frames:v", "24", "-c:v", "rawvideo"}) {
		t.Errorf("args inattendus : %v", got)
	}
}

func TestStepCost(t *testing.T) {
	tests := []struct {
		name               string
		measured, baseline Result
		mpx                float64
		want               float64
		wantErr            bool
	}{
		{
			name:     "soustrait la ligne de base",
			measured: Result{CPU: 10 * time.Second, Frames: 100},
			baseline: Result{CPU: 2 * time.Second, Frames: 100},
			mpx:      2, want: 8.0 / (100 * 2),
		},
		{
			name:     "une étape sans coût",
			measured: Result{CPU: 2 * time.Second, Frames: 100},
			baseline: Result{CPU: 2 * time.Second, Frames: 100},
			mpx:      2, want: 0,
		},
		{
			name:     "le bruit d'une ligne de base plus chère est ramené à 0",
			measured: Result{CPU: 2 * time.Second, Frames: 100},
			baseline: Result{CPU: 3 * time.Second, Frames: 100},
			mpx:      2, want: 0,
		},
		{
			name:     "images différentes : pas comparable",
			measured: Result{CPU: 5 * time.Second, Frames: 100},
			baseline: Result{CPU: 1 * time.Second, Frames: 90},
			mpx:      2, wantErr: true,
		},
		{
			name:     "aucune image",
			measured: Result{CPU: 5 * time.Second},
			baseline: Result{CPU: 1 * time.Second},
			mpx:      2, wantErr: true,
		},
		{
			name:     "taille inconnue",
			measured: Result{CPU: 5 * time.Second, Frames: 10},
			baseline: Result{CPU: 1 * time.Second, Frames: 10},
			mpx:      0, wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := StepCost(tt.measured, tt.baseline, tt.mpx)
			if (err != nil) != tt.wantErr {
				t.Fatalf("erreur = %v, attendue : %v", err, tt.wantErr)
			}
			if !tt.wantErr && math.Abs(got-tt.want) > 1e-12 {
				t.Errorf("coût %v, veut %v", got, tt.want)
			}
		})
	}
}

func TestCoresAt(t *testing.T) {
	// 0,04 cœur-s par Mpx·image, 2,0736 Mpx, 24 images/s.
	got := CoresAt(0.04, Megapixels(1920, 1080), 24)
	if want := 0.04 * 2.0736 * 24; math.Abs(got-want) > 1e-9 {
		t.Errorf("CoresAt = %v, veut %v", got, want)
	}
}

func TestParseProgressFrames(t *testing.T) {
	tests := []struct {
		name, report string
		want         int
	}{
		{"rapport complet : la dernière valeur", "frame=12\nfps=0.0\nprogress=continue\nframe=48\nfps=95.1\nprogress=end\n", 48},
		{"fins de ligne Windows", "frame=7\r\nprogress=end\r\n", 7},
		{"aucun rapport", "", 0},
		{"valeur illisible ignorée", "frame=N/A\nframe=3\nframe=oups\n", 3},
	}
	for _, tt := range tests {
		if got := parseProgressFrames(tt.report); got != tt.want {
			t.Errorf("%s : %d, veut %d", tt.name, got, tt.want)
		}
	}
}

func TestMedianByCPU(t *testing.T) {
	r := func(cpu int) Result { return Result{CPU: time.Duration(cpu) * time.Second} }
	if got := medianByCPU([]Result{r(9), r(1), r(5)}); got.CPU != 5*time.Second {
		t.Errorf("médiane de 9,1,5 : %v", got.CPU)
	}
	if got := medianByCPU([]Result{r(4), r(2)}); got.CPU != 4*time.Second {
		t.Errorf("médiane de deux mesures : %v", got.CPU)
	}
	if got := medianByCPU(nil); got != (Result{}) {
		t.Errorf("médiane de rien : %+v", got)
	}
}

func TestProgressArgs_PrecedesTheCommand(t *testing.T) {
	got := progressArgs([]string{"-i", "x"})
	want := []string{"-nostats", "-progress", "pipe:1", "-i", "x"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestStep_ToneMappingOnlyAppliesToTheHDRSource(t *testing.T) {
	for _, step := range StandardSteps() {
		if !strings.Contains(step.Filter, "tonemap") {
			if !step.Applies(SDRH264) {
				t.Errorf("%s doit se mesurer sur toutes les sources", step.Name)
			}
			continue
		}
		if step.Applies(SDRH264) || step.Applies(HEVC10) || !step.Applies(HDR10) {
			t.Errorf("%s : zscale n'accepte qu'une image au transfert connu", step.Name)
		}
	}
}

func TestStandardSteps_AreMeasurable(t *testing.T) {
	seen := map[string]bool{}
	for _, s := range StandardSteps() {
		if s.Name == "" || seen[s.Name] {
			t.Errorf("étape sans nom ou en double : %q", s.Name)
		}
		seen[s.Name] = true
		if s.Megapixels <= 0 {
			t.Errorf("%s : sans taille d'image, son coût ne se rapporte à rien", s.Name)
		}
		if s.Filter == "" && len(s.Codec) == 0 {
			t.Errorf("%s : une étape sans filtre ni codec ne mesure rien", s.Name)
		}
	}
}

// --- Avec un vrai FFmpeg : sautés quand il manque.

func requireFFmpeg(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath(FFmpeg); err != nil {
		t.Skip("ffmpeg absent : les mesures réelles sont sautées")
	}
}

// small est une source minuscule : le test vérifie le mécanisme, pas la machine.
var small = SourceSpec{Name: "petite", Width: 320, Height: 180, FPS: 24, Codec: "libx264", PixFmt: "yuv420p"}

func TestMeasure_CountsFramesAndCPU(t *testing.T) {
	requireFFmpeg(t)
	args := Step{Name: "rien", Filter: "null"}.BaselineArgs(small.LavfiInput(), 48)

	res, err := Measure(args)
	if err != nil {
		t.Fatalf("Measure: %v", err)
	}
	if res.Frames != 48 {
		t.Errorf("%d images, 48 attendues", res.Frames)
	}
	if res.Elapsed <= 0 || res.CPU <= 0 {
		t.Errorf("temps écoulé %v, processeur %v : un FFmpeg qui a tourné a coûté", res.Elapsed, res.CPU)
	}
}

func TestMeasure_ReportsAFailingCommand(t *testing.T) {
	requireFFmpeg(t)
	if _, err := Measure([]string{"-hide_banner", "-loglevel", "error", "-i", "/n/existe/pas.mkv", "-f", "null", "-"}); err == nil {
		t.Error("une commande qui échoue doit rendre son erreur, pas un coût de 0")
	}
}

func TestGenerateThenMeasureAStep(t *testing.T) {
	requireFFmpeg(t)
	path := filepath.Join(t.TempDir(), "source.mkv")
	if _, err := Measure(small.GenerateArgs(path, 2)); err != nil {
		t.Fatalf("génération : %v", err)
	}
	if info, err := os.Stat(path); err != nil || info.Size() == 0 {
		t.Fatalf("la source n'a pas été écrite : %v", err)
	}

	step := Step{
		Name: "échelle", Filter: "scale=160:90", Megapixels: small.Megapixels(),
	}
	frames := small.Frames(2)
	measured, err := MeasureMedian(context.Background(), step.MeasuredArgs(FileInput(path), frames), 3)
	if err != nil {
		t.Fatal(err)
	}
	baseline, err := MeasureMedian(context.Background(), step.BaselineArgs(FileInput(path), frames), 3)
	if err != nil {
		t.Fatal(err)
	}
	if measured.Frames != frames || baseline.Frames != frames {
		t.Fatalf("images %d et %d, %d attendues", measured.Frames, baseline.Frames, frames)
	}
	cost, err := StepCost(measured, baseline, step.Megapixels)
	if err != nil {
		t.Fatal(err)
	}
	if cost < 0 || math.IsNaN(cost) {
		t.Errorf("coût %v", cost)
	}
}

// ONYX_BENCH=1 go test ./streaming/capacity/bench -run TestReport -v -timeout 30m
//
// Génère les trois sources et chiffre chaque étape standard sur cette
// machine. Aucun seuil : le test écrit le tableau dans le journal de `-v`, que
// l'on copie dans docs/transcodage-adaptatif.md avec la machine et la version
// de FFmpeg. Sauté sans ONYX_BENCH, pour ne pas alourdir la suite.
func TestReport(t *testing.T) {
	if os.Getenv("ONYX_BENCH") == "" {
		t.Skip("ONYX_BENCH=1 pour lancer le banc")
	}
	requireFFmpeg(t)
	const seconds, runs = 5, 3
	dir := t.TempDir()
	for _, src := range Sources() {
		path := filepath.Join(dir, src.Name+".mkv")
		if _, err := Measure(src.GenerateArgs(path, seconds)); err != nil {
			t.Errorf("%s : génération impossible : %v", src.Name, err)
			continue
		}
		frames := src.Frames(seconds)
		for _, step := range StandardSteps() {
			if !step.Applies(src) {
				continue
			}
			measured, err := MeasureMedian(context.Background(), step.MeasuredArgs(FileInput(path), frames), runs)
			if err != nil {
				t.Logf("%-18s %-42s indisponible : %v", src.Name, step.Name, err)
				continue
			}
			baseline, err := MeasureMedian(context.Background(), step.BaselineArgs(FileInput(path), frames), runs)
			if err != nil {
				t.Logf("%-18s %-42s ligne de base impossible : %v", src.Name, step.Name, err)
				continue
			}
			cost, err := StepCost(measured, baseline, step.Megapixels)
			if err != nil {
				t.Logf("%-18s %-42s %v", src.Name, step.Name, err)
				continue
			}
			t.Logf("%-18s %-42s %.4f cœur·s/Mpx·image  (%.2f cœur à 24 images/s en 1080p)",
				src.Name, step.Name, cost, CoresAt(cost, step.Megapixels, 24))
		}
	}
}
