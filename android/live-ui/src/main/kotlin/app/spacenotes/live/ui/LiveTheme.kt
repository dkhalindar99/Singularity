// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.ui

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * The room screen's colours. The notebook passes its own (faded indigo) so
 * the room looks like the rest of the app; [Light] and [Dark] are sensible
 * stand-ins until it does.
 */
@Immutable
public data class LiveTheme(
    /** Behind everything. */
    val background: Color,
    /** Bars and sheets. */
    val surface: Color,
    /** Tiles and chips. */
    val surfaceVariant: Color,
    val onSurface: Color,
    val onSurfaceMuted: Color,
    val accent: Color,
    val onAccent: Color,
    val danger: Color,
    val onDanger: Color,
    /** The paper. */
    val page: Color,
    /** Template lines and dots on the paper. */
    val pageRule: Color,
    val pageShadow: Color,
    /** Ink colours offered in the toolbar, first is the default. */
    val inkPalette: List<Color>,
    val highlighterPalette: List<Color>,
) {
    public companion object {
        public val Light: LiveTheme = LiveTheme(
            background = Color(0xFFEEF0F7),
            surface = Color(0xFFFFFFFF),
            surfaceVariant = Color(0xFFE2E5F1),
            onSurface = Color(0xFF1C1F2E),
            onSurfaceMuted = Color(0xFF5E6378),
            accent = Color(0xFF5566B0),
            onAccent = Color(0xFFFFFFFF),
            danger = Color(0xFFC62F3A),
            onDanger = Color(0xFFFFFFFF),
            page = Color(0xFFFFFFFF),
            pageRule = Color(0xFFC9D0E6),
            pageShadow = Color(0x33000000),
            inkPalette = listOf(
                Color(0xFF1F2330), Color(0xFF3B5BDB), Color(0xFFD9480F),
                Color(0xFF2B9348), Color(0xFF9C36B5), Color(0xFFC2255C),
            ),
            highlighterPalette = listOf(
                Color(0x66FFE066), Color(0x6674C0FC), Color(0x668CE99A), Color(0x66FFA8A8),
            ),
        )

        public val Dark: LiveTheme = Light.copy(
            background = Color(0xFF12141C),
            surface = Color(0xFF1C1F2B),
            surfaceVariant = Color(0xFF2A2E3D),
            onSurface = Color(0xFFE8EAF4),
            onSurfaceMuted = Color(0xFFA2A7BD),
            accent = Color(0xFF8C9BE0),
            onAccent = Color(0xFF10131F),
            pageShadow = Color(0x66000000),
        )
    }
}

internal val LocalLiveTheme = staticCompositionLocalOf { LiveTheme.Light }
