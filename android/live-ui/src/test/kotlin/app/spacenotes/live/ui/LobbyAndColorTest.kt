// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.ui

import androidx.compose.ui.graphics.Color
import app.spacenotes.live.core.LiveColor
import org.junit.Assert.assertEquals
import org.junit.Test

class LobbyAndColorTest {
    @Test
    fun roomCodesKeepOnlyTheirAlphabet() {
        assertEquals("K7QM3X", cleanRoomCode(" k7-qm 3x "))
        assertEquals("ABCDEF", cleanRoomCode("abcdefgh"))
        assertEquals("", cleanRoomCode("0O1I"))
    }

    @Test
    fun memberColoursReadHex() {
        assertEquals(Color(0xFFE4572E), memberColor("#E4572E", Color.Black))
        assertEquals(Color.Black, memberColor("nonsense", Color.Black))
    }

    @Test
    fun inkColoursRoundTrip() {
        val live = LiveColor(0.2, 0.4, 0.6, 0.4)
        val back = live.toColor().toLiveColor()
        assertEquals(0.2, back.r, 0.01)
        assertEquals(0.4, back.a, 0.01)
    }
}
