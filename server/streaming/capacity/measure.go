package capacity

import (
	"context"
	"errors"
	"log"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"project-player/server/streaming/capacity/bench"
)

// Le banc du profil : quelques dizaines d'images par étape, en priorité
// basse, sur les sources du banc de la phase 0.
//
// Le modèle est la course de fytroz (une seconde de 720p par périphérique) :
// assez d'images pour que l'étape pèse plus que le démarrage de FFmpeg, assez
// peu pour que toute la mesure tienne en moins de 20 s sur une petite machine
// (critère 6). Le chiffre est un ordre de grandeur sur une source de
// synthèse ; la rétroaction de la phase 5 le corrigera sur de vrais films.
//
// Sur le processeur, le coût est le temps CPU de la commande moins celui de
// sa ligne de base (bench.StepCost). Sur le circuit, le temps CPU ne dit rien
// du moteur : son occupation s'estime par le temps écoulé de la commande,
// moins celui de sa ligne de base, rapporté aux images traitées.

// benchFrames est le nombre d'images de chaque mesure : une seconde de film.
const benchFrames = 24

// benchWidth, benchHeight sont la taille des sources : 1080p, la taille que
// prennent les barreaux les plus lus. Le reste s'extrapole au prorata des
// pixels (PlanPipeline).
const benchWidth, benchHeight = 1920, 1080

// EncoderBench est un encodeur à mesurer, tel que streaming le lance.
type EncoderBench struct {
	Candidate EncoderCandidate
	// DeviceArgs ouvrent le périphérique de l'encodeur avant l'entrée.
	DeviceArgs []string
	// Upload termine la chaîne de filtres quand l'encodeur ne prend que des
	// images du périphérique (`format=nv12,hwupload`).
	Upload string
	// PixFmt est le format d'image que l'encodeur attend, vide pour un
	// encodeur à Upload.
	PixFmt string
}

// LibplaceboBench est libplacebo sur le périphérique retenu.
type LibplaceboBench struct {
	InitArgs []string
	Filter   string
	GPU      bool
}

// BenchInput est ce que le banc mesure. streaming le remplit avec ses propres
// filtres et encodeurs, pour que le banc mesure ce que les sessions lancent.
type BenchInput struct {
	// Dir reçoit les sources générées.
	Dir string
	// ScaleFilter est la mise à l'échelle logicielle de 1080p vers 720p.
	ScaleFilter string
	// ZscaleFilter est le tone mapping zscale, vide sans zscale.
	ZscaleFilter string
	// Libplacebo est nil quand libplacebo ne tourne pas.
	Libplacebo *LibplaceboBench
	// VAAPIDevice est le nœud de rendu, vide quand ni le décodage ni la mise
	// à l'échelle sur le circuit ne sont à mesurer.
	VAAPIDevice string
	// X264Presets sont les presets de libx264 à mesurer.
	X264Presets []string
	// Hardware sont les encodeurs du circuit qui ont passé leur essai.
	Hardware []EncoderBench
	// Busy dit qu'une session tourne : le banc attend qu'elle finisse, pour
	// ne jamais lui prendre de processeur ni fausser sa propre mesure.
	Busy func() bool
}

// Measurer lance une commande et rend ce qu'elle a coûté ; remplacé dans les
// tests.
type Measurer func(ctx context.Context, args []string) (bench.Result, error)

// MeasureCosts mesure chaque étape qu'elle peut, et rend leurs coûts par
// mégapixel·image. Une mesure qui échoue est journalisée et laissée de côté :
// le profil prendra la référence, marquée estimée.
func MeasureCosts(ctx context.Context, in BenchInput, measure Measurer) []StageCost {
	if measure == nil {
		measure = bench.MeasureBackground
	}
	m := &meter{ctx: ctx, in: in, measure: measure, baselines: map[string]bench.Result{}}
	mpx := bench.Megapixels(benchWidth, benchHeight)
	sdr := source(bench.SDRH264)
	hdr := source(bench.HDR10)

	// Décodage : sur deux fichiers écrits pour l'occasion, la classe légère et
	// la classe lourde.
	for _, d := range []struct {
		spec    bench.SourceSpec
		cpu, hw string
	}{
		{source(bench.SDRH264), DecodeH264CPU, DecodeH264VAAPI},
		{source(bench.HEVC10), DecodeHEVC10CPU, DecodeHEVC10VAAPI},
	} {
		path := filepath.Join(in.Dir, d.spec.Name+".mkv")
		if _, err := m.run(d.spec.GenerateArgs(path, 1)); err != nil {
			log.Printf("Streaming: banc du profil : source %s non écrite, décodage non mesuré : %v", d.spec.Name, err)
			continue
		}
		decode := append(bench.FileInput(path), "-frames:v", strconv.Itoa(benchFrames), "-f", "null", "-")
		m.cpuOnly(StageDecode, d.cpu, decode, nil, mpx)
		if in.VAAPIDevice != "" {
			hw := append([]string{
				"-vaapi_device", in.VAAPIDevice, "-hwaccel", "vaapi", "-hwaccel_output_format", "vaapi",
			}, decode...)
			idle := []string{"-vaapi_device", in.VAAPIDevice, "-f", "lavfi", "-i", "nullsrc=s=16x16", "-frames:v", "1", "-f", "null", "-"}
			m.engine(StageDecode, d.hw, hw, idle, mpx, func(c *Cost, occupancy float64) { c.Decode = occupancy })
		}
	}

	// Mise à l'échelle et tone mapping : sur des images générées, la ligne de
	// base paie la génération.
	m.step(StageScale, ScaleSoftware, bench.Step{Filter: in.ScaleFilter, Megapixels: mpx}, sdr)
	if in.VAAPIDevice != "" {
		head := []string{"-vaapi_device", in.VAAPIDevice}
		head = append(head, sdr.LavfiInput()...)
		frames := []string{"-frames:v", strconv.Itoa(benchFrames), "-f", "null", "-"}
		upload := "format=nv12,hwupload"
		scaled := append(append(append([]string{}, head...), "-vf", upload+",scale_vaapi=w=1280:h=720"), frames...)
		base := append(append(append([]string{}, head...), "-vf", upload), frames...)
		m.engine(StageScale, ScaleVAAPI, scaled, base, mpx, func(c *Cost, occupancy float64) { c.Compute = occupancy })
	}
	if in.ZscaleFilter != "" {
		m.step(StageToneMap, ToneMapZscale, bench.Step{Filter: in.ZscaleFilter, Megapixels: mpx, NeedsHDR: true}, hdr)
	}
	if lp := in.Libplacebo; lp != nil {
		head := append(append([]string{}, lp.InitArgs...),
			"-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24,format=yuv420p10le")
		frames := []string{"-frames:v", strconv.Itoa(benchFrames), "-f", "null", "-"}
		filtered := append(append(append([]string{}, head...), "-vf", lp.Filter), frames...)
		base := append(append([]string{}, head...), frames...)
		if lp.GPU {
			m.engine(StageToneMap, ToneMapLibplacebo, filtered, base, mpx, func(c *Cost, occupancy float64) { c.Compute = occupancy })
		} else {
			m.cpuOnly(StageToneMap, ToneMapLibplacebo, filtered, base, mpx)
		}
	}

	// Encodage : libx264 à chaque preset, puis chaque encodeur du circuit.
	for _, preset := range in.X264Presets {
		m.step(StageEncode, EncodeVariant("libx264", preset), bench.Step{
			Filter:     "format=yuv420p",
			Codec:      []string{"-c:v", "libx264", "-preset", preset, "-crf", "23"},
			Megapixels: mpx,
		}, sdr)
	}
	for _, hw := range in.Hardware {
		head := append(append([]string{}, hw.DeviceArgs...), sdr.LavfiInput()...)
		if hw.Candidate.Codec == "hevc" {
			// Un HEVC garde le HDR : il est mesuré en 10 bits, comme ses sessions.
			head = append(append([]string{}, hw.DeviceArgs...), "-f", "lavfi", "-i",
				"testsrc2=size=1920x1080:rate=24,format=yuv420p10le")
		}
		if hw.Upload != "" {
			head = append(head, "-vf", hw.Upload)
		}
		frames := []string{"-frames:v", strconv.Itoa(benchFrames)}
		encoded := append(append([]string{}, head...), frames...)
		encoded = append(encoded, "-c:v", hw.Candidate.Name)
		if hw.PixFmt != "" {
			encoded = append(encoded, "-pix_fmt", hw.PixFmt)
		}
		encoded = append(encoded, "-b:v", "8M", "-f", "null", "-")
		base := append(append(append([]string{}, head...), frames...), "-f", "null", "-")
		m.engine(StageEncode, hw.Candidate.Name, encoded, base, mpx, func(c *Cost, occupancy float64) { c.Encode = occupancy })
	}
	return m.costs
}

// source rend la spec du banc à la taille des mesures.
func source(spec bench.SourceSpec) bench.SourceSpec {
	spec.Width, spec.Height = benchWidth, benchHeight
	return spec
}

// meter fait les mesures d'un banc et en garde les coûts.
type meter struct {
	ctx       context.Context
	in        BenchInput
	measure   Measurer
	baselines map[string]bench.Result
	costs     []StageCost
}

// run attend que le serveur soit libre, puis mesure.
func (m *meter) run(args []string) (bench.Result, error) {
	for m.in.Busy != nil && m.in.Busy() {
		select {
		case <-m.ctx.Done():
			return bench.Result{}, m.ctx.Err()
		case <-time.After(5 * time.Second):
		}
	}
	return m.measure(m.ctx, args)
}

// baseline mesure une ligne de base une fois, et la réutilise : les trois
// presets de libx264 et la mise à l'échelle partagent la même.
func (m *meter) baseline(args []string) (bench.Result, error) {
	key := strings.Join(args, "\x00")
	if r, ok := m.baselines[key]; ok {
		return r, nil
	}
	r, err := m.run(args)
	if err == nil {
		m.baselines[key] = r
	}
	return r, err
}

func (m *meter) keep(stage Stage, variant string, cost Cost) {
	m.costs = append(m.costs, StageCost{Stage: stage, Variant: variant, Cost: cost.rounded()})
}

func (m *meter) fail(stage Stage, variant string, err error) {
	log.Printf("Streaming: banc du profil : %s %s non mesuré, la référence le remplace : %v", stage, variant, err)
}

// step mesure une étape logicielle du banc par soustraction de sa ligne de base.
func (m *meter) step(stage Stage, variant string, s bench.Step, src bench.SourceSpec) {
	if s.Filter == "" && len(s.Codec) == 0 {
		return
	}
	input := src.LavfiInput()
	measured, err := m.run(s.MeasuredArgs(input, benchFrames))
	if err != nil {
		m.fail(stage, variant, err)
		return
	}
	base, err := m.baseline(s.BaselineArgs(input, benchFrames))
	if err != nil {
		m.fail(stage, variant, err)
		return
	}
	cost, err := bench.StepCost(measured, base, s.Megapixels)
	if err != nil {
		m.fail(stage, variant, err)
		return
	}
	m.keep(stage, variant, Cost{CPU: cost})
}

// cpuOnly mesure une commande dont tout le coût est sur le processeur ; sans
// ligne de base (base nil), tout son temps CPU lui est imputé, démarrage de
// FFmpeg compris : un léger excès, du côté prudent.
func (m *meter) cpuOnly(stage Stage, variant string, args, base []string, mpx float64) {
	measured, err := m.run(args)
	if err != nil {
		m.fail(stage, variant, err)
		return
	}
	reference := bench.Result{Frames: measured.Frames}
	if base != nil {
		if reference, err = m.baseline(base); err != nil {
			m.fail(stage, variant, err)
			return
		}
	}
	cost, err := bench.StepCost(measured, reference, mpx)
	if err != nil {
		m.fail(stage, variant, err)
		return
	}
	m.keep(stage, variant, Cost{CPU: cost})
}

// engine mesure une étape sur le circuit : le CPU par soustraction du temps
// processeur, le moteur par soustraction du temps écoulé. La ligne de base
// peut ne pas avoir le même nombre d'images (une ouverture du périphérique) :
// seul son temps compte alors.
func (m *meter) engine(stage Stage, variant string, args, base []string, mpx float64, set func(*Cost, float64)) {
	measured, err := m.run(args)
	if err != nil {
		m.fail(stage, variant, err)
		return
	}
	if measured.Frames <= 0 {
		m.fail(stage, variant, errNoFrames)
		return
	}
	reference, err := m.baseline(base)
	if err != nil {
		m.fail(stage, variant, err)
		return
	}
	perImage := float64(measured.Frames) * mpx
	cost := Cost{CPU: positive((measured.CPU - reference.CPU).Seconds()) / perImage}
	set(&cost, positive((measured.Elapsed-reference.Elapsed).Seconds())/perImage)
	m.keep(stage, variant, cost)
}

var errNoFrames = errors.New("aucune image mesurée")

func positive(v float64) float64 {
	if v < 0 {
		return 0
	}
	return v
}
