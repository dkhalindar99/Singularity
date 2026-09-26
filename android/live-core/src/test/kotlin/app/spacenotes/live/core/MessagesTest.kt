// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MessagesTest {
    private val server: JsonObject = Fixtures.load("messages/server-to-client.json").jsonObject.getValue("messages").jsonObject
    private val client: JsonObject = Fixtures.load("messages/client-to-server.json").jsonObject.getValue("messages").jsonObject

    private fun serverMessage(name: String): ServerMessage = ServerMessage.decode(server.getValue(name).toString())

    @Test
    fun decodesEveryServerFrame() {
        val expectedTypes = mapOf(
            "welcome" to ServerMessage.Welcome::class,
            "op" to ServerMessage.OpFrame::class,
            "reject" to ServerMessage.Reject::class,
            "members" to ServerMessage.Members::class,
            "presence-ink-live" to ServerMessage.PresenceFrame::class,
            "presence-pointer" to ServerMessage.PresenceFrame::class,
            "presence-pointer-hide" to ServerMessage.PresenceFrame::class,
            "presence-view" to ServerMessage.PresenceFrame::class,
            "presence-hand" to ServerMessage.PresenceFrame::class,
            "removed" to ServerMessage.Removed::class,
            "error" to ServerMessage.Error::class,
            "pong" to ServerMessage.Pong::class,
            "unknown-type" to ServerMessage.Unknown::class,
            "welcome-with-extra-fields" to ServerMessage.Welcome::class,
        )
        assertEquals("every fixture is covered", server.keys, expectedTypes.keys)
        for ((name, type) in expectedTypes) {
            assertTrue("$name decodes as ${type.simpleName}", type.isInstance(serverMessage(name)))
        }
    }

    @Test
    fun serverFramesCarryTheirFields() {
        val welcome = serverMessage("welcome") as ServerMessage.Welcome
        assertEquals("uid-asha", welcome.you.uid)
        assertEquals("K7QM3X", welcome.room.code)
        assertEquals(1L, welcome.state.seq)
        assertEquals(1767322445.123456, welcome.state.pages[0].strokes[0].stroke.captureStamp!!, 0.0)

        val op = serverMessage("op") as ServerMessage.OpFrame
        assertEquals(SequencedOp(13, "uid-asha", "ipad-7F3A:42", Op.StrokeErase("00000001-0000-4000-8000-000000000001", listOf("0000000A-0000-4000-8000-000000000001"))), op.sequenced)

        assertEquals(ServerMessage.Reject("ipad-7F3A:43", "drawing-locked"), serverMessage("reject"))
        val members = serverMessage("members") as ServerMessage.Members
        assertTrue(members.members.single().handRaised)
        assertEquals("00000001-0000-4000-8000-000000000002", members.members.single().pageId)

        val ink = (serverMessage("presence-ink-live") as ServerMessage.PresenceFrame).presence as Presence.InkLive
        assertEquals(listOf(10.0, 20.0, 2.0, 30.5, 41.3, 2.5), ink.p)
        assertEquals(false, ink.done)
        val pointer = serverMessage("presence-pointer") as ServerMessage.PresenceFrame
        assertEquals(PresenceSender("uid-ravi", "c3"), pointer.from)
        assertEquals(Presence.Pointer("00000001-0000-4000-8000-000000000001", 120.5, 300.0, true), pointer.presence)
        assertEquals(Presence.PointerHide, (serverMessage("presence-pointer-hide") as ServerMessage.PresenceFrame).presence)
        assertEquals(Presence.View("00000001-0000-4000-8000-000000000002"), (serverMessage("presence-view") as ServerMessage.PresenceFrame).presence)
        assertEquals(Presence.Hand(true), (serverMessage("presence-hand") as ServerMessage.PresenceFrame).presence)
        assertEquals(ServerMessage.Removed("removed-by-host"), serverMessage("removed"))
        assertEquals(ServerMessage.Error("no-such-room", "That room has ended."), serverMessage("error"))
        assertEquals(ServerMessage.Pong(123), serverMessage("pong"))
        assertEquals("confetti", (serverMessage("unknown-type") as ServerMessage.Unknown).type)
    }

    @Test
    fun extraFieldsAreIgnoredAndUnknownBackgroundsDrawBlank() {
        val welcome = serverMessage("welcome-with-extra-fields") as ServerMessage.Welcome
        assertEquals("Extra fields", welcome.room.title)
        val background = welcome.state.pages.single().background
        assertEquals("hologram", background.kind)
        assertEquals(PageBackground.Drawn.Blank, background.drawnAs)
    }

    @Test
    fun knownServerFramesReEncodeToTheSameValue() {
        for ((name, element) in server) {
            if (name == "unknown-type" || name == "welcome-with-extra-fields") continue
            val encoded = LiveJson.parseToJsonElement(ServerMessage.decode(element.toString()).encode())
            assertEquals(name, normalized(element), normalized(encoded))
        }
    }

    @Test
    fun garbageNeverThrows() {
        assertTrue(ServerMessage.decode("not json") is ServerMessage.Unknown)
        assertTrue(ServerMessage.decode("[1,2]") is ServerMessage.Unknown)
        assertTrue(ServerMessage.decode("""{"type":"op","seq":"x"}""") is ServerMessage.Unknown)
    }

    /** Every client frame, built from this client's own types. */
    private val built: Map<String, ClientMessage> = run {
        val page1 = "00000001-0000-4000-8000-000000000001"
        val stroke1 = LiveStroke(
            id = "0000000A-0000-4000-8000-000000000001",
            ink = "pen",
            color = LiveColor(0.1, 0.2, 0.3, 1.0),
            width = 2.5,
            createdAt = "2026-01-02T03:04:05Z",
            points = listOf(
                LivePoint(10.0, 20.0, 0.5, 0.0, 2.0, 0.25, 1.1),
                LivePoint(30.5, 41.25, 1.75, 0.016, 2.5, 0.3, 1.2),
                LivePoint(50.0, 60.0, 0.25, 0.032, 3.0),
            ),
            captureStamp = 1767322445.123456,
        )
        mapOf(
            "hello" to ClientMessage.Hello(1, "eyJhbGciOi.test.token", "room-1", "Asha", "ipad-7F3A"),
            "op-stroke-add" to ClientMessage.OpRequest("ipad-7F3A:42", Op.StrokeAdd(page1, stroke1)),
            "op-items-move" to ClientMessage.OpRequest(
                "ipad-7F3A:44",
                Op.ItemsMove(page1, listOf("0000000A-0000-4000-8000-000000000001"), listOf("0000000B-0000-4000-8000-000000000001"), -4.5, 12.0),
            ),
            "op-text-upsert" to ClientMessage.OpRequest(
                "web-1:1",
                Op.TextUpsert(
                    page1,
                    LiveText(
                        "0000000B-0000-4000-8000-000000000001",
                        "Lithium — narrow therapeutic index",
                        LiveRect(40.0, 320.0, 260.0, 64.0),
                        18.0,
                        LiveColor(0.15, 0.18, 0.22, 1.0),
                    ),
                ),
            ),
            "op-page-add" to ClientMessage.OpRequest(
                "web-1:2",
                Op.PageAdd(LivePageSpec("00000001-0000-4000-8000-000000000002", 595.0, 842.0, PageBackground.template("lined")), page1),
            ),
            "op-room-policy" to ClientMessage.OpRequest("web-1:3", Op.RoomPolicy(DrawPolicy.PEN, "uid-asha")),
            "presence-ink-live-done" to ClientMessage.PresenceUpdate(
                Presence.InkLive(page1, "0000000A-0000-4000-8000-000000000001", "pen", LiveColor(0.1, 0.2, 0.3, 1.0), 2.5, listOf(50.0, 60.0, 3.0), true),
            ),
            "presence-view" to ClientMessage.PresenceUpdate(Presence.View(page1)),
            "control-remove" to ClientMessage.ControlRequest(Control.Remove("uid-ravi")),
            "control-end" to ClientMessage.ControlRequest(Control.End),
            "ping" to ClientMessage.Ping(123),
        )
    }

    @Test
    fun encodesEveryClientFrameFromOwnTypes() {
        assertEquals("every fixture is covered", client.keys, built.keys)
        for ((name, message) in built) {
            val encoded: JsonElement = LiveJson.parseToJsonElement(message.encode())
            assertEquals(name, normalized(client.getValue(name)), normalized(encoded))
        }
    }

    @Test
    fun decodesEveryClientFrameBackToTheSameTypes() {
        for ((name, element) in client) {
            assertEquals(name, built.getValue(name), ClientMessage.decode(element.toString()))
        }
    }

    @Test
    fun optionalStrokeFieldsAreLeftOutNotNull() {
        val finger = LiveStroke("s", "pen", LiveColor(0.0, 0.0, 0.0), 1.0, "2026-01-01T00:00:00Z", listOf(LivePoint(1.0, 2.0, 1.0, 0.0, 1.0)))
        val text = LiveJson.encodeToString(LiveStroke.serializer(), finger)
        assertTrue(text, "azimuth" !in text && "altitude" !in text && "captureStamp" !in text && "null" !in text)
    }

    @Test
    fun unknownInkIsKeptVerbatim() {
        val stroke = LiveJson.decodeFromString(
            LiveStroke.serializer(),
            """{"id":"s","ink":"glitter","color":{"r":0,"g":0,"b":0,"a":1},"width":1,"createdAt":"2026-01-01T00:00:00Z","points":[]}""",
        )
        assertEquals("glitter", stroke.ink)
        assertEquals(LiveInk.Unknown, stroke.inkKind)
        assertTrue(LiveJson.encodeToString(LiveStroke.serializer(), stroke).contains("\"glitter\""))
    }
}
