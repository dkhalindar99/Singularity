// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.Job

/**
 * Streams one stroke while it is being drawn, so everyone else sees it grow.
 *
 * The first point goes out at once as `ink.live` presence, then batches at
 * most every 16 ms (one screen frame); each
 * message holds only the points since the last one, rounded to 0.1 pt, which
 * is finer than any screen shows. [finish] sends the rest with `done: true`
 * and then commits the stroke with `stroke.add` under the same id, so a
 * receiver swaps its preview for the stroke without a flicker.
 */
public class LiveInkStreamer internal constructor(
    private val client: RoomClient,
    public val pageId: String,
    /** The committed stroke's id, and the presence `liveId`. */
    public val id: String,
    public val ink: String,
    public val color: LiveColor,
    public val width: Double,
) {
    private val startedAt = client.now()
    private val points = ArrayList<LivePoint>()
    private val unsent = ArrayList<Double>()
    private var lastSentAt: Long? = null
    private var flushJob: Job? = null
    private var closed = false

    /** How many points the stroke has; at [Permissions.MAX_STROKE_POINTS] it is full. */
    public val pointCount: Int get() = client.locked { points.size }

    public val isFull: Boolean get() = pointCount >= Permissions.MAX_STROKE_POINTS

    /** Every point so far, for drawing this person's own stroke locally. */
    public val drawnPoints: List<LivePoint> get() = client.locked { points.toList() }

    public fun add(point: LivePoint) {
        client.locked {
            // The server refuses strokes over 5,000 points. The canvas starts
            // a new stroke before this; anything past it is dropped here.
            if (closed || points.size >= Permissions.MAX_STROKE_POINTS) return@locked
            points += point
            unsent += RoomClient.round1(point.x)
            unsent += RoomClient.round1(point.y)
            unsent += RoomClient.round1(point.width)
            scheduleLocked()
        }
    }

    /**
     * Ends the stroke and commits it. Returns the stroke, or null if it had no
     * points (then only the preview is ended).
     */
    public fun finish(): LiveStroke? = client.locked {
        if (closed) return@locked null
        closed = true
        client.strokeEnded()
        flushJob?.cancel()
        flushLocked(done = true)
        if (points.isEmpty()) return@locked null
        val stroke = LiveStroke(
            id = id,
            ink = ink,
            color = color,
            // The notebook's `width` is the mean of the per-point widths.
            width = points.sumOf { it.width } / points.size,
            createdAt = Instant.ofEpochMilli(startedAt).truncatedTo(ChronoUnit.SECONDS).toString(),
            points = points.toList(),
            captureStamp = startedAt / 1000.0,
        )
        client.addStroke(pageId, stroke)
        stroke
    }

    /** Abandons the stroke: ends everyone's preview and commits nothing. */
    public fun cancel() {
        client.locked {
            if (closed) return@locked
            closed = true
            client.strokeEnded()
            flushJob?.cancel()
            unsent.clear()
            flushLocked(done = true)
        }
    }

    private fun scheduleLocked() {
        if (flushJob?.isActive == true) return
        val now = client.now()
        val last = lastSentAt
        val wait = if (last == null) 0 else last + RoomClient.PRESENCE_INTERVAL_MS - now
        if (wait <= 0) {
            flushLocked(done = false)
        } else {
            flushJob = client.launchDelayed(wait) { if (!closed) flushLocked(done = false) }
        }
    }

    private fun flushLocked(done: Boolean) {
        if (unsent.isEmpty() && !done) return
        client.sendPresence(Presence.InkLive(pageId, id, ink, color, width, unsent.toList(), done))
        unsent.clear()
        lastSentAt = client.now()
    }
}
