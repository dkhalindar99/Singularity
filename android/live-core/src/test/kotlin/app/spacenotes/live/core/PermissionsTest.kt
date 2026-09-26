// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PermissionsTest {
    private val cases = Fixtures.load("permissions/cases.json").jsonObject.getValue("cases").jsonArray

    @Test
    fun everyCaseFromTheFixtures() {
        assertEquals(19, cases.size)
        for (element in cases) {
            val case = element.jsonObject
            val name = (case.getValue("name") as JsonPrimitive).content
            val state = LiveJson.decodeFromJsonElement(RoomState.serializer(), case.getValue("state"))
            val actor = LiveJson.decodeFromJsonElement(Actor.serializer(), case.getValue("member"))
            val expected = case["expected"]?.takeUnless { it is JsonNull }?.let { (it as JsonPrimitive).content }
            assertEquals(name, expected, Permissions.authorize(state, actor, case.getValue("op")))
        }
    }

    @Test
    fun typedOpsAgreeWithRawOpsWheneverTheRawOpIsValid() {
        for (element in cases) {
            val case = element.jsonObject
            if (!Permissions.isValidOp(case.getValue("op"))) continue
            val state = LiveJson.decodeFromJsonElement(RoomState.serializer(), case.getValue("state"))
            val actor = LiveJson.decodeFromJsonElement(Actor.serializer(), case.getValue("member"))
            val op = LiveJson.decodeFromJsonElement(Op.serializer(), case.getValue("op"))
            assertEquals(
                (case.getValue("name") as JsonPrimitive).content,
                Permissions.authorize(state, actor, case.getValue("op")),
                Permissions.authorize(state, actor, op),
            )
        }
    }

    @Test
    fun canDrawFollowsThePolicy() {
        val guest = Actor("g", Role.GUEST)
        val host = Actor("h", Role.HOST)
        assertTrue(Permissions.canDraw(RoomState(drawPolicy = DrawPolicy.EVERYONE), guest))
        assertFalse(Permissions.canDraw(RoomState(drawPolicy = DrawPolicy.HOST), guest))
        assertTrue(Permissions.canDraw(RoomState(drawPolicy = DrawPolicy.HOST), host))
        assertTrue(Permissions.canDraw(RoomState(drawPolicy = DrawPolicy.PEN, penHolder = "g"), guest))
        assertFalse(Permissions.canDraw(RoomState(drawPolicy = DrawPolicy.PEN, penHolder = "x"), guest))
    }
}
