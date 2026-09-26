// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/** A frame this client sends (protocol/PROTOCOL.md, Client → server). */
@Serializable(with = ClientMessageSerializer::class)
public sealed interface ClientMessage {
    @Serializable
    public data class Hello(
        val protocol: Int = PROTOCOL_VERSION,
        val token: String,
        val roomId: String,
        val name: String,
        val deviceId: String,
    ) : ClientMessage

    @Serializable
    public data class OpRequest(val clientOpId: String, val op: Op) : ClientMessage

    @Serializable
    public data class PresenceUpdate(val presence: Presence) : ClientMessage

    @Serializable
    public data class ControlRequest(val control: Control) : ClientMessage

    @Serializable
    public data class Ping(val t: Long) : ClientMessage

    /** Only for reading a frame this build does not know; never sent. */
    public data class Unknown(val type: String, val raw: JsonObject) : ClientMessage

    public fun encode(): String = LiveJson.encodeToString(ClientMessageSerializer, this)

    public companion object {
        public fun decode(text: String): ClientMessage =
            LiveJson.decodeFromString(ClientMessageSerializer, text)
    }
}

internal object ClientMessageSerializer : TaggedUnionSerializer<ClientMessage>("app.spacenotes.live.ClientMessage", {
    TaggedUnion(
        tagKey = "type",
        cases = listOf(
            TaggedUnion.case("hello", ClientMessage.Hello.serializer()),
            TaggedUnion.case("op", ClientMessage.OpRequest.serializer()),
            TaggedUnion.case("presence", ClientMessage.PresenceUpdate.serializer()),
            TaggedUnion.case("control", ClientMessage.ControlRequest.serializer()),
            TaggedUnion.case("ping", ClientMessage.Ping.serializer()),
        ),
        unknown = { type, raw -> ClientMessage.Unknown(type, raw) },
        rawOf = { (it as? ClientMessage.Unknown)?.raw },
    )
})

/**
 * A frame the server sends (protocol/PROTOCOL.md, Server → client). A frame of
 * a type this build does not know, or one whose fields do not fit, reads as
 * [Unknown] and is ignored.
 */
@Serializable(with = ServerMessageSerializer::class)
public sealed interface ServerMessage {
    @Serializable
    public data class Welcome(
        val protocol: Int = PROTOCOL_VERSION,
        val you: You,
        val room: RoomInfo,
        val state: RoomState,
        val members: List<Member> = emptyList(),
    ) : ServerMessage

    @Serializable
    public data class OpFrame(
        val seq: Long,
        val author: String,
        val clientOpId: String? = null,
        val op: Op,
    ) : ServerMessage {
        public val sequenced: SequencedOp get() = SequencedOp(seq, author, clientOpId, op)
    }

    @Serializable
    public data class Reject(val clientOpId: String, val reason: String) : ServerMessage

    @Serializable
    public data class Members(val members: List<Member>) : ServerMessage

    @Serializable
    public data class PresenceFrame(val from: PresenceSender, val presence: Presence) : ServerMessage

    @Serializable
    public data class Removed(val reason: String) : ServerMessage

    @Serializable
    public data class Error(val code: String, val message: String = "") : ServerMessage

    @Serializable
    public data class Pong(val t: Long) : ServerMessage

    public data class Unknown(val type: String, val raw: JsonObject) : ServerMessage

    public fun encode(): String = LiveJson.encodeToString(ServerMessageSerializer, this)

    public companion object {
        /** Reads one frame. Never throws: text that is not JSON reads as [Unknown]. */
        public fun decode(text: String): ServerMessage = try {
            LiveJson.decodeFromString(ServerMessageSerializer, text)
        } catch (_: SerializationException) {
            Unknown("", JsonObject(emptyMap()))
        } catch (_: IllegalArgumentException) {
            Unknown("", JsonObject(emptyMap()))
        }
    }
}

internal object ServerMessageSerializer : TaggedUnionSerializer<ServerMessage>("app.spacenotes.live.ServerMessage", {
    TaggedUnion(
        tagKey = "type",
        cases = listOf(
            TaggedUnion.case("welcome", ServerMessage.Welcome.serializer()),
            TaggedUnion.case("op", ServerMessage.OpFrame.serializer()),
            TaggedUnion.case("reject", ServerMessage.Reject.serializer()),
            TaggedUnion.case("members", ServerMessage.Members.serializer()),
            TaggedUnion.case("presence", ServerMessage.PresenceFrame.serializer()),
            TaggedUnion.case("removed", ServerMessage.Removed.serializer()),
            TaggedUnion.case("error", ServerMessage.Error.serializer()),
            TaggedUnion.case("pong", ServerMessage.Pong.serializer()),
        ),
        unknown = { type, raw -> ServerMessage.Unknown(type, raw) },
        rawOf = { (it as? ServerMessage.Unknown)?.raw },
    )
})

/** Reject reasons (protocol/PROTOCOL.md, reject). */
public object RejectReason {
    public const val NOT_HOST: String = "not-host"
    public const val DRAWING_LOCKED: String = "drawing-locked"
    public const val INVALID_OP: String = "invalid-op"

    /** Already sequenced before this connection; the welcome state holds it. */
    public const val DUPLICATE: String = "duplicate"

    /** Never sent by the server: a client's own refusal of an op over the frame limit. */
    public const val TOO_LARGE: String = "too-large"
}

/** Error codes (protocol/PROTOCOL.md, error). */
public object ErrorCode {
    public const val BAD_HELLO: String = "bad-hello"
    public const val UNAUTHENTICATED: String = "unauthenticated"
    public const val NO_SUCH_ROOM: String = "no-such-room"
    public const val ROOM_FULL: String = "room-full"
    public const val GUESTS_NOT_ALLOWED: String = "guests-not-allowed"
    public const val PROTOCOL_MISMATCH: String = "protocol-mismatch"
    public const val TOO_LARGE: String = "too-large"
    public const val RATE_LIMITED: String = "rate-limited"
}

/** Why a [ServerMessage.Removed] was sent. */
public object RemovedReason {
    public const val REMOVED_BY_HOST: String = "removed-by-host"
    public const val ROOM_ENDED: String = "room-ended"
}
