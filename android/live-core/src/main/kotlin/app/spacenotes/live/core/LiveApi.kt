// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/** A page the host starts a room with, and the ink already on it. */
@Serializable
public data class StartingPage(
    val id: String,
    val width: Double,
    val height: Double,
    val background: PageBackground = PageBackground.blank,
    val strokes: List<LiveStroke> = emptyList(),
    val texts: List<LiveText> = emptyList(),
)

@Serializable
public data class CreateRoomRequest(
    val title: String,
    val pages: List<StartingPage>,
    val allowGuests: Boolean = true,
)

@Serializable
public data class CreatedRoom(val roomId: String, val code: String, val joinUrl: String = "")

@Serializable
public data class RoomLookup(
    val roomId: String,
    val title: String = "",
    val hostName: String = "",
    val allowGuests: Boolean = true,
)

/** Where to reach LiveKit for voice, and the ticket for it. */
@Serializable
public data class VoiceTicket(val url: String, val token: String)

/** An HTTP answer that was not a success. [code] is the server's error code, if it sent one. */
public class LiveApiException(
    public val status: Int,
    public val code: String?,
    message: String,
) : IOException(message)

/**
 * The room server's HTTP routes (protocol/PROTOCOL.md, HTTP API). Every call
 * carries a fresh Firebase ID token from [tokenProvider].
 */
public class LiveApi(
    baseUrl: String,
    private val tokenProvider: suspend () -> String,
    private val client: OkHttpClient = OkHttpTransportFactory.defaultClient,
) {
    private val base = baseUrl.trimEnd('/')
        .replaceFirst(Regex("^wss://"), "https://")
        .replaceFirst(Regex("^ws://"), "http://")
        .removeSuffix("/live")

    /** Creates a room with the caller as host. */
    public suspend fun createRoom(title: String, pages: List<StartingPage>, allowGuests: Boolean = true): CreatedRoom {
        val body = LiveJson.encodeToString(CreateRoomRequest.serializer(), CreateRoomRequest(title, pages, allowGuests))
        return decode(CreatedRoom.serializer(), call("POST", "/rooms", body.toRequestBody(JSON)))
    }

    /** The room behind a six-character code, or null if there is none. */
    public suspend fun lookup(code: String): RoomLookup? {
        val path = "/rooms/code/" + encodePath(code.trim().uppercase())
        return try {
            decode(RoomLookup.serializer(), call("GET", path, null))
        } catch (e: LiveApiException) {
            if (e.status == 404) null else throw e
        }
    }

    /**
     * A LiveKit ticket for voice (it allows publishing a microphone only), or
     * null when the server has no LiveKit (503): the room carries on with ink
     * only. The route keeps its protocol name, `video-token`.
     */
    public suspend fun voiceToken(roomId: String): VoiceTicket? {
        return try {
            decode(VoiceTicket.serializer(), call("POST", "/rooms/${encodePath(roomId)}/video-token", ByteArray(0).toRequestBody(JSON)))
        } catch (e: LiveApiException) {
            if (e.status == 503) null else throw e
        }
    }

    /** Host: uploads a page picture (PNG or JPEG, at most 8 MiB). */
    public suspend fun uploadAsset(roomId: String, assetId: String, bytes: ByteArray, contentType: String) {
        call("PUT", "/rooms/${encodePath(roomId)}/assets/${encodePath(assetId)}", bytes.toRequestBody(contentType.toMediaType()))
    }

    /** A page picture, for drawing an `image` background. */
    public suspend fun downloadAsset(roomId: String, assetId: String): ByteArray =
        callBytes("GET", "/rooms/${encodePath(roomId)}/assets/${encodePath(assetId)}", null)

    /** Host: the room's current state, for saving back into the notebook. */
    public suspend fun snapshot(roomId: String): RoomState {
        val element = LiveJson.parseToJsonElement(call("GET", "/rooms/${encodePath(roomId)}/snapshot", null))
        // The server wraps the state as `{ room, ended, state }`; a bare state
        // (what PROTOCOL.md's table suggests) is read too.
        val state = (element as? JsonObject)?.get("state") as? JsonObject ?: element
        return LiveJson.decodeFromJsonElement(RoomState.serializer(), state)
    }

    private fun <T> decode(serializer: KSerializer<T>, text: String): T = LiveJson.decodeFromString(serializer, text)

    private suspend fun call(method: String, path: String, body: RequestBody?): String =
        callBytes(method, path, body).toString(Charsets.UTF_8)

    private suspend fun callBytes(method: String, path: String, body: RequestBody?): ByteArray {
        val token = tokenProvider()
        val request = Request.Builder()
            .url(base + path)
            .header("Authorization", "Bearer $token")
            .method(method, body)
            .build()
        client.newCall(request).await().use { response ->
            val bytes = response.body.bytes()
            if (!response.isSuccessful) {
                val text = bytes.toString(Charsets.UTF_8)
                val code = errorCode(text)
                throw LiveApiException(response.code, code, "$method $path: ${response.code} ${code ?: text.take(200)}")
            }
            return bytes
        }
    }

    private fun errorCode(text: String): String? = try {
        val obj = LiveJson.parseToJsonElement(text).jsonObject
        ((obj["error"] ?: obj["code"]) as? JsonPrimitive)?.content
    } catch (_: Exception) {
        text.trim().takeIf { it.isNotEmpty() && it.length < 64 && ' ' !in it }
    }

    private companion object {
        val JSON = "application/json; charset=utf-8".toMediaType()

        // The String overload: the Charset one needs Android 13, and minSdk is 26.
        fun encodePath(segment: String): String = java.net.URLEncoder.encode(segment, "UTF-8").replace("+", "%20")
    }
}

private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(
        object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                // A response that arrives after cancellation is closed, not leaked.
                continuation.resume(response) { _, value, _ -> value.close() }
            }
        },
    )
}
