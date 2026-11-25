package streaming

import "runtime"

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

// maxEncoderThreads plafonne les threads de libx264 par session.
//
// L'hôte visé est un Xeon à deux sockets : étaler une session sur les deux
// coûte plus en trafic mémoire entre nœuds NUMA que ça ne rapporte, et prive
// les sessions voisines. Seize threads saturent le parallélisme par images
// d'un socket et en laissent à une deuxième session. Sous ce plafond, la
// machine n'a pas plus de cœurs que de threads utiles.
const maxEncoderThreads = 16

// encoderThreads est le nombre de threads d'une session libx264 : tous les
// cœurs disponibles jusqu'au plafond, un au moins.
func encoderThreads() int { return encoderThreadsFor(availableCores()) }

func encoderThreadsFor(cores int) int {
	return min(max(cores, 1), maxEncoderThreads)
}

// minDefaultTranscodes est le plancher du plafond de sessions par défaut : une
// recopie ne coûte presque rien, et moins de quatre bloquerait une famille.
const minDefaultTranscodes = 4

// defaultMaxTranscodes est le plafond de sessions quand MAX_TRANSCODES est
// absent : la moitié des cœurs disponibles, au moins quatre.
func defaultMaxTranscodes() int { return defaultMaxTranscodesFor(availableCores()) }

func defaultMaxTranscodesFor(cores int) int {
	return max(cores/2, minDefaultTranscodes)
}
