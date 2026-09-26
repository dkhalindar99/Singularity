// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class InkGeometryTest {
    private val line = LiveStroke(
        "S", "pen", LiveColor(0.0, 0.0, 0.0), 2.0, "2026-01-01T00:00:00Z",
        listOf(LivePoint(0.0, 0.0, 1.0, 0.0, 2.0), LivePoint(100.0, 0.0, 1.0, 0.1, 2.0)),
    )

    @Test
    fun eraserHitsNearTheInkOnly() {
        assertTrue(InkGeometry.hitsStroke(line, 50.0, 5.0, 4.5)) // 5 away, reach 4.5 + 1
        assertFalse(InkGeometry.hitsStroke(line, 50.0, 6.0, 4.5))
        assertTrue(InkGeometry.hitsStroke(line, 104.0, 0.0, 3.0)) // past the end cap
        assertFalse(InkGeometry.hitsStroke(line, 110.0, 0.0, 3.0))
    }

    @Test
    fun erasedStrokesAndTextsAreNotHit() {
        val text = LiveText("T", "hi", LiveRect(10.0, 10.0, 50.0, 20.0), 12.0, LiveColor(0.0, 0.0, 0.0))
        val page = LivePage(
            "P", 200.0, 200.0,
            strokes = listOf(StrokeItem("a", 1, false, line), StrokeItem("a", 2, true, line.copy(id = "GONE"))),
            texts = listOf(TextItem("a", 3, false, text)),
        )
        assertEquals(listOf("S"), InkGeometry.strokesHit(page, 20.0, 0.0, 2.0))
        assertEquals("T", InkGeometry.textAt(page, 30.0, 20.0)?.text?.id)
        assertNull(InkGeometry.textAt(page.copy(texts = listOf(TextItem("a", 3, true, text))), 30.0, 20.0))
        assertEquals(listOf(StrokeItem("a", 1, false, line)), RoomState(pages = listOf(page)).visibleOnly().pages[0].strokes)
    }

    @Test
    fun pagesFitWholeAndCentred() {
        val fit = InkGeometry.fit(595.0, 842.0, 1190.0, 842.0)
        assertEquals(1.0, fit.scale, 1e-9)
        assertEquals(297.5, fit.offsetX, 1e-9)
        assertEquals(0.0, fit.offsetY, 1e-9)
        assertEquals(100.0, fit.toPageX(fit.toViewX(100.0)), 1e-9)
    }
}
