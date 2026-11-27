package com.projectplayer.onyx_player_android

import kotlin.test.Test
import kotlin.test.assertEquals

class ClusterScanTest {
    private val clusterId = byteArrayOf(0x1F, 0x43, 0xB6.toByte(), 0x75)

    /// Un en-tête de Cluster tel que mkvmerge l'écrit : identifiant, taille sur
    /// huit octets, puis le Timestamp.
    private fun cluster(firstChild: Int = 0xE7): ByteArray =
        clusterId + byteArrayOf(0x01, 0, 0, 0, 0, 0x17, 0x3E, 0x63) +
            byteArrayOf(firstChild.toByte(), 0x81.toByte(), 0x00)

    private fun junk(size: Int): ByteArray = ByteArray(size) { (it * 37 + 11).toByte() }

    @Test
    fun `trouve le cluster qui suit une zone abimee`() {
        val bytes = junk(500) + cluster()
        assertEquals(500, ClusterScan.find(bytes, bytes.size))
    }

    @Test
    fun `accepte un cluster qui commence par un CRC-32`() {
        val bytes = junk(10) + cluster(firstChild = 0xBF)
        assertEquals(10, ClusterScan.find(bytes, bytes.size))
    }

    @Test
    fun `ignore un identifiant croise au hasard dans la video`() {
        // L'identifiant, une taille valide, mais pas de Timestamp derrière.
        val decoy = clusterId + byteArrayOf(0x81.toByte(), 0x42)
        val bytes = junk(20) + decoy + junk(30) + cluster()
        assertEquals(20 + decoy.size + 30, ClusterScan.find(bytes, bytes.size))
    }

    @Test
    fun `ignore une taille EBML invalide`() {
        val decoy = clusterId + byteArrayOf(0x00, 0xE7.toByte())
        val bytes = decoy + cluster()
        assertEquals(decoy.size, ClusterScan.find(bytes, bytes.size))
    }

    @Test
    fun `ne tranche pas un candidat coupe par la fin du morceau`() {
        val full = junk(40) + cluster()
        // Coupé avant le Timestamp : le candidat tient dans la queue gardée.
        val cut = 40 + 4 + 8
        assertEquals(-1, ClusterScan.find(full, cut))
        assert(full.size - 40 <= ClusterScan.CARRY)
    }

    @Test
    fun `rien dans des octets quelconques`() {
        val bytes = junk(4096)
        assertEquals(-1, ClusterScan.find(bytes, bytes.size))
    }
}
