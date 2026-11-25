package capacity

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"project-player/server/streaming/capacity/bench"
)

// fakeBench répond aux mesures du banc selon la commande : chaque étape
// connue a un temps CPU et un temps écoulé, que la ligne de base n'a pas.
type fakeBench struct {
	seen []string
}

func (f *fakeBench) measure(_ context.Context, args []string) (bench.Result, error) {
	cmd := strings.Join(args, " ")
	f.seen = append(f.seen, cmd)
	r := bench.Result{CPU: time.Second, Elapsed: time.Second, Frames: benchFrames}
	switch {
	case strings.Contains(cmd, "-c:v libx264 -preset veryfast"):
		r.CPU += 2 * time.Second
	case strings.Contains(cmd, "-c:v h264_vaapi"):
		r.CPU += 100 * time.Millisecond
		r.Elapsed += 500 * time.Millisecond
	case strings.Contains(cmd, "zscale"):
		return bench.Result{}, errors.New("zscale absent")
	}
	return r, nil
}

func TestMeasureCosts_SubtractsTheBaselinePerResource(t *testing.T) {
	f := &fakeBench{}
	costs := MeasureCosts(context.Background(), BenchInput{
		Dir:          t.TempDir(),
		ScaleFilter:  "scale=w=1280:h=720",
		ZscaleFilter: "zscale=t=linear",
		VAAPIDevice:  "/dev/dri/renderD128",
		X264Presets:  []string{"veryfast"},
		Hardware: []EncoderBench{{
			Candidate: vaapiH264, DeviceArgs: []string{"-vaapi_device", "/dev/dri/renderD128"},
			Upload: "format=nv12,hwupload",
		}},
	}, f.measure)

	byVariant := map[string]StageCost{}
	for _, c := range costs {
		byVariant[string(c.Stage)+":"+c.Variant] = c
	}
	perImage := float64(benchFrames) * bench.Megapixels(1920, 1080)
	if got := byVariant["encode:libx264/veryfast"].Cost.CPU; diff(got, 2/perImage) > 1e-6 {
		t.Errorf("x264 veryfast %.6f, voulu %.6f (2 s de CPU au-dessus de la ligne de base)", got, 2/perImage)
	}
	vaapi := byVariant["encode:h264_vaapi"].Cost
	if diff(vaapi.Encode, 0.5/perImage) > 1e-6 || diff(vaapi.CPU, 0.1/perImage) > 1e-6 {
		t.Errorf("h264_vaapi %+v : l'occupation vient du temps écoulé, le CPU du temps processeur", vaapi)
	}
	if _, ok := byVariant["tonemap:zscale"]; ok {
		t.Error("une mesure qui échoue ne doit pas laisser de coût")
	}
	for _, want := range []string{"decode:" + DecodeH264CPU, "decode:" + DecodeHEVC10VAAPI, "scale:" + ScaleVAAPI} {
		if _, ok := byVariant[want]; !ok {
			t.Errorf("%s non mesuré", want)
		}
	}
	// Une seule ligne de base pour x264 et swscale : même entrée, mêmes images.
	baselines := 0
	for _, cmd := range f.seen {
		if strings.Contains(cmd, "-c:v rawvideo") && !strings.Contains(cmd, "-vf") {
			baselines++
		}
	}
	if baselines != 1 {
		t.Errorf("%d lignes de base logicielles mesurées, voulu 1", baselines)
	}
}

// Les commandes du circuit ouvrent le périphérique et passent par l'envoi de
// l'encodeur, comme ses sessions.
func TestMeasureCosts_HardwareCommandsUseTheSessionDevice(t *testing.T) {
	f := &fakeBench{}
	MeasureCosts(context.Background(), BenchInput{
		Dir: t.TempDir(),
		Hardware: []EncoderBench{{
			Candidate:  EncoderCandidate{Name: "hevc_vaapi", Codec: "hevc", Hardware: true, Upload: true},
			DeviceArgs: []string{"-vaapi_device", "/dev/dri/renderD128"}, Upload: "format=p010,hwupload",
		}},
	}, f.measure)
	found := false
	for _, cmd := range f.seen {
		if strings.Contains(cmd, "-c:v hevc_vaapi") {
			found = true
			for _, want := range []string{"-vaapi_device /dev/dri/renderD128", "format=yuv420p10le", "-vf format=p010,hwupload"} {
				if !strings.Contains(cmd, want) {
					t.Errorf("commande sans %q : %s", want, cmd)
				}
			}
		}
	}
	if !found {
		t.Error("hevc_vaapi non mesuré")
	}
}

// Le banc ne tourne jamais pendant une session : il attend, et rend la main
// quand le serveur s'arrête.
func TestMeasureCosts_WaitsWhileTheServerIsBusy(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	f := &fakeBench{}
	busy := func() bool {
		cancel()
		return true
	}
	costs := MeasureCosts(ctx, BenchInput{Dir: t.TempDir(), X264Presets: []string{"veryfast"}, Busy: busy}, f.measure)
	if len(f.seen) != 0 || len(costs) != 0 {
		t.Errorf("le banc a mesuré pendant une session : %v", f.seen)
	}
}
