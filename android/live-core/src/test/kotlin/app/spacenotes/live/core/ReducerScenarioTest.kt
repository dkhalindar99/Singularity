// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReducerScenarioTest {
    @Test
    fun everyScenarioMatchesItsExpectedState() {
        val files = Fixtures.files("scenarios")
        assertTrue("no scenarios found", files.size >= 7)
        for (file in files) {
            val scenario = Fixtures.load("scenarios/${file.name}").jsonObject
            val initialJson = scenario.getValue("initial")
            val initial = LiveJson.decodeFromJsonElement(RoomState.serializer(), initialJson)
            val ops = LiveJson.decodeFromJsonElement(ListSerializer(SequencedOp.serializer()), scenario.getValue("ops"))

            val result = Reducer.applyAll(initial, ops)

            val actual = LiveJson.encodeToJsonElement(RoomState.serializer(), result)
            assertEquals("scenario ${file.name}", normalized(scenario.getValue("expected")), normalized(actual))
            // Pure: the input state is untouched.
            assertEquals(
                "scenario ${file.name} changed its input",
                normalized(initialJson),
                normalized(LiveJson.encodeToJsonElement(RoomState.serializer(), initial)),
            )
        }
    }

    @Test
    fun movesAddUpToTheSameDoubleAsJavaScript() {
        // 0.1 + 0.2 is 0.30000000000000004 in every IEEE-754 language.
        assertEquals(0.30000000000000004, 0.1 + 0.2, 0.0)
        val page = LivePage("p", 100.0, 100.0)
        val stroke = LiveStroke("s", "pen", LiveColor(0.0, 0.0, 0.0), 1.0, "2026-01-01T00:00:00Z", listOf(LivePoint(0.1, 0.0, 1.0, 0.0, 1.0)))
        var state = RoomState(pages = listOf(page))
        state = Reducer.apply(state, SequencedOp(1, "a", null, Op.StrokeAdd("p", stroke)))
        state = Reducer.apply(state, SequencedOp(2, "a", null, Op.ItemsMove("p", listOf("s"), emptyList(), 0.2, 0.0)))
        assertEquals(0.30000000000000004, state.pages[0].strokes[0].stroke.points[0].x, 0.0)
    }

    @Test
    fun unknownOpsKeepTheirRawJson() {
        val raw = """{"kind":"shape.add","pageId":"p","shape":{"circle":true}}"""
        val op = LiveJson.decodeFromString(Op.serializer(), raw)
        assertTrue(op is Op.Unknown)
        assertEquals(normalized(LiveJson.parseToJsonElement(raw)), normalized(LiveJson.encodeToJsonElement(Op.serializer(), op)))
    }

    @Test
    fun malformedKnownOpChangesOnlySeq() {
        val op = LiveJson.decodeFromString(Op.serializer(), """{"kind":"stroke.add","pageId":"p"}""")
        assertTrue(op is Op.Unknown)
        val state = RoomState(seq = 4, pages = listOf(LivePage("p", 1.0, 1.0)))
        assertEquals(state.copy(seq = 5), Reducer.apply(state, SequencedOp(5, "a", null, op)))
    }
}
