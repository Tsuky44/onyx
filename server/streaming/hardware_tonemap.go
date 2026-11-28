package streaming

import (
	"log"
	"os"
	"strings"
	"sync/atomic"
)

// Le tone mapping sur la carte.
//
// Avec la chaîne matérielle seule (hardware_filters.go), une source HDR
// redescendait en mémoire pour le tone mapping zscale du processeur. Mesuré
// sur une Quadro P2200 et un i7-10700K, 30 s d'un remux 4K HDR10 à 71 Mbit/s
// vers 1080p :
//
//	carte de bout en bout, sans tone mapping     7,2×   processeur au repos
//	décodage carte + tone mapping processeur     1,6×   3,5 cœurs occupés
//	chaîne complète de la session                1,1× à 1,5×
//
// La carte attendait : décodeur à 22 %, encodeur à 10 %. C'est le tone
// mapping logiciel qui tenait la session près du temps réel.
//
// Ici libplacebo le fait sur la carte. L'image redescend toujours une fois, à
// la taille du barreau, parce que ce FFmpeg ne sait pas faire autrement :
// avec CUDA comme périphérique des filtres, libplacebo refuse les images
// Vulkan en entrée, et `hwupload` vers Vulkan ne prend pas d'images CUDA (lu
// dans vf_libplacebo.c et hwcontext_vulkan.c de la 8.1, puis vu échouer sur
// la carte). En revanche libplacebo crée alors son propre contexte Vulkan sur
// la carte et prend des images logicielles : il suffit de le mettre à la
// place de zscale. Même mesure, avec cette chaîne : 3,0× à 3,9×, et quatre
// secondes de processeur pour trente secondes de film au lieu de
// soixante-sept.
//
// La courbe n'est pas le « hable » du Dolby Vision (tonemap_dovi.go) : celui
// de libplacebo sort une image 10 % plus sombre que la chaîne zscale, jusqu'à
// 35 % dans les ombres. `st2094-40` est la courbe la plus proche de cette
// référence sur six moments du film (luminance moyenne à +2,5 %, ombres
// identiques, 38 dB de PSNR moyen contre 33 pour hable), avec une saturation
// de 22 % plus forte que `saturation=0.85` ramène à 4 % près en moyenne
// (39 dB). L'utilisateur a retenu ce réglage à l'œil.
//
// Il ne s'active que sur demande, HARDWARE_TONEMAP=on. Le banc tenait 3,0× à
// 3,9×, mais les premières vraies sessions sur la même carte (2026-11-28)
// n'ont tenu que 0,5× à 0,7× à toutes les résolutions, 360p compris : le
// lecteur changeait de barreau toutes les cinq secondes, là où la chaîne
// zscale tenait 1,3× sans accroc. Le flux n'est pas en cause (mêmes durées de
// segment et mêmes horodatages que zscale, vérifié) ; ce qui ralentit la
// commande dans une session et pas au banc n'est pas trouvé. Tant qu'il ne
// l'est pas, le défaut reste le tone mapping du processeur.
//
// Deux gardes restent quand il est demandé : l'essai du démarrage par la
// commande d'une session, et le retrait pour tout le serveur si une session
// meurt avec ce tone mapping avant son premier segment. Dans les deux cas la
// chaîne matérielle reste, avec le tone mapping du processeur.

// cudaToneMapFilter est le tone mapping HDR vers SDR d'une session sur une
// carte NVIDIA. Sortie en NV12 : c'est le format que l'envoi vers la carte et
// NVENC prennent sans conversion, et le plus régulier des deux essayés (la
// sortie yuv420p est tombée à 1,5× sur un passage).
const cudaToneMapFilter = "libplacebo=tonemapping=st2094-40:saturation=0.85" +
	":colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv" +
	":format=nv12" +
	":peak_detect=false:gamut_mode=clip:contrast_recovery=0:dithering=none" +
	":disable_linear=true:skip_aa=true"

var (
	// hardwareToneMapOK est écrit une fois, avec hardwareFiltersOK, par
	// HardwareFiltersUsable.
	hardwareToneMapOK bool
	// hardwareToneMapOff est posé quand une session est morte avec ce tone
	// mapping : l'essai du démarrage ne voit qu'une source de synthèse.
	hardwareToneMapOff atomic.Bool
)

// HardwareToneMapUsable dit si le tone mapping d'une source HDR peut se faire
// sur le matériel de la chaîne. Résolu au démarrage, avec elle.
func HardwareToneMapUsable() bool {
	return HardwareFiltersUsable() && hardwareToneMapOK && !hardwareToneMapOff.Load()
}

// wantsHardwareToneMap dit que cette session, si elle prend la chaîne
// matérielle, y fait aussi son tone mapping. Le Dolby Vision profil 5 garde
// son libplacebo à lui, qui applique la couche RPU avant toute mise à
// l'échelle.
func (o TranscodeOptions) wantsHardwareToneMap() bool {
	if !o.HardwareToneMap || !o.Video.Tonemap {
		return false
	}
	return o.encoder().surfaceToneMap != "" && !sessionToneMapper(o).Vulkan
}

// usesHardwareToneMap dit que le tone mapping de cette session se fait sur le
// matériel de la chaîne.
func (o TranscodeOptions) usesHardwareToneMap() bool {
	return o.wantsHardwareToneMap() && o.usesHardwareFilters()
}

// detectHardwareToneMap fait passer la source d'essai, marquée HDR10, par la
// chaîne d'une session dont le tone mapping reste sur le matériel. Un échec
// ne retire rien d'autre : la chaîne matérielle garde le tone mapping du
// processeur, et le journal dit pourquoi.
func detectHardwareToneMap(
	encoder VideoEncoder,
	sample string,
	hasFilter func(name string) bool,
	run func(args []string) error,
) bool {
	if encoder.surfaceToneMap == "" {
		return false
	}
	if !hardwareToneMapRequestedByEnv() {
		log.Println("Streaming: tone mapping stays on the CPU (HARDWARE_TONEMAP=on tries it on the device)")
		return false
	}
	if !hasFilter("libplacebo") {
		log.Println("Streaming: this FFmpeg has no libplacebo, tone mapping stays on the CPU")
		return false
	}
	opt := hardwareProbeOptions(encoder, true)
	opt.HardwareToneMap = true
	if err := run(hardwareChainProbeArgs(opt, sample)); err != nil {
		log.Printf("Streaming: tone mapping stays on the CPU, libplacebo did not run in the %s chain: %v",
			encoder.surface, err)
		return false
	}
	log.Printf("Streaming: tone mapping on the device (%s chain, libplacebo)", encoder.surface)
	return true
}

// hardwareToneMapRequestedByEnv lit HARDWARE_TONEMAP. Le tone mapping sur le
// matériel est une demande de l'opérateur, pas un défaut : voir plus haut ce
// que les premières sessions ont donné.
func hardwareToneMapRequestedByEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("HARDWARE_TONEMAP"))) {
	case "1", "on", "true", "yes":
		return true
	}
	return false
}

// noteHardwareToneMapDied ramène le tone mapping au processeur pour tout le
// serveur : une session vient de mourir avec lui avant son premier segment.
// La chaîne matérielle reste, et c'est elle que la nouvelle tentative du
// lecteur prend.
func noteHardwareToneMapDied(sessionID, stderr string) {
	if hardwareToneMapOff.CompareAndSwap(false, true) {
		log.Printf("Streaming: session %s died with tone mapping on the device before its first segment, "+
			"tone mapping on the CPU from now on: %s", sessionID, strings.TrimSpace(stderr))
	}
}
