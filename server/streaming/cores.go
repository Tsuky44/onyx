package streaming

import (
	"runtime"

	"project-player/server/streaming/capacity"
)

// availableCores est le nombre de cœurs que ce processus peut réellement
// utiliser. Le seul endroit du paquet qui le demande : les threads de
// l'encodeur et le plafond de sessions s'en déduisent, et un test le remplace.
//
// GOMAXPROCS et non NumCPU : depuis Go 1.25, GOMAXPROCS suit le quota cgroup
// d'un `docker --cpus` (et le recalcule quand il change), alors que NumCPU
// rend toujours les cœurs de l'hôte. Un conteneur bridé à 4 cœurs sur un
// Xeon de 32 voyait donc 32 : 16 threads par session et seize sessions
// permises, pour une machine qui en tient une.
var availableCores = func() int { return runtime.GOMAXPROCS(0) }

// encoderThreads est le nombre de threads d'une session libx264 tant que le
// planificateur n'a pas de recette : tous les cœurs disponibles jusqu'au
// plafond, un au moins. La règle et le plafond (seize, un socket de Xeon) sont
// ceux du planificateur, qui en donne autant à charge nulle :
// capacity.ThreadsFor.
func encoderThreads() int { return encoderThreadsFor(availableCores()) }

func encoderThreadsFor(cores int) int { return capacity.ThreadsFor(cores) }

// minDefaultTranscodes est le plancher du plafond de sessions par défaut : une
// recopie ne coûte presque rien, et moins de quatre bloquerait une famille.
const minDefaultTranscodes = 4

// defaultMaxTranscodes est le plafond de sessions quand MAX_TRANSCODES est
// absent : la moitié des cœurs disponibles, au moins quatre.
func defaultMaxTranscodes() int { return defaultMaxTranscodesFor(availableCores()) }

func defaultMaxTranscodesFor(cores int) int {
	return max(cores/2, minDefaultTranscodes)
}
