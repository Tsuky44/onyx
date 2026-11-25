package streaming

import "project-player/server/streaming/capacity"

// Les pistes audio qu'une session publie.
//
// Chaque piste publiée est décodée et encodée en continu, pendant tout le film,
// pour qu'un changement de langue soit un simple changement de piste dans le
// lecteur. Sur une grosse machine, c'est gratuit. Sur une petite, huit pistes
// TrueHD coûtent quelques dixièmes de cœur (§7 du plan
// docs/transcodage-adaptatif.md), pris à l'image. Décision §0.4 : une petite
// machine n'en publie que deux, la piste choisie et la VO ; un changement vers
// une autre langue, rare, relance une session (le client le fait déjà :
// _playerAudioPosition rend null pour une piste absente de audio_map, et le
// lecteur recharge la session HLS avec la nouvelle piste).

// maxAudioRenditions caps how many audio tracks a session publishes.
//
// Each rendition is a cheap stereo AAC encode (~1% of a core once the JIT
// throttle settles), but every one of them also writes segments for the whole
// film, so an unbounded count would fill the session's temp dir on a remux
// carrying a dozen dub tracks.
const maxAudioRenditions = 8

// smallMachineAudioRenditions est le plafond d'une petite machine : la piste
// choisie et la VO.
const smallMachineAudioRenditions = 2

// smallMachineCores est le nombre de cœurs à partir duquel une machine sans
// circuit est petite. Quatre : c'est la machine de fytroz, où un 4K HDR10 vers
// 1080p prend 3,44 cœurs et tient 1,1× (*mesuré*). Les 0,3 cœur de huit pistes
// y sont ce qui sépare 1,1× de 1,0×. À huit cœurs, la même session laisse
// plus de quatre cœurs libres, et les pistes ne pèsent plus sur l'image.
const smallMachineCores = 4

// audioRenditionLimit est le nombre de pistes que cette machine publie. Sans
// profil, celui d'avant : huit.
func audioRenditionLimit(profile *capacity.Profile) int {
	if smallMachine(profile) {
		return smallMachineAudioRenditions
	}
	return maxAudioRenditions
}

// smallMachine dit qu'une machine a peu de cœurs et aucun circuit utilisable :
// ni encodeur du circuit qui a passé son essai, ni libplacebo sur un vrai
// circuit. Avec un circuit, l'image quitte le processeur, qui garde de quoi
// encoder l'audio.
func smallMachine(profile *capacity.Profile) bool {
	if profile == nil || profile.Inventory.Cores > smallMachineCores {
		return false
	}
	for _, codec := range []string{"h264", "hevc"} {
		for _, c := range profile.Candidates(codec) {
			if c.Hardware {
				return false
			}
		}
	}
	if _, gpu := profile.Libplacebo(); gpu {
		return false
	}
	return true
}

// originalAudioTrack est la VO : la piste que la sonde marque originale,
// sinon celle marquée par défaut, sinon la première.
func originalAudioTrack(probe *ProbeResult) int {
	for i, a := range probe.Audio {
		if a.Original {
			return i
		}
	}
	for i, a := range probe.Audio {
		if a.Default {
			return i
		}
	}
	return 0
}

// SelectAudioRenditions picks which source audio tracks a session will carry,
// in source order, always including the one the client asked for.
func SelectAudioRenditions(probe *ProbeResult, requested int) []int {
	return selectAudioRenditions(probe, requested, maxAudioRenditions)
}

// selectAudioRenditions garde au plus limit pistes, dans l'ordre de la
// source : la piste demandée d'abord, puis la VO, puis les premières.
func selectAudioRenditions(probe *ProbeResult, requested, limit int) []int {
	if probe == nil || len(probe.Audio) == 0 {
		return nil
	}
	total := len(probe.Audio)
	if requested < 0 || requested >= total {
		requested = 0
	}
	limit = max(limit, 1)

	keep := make(map[int]bool, limit)
	keep[requested] = true
	if len(keep) < limit {
		keep[originalAudioTrack(probe)] = true
	}
	for i := 0; i < total && len(keep) < limit; i++ {
		keep[i] = true
	}
	out := make([]int, 0, len(keep))
	for i := 0; i < total; i++ {
		if keep[i] {
			out = append(out, i)
		}
	}
	return out
}
