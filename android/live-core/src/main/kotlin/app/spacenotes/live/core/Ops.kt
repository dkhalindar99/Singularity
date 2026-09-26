// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/**
 * A change to the shared notebook (protocol/PROTOCOL.md, The reducer).
 *
 * An op whose `kind` this build does not know, or whose fields do not fit its
 * kind, reads as [Unknown] and changes nothing but `seq`. It is written back
 * exactly as it arrived.
 */
@Serializable(with = OpSerializer::class)
public sealed interface Op {
    public val kind: String

    @Serializable
    public data class StrokeAdd(val pageId: String, val stroke: LiveStroke) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "stroke.add" }
    }

    @Serializable
    public data class StrokeErase(val pageId: String, val strokeIds: List<String>) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "stroke.erase" }
    }

    @Serializable
    public data class StrokeRestore(val pageId: String, val strokeIds: List<String>) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "stroke.restore" }
    }

    @Serializable
    public data class TextUpsert(val pageId: String, val text: LiveText) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "text.upsert" }
    }

    @Serializable
    public data class TextErase(val pageId: String, val textIds: List<String>) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "text.erase" }
    }

    @Serializable
    public data class ItemsMove(
        val pageId: String,
        val strokeIds: List<String> = emptyList(),
        val textIds: List<String> = emptyList(),
        val dx: Double,
        val dy: Double,
    ) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "items.move" }
    }

    @Serializable
    public data class PageAdd(val page: LivePageSpec, val afterPageId: String? = null) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "page.add" }
    }

    @Serializable
    public data class RoomPolicy(val drawPolicy: String, val penHolder: String? = null) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "room.policy" }
    }

    @Serializable
    public data class HostPage(val pageId: String) : Op {
        override val kind: String get() = KIND
        public companion object { public const val KIND: String = "host.page" }
    }

    /** Anything else. [raw] is the whole op object as received. */
    public data class Unknown(override val kind: String, val raw: JsonObject) : Op
}

internal object OpSerializer : TaggedUnionSerializer<Op>("app.spacenotes.live.Op", {
    TaggedUnion(
        tagKey = "kind",
        cases = listOf(
            TaggedUnion.case(Op.StrokeAdd.KIND, Op.StrokeAdd.serializer()),
            TaggedUnion.case(Op.StrokeErase.KIND, Op.StrokeErase.serializer()),
            TaggedUnion.case(Op.StrokeRestore.KIND, Op.StrokeRestore.serializer()),
            TaggedUnion.case(Op.TextUpsert.KIND, Op.TextUpsert.serializer()),
            TaggedUnion.case(Op.TextErase.KIND, Op.TextErase.serializer()),
            TaggedUnion.case(Op.ItemsMove.KIND, Op.ItemsMove.serializer()),
            TaggedUnion.case(Op.PageAdd.KIND, Op.PageAdd.serializer()),
            TaggedUnion.case(Op.RoomPolicy.KIND, Op.RoomPolicy.serializer()),
            TaggedUnion.case(Op.HostPage.KIND, Op.HostPage.serializer()),
        ),
        unknown = { kind, raw -> Op.Unknown(kind, raw) },
        rawOf = { (it as? Op.Unknown)?.raw },
    )
})
