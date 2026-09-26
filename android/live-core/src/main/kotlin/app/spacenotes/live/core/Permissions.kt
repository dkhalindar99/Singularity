// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/**
 * protocol/PROTOCOL.md "Permissions", ported from web/src/core/permissions.js.
 * The server's answer is the one that counts; the client uses this to grey out
 * its tools.
 *
 * Validation reads the raw JSON rather than a decoded [Op], because the typed
 * decoder is forgiving in ways the server is not (it would, for instance,
 * accept the string "10" as a coordinate).
 */
public object Permissions {
    public const val NOT_HOST: String = RejectReason.NOT_HOST
    public const val DRAWING_LOCKED: String = RejectReason.DRAWING_LOCKED
    public const val INVALID_OP: String = RejectReason.INVALID_OP

    /** The most points one stroke may have. */
    public const val MAX_STROKE_POINTS: Int = 5000

    private val hostOnly = setOf(Op.RoomPolicy.KIND, Op.HostPage.KIND, Op.PageAdd.KIND)

    /** True if this member may change the notebook's content right now. */
    public fun canDraw(state: RoomState, actor: Actor): Boolean {
        if (actor.role == Role.HOST) return true
        if (state.drawPolicy == DrawPolicy.EVERYONE) return true
        return state.drawPolicy == DrawPolicy.PEN && state.penHolder == actor.uid
    }

    /** `null` when allowed, otherwise the reject reason. */
    public fun authorize(state: RoomState, actor: Actor, op: JsonElement): String? {
        if (!isValidOp(op)) return INVALID_OP
        val kind = ((op as JsonObject)["kind"] as JsonPrimitive).content
        if (kind in hostOnly) return if (actor.role == Role.HOST) null else NOT_HOST
        return if (canDraw(state, actor)) null else DRAWING_LOCKED
    }

    /** Same check for a typed op, through its wire form. */
    public fun authorize(state: RoomState, actor: Actor, op: Op): String? =
        authorize(state, actor, LiveJson.encodeToJsonElement(OpSerializer, op))

    public fun isValidOp(op: JsonElement?): Boolean {
        val o = op as? JsonObject ?: return false
        val kind = o.str("kind") ?: return false
        return when (kind) {
            Op.StrokeAdd.KIND -> o.isString("pageId") && isValidStroke(o["stroke"])
            Op.StrokeErase.KIND, Op.StrokeRestore.KIND -> o.isString("pageId") && isStringArray(o["strokeIds"])
            Op.TextUpsert.KIND -> o.isString("pageId") && isValidText(o["text"])
            Op.TextErase.KIND -> o.isString("pageId") && isStringArray(o["textIds"])
            Op.ItemsMove.KIND ->
                o.isString("pageId") && isNumber(o["dx"]) && isNumber(o["dy"]) &&
                    (!o.containsKey("strokeIds") || isStringArray(o["strokeIds"])) &&
                    (!o.containsKey("textIds") || isStringArray(o["textIds"]))
            Op.PageAdd.KIND -> isValidPage(o["page"]) && (o.isNullish("afterPageId") || o.isString("afterPageId"))
            Op.RoomPolicy.KIND ->
                o.str("drawPolicy") in DrawPolicy.all && (o.isNullish("penHolder") || o.isString("penHolder"))
            Op.HostPage.KIND -> o.isString("pageId")
            else -> false
        }
    }

    public fun isValidStroke(element: JsonElement?): Boolean {
        val s = element as? JsonObject ?: return false
        if (!s.isString("id") || !s.isString("ink") || !isColor(s["color"]) || !isNumber(s["width"])) return false
        val points = s["points"] as? JsonArray ?: return false
        if (points.isEmpty() || points.size > MAX_STROKE_POINTS) return false
        return points.all { p ->
            p is JsonObject && listOf("x", "y", "pressure", "timeOffset", "width").all { isNumber(p[it]) }
        }
    }

    public fun isValidText(element: JsonElement?): Boolean {
        val t = element as? JsonObject ?: return false
        val text = t["text"]
        return t.isString("id") && text is JsonPrimitive && text.isString &&
            isFrame(t["frame"]) && isNumber(t["fontSize"]) && isColor(t["color"])
    }

    public fun isValidPage(element: JsonElement?): Boolean {
        val p = element as? JsonObject ?: return false
        val width = number(p["width"]) ?: return false
        val height = number(p["height"]) ?: return false
        val background = p["background"] as? JsonObject ?: return false
        return p.isString("id") && width > 0 && height > 0 && background.isString("kind")
    }

    private fun number(element: JsonElement?): Double? {
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive.isString || primitive is JsonNull) return null
        return primitive.doubleOrNull?.takeIf { it.isFinite() }
    }

    private fun isNumber(element: JsonElement?): Boolean = number(element) != null

    /** A non-empty string, as the reference implementation requires. */
    private fun isNonEmptyString(element: JsonElement?): Boolean =
        element is JsonPrimitive && element.isString && element.content.isNotEmpty()

    private fun isStringArray(element: JsonElement?): Boolean =
        element is JsonArray && element.all(::isNonEmptyString)

    private fun isColor(element: JsonElement?): Boolean {
        val c = element as? JsonObject ?: return false
        return listOf("r", "g", "b", "a").all { isNumber(c[it]) }
    }

    private fun isFrame(element: JsonElement?): Boolean {
        val f = element as? JsonObject ?: return false
        return listOf("x", "y", "width", "height").all { isNumber(f[it]) }
    }

    private fun JsonObject.isString(key: String): Boolean = isNonEmptyString(this[key])

    private fun JsonObject.str(key: String): String? = this[key].takeIf(::isNonEmptyString)?.let { (it as JsonPrimitive).content }

    /** Absent or null, the reference implementation's `== null`. */
    private fun JsonObject.isNullish(key: String): Boolean = this[key] == null || this[key] is JsonNull
}

/** Convenience for the typed state. */
public fun RoomState.canDraw(actor: Actor?): Boolean = actor != null && Permissions.canDraw(this, actor)
