// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlin.math.hypot
import kotlin.math.min

/**
 * Page geometry the room screen needs, kept here so it is tested on the JVM:
 * eraser hit tests and fitting a page into a view.
 */
public object InkGeometry {
    /**
     * True if a circle of [radius] at ([x], [y]) touches the stroke's ink,
     * counting half of each point's width, since ink extends past its centre line.
     */
    public fun hitsStroke(stroke: LiveStroke, x: Double, y: Double, radius: Double): Boolean {
        val points = stroke.points
        if (points.isEmpty()) return false
        if (points.size == 1) {
            val p = points[0]
            return hypot(p.x - x, p.y - y) <= radius + p.width / 2
        }
        for (i in 1 until points.size) {
            val a = points[i - 1]
            val b = points[i]
            val reach = radius + maxOf(a.width, b.width) / 2
            if (distanceToSegment(x, y, a.x, a.y, b.x, b.y) <= reach) return true
        }
        return false
    }

    public fun containsPoint(frame: LiveRect, x: Double, y: Double, slop: Double = 0.0): Boolean =
        x >= frame.x - slop && x <= frame.x + frame.width + slop &&
            y >= frame.y - slop && y <= frame.y + frame.height + slop

    /** Visible strokes on [page] that an eraser at (x, y) touches. */
    public fun strokesHit(page: LivePage, x: Double, y: Double, radius: Double): List<String> =
        page.strokes.filter { !it.erased && hitsStroke(it.stroke, x, y, radius) }.map { it.stroke.id }

    /** The topmost visible text box under (x, y), if any. */
    public fun textAt(page: LivePage, x: Double, y: Double, slop: Double = 0.0): TextItem? =
        page.texts.lastOrNull { !it.erased && containsPoint(it.text.frame, x, y, slop) }

    public fun distanceToSegment(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double): Double {
        val dx = bx - ax
        val dy = by - ay
        val lengthSquared = dx * dx + dy * dy
        if (lengthSquared == 0.0) return hypot(px - ax, py - ay)
        val t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared).coerceIn(0.0, 1.0)
        return hypot(px - (ax + t * dx), py - (ay + t * dy))
    }

    /** How a page of [pageWidth] x [pageHeight] points sits, whole and centred, in a view. */
    public data class Fit(val scale: Double, val offsetX: Double, val offsetY: Double) {
        public fun toPageX(viewX: Double): Double = (viewX - offsetX) / scale
        public fun toPageY(viewY: Double): Double = (viewY - offsetY) / scale
        public fun toViewX(pageX: Double): Double = pageX * scale + offsetX
        public fun toViewY(pageY: Double): Double = pageY * scale + offsetY
    }

    public fun fit(pageWidth: Double, pageHeight: Double, viewWidth: Double, viewHeight: Double, margin: Double = 0.0): Fit {
        if (pageWidth <= 0 || pageHeight <= 0 || viewWidth <= 0 || viewHeight <= 0) return Fit(1.0, 0.0, 0.0)
        val availableW = (viewWidth - 2 * margin).coerceAtLeast(1.0)
        val availableH = (viewHeight - 2 * margin).coerceAtLeast(1.0)
        val scale = min(availableW / pageWidth, availableH / pageHeight)
        return Fit(scale, (viewWidth - pageWidth * scale) / 2, (viewHeight - pageHeight * scale) / 2)
    }
}

/** The notebook without the tombstones: what gets saved back when a session ends. */
public fun RoomState.visibleOnly(): RoomState = copy(
    pages = pages.map { page -> page.copy(strokes = page.visibleStrokes, texts = page.visibleTexts) },
)
