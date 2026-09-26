// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import java.io.File
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/** The shared protocol fixtures, read from the repository (../../fixtures/protocol). */
object Fixtures {
    val root: File by lazy {
        val configured = System.getProperty("spacenotes.live.fixtures")?.let(::File)
        val candidates = listOfNotNull(configured, File("../../fixtures/protocol"), File("../fixtures/protocol"))
        candidates.firstOrNull { File(it, "scenarios").isDirectory }
            ?: error("protocol fixtures not found; looked in ${candidates.map { it.absolutePath }}")
    }

    fun load(path: String): JsonElement = LiveJson.parseToJsonElement(File(root, path).readText())

    fun files(dir: String): List<File> =
        File(root, dir).listFiles { f -> f.extension == "json" }.orEmpty().sortedBy { it.name }
}

/**
 * Value equality as protocol/PROTOCOL.md defines it: a missing field equals
 * null, and numbers compare as doubles (so 10 and 10.0 are the same).
 */
fun normalized(element: JsonElement): Any? = when (element) {
    is JsonNull -> null
    is JsonObject -> element.entries
        .mapNotNull { (k, v) -> normalized(v)?.let { k to it } }
        .sortedBy { it.first }
        .toMap()
    is JsonArray -> element.map(::normalized)
    is JsonPrimitive -> when {
        element.isString -> element.content
        element.booleanOrNull != null -> element.booleanOrNull
        else -> element.content.toDouble()
    }
}
