// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import app.spacenotes.live.core.InkGeometry
import app.spacenotes.live.core.LiveColor
import app.spacenotes.live.core.LiveInk
import app.spacenotes.live.core.LiveInkStreamer
import app.spacenotes.live.core.LivePage
import app.spacenotes.live.core.LivePoint
import app.spacenotes.live.core.LiveText
import app.spacenotes.live.core.Member
import app.spacenotes.live.core.PageBackground
import app.spacenotes.live.core.RemoteInk
import app.spacenotes.live.core.RemotePointer
import app.spacenotes.live.core.RoomClient
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/** What a touch on the page does. */
public enum class LiveTool { Pen, Highlighter, Eraser, Text, Laser }

/** The drawing settings the toolbar controls. */
public data class InkSettings(
    val tool: LiveTool = LiveTool.Pen,
    val penColor: Color = LiveTheme.Light.inkPalette.first(),
    val highlighterColor: Color = LiveTheme.Light.highlighterPalette.first(),
    val penWidth: Double = 2.5,
    /** Ignore fingers on the page, so a resting palm draws nothing. */
    val stylusOnly: Boolean = false,
)

internal fun LiveColor.toColor(): Color =
    Color(r.toFloat().coerceIn(0f, 1f), g.toFloat().coerceIn(0f, 1f), b.toFloat().coerceIn(0f, 1f), a.toFloat().coerceIn(0f, 1f))

internal fun Color.toLiveColor(): LiveColor = LiveColor(red.toDouble(), green.toDouble(), blue.toDouble(), alpha.toDouble())

/** "#RRGGBB" from the server into a colour; anything unreadable is the accent. */
internal fun memberColor(hex: String, fallback: Color): Color {
    val digits = hex.removePrefix("#")
    val value = digits.toLongOrNull(16) ?: return fallback
    return when (digits.length) {
        6 -> Color(0xFF000000 or value)
        8 -> Color(value)
        else -> fallback
    }
}

/** The text a tap with the text tool opens for editing. */
public data class TextDraft(
    val pageId: String,
    /** Set when editing an existing box. */
    val existing: LiveText?,
    val x: Double,
    val y: Double,
)

/**
 * The shared page: paper, committed ink and text from `client.state`, other
 * people's strokes in progress and their pointers, and this person's own
 * input. The page is fitted whole into the available space.
 */
@Composable
public fun LivePageCanvas(
    client: RoomClient,
    page: LivePage,
    settings: InkSettings,
    canDraw: Boolean,
    liveInk: Collection<RemoteInk>,
    pointers: Collection<RemotePointer>,
    members: List<Member>,
    backgroundImage: ImageBitmap?,
    onTextTap: (TextDraft) -> Unit,
    modifier: Modifier = Modifier,
) {
    val theme = LocalLiveTheme.current
    val textMeasurer = rememberTextMeasurer()
    val localPoints = remember(page.id) { mutableStateListOf<LivePoint>() }
    var localStyle by remember { mutableStateOf<LocalStroke?>(null) }
    val currentSettings by rememberUpdatedState(settings)
    val currentCanDraw by rememberUpdatedState(canDraw)
    val currentPage by rememberUpdatedState(page)
    val currentOnTextTap by rememberUpdatedState(onTextTap)

    // Lasers fade out; tick while any is on screen.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val hasLaser = pointers.any { it.laser && it.pageId == page.id }
    LaunchedEffect(hasLaser) {
        while (hasLaser) {
            now = System.currentTimeMillis()
            delay(100)
        }
    }

    val names = members.associate { it.connectionId to it }
    var viewSize by remember { mutableStateOf(IntSize.Zero) }
    val fit = InkGeometry.fit(page.width, page.height, viewSize.width.toDouble(), viewSize.height.toDouble(), margin = 12.0)
    val currentFit by rememberUpdatedState(fit)

    Box(modifier) {
        Canvas(
            Modifier
                .fillMaxSize()
                .onSizeChanged { viewSize = it }
                .pointerInput(page.id, client) {
                    awaitPointerEventScope {
                        val gesture = PageGesture(client, localPoints) { localStyle = it }
                        try {
                            var active: PointerId? = null
                            while (true) {
                                val event = awaitPointerEvent()
                                val fitNow = currentFit
                                when (event.type) {
                                    PointerEventType.Press -> {
                                        val change = event.changes.firstOrNull { it.pressed && !it.previousPressed } ?: continue
                                        if (active != null) continue
                                        val s = currentSettings
                                        if (s.stylusOnly && change.type == PointerType.Touch) continue
                                        if (!currentCanDraw && s.tool != LiveTool.Laser) continue
                                        active = change.id
                                        change.consume()
                                        val x = fitNow.toPageX(change.position.x.toDouble())
                                        val y = fitNow.toPageY(change.position.y.toDouble())
                                        gesture.start(currentPage, s, fitNow.scale, x, y, change, currentOnTextTap)
                                    }
                                    PointerEventType.Move -> {
                                        val change = event.changes.firstOrNull { it.id == active }
                                        if (change != null) {
                                            for (h in change.historical) {
                                                gesture.move(
                                                    fitNow.toPageX(h.position.x.toDouble()),
                                                    fitNow.toPageY(h.position.y.toDouble()),
                                                    change.pressure,
                                                    h.uptimeMillis,
                                                    change.type,
                                                )
                                            }
                                            gesture.move(
                                                fitNow.toPageX(change.position.x.toDouble()),
                                                fitNow.toPageY(change.position.y.toDouble()),
                                                change.pressure,
                                                change.uptimeMillis,
                                                change.type,
                                            )
                                            change.consume()
                                        } else if (active == null) {
                                            // A hovering pen shows where it is to everyone else.
                                            val hover = event.changes.firstOrNull { !it.pressed && it.type == PointerType.Stylus }
                                            if (hover != null) {
                                                client.sendPointer(
                                                    currentPage.id,
                                                    fitNow.toPageX(hover.position.x.toDouble()),
                                                    fitNow.toPageY(hover.position.y.toDouble()),
                                                )
                                            }
                                        }
                                    }
                                    PointerEventType.Release -> {
                                        val change = event.changes.firstOrNull { it.id == active && !it.pressed } ?: continue
                                        change.consume()
                                        active = null
                                        gesture.end()
                                    }
                                    PointerEventType.Exit -> if (active == null) client.hidePointer()
                                    else -> Unit
                                }
                            }
                        } finally {
                            gesture.cancel()
                        }
                    }
                },
        ) {
            val f = InkGeometry.fit(page.width, page.height, size.width.toDouble(), size.height.toDouble(), margin = 12.0)
            val scale = f.scale.toFloat()
            val origin = Offset(f.offsetX.toFloat(), f.offsetY.toFloat())
            val pageSize = Size((page.width * f.scale).toFloat(), (page.height * f.scale).toFloat())

            drawPaper(page, origin, pageSize, scale, theme, backgroundImage)
            clipRect(origin.x, origin.y, origin.x + pageSize.width, origin.y + pageSize.height) {
                for (item in page.strokes) {
                    if (!item.erased) drawInk(item.stroke.points, item.stroke.color.toColor(), item.stroke.inkKind, item.stroke.isHighlighter, origin, scale)
                }
                for (item in page.texts) {
                    if (!item.erased) drawTextBox(item.text, origin, scale, textMeasurer)
                }
                for (ink in liveInk) {
                    if (ink.pageId != page.id) continue
                    val color = ink.color.toColor()
                    drawInk(ink.points, color, ink.inkKind, ink.inkKind == LiveInk.Marker && ink.color.a < 1.0, origin, scale)
                    val last = ink.points.lastOrNull() ?: continue
                    val member = names[ink.connectionId]
                    if (member != null && !ink.done) {
                        drawNameTag(
                            member.name,
                            memberColor(member.color, theme.accent),
                            Offset(origin.x + (last.x * scale).toFloat() + 10f, origin.y + (last.y * scale).toFloat() + 10f),
                            textMeasurer,
                        )
                    }
                }
                localStyle?.let { style ->
                    drawInk(localPoints, style.color, style.ink, style.highlighter, origin, scale)
                }
            }
            for (pointer in pointers) {
                if (pointer.pageId != page.id) continue
                val member = names[pointer.connectionId]
                val color = memberColor(member?.color ?: "", theme.accent)
                val center = Offset(origin.x + (pointer.x * scale).toFloat(), origin.y + (pointer.y * scale).toFloat())
                val age = (now - pointer.receivedAt).coerceAtLeast(0)
                if (pointer.laser) {
                    val alpha = (1f - (age - LASER_HOLD_MS).coerceAtLeast(0) / LASER_FADE_MS.toFloat()).coerceIn(0f, 1f)
                    if (alpha <= 0f) continue
                    drawCircle(color.copy(alpha = 0.25f * alpha), radius = 16f, center = center)
                    drawCircle(color.copy(alpha = alpha), radius = 7f, center = center)
                    drawCircle(Color.White.copy(alpha = alpha), radius = 3f, center = center)
                } else {
                    drawCircle(color, radius = 5f, center = center)
                    drawCircle(Color.White, radius = 5f, center = center, style = Stroke(width = 1.5f))
                }
                if (member != null) drawNameTag(member.name, color, center + Offset(10f, 10f), textMeasurer)
            }
        }
    }
}

private const val LASER_HOLD_MS = 1200L
private const val LASER_FADE_MS = 800L

/** This person's own stroke while it is being drawn. */
internal data class LocalStroke(val color: Color, val ink: LiveInk, val highlighter: Boolean)

/**
 * One touch on the page, from press to release. Pen and highlighter stream
 * through [LiveInkStreamer] and commit on release; the eraser erases whatever
 * it crosses as it goes; the laser moves a pointer everyone sees.
 */
private class PageGesture(
    private val client: RoomClient,
    private val localPoints: SnapshotStateList<LivePoint>,
    private val setLocalStyle: (LocalStroke?) -> Unit,
) {
    private var tool: LiveTool? = null
    private var page: LivePage? = null
    private var streamer: LiveInkStreamer? = null
    private var startUptime = 0L
    private var baseWidth = 2.5
    private var eraserRadius = 8.0
    private val erased = HashSet<String>()

    fun start(
        page: LivePage,
        settings: InkSettings,
        scale: Double,
        x: Double,
        y: Double,
        change: PointerInputChange,
        onTextTap: (TextDraft) -> Unit,
    ) {
        this.page = page
        tool = settings.tool
        startUptime = change.uptimeMillis
        when (settings.tool) {
            LiveTool.Pen, LiveTool.Highlighter -> {
                val highlighter = settings.tool == LiveTool.Highlighter
                val color = if (highlighter) settings.highlighterColor else settings.penColor
                baseWidth = if (highlighter) settings.penWidth * 6 else settings.penWidth
                val ink = if (highlighter) LiveInk.Marker else LiveInk.Pen
                streamer = client.beginStroke(page.id, ink.wireName, color.toLiveColor(), baseWidth)
                localPoints.clear()
                setLocalStyle(LocalStroke(color, ink, highlighter))
                move(x, y, change.pressure, change.uptimeMillis, change.type)
            }
            LiveTool.Eraser -> {
                // About twelve screen pixels, whatever the zoom.
                eraserRadius = 12.0 / scale
                erased.clear()
                move(x, y, change.pressure, change.uptimeMillis, change.type)
            }
            LiveTool.Laser -> client.sendPointer(page.id, x, y, laser = true)
            LiveTool.Text -> {
                val existing = InkGeometry.textAt(page, x, y, slop = 6.0 / scale)?.text
                onTextTap(TextDraft(page.id, existing, x, y))
                tool = null
            }
        }
    }

    fun move(x: Double, y: Double, pressure: Float, uptime: Long, type: PointerType) {
        val page = page ?: return
        when (tool) {
            LiveTool.Pen, LiveTool.Highlighter -> {
                val streamer = streamer ?: return
                // Pressure widens a stylus line; a finger reports a constant.
                val width = if (type == PointerType.Stylus && tool == LiveTool.Pen) {
                    baseWidth * (0.4 + 1.2 * pressure.coerceIn(0f, 1f))
                } else {
                    baseWidth
                }
                val point = LivePoint(x, y, pressure.toDouble(), (uptime - startUptime) / 1000.0, width)
                streamer.add(point)
                localPoints += point
            }
            LiveTool.Eraser -> {
                val current = client.state.value.page(page.id) ?: return
                val strokes = InkGeometry.strokesHit(current, x, y, eraserRadius).filter { erased.add(it) }
                if (strokes.isNotEmpty()) client.eraseStrokes(page.id, strokes)
                InkGeometry.textAt(current, x, y)?.let { text ->
                    if (erased.add(text.text.id)) client.eraseTexts(page.id, listOf(text.text.id))
                }
            }
            LiveTool.Laser -> client.sendPointer(page.id, x, y, laser = true)
            else -> Unit
        }
    }

    fun end() {
        when (tool) {
            LiveTool.Pen, LiveTool.Highlighter -> {
                streamer?.finish()
                streamer = null
                localPoints.clear()
                setLocalStyle(null)
            }
            LiveTool.Laser -> client.hidePointer()
            else -> Unit
        }
        tool = null
    }

    fun cancel() {
        streamer?.cancel()
        streamer = null
        localPoints.clear()
        setLocalStyle(null)
        tool = null
    }
}

private fun DrawScope.drawPaper(
    page: LivePage,
    origin: Offset,
    pageSize: Size,
    scale: Float,
    theme: LiveTheme,
    image: ImageBitmap?,
) {
    drawRect(theme.pageShadow, topLeft = origin + Offset(0f, 2f), size = pageSize)
    drawRect(theme.page, topLeft = origin, size = pageSize)
    when (val background = page.background.drawnAs) {
        is PageBackground.Drawn.Image -> if (image != null) {
            drawImage(
                image,
                dstOffset = IntOffset(origin.x.roundToInt(), origin.y.roundToInt()),
                dstSize = IntSize(pageSize.width.roundToInt(), pageSize.height.roundToInt()),
            )
        }
        is PageBackground.Drawn.Template -> {
            val step = 24f * scale
            if (step < 3f) return
            when (background.template) {
                "lined" -> {
                    var y = origin.y + step * 3
                    while (y < origin.y + pageSize.height) {
                        drawLine(theme.pageRule, Offset(origin.x, y), Offset(origin.x + pageSize.width, y), strokeWidth = 1f)
                        y += step
                    }
                }
                "grid" -> {
                    var x = origin.x + step
                    while (x < origin.x + pageSize.width) {
                        drawLine(theme.pageRule, Offset(x, origin.y), Offset(x, origin.y + pageSize.height), strokeWidth = 1f)
                        x += step
                    }
                    var y = origin.y + step
                    while (y < origin.y + pageSize.height) {
                        drawLine(theme.pageRule, Offset(origin.x, y), Offset(origin.x + pageSize.width, y), strokeWidth = 1f)
                        y += step
                    }
                }
                else -> {
                    var y = origin.y + step
                    while (y < origin.y + pageSize.height) {
                        var x = origin.x + step
                        while (x < origin.x + pageSize.width) {
                            drawCircle(theme.pageRule, radius = 1.5f, center = Offset(x, y))
                            x += step
                        }
                        y += step
                    }
                }
            }
        }
        PageBackground.Drawn.Blank -> Unit
    }
}

/**
 * Draws a stroke from its own per-point widths, the way the notebook redraws
 * PencilKit ink. A highlighter is one translucent path, so overlapping
 * segments do not darken where they meet.
 */
private fun DrawScope.drawInk(
    points: List<LivePoint>,
    color: Color,
    ink: LiveInk,
    highlighter: Boolean,
    origin: Offset,
    scale: Float,
) {
    if (points.isEmpty()) return
    fun at(p: LivePoint) = Offset(origin.x + (p.x * scale).toFloat(), origin.y + (p.y * scale).toFloat())
    if (points.size == 1) {
        drawCircle(color, radius = (points[0].width * scale / 2).toFloat().coerceAtLeast(0.5f), center = at(points[0]))
        return
    }
    if (highlighter || ink == LiveInk.Marker) {
        val path = Path()
        path.moveTo(at(points[0]).x, at(points[0]).y)
        for (i in 1 until points.size) at(points[i]).let { path.lineTo(it.x, it.y) }
        val width = (points.sumOf { it.width } / points.size * scale).toFloat()
        drawPath(path, color, style = Stroke(width = width, cap = StrokeCap.Round, join = StrokeJoin.Round))
        return
    }
    for (i in 1 until points.size) {
        val a = points[i - 1]
        val b = points[i]
        drawLine(
            color,
            at(a),
            at(b),
            strokeWidth = ((a.width + b.width) / 2 * scale).toFloat().coerceAtLeast(0.5f),
            cap = StrokeCap.Round,
        )
    }
}

private fun DrawScope.drawTextBox(text: LiveText, origin: Offset, scale: Float, measurer: TextMeasurer) {
    val width = (text.frame.width * scale).toFloat()
    if (width <= 1f || text.text.isEmpty()) return
    val layout = measurer.measure(
        text.text,
        style = TextStyle(color = text.color.toColor(), fontSize = (text.fontSize * scale).toFloat().toSp()),
        constraints = Constraints(maxWidth = width.roundToInt().coerceAtLeast(1)),
    )
    drawText(layout, topLeft = Offset(origin.x + (text.frame.x * scale).toFloat(), origin.y + (text.frame.y * scale).toFloat()))
}

private fun DrawScope.drawNameTag(name: String, color: Color, at: Offset, measurer: TextMeasurer) {
    val layout = measurer.measure(name, style = TextStyle(color = Color.White, fontSize = 11f.toSp()), maxLines = 1)
    val padding = 4f
    drawRoundRect(
        color,
        topLeft = at,
        size = Size(layout.size.width + padding * 2, layout.size.height + padding),
        cornerRadius = CornerRadius(6f, 6f),
    )
    drawText(layout, topLeft = at + Offset(padding, padding / 2))
}
