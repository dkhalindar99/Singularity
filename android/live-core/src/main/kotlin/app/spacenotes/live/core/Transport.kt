// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

/** One open WebSocket, as the room client needs it. */
public interface LiveTransport {
    /** Queues a text frame. False if the socket is already closing. */
    public fun send(text: String): Boolean

    public fun close(code: Int = 1000, reason: String = "")
}

/** Callbacks from a [LiveTransport]. May arrive on any thread. */
public interface LiveTransportListener {
    public fun onMessage(text: String)

    /** The socket is gone, cleanly or not. Called at most once per transport. */
    public fun onClosed(code: Int, reason: String)
}

/** Opens a socket. Tests supply a fake; the app uses [OkHttpTransportFactory]. */
public fun interface LiveTransportFactory {
    public fun open(url: String, listener: LiveTransportListener): LiveTransport
}

/** The real transport, over OkHttp's WebSocket. */
public class OkHttpTransportFactory(
    private val client: OkHttpClient = defaultClient,
) : LiveTransportFactory {
    override fun open(url: String, listener: LiveTransportListener): LiveTransport {
        val request = Request.Builder().url(url).build()
        val socket = client.newWebSocket(
            request,
            object : WebSocketListener() {
                // Closing and failure can both be reported; tell the client once.
                private var reported = false

                private fun report(code: Int, reason: String) {
                    synchronized(this) {
                        if (reported) return
                        reported = true
                    }
                    listener.onClosed(code, reason)
                }

                override fun onMessage(webSocket: WebSocket, text: String) = listener.onMessage(text)

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(1000, null)
                    report(code, reason)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = report(code, reason)

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) =
                    report(1006, t.message ?: "failure")
            },
        )
        return object : LiveTransport {
            // OkHttp queues frames sent before the handshake finishes, so the
            // client can send `hello` straight away.
            override fun send(text: String): Boolean = socket.send(text)

            override fun close(code: Int, reason: String) {
                if (!socket.close(code, reason.ifEmpty { null })) socket.cancel()
            }
        }
    }

    public companion object {
        internal val defaultClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .build()
        }
    }
}
