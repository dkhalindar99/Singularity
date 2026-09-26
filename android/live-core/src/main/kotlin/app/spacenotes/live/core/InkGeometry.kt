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

    /**
     * One piece of a smoothed stroke: a quadratic curve from ([x0], [y0]) to
     * ([x1], [y1]) bending towards ([cx], [cy]), drawn at [width].
     */
    public data class Piece(
        val x0: Double, val y0: Double,
        val cx: Double, val cy: Double,
        val x1: Double, val y1: Double,
        val width: Double,
    )

    /**
     * A stroke as smooth curves: each sampled point becomes the control point
     * of a quadratic curve between the midpoints on either side of it, so the
     * line passes through no corners, and each piece keeps that point's own
     * width. The first and last half-segments are straight, so the curve
     * still starts and ends exactly at the first and last points. Every
     * piece's end is the next one's start, so the pieces join without gaps.
     */
    public fun smoothPieces(points: List<LivePoint>): List<Piece> {
        val n = points.size
        if (n < 2) return emptyList()
        if (n == 2) {
            val a = points[0]
            val b = points[1]
            return listOf(Piece(a.x, a.y, (a.x + b.x) / 2, (a.y + b.y) / 2, b.x, b.y, (a.width + b.width) / 2))
        }
        val pieces = ArrayList<Piece>(n)
        val first = points[0]
        val m01x = (first.x + points[1].x) / 2
        val m01y = (first.y + points[1].y) / 2
        pieces += Piece(first.x, first.y, (first.x + m01x) / 2, (first.y + m01y) / 2, m01x, m01y, first.width)
        for (i in 1 until n - 1) {
            val prev = points[i - 1]
            val p = points[i]
            val next = points[i + 1]
            pieces += Piece(
                (prev.x + p.x) / 2, (prev.y + p.y) / 2,
                p.x, p.y,
                (p.x + next.x) / 2, (p.y + next.y) / 2,
                p.width,
            )
        }
        val last = points[n - 1]
        val mx = (points[n - 2].x + last.x) / 2
        val my = (points[n - 2].y + last.y) / 2
        pieces += Piece(mx, my, (mx + last.x) / 2, (my + last.y) / 2, last.x, last.y, last.width)
        return pieces
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
