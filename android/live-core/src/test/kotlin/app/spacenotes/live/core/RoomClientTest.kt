// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A socket that records what the client sends and lets the test answer. */
class FakeSocket(val url: String, private val listener: LiveTransportListener) : LiveTransport {
    val sent = mutableListOf<String>()
    var closed = false
        private set

    override fun send(text: String): Boolean {
        if (closed) return false
        sent += text
        return true
    }

    override fun close(code: Int, reason: String) {
        closed = true
    }

    fun receive(message: ServerMessage) = listener.onMessage(message.encode())
    fun receiveRaw(text: String) = listener.onMessage(text)
    fun drop() = listener.onClosed(1006, "gone")

    fun messages(): List<ClientMessage> = sent.map { ClientMessage.decode(it) }
    fun ops(): List<ClientMessage.OpRequest> = messages().filterIsInstance<ClientMessage.OpRequest>()
    fun presence(): List<Presence> = messages().filterIsInstance<ClientMessage.PresenceUpdate>().map { it.presence }
}

class FakeNetwork : LiveTransportFactory {
    val sockets = mutableListOf<FakeSocket>()
    val last: FakeSocket get() = sockets.last()

    override fun open(url: String, listener: LiveTransportListener): LiveTransport =
        FakeSocket(url, listener).also { sockets += it }
}

@OptIn(ExperimentalCoroutinesApi::class)
class RoomClientTest {
    private val page1 = "PAGE-1"
    private val me = You("uid-me", "c1", "Me", Role.GUEST, "#E4572E")
    private val info = RoomInfo("room-1", "K7QM3X", "Cardiology", "uid-host")
    private val emptyRoom = RoomState(hostPageId = page1, pages = listOf(LivePage(page1, 595.0, 842.0)))
    private var tokens = 0

    private fun TestScope.client(network: FakeNetwork): RoomClient = RoomClient(
        serverUrl = "https://live.example",
        roomId = "room-1",
        name = "Me",
        deviceId = "dev",
        tokenProvider = { "token-${++tokens}" },
        transportFactory = network,
        scope = backgroundScope,
        clock = { testScheduler.currentTime },
        firstOpNumber = 1,
    )

    private fun stroke(id: String, x: Double = 10.0) = LiveStroke(
        id, "pen", LiveColor(0.1, 0.2, 0.3), 2.0, "2026-01-02T03:04:05Z",
        listOf(LivePoint(x, 20.0, 1.0, 0.0, 2.0), LivePoint(x + 5, 25.0, 1.0, 0.01, 2.0)),
    )

    private fun welcome(state: RoomState = emptyRoom, members: List<Member> = listOf(Member("uid-me", "c1", "Me"))) =
        ServerMessage.Welcome(1, me, info, state, members)

    /** Connects and answers the hello with a welcome. */
    private fun TestScope.joined(network: FakeNetwork, state: RoomState = emptyRoom): RoomClient {
        val client = client(network)
        client.connect()
        runCurrent()
        network.last.receive(welcome(state))
        return client
    }

    private fun FakeSocket.echo(request: ClientMessage.OpRequest, seq: Long, author: String = "uid-me") =
        receive(ServerMessage.OpFrame(seq, author, request.clientOpId, request.op))

    @Test
    fun helloThenWelcome() = runTest {
        val network = FakeNetwork()
        val client = client(network)
        assertEquals(RoomStatus.Connecting, client.status.value)
        client.connect()
        runCurrent()
        assertEquals("wss://live.example/live", network.last.url)
        assertEquals(ClientMessage.Hello(1, "token-1", "room-1", "Me", "dev"), network.last.messages().single())
        network.last.receive(welcome())
        assertEquals(RoomStatus.Connected, client.status.value)
        assertEquals(me, client.me.value)
        assertEquals(info, client.room.value)
        assertTrue(client.canDraw.value)
    }

    @Test
    fun ownOpsShowAtOnceAndLeavePendingWhenNumbered() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val id = client.addStroke(page1, stroke("S1"))
        assertEquals("dev:1", id)

        val optimistic = client.state.value.pages[0].strokes.single()
        assertEquals("uid-me", optimistic.author)
        assertEquals(0L, optimistic.seq)
        assertTrue(client.confirmed.value.pages[0].strokes.isEmpty())

        val request = network.last.ops().single()
        assertEquals("dev:1", request.clientOpId)
        network.last.echo(request, 1)
        assertEquals(client.confirmed.value, client.state.value)
        assertEquals(1L, client.state.value.pages[0].strokes.single().seq)
    }

    @Test
    fun othersOpsApplyUnderPendingOnes() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.addStroke(page1, stroke("MINE"))
        network.last.receive(ServerMessage.OpFrame(1, "uid-ravi", "r:1", Op.StrokeAdd(page1, stroke("THEIRS"))))
        assertEquals(listOf("THEIRS", "MINE"), client.state.value.pages[0].strokes.map { it.stroke.id })
        assertEquals(listOf("THEIRS"), client.confirmed.value.pages[0].strokes.map { it.stroke.id })
    }

    @Test
    fun pendingOpsAreResentWithTheSameIdAfterWelcome() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.addStroke(page1, stroke("S1"))
        network.last.drop()
        assertEquals(RoomStatus.Reconnecting, client.status.value)
        // Still shown while offline.
        assertEquals(1, client.state.value.pages[0].strokes.size)
        client.addStroke(page1, stroke("S2")) // drawn while offline: queued

        advanceTimeBy(499)
        runCurrent()
        assertEquals(1, network.sockets.size)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, network.sockets.size)
        assertEquals("token-2", (network.last.messages().first() as ClientMessage.Hello).token)
        assertTrue(network.last.ops().isEmpty())

        network.last.receive(welcome())
        assertEquals(RoomStatus.Connected, client.status.value)
        assertEquals(listOf("dev:1", "dev:2"), network.last.ops().map { it.clientOpId })
        assertEquals(listOf("S1", "S2"), client.state.value.pages[0].strokes.map { it.stroke.id })
    }

    @Test
    fun rejectRollsBackTheOptimisticEffect() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val events = mutableListOf<RoomEvent>()
        backgroundScope.launch { client.events.toList(events) }
        runCurrent()

        client.addStroke(page1, stroke("S1"))
        assertTrue(client.canUndo.value)
        network.last.receive(ServerMessage.Reject("dev:1", RejectReason.DRAWING_LOCKED))
        runCurrent()
        assertTrue(client.state.value.pages[0].strokes.isEmpty())
        assertFalse(client.canUndo.value)
        assertEquals(listOf<RoomEvent>(RoomEvent.Rejected("dev:1", RejectReason.DRAWING_LOCKED)), events)
    }

    @Test
    fun duplicateRejectOnlyStopsWaiting() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val events = mutableListOf<RoomEvent>()
        backgroundScope.launch { client.events.toList(events) }
        runCurrent()

        client.addStroke(page1, stroke("S1"))
        val request = network.last.ops().single()
        network.last.drop() // the op was numbered, but its echo was lost
        advanceTimeBy(500)
        runCurrent()

        val numbered = Reducer.apply(emptyRoom, SequencedOp(1, "uid-me", "dev:1", request.op))
        network.last.receive(welcome(numbered))
        assertEquals("dev:1", network.last.ops().single().clientOpId)
        network.last.receive(ServerMessage.Reject("dev:1", RejectReason.DUPLICATE))
        runCurrent()

        assertEquals(numbered, client.confirmed.value)
        assertEquals(numbered, client.state.value) // nothing pending, nothing rolled back
        assertTrue(events.isEmpty())
        assertTrue("still undoable", client.canUndo.value)
    }

    @Test
    fun aSeqGapClosesAndReconnects() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val first = network.last
        first.receive(ServerMessage.OpFrame(2, "uid-ravi", "r:1", Op.StrokeAdd(page1, stroke("S1"))))
        assertTrue(first.closed)
        assertEquals(0L, client.confirmed.value.seq) // the gapped op was not applied
        assertEquals(RoomStatus.Reconnecting, client.status.value)
        advanceTimeBy(500)
        runCurrent()
        assertEquals(2, network.sockets.size)
        // Frames from the old socket are ignored from now on.
        first.receive(ServerMessage.OpFrame(1, "uid-ravi", "r:0", Op.HostPage(page1)))
        assertEquals(0L, client.confirmed.value.seq)
    }

    @Test
    fun backoffIsHalfOneTwoFourThenEight() = runTest {
        val network = FakeNetwork()
        client(network).connect()
        runCurrent()
        val waits = mutableListOf<Long>()
        repeat(6) {
            val before = testScheduler.currentTime
            val count = network.sockets.size
            network.last.drop()
            while (network.sockets.size == count) {
                advanceTimeBy(100)
                runCurrent()
            }
            waits += testScheduler.currentTime - before
        }
        assertEquals(listOf(500L, 1000L, 2000L, 4000L, 8000L, 8000L), waits)
    }

    @Test
    fun welcomeResetsTheBackoff() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.drop()
        advanceTimeBy(500); runCurrent()
        network.last.drop()
        advanceTimeBy(1000); runCurrent()
        network.last.receive(welcome())
        assertEquals(RoomStatus.Connected, client.status.value)
        val count = network.sockets.size
        network.last.drop()
        advanceTimeBy(500); runCurrent()
        assertEquals(count + 1, network.sockets.size)
    }

    @Test
    fun removedEndsTheRoomForGood() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.receive(ServerMessage.Removed(RemovedReason.REMOVED_BY_HOST))
        assertEquals(RoomStatus.Ended(RemovedReason.REMOVED_BY_HOST), client.status.value)
        assertTrue(network.last.closed)
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(1, network.sockets.size)
        assertNull(client.addStroke(page1, stroke("S1")))
    }

    @Test
    fun aRemovedPersonRejoiningGetsRemovedInsteadOfWelcome() = runTest {
        val network = FakeNetwork()
        val client = client(network)
        client.connect()
        runCurrent()
        network.last.receive(ServerMessage.Removed(RemovedReason.REMOVED_BY_HOST))
        assertEquals(RoomStatus.Ended(RemovedReason.REMOVED_BY_HOST), client.status.value)
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(1, network.sockets.size)
    }

    @Test
    fun errorsEndOrRetryByCode() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.receive(ServerMessage.Error(ErrorCode.RATE_LIMITED, "slow down"))
        network.last.drop()
        assertEquals(RoomStatus.Reconnecting, client.status.value)
        advanceTimeBy(500); runCurrent()
        network.last.receive(ServerMessage.Error(ErrorCode.NO_SUCH_ROOM, "gone"))
        assertEquals(RoomStatus.Ended(ErrorCode.NO_SUCH_ROOM), client.status.value)
        advanceTimeBy(60_000); runCurrent()
        assertEquals(2, network.sockets.size)
    }

    @Test
    fun unknownFramesAreIgnored() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.receiveRaw("""{"type":"confetti","colour":"gold"}""")
        network.last.receiveRaw("not json at all")
        assertEquals(RoomStatus.Connected, client.status.value)
    }

    @Test
    fun pingsEveryTwentySeconds() = runTest {
        val network = FakeNetwork()
        joined(network)
        advanceTimeBy(19_999); runCurrent()
        assertTrue(network.last.messages().none { it is ClientMessage.Ping })
        advanceTimeBy(1); runCurrent()
        assertEquals(1, network.last.messages().count { it is ClientMessage.Ping })
        advanceTimeBy(20_000); runCurrent()
        assertEquals(2, network.last.messages().count { it is ClientMessage.Ping })
    }

    @Test
    fun disconnectEnds() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.disconnect()
        assertEquals(RoomStatus.Ended(RoomStatus.LEFT), client.status.value)
        assertTrue(network.last.closed)
    }

    // ---- Undo and redo -------------------------------------------------------

    @Test
    fun undoThenRedoOfStrokeAddUsesEraseAndRestore() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.addStroke(page1, stroke("S1"))
        network.last.echo(network.last.ops().last(), 1)

        assertTrue(client.undo())
        val undo = network.last.ops().last()
        assertEquals("dev:2", undo.clientOpId)
        assertEquals(Op.StrokeErase(page1, listOf("S1")), undo.op)
        assertTrue(client.state.value.pages[0].strokes.single().erased)
        assertTrue(client.canRedo.value)
        network.last.echo(undo, 2)

        assertTrue(client.redo())
        val redo = network.last.ops().last()
        assertEquals("dev:3", redo.clientOpId)
        // Not a second stroke.add: that would be a no-op for an id already there.
        assertEquals(Op.StrokeRestore(page1, listOf("S1")), redo.op)
        assertFalse(client.state.value.pages[0].strokes.single().erased)
        network.last.echo(redo, 3)
        assertFalse(client.confirmed.value.pages[0].strokes.single().erased)
        assertTrue(client.canUndo.value)
        assertFalse(client.canRedo.value)
    }

    @Test
    fun undoTouchesOnlyMyOwnActions() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.receive(ServerMessage.OpFrame(1, "uid-ravi", "r:1", Op.StrokeAdd(page1, stroke("THEIRS"))))
        assertFalse(client.canUndo.value)
        assertFalse(client.undo())
        assertTrue(network.last.ops().isEmpty())
    }

    @Test
    fun eraseUndoRestoresOnlyWhatItHid() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.receive(ServerMessage.OpFrame(1, "uid-ravi", "r:1", Op.StrokeAdd(page1, stroke("A"))))
        network.last.receive(ServerMessage.OpFrame(2, "uid-ravi", "r:2", Op.StrokeAdd(page1, stroke("B"))))
        network.last.receive(ServerMessage.OpFrame(3, "uid-ravi", "r:3", Op.StrokeErase(page1, listOf("B"))))

        client.eraseStrokes(page1, listOf("A", "B"))
        client.undo()
        assertEquals(Op.StrokeRestore(page1, listOf("A")), network.last.ops().last().op)
        client.redo()
        assertEquals(Op.StrokeErase(page1, listOf("A")), network.last.ops().last().op)
    }

    @Test
    fun moveUndoMovesBack() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.addStroke(page1, stroke("S1"))
        client.moveItems(page1, listOf("S1"), emptyList(), 5.0, -2.0)
        assertEquals(15.0, client.state.value.pages[0].strokes[0].stroke.points[0].x, 0.0)
        client.undo()
        assertEquals(Op.ItemsMove(page1, listOf("S1"), emptyList(), -5.0, 2.0), network.last.ops().last().op)
        assertEquals(10.0, client.state.value.pages[0].strokes[0].stroke.points[0].x, 0.0)
        client.redo()
        assertEquals(Op.ItemsMove(page1, listOf("S1"), emptyList(), 5.0, -2.0), network.last.ops().last().op)
    }

    @Test
    fun textUndoAndRedo() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val first = LiveText("T1", "Lithium", LiveRect(1.0, 2.0, 100.0, 20.0), 18.0, LiveColor(0.0, 0.0, 0.0))
        val edited = first.copy(text = "Lithium — narrow index")

        client.upsertText(page1, first)
        client.upsertText(page1, edited)
        client.undo()
        assertEquals(Op.TextUpsert(page1, first), network.last.ops().last().op)
        client.undo()
        assertEquals(Op.TextErase(page1, listOf("T1")), network.last.ops().last().op)
        assertTrue(client.state.value.pages[0].texts.single().erased)
        client.redo()
        assertEquals(Op.TextUpsert(page1, first), network.last.ops().last().op)
        client.redo()
        assertEquals(Op.TextUpsert(page1, edited), network.last.ops().last().op)

        client.eraseTexts(page1, listOf("T1"))
        client.undo()
        assertEquals(Op.TextUpsert(page1, edited), network.last.ops().last().op)
        assertFalse(client.state.value.pages[0].texts.single().erased)
        client.redo()
        assertEquals(Op.TextErase(page1, listOf("T1")), network.last.ops().last().op)
    }

    @Test
    fun aNewActionClearsRedo() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.addStroke(page1, stroke("S1"))
        client.undo()
        assertTrue(client.canRedo.value)
        client.addStroke(page1, stroke("S2"))
        assertFalse(client.canRedo.value)
        assertFalse(client.redo())
    }

    @Test
    fun aRejectedUndoDropsItsEntry() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.addStroke(page1, stroke("S1"))
        network.last.echo(network.last.ops().last(), 1)
        client.undo()
        val undo = network.last.ops().last()
        network.last.receive(ServerMessage.Reject(undo.clientOpId, RejectReason.DRAWING_LOCKED))
        assertFalse(client.state.value.pages[0].strokes.single().erased)
        assertFalse(client.canUndo.value)
        assertFalse(client.canRedo.value)
    }

    @Test
    fun hostOpsAreNotUndoable() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.setHostPage(page1)
        client.setPolicy(DrawPolicy.PEN, "uid-ravi")
        client.addPage(LivePageSpec("PAGE-2", 595.0, 842.0), page1)
        assertFalse(client.canUndo.value)
        assertEquals(listOf("PAGE-1", "PAGE-2"), client.state.value.pages.map { it.id })
        assertEquals(DrawPolicy.PEN, client.state.value.drawPolicy)
    }

    // ---- Live ink ----------------------------------------------------------------

    @Test
    fun liveInkGoesOutAtOnceThenEverySixteenMillisecondsAndCommitsWithTheSameId() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val streamer = client.beginStroke(page1, "pen", LiveColor(0.1, 0.2, 0.3), 2.5, id = "S1")

        streamer.add(LivePoint(10.04, 20.06, 1.0, 0.0, 2.0))
        runCurrent()
        assertEquals(
            listOf<Presence>(Presence.InkLive(page1, "S1", "pen", LiveColor(0.1, 0.2, 0.3), 2.5, listOf(10.0, 20.1, 2.0), false)),
            network.last.presence(),
        )

        advanceTimeBy(5)
        streamer.add(LivePoint(11.0, 21.0, 1.0, 0.01, 2.2))
        advanceTimeBy(5)
        streamer.add(LivePoint(12.0, 22.0, 1.0, 0.02, 2.4))
        runCurrent()
        assertEquals(1, network.last.presence().size) // held back: under 16 ms since the last

        advanceTimeBy(6)
        runCurrent()
        val second = network.last.presence()[1] as Presence.InkLive
        assertEquals(listOf(11.0, 21.0, 2.2, 12.0, 22.0, 2.4), second.p)
        assertEquals(16L, testScheduler.currentTime)

        advanceTimeBy(5)
        streamer.add(LivePoint(13.0, 23.0, 1.0, 0.03, 2.6))
        val stroke = streamer.finish()!!
        val last = network.last.presence().last() as Presence.InkLive
        assertTrue(last.done)
        assertEquals(listOf(13.0, 23.0, 2.6), last.p)

        // The commit comes straight after `done`, under the same id.
        val kinds = network.last.messages().takeLast(2)
        assertTrue(kinds[0] is ClientMessage.PresenceUpdate)
        val commit = kinds[1] as ClientMessage.OpRequest
        assertEquals(Op.StrokeAdd(page1, stroke), commit.op)
        assertEquals("S1", stroke.id)
        assertEquals(4, stroke.points.size)
        assertEquals((2.0 + 2.2 + 2.4 + 2.6) / 4, stroke.width, 1e-12)
        assertEquals("1970-01-01T00:00:00Z", stroke.createdAt)

        // Nothing more after the stroke is finished.
        advanceTimeBy(100); runCurrent()
        assertEquals(3, network.last.presence().size)
    }

    @Test
    fun cancelledStrokeEndsThePreviewWithoutCommitting() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val streamer = client.beginStroke(page1, "pen", LiveColor(0.0, 0.0, 0.0), 2.0, id = "S1")
        streamer.add(LivePoint(1.0, 1.0, 1.0, 0.0, 2.0))
        streamer.cancel()
        assertTrue((network.last.presence().last() as Presence.InkLive).done)
        assertTrue(network.last.ops().isEmpty())
    }

    @Test
    fun hoverPointerAtMostEveryHundredMillisecondsLatestWins() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.sendPointer(page1, 1.0, 1.0)
        client.sendPointer(page1, 5.0, 5.0)
        client.sendPointer(page1, 9.0, 9.0)
        runCurrent()
        assertEquals(listOf<Presence>(Presence.Pointer(page1, 1.0, 1.0, false)), network.last.presence())
        advanceTimeBy(99); runCurrent()
        assertEquals(1, network.last.presence().size)
        advanceTimeBy(1); runCurrent()
        assertEquals(listOf<Presence>(Presence.Pointer(page1, 1.0, 1.0, false), Presence.Pointer(page1, 9.0, 9.0, false)), network.last.presence())
        client.hidePointer()
        assertEquals(Presence.PointerHide, network.last.presence().last())
    }

    @Test
    fun aPointerThatBarelyMovedIsNotSentAgain() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.sendPointer(page1, 10.0, 10.0)
        advanceTimeBy(200); runCurrent()
        client.sendPointer(page1, 10.5, 10.6) // 0.78 pt
        advanceTimeBy(200); runCurrent()
        assertEquals(1, network.last.presence().size)
        client.sendPointer(page1, 11.0, 10.0) // 1 pt
        assertEquals(Presence.Pointer(page1, 11.0, 10.0, false), network.last.presence().last())
        // After a hide, the same spot is sent again.
        client.hidePointer()
        advanceTimeBy(200); runCurrent()
        client.sendPointer(page1, 11.0, 10.0)
        assertEquals(Presence.Pointer(page1, 11.0, 10.0, false), network.last.presence().last())
    }

    @Test
    fun theLaserGoesOutEveryThirtyThreeMilliseconds() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.sendPointer(page1, 1.0, 1.0, laser = true)
        client.sendPointer(page1, 5.0, 5.0, laser = true)
        advanceTimeBy(32); runCurrent()
        assertEquals(1, network.last.presence().size)
        advanceTimeBy(1); runCurrent()
        assertEquals(Presence.Pointer(page1, 5.0, 5.0, true), network.last.presence().last())
    }

    @Test
    fun noPointerWhileDrawing() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.sendPointer(page1, 1.0, 1.0)
        client.sendPointer(page1, 50.0, 50.0) // waiting for its 100 ms
        val streamer = client.beginStroke(page1, "pen", LiveColor(0.0, 0.0, 0.0), 2.0, id = "S")
        client.sendPointer(page1, 90.0, 90.0)
        advanceTimeBy(500); runCurrent()
        // The hover dot is taken away when the pen comes down; nothing else is sent.
        assertEquals(listOf(Presence.Pointer(page1, 1.0, 1.0, false), Presence.PointerHide), network.last.presence())
        streamer.add(LivePoint(1.0, 1.0, 1.0, 0.0, 2.0))
        streamer.finish()
        client.sendPointer(page1, 90.0, 90.0)
        assertEquals(Presence.Pointer(page1, 90.0, 90.0, false), network.last.presence().last())
    }

    @Test
    fun inkActivityCountsInkAndTextButNotPresenceOrPolicy() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val start = client.inkActivity.value
        network.last.receive(ServerMessage.OpFrame(1, "uid-host", "h:1", Op.RoomPolicy(DrawPolicy.HOST)))
        network.last.receive(ServerMessage.PresenceFrame(PresenceSender("uid-ravi", "c3"), Presence.Pointer(page1, 1.0, 1.0)))
        assertEquals(start, client.inkActivity.value)
        network.last.receive(ServerMessage.PresenceFrame(PresenceSender("uid-ravi", "c3"), Presence.InkLive(page1, "S9", p = listOf(1.0, 2.0, 2.0))))
        network.last.receive(ServerMessage.OpFrame(2, "uid-ravi", "r:1", Op.StrokeAdd(page1, stroke("S9"))))
        assertEquals(start + 2, client.inkActivity.value)
    }

    @Test
    fun viewAndHandAreSentAgainAfterAReconnect() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        client.sendView("PAGE-1")
        client.setHandRaised(true)
        assertTrue(client.members.value.single().handRaised)
        network.last.drop()
        advanceTimeBy(500); runCurrent()
        network.last.receive(welcome())
        assertEquals(listOf(Presence.View("PAGE-1"), Presence.Hand(true)), network.last.presence())
    }

    // ---- Receiving presence ---------------------------------------------------------

    private val ravi = PresenceSender("uid-ravi", "c3")
    private val members = listOf(Member("uid-me", "c1", "Me"), Member("uid-ravi", "c3", "Ravi"))

    @Test
    fun remoteInkGrowsAndIsSwappedForTheCommittedStroke() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.receive(ServerMessage.Members(members))
        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.InkLive(page1, "S9", "pen", LiveColor(1.0, 0.0, 0.0), 2.0, listOf(1.0, 2.0, 2.0), false)))
        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.InkLive(page1, "S9", "pen", LiveColor(1.0, 0.0, 0.0), 2.0, listOf(3.0, 4.0, 2.5, 5.0, 6.0, 3.0), true)))
        val ink = client.liveInk.value.getValue("S9")
        assertEquals(listOf(1.0, 3.0, 5.0), ink.points.map { it.x })
        assertEquals(listOf(2.0, 2.5, 3.0), ink.points.map { it.width })
        assertTrue(ink.done)
        assertEquals("c3", ink.connectionId)

        network.last.receive(ServerMessage.OpFrame(1, "uid-ravi", "r:1", Op.StrokeAdd(page1, stroke("S9"))))
        assertTrue(client.liveInk.value.isEmpty())
    }

    @Test
    fun aFinishedPreviewWhoseStrokeNeverComesIsCleared() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.InkLive(page1, "S9", p = listOf(1.0, 2.0, 2.0), done = true)))
        assertEquals(1, client.liveInk.value.size)
        advanceTimeBy(RoomClient.DONE_INK_GRACE_MS + 1); runCurrent()
        assertTrue(client.liveInk.value.isEmpty())
    }

    @Test
    fun presenceOfSomeoneWhoLeftIsDropped() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        network.last.receive(ServerMessage.Members(members))
        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.InkLive(page1, "S9", p = listOf(1.0, 2.0, 2.0))))
        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.Pointer(page1, 5.0, 6.0, true)))
        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.View("PAGE-2")))
        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.Hand(true)))
        assertEquals(1, client.liveInk.value.size)
        assertEquals(RemotePointer("uid-ravi", "c3", page1, 5.0, 6.0, true, 0), client.pointers.value["c3"])
        assertEquals("PAGE-2", client.views.value["c3"])
        assertEquals("PAGE-2", client.members.value[1].pageId)
        assertTrue(client.members.value[1].handRaised)

        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.PointerHide))
        assertTrue(client.pointers.value.isEmpty())
        network.last.receive(ServerMessage.PresenceFrame(ravi, Presence.Pointer(page1, 5.0, 6.0, false)))

        network.last.receive(ServerMessage.Members(listOf(members[0], members[1].copy(pageId = "PAGE-3"))))
        assertEquals(mapOf("c3" to "PAGE-3"), client.views.value) // the list is the truth, and excludes me

        network.last.receive(ServerMessage.Members(members.take(1)))
        assertTrue(client.liveInk.value.isEmpty())
        assertTrue(client.pointers.value.isEmpty())
        assertTrue(client.views.value.isEmpty())
    }

    @Test
    fun tooLargeOpsAreDroppedLocallyAsRejects() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val events = mutableListOf<RoomEvent>()
        backgroundScope.launch { client.events.toList(events) }
        runCurrent()

        val huge = LiveText("T", "x".repeat(RoomClient.MAX_OP_FRAME_BYTES), LiveRect(0.0, 0.0, 1.0, 1.0), 12.0, LiveColor(0.0, 0.0, 0.0))
        assertNull(client.upsertText(page1, huge))
        runCurrent()
        assertTrue(network.last.ops().isEmpty())
        assertTrue(client.state.value.pages[0].texts.isEmpty())
        assertFalse("not an undo step", client.canUndo.value)
        assertEquals(listOf<RoomEvent>(RoomEvent.Rejected("dev:1", RejectReason.TOO_LARGE)), events)

        // Nothing is left to resend after a reconnect.
        network.last.drop()
        advanceTimeBy(500); runCurrent()
        network.last.receive(welcome())
        assertTrue(network.last.ops().isEmpty())
    }

    @Test
    fun aFullFiveThousandPointStrokeStillFitsInOneFrame() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val points = (0 until Permissions.MAX_STROKE_POINTS).map {
            LivePoint(123.456789 + it, 654.321987 + it, 0.987654321, it * 0.008333333, 2.345678901, 0.785398163, 1.047197551)
        }
        val full = LiveStroke("S", "fountainPen", LiveColor(0.123456789, 0.23456789, 0.3456789, 1.0), 2.345678901, "2026-01-02T03:04:05Z", points, 1767322445.123456)
        assertEquals("dev:1", client.addStroke(page1, full))
        assertEquals(1, network.last.ops().size)
    }

    @Test
    fun theStreamerStopsAtTheStrokeLimit() = runTest {
        val network = FakeNetwork()
        val client = joined(network)
        val streamer = client.beginStroke(page1, "pen", LiveColor(0.0, 0.0, 0.0), 2.0, id = "S")
        repeat(Permissions.MAX_STROKE_POINTS + 10) { streamer.add(LivePoint(it.toDouble(), 0.0, 1.0, 0.0, 2.0)) }
        assertTrue(streamer.isFull)
        assertEquals(Permissions.MAX_STROKE_POINTS, streamer.finish()!!.points.size)
    }

    @Test
    fun socketUrls() {
        assertEquals("wss://a.example/live", RoomClient.liveSocketUrl("https://a.example/"))
        assertEquals("ws://localhost:8080/live", RoomClient.liveSocketUrl("http://localhost:8080"))
        assertEquals("wss://a.example/live", RoomClient.liveSocketUrl("wss://a.example/live"))
    }
}
