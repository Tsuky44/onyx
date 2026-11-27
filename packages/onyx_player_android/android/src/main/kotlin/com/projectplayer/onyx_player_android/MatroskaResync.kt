package com.projectplayer.onyx_player_android

import android.net.Uri
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.ParserException
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SniffFailure
import androidx.media3.extractor.mkv.MatroskaExtractor
import androidx.media3.extractor.text.SubtitleParser

/// Les extracteurs par défaut, avec un Matroska qui survit à un fichier abîmé.
///
/// Tout le reste — MP4, TS, sous-titres transcodés — est rendu tel quel ;
/// seul l'extracteur Matroska est enveloppé, puisque c'est le seul conteneur
/// où ce recalage a un sens (voir [MatroskaResyncExtractor]).
internal class ResyncingExtractorsFactory(
    private val delegate: DefaultExtractorsFactory = DefaultExtractorsFactory(),
) : ExtractorsFactory {
    override fun createExtractors(): Array<Extractor> = wrap(delegate.createExtractors())

    override fun createExtractors(
        uri: Uri,
        responseHeaders: Map<String, List<String>>,
    ): Array<Extractor> = wrap(delegate.createExtractors(uri, responseHeaders))

    // `DefaultMediaSourceFactory` règle ces options sur la fabrique qu'on lui
    // donne : elles doivent atteindre la vraie, sans quoi les sous-titres
    // internes ne seraient plus analysés pendant l'extraction.
    override fun setSubtitleParserFactory(factory: SubtitleParser.Factory): ExtractorsFactory {
        delegate.setSubtitleParserFactory(factory)
        return this
    }

    override fun experimentalSetTextTrackTranscodingEnabled(enabled: Boolean): ExtractorsFactory {
        delegate.experimentalSetTextTrackTranscodingEnabled(enabled)
        return this
    }

    override fun experimentalSetCodecsToParseWithinGopSampleDependencies(
        codecsToParseWithinGopSampleDependencies: Int,
    ): ExtractorsFactory {
        delegate.experimentalSetCodecsToParseWithinGopSampleDependencies(
            codecsToParseWithinGopSampleDependencies,
        )
        return this
    }

    private fun wrap(extractors: Array<Extractor>): Array<Extractor> =
        Array(extractors.size) { i ->
            val extractor = extractors[i]
            // `underlyingImplementation` traverse l'enveloppe de transcodage
            // des sous-titres, qui entoure le Matroska quand elle est active.
            if (extractor.underlyingImplementation is MatroskaExtractor) {
                MatroskaResyncExtractor(extractor)
            } else {
                extractor
            }
        }
}

/// Un extracteur Matroska qui se recale au cluster suivant au lieu d'abandonner.
///
/// **Le problème.** L'extracteur de media3 lit les éléments EBML les uns
/// derrière les autres et lève une `ParserException` « malformée » dès qu'une
/// suite d'octets ne forme plus un élément valide. Un fichier où un
/// téléchargement ou un remux a laissé quelques dizaines de kilo-octets hors de
/// tout bloc — mesuré sur un épisode 4K : trois trous de 37 à 90 Ko sur
/// 6,4 Go — devient alors illisible en entier, alors que mpv et AetherEngine,
/// qui démuxent avec FFmpeg, n'en montrent qu'un accroc d'image.
///
/// **Le recalage.** On fait ce que fait FFmpeg : chercher, à partir de l'endroit
/// où la lecture a buté, le prochain identifiant de Cluster suivi d'un élément
/// qui ouvre bien un Cluster, puis y reprendre. Reprendre là est exactement ce
/// qu'ExoPlayer fait quand on saute à un repère de l'index : `seek` remet le
/// lecteur EBML et l'état des blocs à zéro sans oublier les pistes. Ce qui se
/// perd est la fin du cluster abîmé, une fraction de seconde.
///
/// Les données d'un échantillon à moitié écrit au moment de la panne ne
/// polluent pas le suivant : la file d'échantillons situe chaque échantillon
/// en comptant depuis la fin de ce qui a été écrit, et ce qui précède sans
/// avoir été validé n'est jamais lu.
///
/// Ce qui n'est **pas** rattrapé, volontairement : une panne avant que les
/// pistes ne soient connues (l'en-tête lui-même est cassé, il n'y a rien à
/// lire), et un fichier où aucun cluster valide ne réapparaît dans
/// [MAX_SCAN_BYTES]. Dans les deux cas l'erreur d'origine remonte, et Dart se
/// replie sur le flux HLS du serveur.
internal class MatroskaResyncExtractor(private val delegate: Extractor) : Extractor {
    private var tracksEnded = false
    private var resyncs = 0

    /// Le dernier point de reprise, pour ne jamais tourner en rond : une
    /// reprise qui ne fait pas avancer la lecture est une vraie panne.
    private var lastResyncAt = C.INDEX_UNSET.toLong()

    override fun sniff(input: ExtractorInput): Boolean = delegate.sniff(input)

    override fun getSniffFailureDetails(): List<SniffFailure> = delegate.sniffFailureDetails

    override fun init(output: ExtractorOutput) {
        delegate.init(object : ExtractorOutput by output {
            override fun endTracks() {
                tracksEnded = true
                output.endTracks()
            }
        })
    }

    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int {
        try {
            return delegate.read(input, seekPosition)
        } catch (error: ParserException) {
            if (!error.contentIsMalformed || !tracksEnded || resyncs >= MAX_RESYNCS) throw error
            val from = input.position
            return when (val cluster = findNextCluster(input)) {
                null -> throw error
                END_OF_INPUT -> {
                    // Abîmé jusqu'au bout : on finit le film là où il casse
                    // plutôt que de le déclarer illisible après l'avoir lu.
                    Log.w(TAG, "Matroska abîmé à $from, aucun cluster ensuite : fin de lecture")
                    Extractor.RESULT_END_OF_INPUT
                }
                else -> {
                    if (cluster <= lastResyncAt) throw error
                    resyncs++
                    lastResyncAt = cluster
                    Log.w(
                        TAG,
                        "Matroska abîmé à $from (${error.message}) : " +
                            "reprise au cluster $cluster (${cluster - from} octets sautés)",
                    )
                    delegate.seek(cluster, 0)
                    seekPosition.position = cluster
                    Extractor.RESULT_SEEK
                }
            }
        }
    }

    /// La position du prochain cluster valide, [END_OF_INPUT] si le fichier se
    /// termine avant, ou null si rien n'apparaît dans [MAX_SCAN_BYTES].
    private fun findNextCluster(input: ExtractorInput): Long? {
        input.resetPeekPosition()
        val buffer = ByteArray(SCAN_CHUNK + ClusterScan.CARRY)
        var carried = 0
        var base = input.position
        var scanned = 0L
        while (scanned < MAX_SCAN_BYTES) {
            val read = input.read(buffer, carried, SCAN_CHUNK)
            if (read == C.RESULT_END_OF_INPUT) return END_OF_INPUT
            val length = carried + read
            val at = ClusterScan.find(buffer, length)
            if (at >= 0) return base + at
            // Un identifiant peut être coupé en deux par la fin du morceau :
            // la queue est gardée et relue avec le suivant.
            val keep = minOf(ClusterScan.CARRY, length)
            System.arraycopy(buffer, length - keep, buffer, 0, keep)
            base += (length - keep)
            carried = keep
            scanned += read
        }
        return null
    }

    override fun seek(position: Long, timeUs: Long) {
        // Après un saut demandé par l'utilisateur, une reprise plus tôt dans le
        // fichier qu'avant est légitime.
        lastResyncAt = C.INDEX_UNSET.toLong()
        delegate.seek(position, timeUs)
    }

    override fun release() = delegate.release()

    override fun getUnderlyingImplementation(): Extractor = delegate.underlyingImplementation

    private companion object {
        const val TAG = "OnyxMatroskaResync"
        const val SCAN_CHUNK = 64 * 1024

        /// Un cluster 4K à fort débit dure quelques secondes : 64 Mo couvre
        /// largement le plus gros qu'on ait à traverser.
        const val MAX_SCAN_BYTES = 64L * 1024 * 1024

        /// Un fichier abîmé tous les quelques clusters n'est plus un fichier
        /// abîmé, c'est un fichier illisible : le serveur fera mieux.
        const val MAX_RESYNCS = 64

        const val END_OF_INPUT = -2L
    }
}

/// La recherche d'un début de Cluster dans des octets quelconques, sans Android.
internal object ClusterScan {
    /// Ce qu'il faut garder d'un morceau au suivant : l'identifiant (4), la
    /// taille la plus longue (8), et l'identifiant de l'élément qui suit (1).
    const val CARRY = 16

    private const val TIMESTAMP_ID = 0xE7
    private const val CRC32_ID = 0xBF

    /// L'indice du premier Cluster plausible dans `buffer[0, length)`, ou -1.
    ///
    /// Les quatre octets de l'identifiant ne suffisent pas : on en croise au
    /// hasard dans de la vidéo compressée. Un vrai Cluster a une taille EBML
    /// valide, puis commence par son Timestamp — ou par un CRC-32 quand le
    /// multiplexeur en pose. Un candidat trop près de la fin pour être vérifié
    /// n'est pas tranché : il est dans la queue gardée, et sera revu.
    fun find(buffer: ByteArray, length: Int): Int {
        var i = 0
        while (i + 4 <= length) {
            if (buffer[i] == 0x1F.toByte() &&
                buffer[i + 1] == 0x43.toByte() &&
                buffer[i + 2] == 0xB6.toByte() &&
                buffer[i + 3] == 0x75.toByte()
            ) {
                val sizeAt = i + 4
                if (sizeAt >= length) return -1
                val sizeLength = vintLength(buffer[sizeAt])
                if (sizeLength > 0) {
                    val next = sizeAt + sizeLength
                    if (next >= length) return -1
                    val id = buffer[next].toInt() and 0xFF
                    if (id == TIMESTAMP_ID || id == CRC32_ID) return i
                }
            }
            i++
        }
        return -1
    }

    /// La longueur d'un entier EBML d'après son premier octet, 0 si invalide.
    private fun vintLength(first: Byte): Int {
        val b = first.toInt() and 0xFF
        for (length in 1..8) {
            if (b and (0x80 ushr (length - 1)) != 0) return length
        }
        return 0
    }
}
