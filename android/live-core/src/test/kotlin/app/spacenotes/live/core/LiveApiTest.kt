// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** LiveApi against a tiny local HTTP server playing the room server. */
class LiveApiTest {
    private lateinit var server: HttpServer
    private val seen = mutableListOf<Triple<String, String, String?>>() // method, path, auth
    private var lastBody = ByteArray(0)
    private lateinit var api: LiveApi

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            val path = exchange.requestURI.rawPath
            seen += Triple(exchange.requestMethod, path, exchange.requestHeaders.getFirst("Authorization"))
            lastBody = exchange.requestBody.readBytes()
            val (status, body) = when {
                path == "/rooms" -> 200 to """{"roomId":"r1","code":"K7QM3X","joinUrl":"https://web/join/K7QM3X"}"""
                path == "/rooms/code/K7QM3X" -> 200 to """{"roomId":"r1","title":"Cardiology","hostName":"Asha","allowGuests":false,"extra":1}"""
                path.startsWith("/rooms/code/") -> 404 to """{"error":"no-such-room"}"""
                path == "/rooms/r1/video-token" -> 200 to """{"url":"wss://lk.example","token":"lk-token"}"""
                path == "/rooms/r2/video-token" -> 503 to """{"error":"video-unavailable"}"""
                path == "/rooms/r1/snapshot" -> 200 to """{"room":{"id":"r1"},"ended":false,"state":{"protocol":1,"seq":7,"drawPolicy":"host","penHolder":null,"hostPageId":"P","pages":[]}}"""
                path == "/rooms/bare/snapshot" -> 200 to """{"protocol":1,"seq":3,"pages":[]}"""
                path == "/rooms/r1/assets/A1" && exchange.requestMethod == "GET" -> 200 to "PNGDATA"
                path == "/rooms/r1/assets/A1" -> 204 to ""
                else -> 500 to "boom"
            }
            val bytes = body.toByteArray()
            exchange.sendResponseHeaders(status, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            if (bytes.isNotEmpty()) exchange.responseBody.use { it.write(bytes) }
            exchange.close()
        }
        server.start()
        // A plain client: the test must not go through the machine's proxy.
        val http = OkHttpClient.Builder().proxy(java.net.Proxy.NO_PROXY).build()
        api = LiveApi("http://127.0.0.1:${server.address.port}/", { "tok" }, http)
    }

    @After
    fun stop() = server.stop(0)

    @Test
    fun routes() = runBlocking {
        val page = StartingPage("P", 595.0, 842.0, PageBackground.image("A1"))
        assertEquals(CreatedRoom("r1", "K7QM3X", "https://web/join/K7QM3X"), api.createRoom("Cardiology", listOf(page), allowGuests = false))
        val sent = LiveJson.parseToJsonElement(lastBody.decodeToString()).jsonObject
        assertEquals("image", sent.getValue("pages").jsonArray[0].jsonObject.getValue("background").jsonObject["kind"]!!.toString().trim('"'))
        assertEquals("false", sent.getValue("allowGuests").toString())

        assertEquals(RoomLookup("r1", "Cardiology", "Asha", false), api.lookup("k7qm3x"))
        assertNull(api.lookup("ZZZZZZ"))
        assertEquals(VoiceTicket("wss://lk.example", "lk-token"), api.voiceToken("r1"))
        assertNull(api.voiceToken("r2"))
        api.uploadAsset("r1", "A1", byteArrayOf(1, 2, 3), "image/png")
        assertArrayEquals(byteArrayOf(1, 2, 3), lastBody)
        assertArrayEquals("PNGDATA".toByteArray(), api.downloadAsset("r1", "A1"))
        assertEquals(7L, api.snapshot("r1").seq)
        assertEquals(3L, api.snapshot("bare").seq)
        try {
            api.snapshot("nope")
            fail("expected an error")
        } catch (e: LiveApiException) {
            assertEquals(500, e.status)
        }
        assertEquals(setOf("Bearer tok"), seen.map { it.third }.toSet())
        assertEquals(listOf("POST", "GET", "GET", "POST", "POST", "PUT", "GET", "GET", "GET", "GET"), seen.map { it.first })
    }
}
