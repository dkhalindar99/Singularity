// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import java.net.Proxy
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Two real clients against a real room server, over real sockets. Skipped
 * unless SPACENOTES_LIVE_SERVER names a server started with dev tokens:
 *
 *     (cd server && LIVE_DEV_AUTH=1 PORT=18931 node src/server.js)
 *     SPACENOTES_LIVE_SERVER=http://127.0.0.1:18931 ./gradlew :live-core:test
 */
class LiveServerTest {
    private val server: String? = System.getenv("SPACENOTES_LIVE_SERVER")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val http = OkHttpClient.Builder()
        .proxy(Proxy.NO_PROXY)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()
    private val run = System.nanoTime().toString(36)

    @After
    fun stop() = scope.cancel()

    private suspend fun <T> StateFlow<T>.await(what: String, predicate: (T) -> Boolean): T =
        try {
            withTimeout(5_000) { first(predicate) }
        } catch (e: Exception) {
            throw AssertionError("timed out waiting for $what; last value $value", e)
        }

    private fun client(roomId: String, uid: String, name: String) = RoomClient(
        server!!, roomId, name, "$uid-device", { "dev:$uid:$name" }, OkHttpTransportFactory(http), scope,
    )

    private fun stroke(id: String) = LiveStroke(
        id, "pen", LiveColor(0.1, 0.2, 0.3), 2.0, "2026-09-26T10:00:00Z",
        listOf(LivePoint(10.0, 10.0, 1.0, 0.0, 2.0), LivePoint(40.0, 30.0, 1.0, 0.02, 2.0)),
    )

    @Test
    fun twoPeopleShareOneNotebook() = runBlocking {
        assumeTrue("SPACENOTES_LIVE_SERVER not set", server != null)
        val hostUid = "host-$run"
        val guestUid = "asha-$run"
        val api = LiveApi(server!!, { "dev:$hostUid:Host" }, http)
        val created = api.createRoom("Cardiology", listOf(StartingPage("P1", 595.0, 842.0, strokes = listOf(stroke("START")))))
        assertEquals(created.roomId, LiveApi(server, { "dev:$guestUid:Asha" }, http).lookup(created.code)?.roomId)

        val host = client(created.roomId, hostUid, "Host")
        val guest = client(created.roomId, guestUid, "Asha")
        host.connect()
        host.status.await("host connected") { it == RoomStatus.Connected }
        guest.connect()
        guest.status.await("guest connected") { it == RoomStatus.Connected }
        assertEquals(listOf("START"), guest.state.value.pages.single().strokes.map { it.stroke.id })
        host.members.await("two members") { it.size == 2 }

        // Live ink reaches the guest while it is drawn, then the stroke replaces it.
        val streamer = host.beginStroke("P1", "pen", LiveColor(0.0, 0.0, 0.0), 2.0)
        for (i in 0 until 10) {
            streamer.add(LivePoint(100.0 + i, 100.0 + i, 1.0, i * 0.016, 2.0))
            delay(16)
        }
        guest.liveInk.await("preview") { it[streamer.id]?.points?.isNotEmpty() == true }
        streamer.finish()
        guest.confirmed.await("committed stroke") { s -> s.pages[0].strokes.any { it.stroke.id == streamer.id } }
        guest.liveInk.await("preview gone") { streamer.id !in it }
        host.state.await("host pending cleared") { it == host.confirmed.value && it.seq == 1L }

        // Undo goes to everyone.
        assertTrue(host.undo())
        guest.confirmed.await("erased by undo") { s -> s.pages[0].strokes.single { it.stroke.id == streamer.id }.erased }
        assertTrue(host.redo())
        guest.confirmed.await("restored by redo") { s -> !s.pages[0].strokes.single { it.stroke.id == streamer.id }.erased }

        // The host locks drawing; the guest's optimistic stroke is rolled back.
        val rejections = java.util.Collections.synchronizedList(mutableListOf<RoomEvent>())
        scope.launch(start = CoroutineStart.UNDISPATCHED) { guest.events.collect { rejections += it } }
        host.setPolicy(DrawPolicy.HOST)
        guest.canDraw.await("locked") { !it }
        guest.addStroke("P1", stroke("GUEST-$run"))
        guest.state.await("rolled back") { s -> s.pages[0].strokes.none { it.stroke.id == "GUEST-$run" } && s == guest.confirmed.value }
        withTimeout(5_000) { while (rejections.isEmpty()) delay(10) }
        assertEquals(RejectReason.DRAWING_LOCKED, (rejections.first() as RoomEvent.Rejected).reason)

        // Presence: a raised hand and a laser pointer.
        guest.setHandRaised(true)
        host.members.await("hand raised") { m -> m.any { it.uid == guestUid && it.handRaised } }
        guest.sendPointer("P1", 50.0, 60.0, laser = true)
        host.pointers.await("laser") { p -> p.values.any { it.uid == guestUid && it.laser } }

        val snapshot = api.snapshot(created.roomId)
        assertEquals(host.confirmed.value.seq, snapshot.seq)

        // Removed, and refused on the way back in.
        host.remove(guestUid)
        guest.status.await("guest removed") { it == RoomStatus.Ended(RemovedReason.REMOVED_BY_HOST) }
        val again = client(created.roomId, guestUid, "Asha")
        again.connect()
        again.status.await("rejoin refused") { it == RoomStatus.Ended(RemovedReason.REMOVED_BY_HOST) }

        host.endRoom()
        host.status.await("room ended") { it == RoomStatus.Ended(RemovedReason.ROOM_ENDED) }
        Unit
    }
}
