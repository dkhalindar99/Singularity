// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/**
 * Things that do not change the notebook: relayed to everyone else, never
 * numbered, never stored (protocol/PROTOCOL.md, Presence kinds).
 */
@Serializable(with = PresenceSerializer::class)
public sealed interface Presence {
    public val kind: String

    /**
     * Points of a stroke still being drawn. [p] is flat `[x, y, width, …]` and
     * holds only the points since the previous message. [liveId] is the id the
     * committed stroke will have.
     */
    @Serializable
    public data class InkLive(
        val pageId: String,
        val liveId: String,
        val ink: String = LiveInk.Pen.wireName,
        val color: LiveColor = LiveColor(0.0, 0.0, 0.0, 1.0),
        val width: Double = 2.0,
        val p: List<Double> = emptyList(),
        val done: Boolean = false,
    ) : Presence {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "ink.live" }
    }

    @Serializable
    public data class Pointer(
        val pageId: String,
        val x: Double,
        val y: Double,
        val laser: Boolean = false,
    ) : Presence {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "pointer" }
    }

    @Serializable
    public data object PointerHide : Presence {
        override val kind: String get() = "pointer.hide"
    }

    @Serializable
    public data class View(val pageId: String) : Presence {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "view" }
    }

    @Serializable
    public data class Hand(val raised: Boolean) : Presence {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "hand" }
    }

    public data class Unknown(override val kind: String, val raw: JsonObject) : Presence
}

internal object PresenceSerializer : TaggedUnionSerializer<Presence>("app.spacenotes.live.Presence", {
    TaggedUnion(
        tagKey = "kind",
        cases = listOf(
            TaggedUnion.case(Presence.InkLive.KIND, Presence.InkLive.serializer()),
            TaggedUnion.case(Presence.Pointer.KIND, Presence.Pointer.serializer()),
            TaggedUnion.objectCase("pointer.hide", Presence.PointerHide),
            TaggedUnion.case(Presence.View.KIND, Presence.View.serializer()),
            TaggedUnion.case(Presence.Hand.KIND, Presence.Hand.serializer()),
        ),
        unknown = { kind, raw -> Presence.Unknown(kind, raw) },
        rawOf = { (it as? Presence.Unknown)?.raw },
    )
})

/** Host actions that are not notebook changes. */
@Serializable(with = ControlSerializer::class)
public sealed interface Control {
    public val kind: String

    @Serializable
    public data class Remove(val uid: String) : Control {
        override val kind: String get() = "remove"
    }

    @Serializable
    public data object End : Control {
        override val kind: String get() = "end"
    }

    public data class Unknown(override val kind: String, val raw: JsonObject) : Control
}

internal object ControlSerializer : TaggedUnionSerializer<Control>("app.spacenotes.live.Control", {
    TaggedUnion(
        tagKey = "kind",
        cases = listOf(
            TaggedUnion.case("remove", Control.Remove.serializer()),
            TaggedUnion.objectCase("end", Control.End),
        ),
        unknown = { kind, raw -> Control.Unknown(kind, raw) },
        rawOf = { (it as? Control.Unknown)?.raw },
    )
})
