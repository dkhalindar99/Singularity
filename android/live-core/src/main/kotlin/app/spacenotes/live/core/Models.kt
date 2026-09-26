// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.serialization.Serializable

/** The protocol version this client speaks (protocol/PROTOCOL.md, Versioning). */
public const val PROTOCOL_VERSION: Int = 1

/**
 * A colour with components in 0..1. Same JSON as the notebook's `PortableColor`.
 */
@Serializable
public data class LiveColor(
    val r: Double,
    val g: Double,
    val b: Double,
    val a: Double = 1.0,
)

/**
 * One sampled point, the notebook's `PortablePoint`. [pressure] is the raw
 * value the capture surface reported (iPad force can exceed 1), and [width] is
 * what a renderer draws from. [azimuth] and [altitude] stay absent for finger
 * input rather than becoming zero, because iOS reads a missing altitude as
 * upright and a zero as flat.
 */
@Serializable
public data class LivePoint(
    val x: Double,
    val y: Double,
    val pressure: Double,
    val timeOffset: Double,
    val width: Double,
    val azimuth: Double? = null,
    val altitude: Double? = null,
)

/** The ink names the notebook knows. Any other name reads as [Unknown]. */
public enum class LiveInk(public val wireName: String) {
    Pen("pen"),
    Pencil("pencil"),
    Marker("marker"),
    Monoline("monoline"),
    FountainPen("fountainPen"),
    Watercolor("watercolor"),
    Crayon("crayon"),
    Reed("reed"),
    Unknown("unknown"),
    ;

    public companion object {
        public fun fromWireName(raw: String): LiveInk = entries.firstOrNull { it.wireName == raw } ?: Unknown
    }
}

/**
 * A committed stroke, JSON-identical to the notebook's `PortableStroke`.
 *
 * [ink] keeps the string it arrived with, so a stroke from a newer client is
 * stored and forwarded as it was written; [inkKind] is what a renderer uses.
 * [createdAt] stays a string for the same reason (and because the notebook
 * writes whole-second ISO-8601 that must round-trip exactly). It is nullable
 * only so one stroke from a client that left it out cannot fail a whole
 * `welcome`; this client always writes it.
 */
@Serializable
public data class LiveStroke(
    val id: String,
    val ink: String,
    val color: LiveColor,
    val width: Double,
    val createdAt: String? = null,
    val points: List<LivePoint>,
    val captureStamp: Double? = null,
) {
    public val inkKind: LiveInk get() = LiveInk.fromWireName(ink)

    /** The highlighter is a marker that lets the page show through. */
    public val isHighlighter: Boolean get() = inkKind == LiveInk.Marker && color.a < 1.0
}

@Serializable
public data class LiveRect(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
)

/** A text box on a page. */
@Serializable
public data class LiveText(
    val id: String,
    val text: String,
    val frame: LiveRect,
    val fontSize: Double,
    val color: LiveColor,
)

/**
 * What is drawn under a page's ink. The wire fields are kept as they came, so
 * a background kind added later survives a round trip; [drawnAs] is what a
 * renderer should show, and anything it does not understand is blank.
 */
@Serializable
public data class PageBackground(
    val kind: String,
    val template: String? = null,
    val assetId: String? = null,
) {
    public sealed interface Drawn {
        public data object Blank : Drawn
        public data class Template(val template: String) : Drawn
        public data class Image(val assetId: String) : Drawn
    }

    public val drawnAs: Drawn
        get() = when {
            kind == KIND_TEMPLATE && template in TEMPLATES -> Drawn.Template(template!!)
            kind == KIND_IMAGE && !assetId.isNullOrEmpty() -> Drawn.Image(assetId)
            else -> Drawn.Blank
        }

    public companion object {
        public const val KIND_BLANK: String = "blank"
        public const val KIND_TEMPLATE: String = "template"
        public const val KIND_IMAGE: String = "image"
        public val TEMPLATES: Set<String> = setOf("lined", "grid", "dotted")

        public val blank: PageBackground = PageBackground(KIND_BLANK)
        public fun template(name: String): PageBackground = PageBackground(KIND_TEMPLATE, template = name)
        public fun image(assetId: String): PageBackground = PageBackground(KIND_IMAGE, assetId = assetId)
    }
}

/** A page as `page.add` carries it: no content yet. */
@Serializable
public data class LivePageSpec(
    val id: String,
    val width: Double,
    val height: Double,
    val background: PageBackground = PageBackground.blank,
)

@Serializable
public data class StrokeItem(
    val author: String,
    val seq: Long,
    val erased: Boolean = false,
    val stroke: LiveStroke,
)

@Serializable
public data class TextItem(
    val author: String,
    val seq: Long,
    val erased: Boolean = false,
    val text: LiveText,
)

/**
 * A page of the shared notebook. Items keep the order they were first added;
 * an erased item stays in the list so an undo can bring it back.
 */
@Serializable
public data class LivePage(
    val id: String,
    val width: Double,
    val height: Double,
    val background: PageBackground = PageBackground.blank,
    val strokes: List<StrokeItem> = emptyList(),
    val texts: List<TextItem> = emptyList(),
) {
    public val visibleStrokes: List<StrokeItem> get() = strokes.filterNot { it.erased }
    public val visibleTexts: List<TextItem> get() = texts.filterNot { it.erased }

    public val spec: LivePageSpec get() = LivePageSpec(id, width, height, background)
}

/** Draw policies (protocol/PROTOCOL.md, Room state). */
public object DrawPolicy {
    public const val EVERYONE: String = "everyone"
    public const val HOST: String = "host"
    public const val PEN: String = "pen"
    public val all: Set<String> = setOf(EVERYONE, HOST, PEN)
}

/** Member roles. */
public object Role {
    public const val HOST: String = "host"
    public const val GUEST: String = "guest"
}

/** The whole shared notebook: what every client holds and the reducer changes. */
@Serializable
public data class RoomState(
    val protocol: Int = PROTOCOL_VERSION,
    val seq: Long = 0,
    val drawPolicy: String = DrawPolicy.EVERYONE,
    val penHolder: String? = null,
    val hostPageId: String? = null,
    val pages: List<LivePage> = emptyList(),
) {
    public fun page(id: String?): LivePage? = if (id == null) null else pages.firstOrNull { it.id == id }
}

/** An op the server has numbered. */
@Serializable
public data class SequencedOp(
    val seq: Long,
    val author: String,
    val clientOpId: String? = null,
    val op: Op,
)

/** Who is asking, for [Permissions]. */
@Serializable
public data class Actor(
    val uid: String,
    val role: String,
)

/** Someone connected to the room. One person on two devices is two members. */
@Serializable
public data class Member(
    val uid: String,
    val connectionId: String,
    val name: String,
    val role: String = Role.GUEST,
    val color: String = "#3B5BDB",
    val handRaised: Boolean = false,
    val pageId: String? = null,
) {
    public val isHost: Boolean get() = role == Role.HOST
    public val actor: Actor get() = Actor(uid, role)
}

/** This connection, as the server sees it. */
@Serializable
public data class You(
    val uid: String,
    val connectionId: String,
    val name: String,
    val role: String = Role.GUEST,
    val color: String = "#3B5BDB",
) {
    public val isHost: Boolean get() = role == Role.HOST
    public val actor: Actor get() = Actor(uid, role)
}

@Serializable
public data class RoomInfo(
    val id: String,
    val code: String,
    val title: String,
    val hostUid: String,
)

/** The connection a presence message came from. */
@Serializable
public data class PresenceSender(
    val uid: String,
    val connectionId: String,
)
