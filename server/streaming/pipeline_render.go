package streaming

import (
	"fmt"
	"strconv"
	"strings"
)

// Le rendu du pipeline vidéo en arguments FFmpeg : le décodage, la chaîne de
// filtres et l'encodeur d'une session qui réencode l'image.
//
// Sorti de ffmpeg.go, qui approchait la limite de 800 lignes (ADR-0052), au
// moment où la recette cesse d'être fixe : elle vient du planificateur
// (capacity.PlanPipeline) quand le profil matériel est prêt, et de l'encodeur
// choisi au démarrage sinon. Ce fichier ne décide rien ; il rend ce que les
// options disent.

// decodeArgs est la façon dont la commande décode, placée avant l'entrée.
func decodeArgs(opt TranscodeOptions) []string {
	// Hardware-assisted DECODING when the host offers any (VAAPI, VideoToolbox,
	// NVDEC...). ffmpeg silently falls back to software when nothing is
	// available, so this is free. On CPU-only hosts the decode of a 4K HEVC
	// 10-bit source is the real time-to-first-segment bottleneck, not the encode.
	//
	// Sauf quand le tone mapping passe par libplacebo : la commande ouvre alors
	// un périphérique Vulkan, et `auto` tente d'abord de décoder avec lui. Sur
	// le Vulkan logiciel d'un hôte sans GPU, c'est un échec journalisé et près
	// d'une seconde perdue avant le premier segment (ADR-0060).
	//
	// Et quand l'image reste sur le circuit (hardware_filters.go), le décodage
	// est nommé et rend des images du périphérique : `auto` les ramènerait en
	// mémoire, en 4K, avant le premier filtre.
	switch decodeMode(opt) {
	case decodeVulkan:
		return vulkanInitArgs()
	case decodeAuto:
		return []string{"-hwaccel", "auto"}
	default:
		return hardwareDecodeArgs(opt.encoder())
	}
}

// videoEncodeArgs règle l'encodeur, le marquage des couleurs et la place des
// images clés d'une session qui réencode l'image.
func videoEncodeArgs(opt TranscodeOptions, preset qualityPreset, segDur int) []string {
	// Force 8-bit 4:2:0 so 10-bit HEVC sources don't yield a "High 10" H.264
	// stream most clients can't decode. The pixel format comes from the encoder
	// because Quick Sync wants NV12 and would otherwise convert every frame. Un
	// encodeur HEVC le donne en 10 bits.
	encoder := opt.encoder()
	args := []string{"-c:v", encoder.Name}
	if encoder.PixelFormat != "" {
		args = append(args, "-pix_fmt", encoder.PixelFormat)
	}
	if encoder.isHEVC() {
		// Main 10 pour le HDR gardé, `hvc1` pour AVPlayer comme sur la recopie.
		// Pas de niveau imposé : l'encodeur écrit celui de l'image et du
		// débit, et seul le H.264 du navigateur s'y fiait.
		args = append(args, "-profile:v", "main10", "-tag:v", "hvc1")
	} else {
		args = append(args,
			"-profile:v", "high",
			"-level", h264LevelFor(preset, opt.Probe),
		)
	}
	args = append(args, encoder.rateControl(opt.encodeTarget(preset))...)

	// A tone-mapped picture is BT.709 now, and it has to say so. The tags are
	// not decoration: a player handed untagged frames from an HDR source falls
	// back to the container's own colour metadata, which still says BT.2020 PQ —
	// and re-applies a conversion to a picture that has already had one.
	if opt.Video.Tonemap {
		args = append(args,
			"-colorspace", "bt709",
			"-color_primaries", "bt709",
			"-color_trc", "bt709",
		)
	}

	// --- Keyframe layout ---
	// GOP is derived from the SOURCE frame rate: a fixed segDur*24 gives a 60fps
	// source a 1.6s GOP, spending bitrate on keyframes nobody needs.
	// sc_threshold=0 stops scene cuts from inserting extra IDRs that would
	// desynchronise the segment boundaries.
	gop := gopSize(opt.Probe, segDur)
	args = append(args, "-g", strconv.Itoa(gop))
	// keyint_min and sc_threshold are x264's spelling of "do not put an IDR
	// anywhere I did not ask for one". The hardware encoders take neither and
	// decide it themselves; force_key_frames is FFmpeg's own and reaches all of
	// them, which is what actually pins the segment boundaries.
	if !encoder.Hardware {
		args = append(args,
			"-keyint_min", strconv.Itoa(gop),
			"-sc_threshold", "0",
		)
	}
	args = append(args,
		"-force_key_frames", fmt.Sprintf("expr:gte(t,n_forced*%d)", segDur),
	)
	return args
}

// encodeTarget est ce que l'encodeur reçoit : le barreau, et le preset et les
// threads de libx264. Sans recette du planificateur, ce sont ceux de toujours
// (le preset du barreau, tous les cœurs jusqu'à seize) ; avec une recette,
// ceux qu'elle a choisis.
type encodeTarget struct {
	qualityPreset
	x264Preset string
	threads    int
}

func (o TranscodeOptions) encodeTarget(preset qualityPreset) encodeTarget {
	target := encodeTarget{qualityPreset: preset, x264Preset: encoderPresetFor(preset), threads: encoderThreads()}
	if p := o.Pipeline; p != nil {
		if p.Preset != "" {
			target.x264Preset = p.Preset
		}
		if p.Threads > 0 {
			target.threads = p.Threads
		}
	}
	return target
}

// videoFilterChain is everything the picture goes through on the encoding path,
// or "" when it needs nothing.
//
// Order is deliberate. Scaling comes first because every filter after it then
// runs on fewer pixels, and tone mapping is by far the most expensive thing
// here — on the CPU-only host that difference is the margin between keeping up
// with playback and not. Scaling in PQ space before the transfer is undone is
// a known, universally accepted approximation; doing it the other way round is
// marginally more correct and measurably too slow.
func videoFilterChain(opt TranscodeOptions, preset qualityPreset) string {
	if opt.Video.Copy {
		return "" // copied frames are never filtered, by definition
	}
	if opt.usesHardwareFilters() {
		return hardwareFilterChain(opt, preset)
	}
	var parts []string
	// Le désentrelacement passe avant la mise à l'échelle, qui mélangerait les
	// deux trames. Avec un sous-titre incrusté, il est déjà fait dans le graphe.
	if opt.Video.Deinterlace && !(opt.BurnSubtitle && opt.BurnSubtitleTypedIndex >= 0) {
		parts = append(parts, deinterlaceFilter)
	}
	if scale := buildScaleFilter(opt.Probe, preset); scale != "" {
		parts = append(parts, scale)
	}
	if tm := sessionToneMapper(opt).Filter; tm != "" {
		parts = append(parts, tm)
	}
	if opt.Video.HEVC && opt.Probe != nil && opt.Probe.Video != nil {
		parts = append(parts, hdrTagFilter(opt.Probe.Video))
	}
	// Toujours en dernier : passé ce filtre l'image est sur le périphérique, et
	// plus aucun filtre logiciel ne peut la toucher.
	if upload := opt.encoder().uploadFilter; upload != "" {
		parts = append(parts, upload)
	}
	return strings.Join(parts, ",")
}

// sessionToneMapper est le tone mapping de cette session, vide quand l'image
// est recopiée ou que la source est déjà en SDR.
func sessionToneMapper(opt TranscodeOptions) ToneMapper {
	if opt.Video.Copy || !opt.Video.Tonemap {
		return ToneMapper{}
	}
	if opt.Probe == nil {
		return toneMapperFor(nil)
	}
	return toneMapperFor(opt.Probe.Video)
}
