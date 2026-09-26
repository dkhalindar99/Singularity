// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlin.reflect.KClass
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

/**
 * The one JSON configuration every frame goes through.
 *
 * - Unknown keys are ignored, so a newer server can add fields.
 * - Absent optional fields are left out rather than written as `null`, which
 *   is how the notebook writes a stroke (no `azimuth` for a finger point).
 * - Defaults are written, so every required field is always on the wire.
 */
public val LiveJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}

/**
 * A JSON object whose shape is chosen by one string field (`type` for frames,
 * `kind` for ops, presence and control). A tag this build does not know, or a
 * known tag whose fields do not fit, becomes the union's "unknown" case, so
 * reading never throws for content a newer peer sent.
 */
internal class TaggedUnion<T : Any>(
    private val tagKey: String,
    private val cases: List<Case<out T>>,
    private val unknown: (tag: String, raw: JsonObject) -> T,
    private val rawOf: (T) -> JsonObject?,
) {
    internal class Case<C : Any>(
        val tag: String,
        val type: KClass<C>,
        val serializer: KSerializer<C>?,
        val instance: C?,
    )

    fun decode(element: JsonElement, json: Json): T {
        val obj = element as? JsonObject ?: return unknown("", JsonObject(emptyMap()))
        val tag = (obj[tagKey] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return unknown("", obj)
        val case = cases.firstOrNull { it.tag == tag } ?: return unknown(tag, obj)
        case.instance?.let { return it }
        return try {
            json.decodeFromJsonElement(case.serializer!!, obj)
        } catch (_: SerializationException) {
            unknown(tag, obj)
        } catch (_: IllegalArgumentException) {
            unknown(tag, obj)
        }
    }

    fun encode(value: T, json: Json): JsonObject {
        rawOf(value)?.let { return it }
        val case = cases.first { it.type.isInstance(value) }
        val fields = LinkedHashMap<String, JsonElement>()
        fields[tagKey] = JsonPrimitive(case.tag)
        if (case.serializer != null) {
            @Suppress("UNCHECKED_CAST")
            val body = json.encodeToJsonElement(case.serializer as KSerializer<Any>, value).jsonObject
            for ((key, field) in body) if (key != tagKey) fields[key] = field
        }
        return JsonObject(fields)
    }

    companion object {
        inline fun <reified C : Any> case(tag: String, serializer: KSerializer<C>): Case<C> =
            Case(tag, C::class, serializer, null)

        inline fun <reified C : Any> objectCase(tag: String, instance: C): Case<C> =
            Case(tag, C::class, null, instance)
    }
}

/** Plugs a [TaggedUnion] into kotlinx.serialization. JSON only, by design. */
internal open class TaggedUnionSerializer<T : Any>(
    serialName: String,
    unionFactory: () -> TaggedUnion<T>,
) : KSerializer<T> {
    private val union by lazy(unionFactory)

    override val descriptor: SerialDescriptor = buildClassSerialDescriptor(serialName)

    override fun deserialize(decoder: Decoder): T {
        val input = decoder as? JsonDecoder ?: throw SerializationException("$descriptor is JSON only")
        return union.decode(input.decodeJsonElement(), input.json)
    }

    override fun serialize(encoder: Encoder, value: T) {
        val output = encoder as? JsonEncoder ?: throw SerializationException("$descriptor is JSON only")
        output.encodeJsonElement(union.encode(value, output.json))
    }
}
