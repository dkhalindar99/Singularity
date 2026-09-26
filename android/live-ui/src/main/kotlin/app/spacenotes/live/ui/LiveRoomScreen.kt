// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.ui

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoFixNormal
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.Highlight
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.WbIncandescent
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.spacenotes.live.core.DrawPolicy
import app.spacenotes.live.core.LiveApi
import app.spacenotes.live.core.LivePageSpec
import app.spacenotes.live.core.LiveRect
import app.spacenotes.live.core.LiveText
import app.spacenotes.live.core.Member
import app.spacenotes.live.core.PageBackground
import app.spacenotes.live.core.RejectReason
import app.spacenotes.live.core.RemovedReason
import app.spacenotes.live.core.RoomClient
import app.spacenotes.live.core.RoomEvent
import app.spacenotes.live.core.RoomStatus
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Creates a [RoomClient] for this composition and connects it. The client
 * leaves the room when the composition goes away, so an app that keeps the
 * room across configuration changes should hold the client in a ViewModel
 * instead and pass it to [LiveRoomScreen] directly.
 */
@Composable
public fun rememberRoomClient(
    serverUrl: String,
    roomId: String,
    name: String,
    deviceId: String,
    tokenProvider: suspend () -> String,
): RoomClient {
    val scope = rememberCoroutineScope()
    val client = remember(serverUrl, roomId) {
        RoomClient(serverUrl, roomId, name, deviceId, tokenProvider, scope = scope)
    }
    DisposableEffect(client) {
        client.connect()
        onDispose { client.disconnect() }
    }
    return client
}

/**
 * The SpaceNotes Live room: people along the top, the shared page in the
 * middle, tools and call controls below.
 *
 * [onSessionEnded] is called once when the session is over for this person —
 * they left, the host ended it, or they were removed — with the notebook as
 * it stood, for the host app to save back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
public fun LiveRoomScreen(
    client: RoomClient,
    api: LiveApi,
    onSessionEnded: (LiveSessionResult) -> Unit,
    modifier: Modifier = Modifier,
    voiceProvider: LiveVoiceProvider = NoVoice,
    theme: LiveTheme = LiveTheme.Light,
) {
    CompositionLocalProvider(LocalLiveTheme provides theme) {
        val context = LocalContext.current
        val status by client.status.collectAsStateWithLifecycle()
        val state by client.state.collectAsStateWithLifecycle()
        val members by client.members.collectAsStateWithLifecycle()
        val me by client.me.collectAsStateWithLifecycle()
        val room by client.room.collectAsStateWithLifecycle()
        val canDraw by client.canDraw.collectAsStateWithLifecycle()
        val canUndo by client.canUndo.collectAsStateWithLifecycle()
        val canRedo by client.canRedo.collectAsStateWithLifecycle()
        val liveInk by client.liveInk.collectAsStateWithLifecycle()
        val pointers by client.pointers.collectAsStateWithLifecycle()
        val voiceParticipants by voiceProvider.participants.collectAsStateWithLifecycle()
        val micOn by voiceProvider.microphoneOn.collectAsStateWithLifecycle()
        val snackbar = remember { SnackbarHostState() }

        val isHost = me?.isHost == true
        var chosenPageId by rememberSaveable { mutableStateOf<String?>(null) }
        var followHost by rememberSaveable { mutableStateOf(true) }
        var settings by remember { mutableStateOf(InkSettings(penColor = theme.inkPalette.first(), highlighterColor = theme.highlighterPalette.first())) }
        var textDraft by remember { mutableStateOf<TextDraft?>(null) }
        var showPeople by remember { mutableStateOf(false) }
        var confirmLeave by remember { mutableStateOf(false) }
        var handRaised by rememberSaveable { mutableStateOf(false) }

        val page = state.page(chosenPageId) ?: state.page(state.hostPageId) ?: state.pages.firstOrNull()
        val pageIndex = state.pages.indexOfFirst { it.id == page?.id }

        // Follow the host's page unless this person has wandered off on purpose.
        LaunchedEffect(followHost, state.hostPageId, isHost) {
            if (followHost && !isHost && state.hostPageId != null) chosenPageId = state.hostPageId
        }
        LaunchedEffect(page?.id, status) {
            val id = page?.id ?: return@LaunchedEffect
            if (status != RoomStatus.Connected) return@LaunchedEffect
            client.sendView(id)
            if (isHost && state.hostPageId != id) client.setHostPage(id)
        }

        fun goTo(index: Int) {
            val target = state.pages.getOrNull(index) ?: return
            chosenPageId = target.id
            if (!isHost && target.id != state.hostPageId) followHost = false
        }

        // Voice starts once the room has let us in (the ticket needs membership).
        var micDecision by remember { mutableStateOf<Boolean?>(null) }
        val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { micDecision = it }
        val hasVoice = voiceProvider !== NoVoice
        val joined = status == RoomStatus.Connected
        LaunchedEffect(joined) {
            if (!hasVoice || !joined || micDecision != null) return@LaunchedEffect
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            if (granted) micDecision = true else micPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
        LaunchedEffect(micDecision) {
            val microphone = micDecision ?: return@LaunchedEffect
            val ticket = runCatching { api.voiceToken(client.roomId) }.getOrNull() ?: return@LaunchedEffect
            runCatching { voiceProvider.connect(ticket.url, ticket.token, microphone) }
        }
        DisposableEffect(voiceProvider) { onDispose { voiceProvider.disconnect() } }

        LaunchedEffect(client) {
            client.events.collect { event ->
                val text = when (event) {
                    is RoomEvent.Rejected -> when (event.reason) {
                        RejectReason.DRAWING_LOCKED -> "The host has paused drawing."
                        RejectReason.NOT_HOST -> "Only the host can do that."
                        "too-large" -> "That was too big to share."
                        else -> "That change could not be shared."
                    }
                    is RoomEvent.ServerError -> event.message.ifEmpty { event.code }
                }
                snackbar.showSnackbar(text)
            }
        }

        var reported by remember { mutableStateOf(false) }
        LaunchedEffect(status) {
            val ended = status as? RoomStatus.Ended ?: return@LaunchedEffect
            if (reported) return@LaunchedEffect
            reported = true
            voiceProvider.disconnect()
            val snapshot = if (isHost) {
                runCatching { api.snapshot(client.roomId) }.getOrNull() ?: client.state.value
            } else {
                client.state.value
            }
            onSessionEnded(LiveSessionResult(client.roomId, ended.reason, isHost, snapshot))
        }

        val images = remember { mutableStateMapOf<String, ImageBitmap>() }
        val assetId = (page?.background?.drawnAs as? PageBackground.Drawn.Image)?.assetId
        LaunchedEffect(assetId) {
            if (assetId == null || assetId in images) return@LaunchedEffect
            // The host uploads pictures just after creating the room, so a
            // guest who is quick may have to wait for one.
            repeat(6) { attempt ->
                val bitmap = runCatching {
                    val bytes = api.downloadAsset(client.roomId, assetId)
                    withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }
                }.getOrNull()
                if (bitmap != null) {
                    images[assetId] = bitmap
                    return@LaunchedEffect
                }
                delay(1000L shl attempt)
            }
        }

        Surface(modifier.fillMaxSize(), color = theme.background) {
            Box(Modifier.fillMaxSize()) {
                Column(Modifier.fillMaxSize()) {
                    RoomHeader(room?.title ?: "SpaceNotes Live", room?.code, status)
                    ParticipantStrip(members, me?.uid, voiceParticipants)
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        if (page != null) {
                            LivePageCanvas(
                                client = client,
                                page = page,
                                settings = settings,
                                canDraw = canDraw,
                                liveInk = liveInk.values,
                                pointers = pointers.values,
                                members = members,
                                backgroundImage = assetId?.let { images[it] },
                                onTextTap = { textDraft = it },
                                modifier = Modifier.fillMaxSize(),
                            )
                        } else {
                            Text(
                                if (status is RoomStatus.Ended) "The session has ended." else "Opening the notebook…",
                                color = theme.onSurfaceMuted,
                                modifier = Modifier.align(Alignment.Center),
                            )
                        }
                        if (!canDraw && page != null && status == RoomStatus.Connected) {
                            Chip("View only — the host is drawing", Modifier.align(Alignment.TopCenter).padding(8.dp))
                        }
                    }
                    InkToolbar(
                        settings = settings,
                        onSettings = { settings = it },
                        canDraw = canDraw,
                        canUndo = canUndo,
                        canRedo = canRedo,
                        onUndo = { client.undo() },
                        onRedo = { client.redo() },
                    )
                    ControlBar(
                        pageLabel = if (pageIndex >= 0) "${pageIndex + 1} / ${state.pages.size}" else "–",
                        canGoBack = pageIndex > 0,
                        canGoForward = pageIndex >= 0 && pageIndex < state.pages.lastIndex,
                        onBack = { goTo(pageIndex - 1) },
                        onForward = { goTo(pageIndex + 1) },
                        isHost = isHost,
                        followHost = followHost,
                        onFollowHost = {
                            followHost = true
                            state.hostPageId?.let { chosenPageId = it }
                        },
                        onAddPage = {
                            val current = page ?: return@ControlBar
                            val newPage = LivePageSpec(UUID.randomUUID().toString(), current.width, current.height, PageBackground.blank)
                            client.addPage(newPage, current.id)
                            chosenPageId = newPage.id
                        },
                        hasVoice = hasVoice,
                        micOn = micOn,
                        onMic = {
                            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                            if (granted) voiceProvider.setMicrophone(!micOn) else micPermission.launch(Manifest.permission.RECORD_AUDIO)
                        },
                        handRaised = handRaised,
                        onHand = {
                            handRaised = !handRaised
                            client.setHandRaised(handRaised)
                        },
                        raisedHands = members.count { it.handRaised },
                        onPeople = { showPeople = true },
                        onLeave = { if (isHost) confirmLeave = true else client.disconnect() },
                    )
                }
                SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).padding(bottom = 120.dp))
            }
        }

        textDraft?.let { draft ->
            TextEditor(
                draft = draft,
                onDismiss = { textDraft = null },
                onSave = { value ->
                    textDraft = null
                    val existing = draft.existing
                    when {
                        existing != null && value.isBlank() -> client.eraseTexts(draft.pageId, listOf(existing.id))
                        existing != null -> client.upsertText(draft.pageId, existing.copy(text = value, frame = existing.frame.fitting(value, existing.fontSize)))
                        value.isNotBlank() -> {
                            val fontSize = 18.0
                            client.upsertText(
                                draft.pageId,
                                LiveText(
                                    id = UUID.randomUUID().toString(),
                                    text = value,
                                    frame = LiveRect(draft.x, draft.y, 260.0, 0.0).fitting(value, fontSize),
                                    fontSize = fontSize,
                                    color = settings.penColor.toLiveColor(),
                                ),
                            )
                        }
                    }
                },
            )
        }

        if (showPeople) {
            ModalBottomSheet(onDismissRequest = { showPeople = false }, containerColor = theme.surface) {
                PeopleSheet(
                    members = members,
                    myUid = me?.uid,
                    isHost = isHost,
                    drawPolicy = state.drawPolicy,
                    penHolder = state.penHolder,
                    onPolicy = { policy, holder -> client.setPolicy(policy, holder) },
                    onRemove = { uid -> client.remove(uid) },
                )
            }
        }

        if (confirmLeave) {
            AlertDialog(
                onDismissRequest = { confirmLeave = false },
                title = { Text("Leave the session?") },
                text = { Text("Ending it closes the room for everyone and brings the notebook back to you. Leaving keeps it open for the others.") },
                confirmButton = {
                    TextButton(onClick = {
                        confirmLeave = false
                        client.endRoom()
                    }) { Text("End for everyone", color = theme.danger) }
                },
                dismissButton = {
                    Row {
                        TextButton(onClick = { confirmLeave = false }) { Text("Cancel") }
                        TextButton(onClick = {
                            confirmLeave = false
                            client.disconnect()
                        }) { Text("Leave") }
                    }
                },
            )
        }
    }
}

/** Grows a text frame to hold its text, roughly: the page redraws it exactly. */
private fun LiveRect.fitting(text: String, fontSize: Double): LiveRect {
    val charsPerLine = (width / (fontSize * 0.5)).toInt().coerceAtLeast(1)
    val lines = text.split('\n').sumOf { line -> ((line.length + charsPerLine - 1) / charsPerLine).coerceAtLeast(1) }
    return copy(height = lines * fontSize * 1.35 + 8)
}

@Composable
private fun RoomHeader(title: String, code: String?, status: RoomStatus) {
    val theme = LocalLiveTheme.current
    Row(
        Modifier.fillMaxWidth().background(theme.surface).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = theme.onSurface, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                when (status) {
                    RoomStatus.Connecting -> "Connecting…"
                    RoomStatus.Reconnecting -> "Reconnecting…"
                    RoomStatus.Connected -> "SpaceNotes Live" + (code?.let { " · code $it" } ?: "")
                    is RoomStatus.Ended -> endedText(status.reason)
                },
                color = if (status == RoomStatus.Connected) theme.onSurfaceMuted else theme.danger,
                fontSize = 12.sp,
            )
        }
    }
}

private fun endedText(reason: String): String = when (reason) {
    RoomStatus.LEFT -> "You left the session"
    RemovedReason.ROOM_ENDED -> "The host ended the session"
    RemovedReason.REMOVED_BY_HOST -> "The host removed you from the session"
    "no-such-room" -> "This room has ended"
    "room-full" -> "This room is full"
    "guests-not-allowed" -> "Sign in to join this room"
    else -> "The session has ended"
}

private fun initials(name: String): String =
    name.split(' ', '-', '_').filter { it.isNotBlank() }.take(2).joinToString("") { it.first().uppercase() }.ifEmpty { "?" }

@Composable
private fun ParticipantStrip(
    members: List<Member>,
    myUid: String?,
    voice: Map<String, LiveVoiceParticipant>,
) {
    val theme = LocalLiveTheme.current
    // One tile per person, even when they are here on two devices.
    val people = members.groupBy { it.uid }.values.map { connections ->
        connections.first().copy(handRaised = connections.any { it.handRaised })
    }.sortedWith(compareByDescending<Member> { it.isHost }.thenBy { it.uid != myUid })
    LazyRow(
        Modifier.fillMaxWidth().background(theme.surface),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(people, key = { it.uid }) { person ->
            val v = voice[person.uid]
            val color = memberColor(person.color, theme.accent)
            Box(
                Modifier
                    .size(width = 112.dp, height = 88.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(theme.surfaceVariant),
            ) {
                // Voice only, so the tile is the person's initials; a ring
                // round them lights up while they speak.
                Box(
                    Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 8.dp)
                        .size(52.dp)
                        .border(3.dp, if (v?.speaking == true) theme.accent else Color.Transparent, CircleShape)
                        .padding(5.dp)
                        .clip(CircleShape)
                        .background(color),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(initials(person.name), color = Color.White, fontWeight = FontWeight.SemiBold)
                }
                Row(
                    Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(horizontal = 6.dp, vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (v != null) {
                        Icon(
                            if (v.microphoneOn) Icons.Filled.Mic else Icons.Filled.MicOff,
                            contentDescription = if (v.microphoneOn) "Microphone on" else "Muted",
                            tint = if (v.microphoneOn) theme.onSurfaceMuted else theme.danger,
                            modifier = Modifier.size(14.dp),
                        )
                        Spacer(Modifier.width(4.dp))
                    }
                    Text(
                        (if (person.uid == myUid) "You" else person.name) + if (person.isHost) " · host" else "",
                        color = theme.onSurface,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (person.handRaised) {
                    Box(
                        Modifier.align(Alignment.TopEnd).padding(4.dp).size(24.dp).clip(CircleShape).background(Color(0xFFFFC53D)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.PanTool, contentDescription = "Hand raised", tint = Color(0xFF3D2A00), modifier = Modifier.size(14.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun Chip(text: String, modifier: Modifier = Modifier) {
    val theme = LocalLiveTheme.current
    Text(
        text,
        color = theme.onSurface,
        fontSize = 12.sp,
        modifier = modifier.clip(RoundedCornerShape(50)).background(theme.surface).padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

@Composable
private fun ToolButton(icon: ImageVector, label: String, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val theme = LocalLiveTheme.current
    IconButton(
        onClick = onClick,
        enabled = enabled,
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = if (selected) theme.accent else Color.Transparent,
            contentColor = if (selected) theme.onAccent else theme.onSurface,
            disabledContentColor = theme.onSurfaceMuted.copy(alpha = 0.4f),
        ),
    ) {
        Icon(icon, contentDescription = label)
    }
}

@Composable
private fun InkToolbar(
    settings: InkSettings,
    onSettings: (InkSettings) -> Unit,
    canDraw: Boolean,
    canUndo: Boolean,
    canRedo: Boolean,
    onUndo: () -> Unit,
    onRedo: () -> Unit,
) {
    val theme = LocalLiveTheme.current
    Row(
        Modifier.fillMaxWidth().background(theme.surface).horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ToolButton(Icons.Filled.Create, "Pen", settings.tool == LiveTool.Pen, canDraw) { onSettings(settings.copy(tool = LiveTool.Pen)) }
        ToolButton(Icons.Filled.Highlight, "Highlighter", settings.tool == LiveTool.Highlighter, canDraw) { onSettings(settings.copy(tool = LiveTool.Highlighter)) }
        ToolButton(Icons.Filled.AutoFixNormal, "Eraser", settings.tool == LiveTool.Eraser, canDraw) { onSettings(settings.copy(tool = LiveTool.Eraser)) }
        ToolButton(Icons.Filled.TextFields, "Text", settings.tool == LiveTool.Text, canDraw) { onSettings(settings.copy(tool = LiveTool.Text)) }
        // Pointing is not changing the notebook, so the laser works for everyone.
        ToolButton(Icons.Filled.WbIncandescent, "Laser pointer", settings.tool == LiveTool.Laser, true) { onSettings(settings.copy(tool = LiveTool.Laser)) }
        Spacer(Modifier.width(8.dp))
        ToolButton(Icons.AutoMirrored.Filled.Undo, "Undo", false, canDraw && canUndo, onUndo)
        ToolButton(Icons.AutoMirrored.Filled.Redo, "Redo", false, canDraw && canRedo, onRedo)
        Spacer(Modifier.width(8.dp))
        val palette = if (settings.tool == LiveTool.Highlighter) theme.highlighterPalette else theme.inkPalette
        val current = if (settings.tool == LiveTool.Highlighter) settings.highlighterColor else settings.penColor
        for (color in palette) {
            Box(
                Modifier
                    .padding(4.dp)
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(color.copy(alpha = 1f))
                    .border(3.dp, if (color == current) theme.accent else Color.Transparent, CircleShape)
                    .clickable(enabled = canDraw) {
                        onSettings(
                            if (settings.tool == LiveTool.Highlighter) {
                                settings.copy(highlighterColor = color)
                            } else {
                                settings.copy(penColor = color, tool = if (settings.tool == LiveTool.Pen || settings.tool == LiveTool.Text) settings.tool else LiveTool.Pen)
                            },
                        )
                    },
            )
        }
        Spacer(Modifier.width(8.dp))
        val widths = listOf(1.5, 2.5, 4.5)
        ToolButton(Icons.Filled.Draw, "Line width ${settings.penWidth}", false, canDraw) {
            val next = widths[(widths.indexOf(settings.penWidth) + 1).mod(widths.size)]
            onSettings(settings.copy(penWidth = next))
        }
        ToolButton(Icons.Filled.TouchApp, if (settings.stylusOnly) "Stylus only: on" else "Stylus only: off", settings.stylusOnly, true) {
            onSettings(settings.copy(stylusOnly = !settings.stylusOnly))
        }
    }
}

@Composable
private fun ControlBar(
    pageLabel: String,
    canGoBack: Boolean,
    canGoForward: Boolean,
    onBack: () -> Unit,
    onForward: () -> Unit,
    isHost: Boolean,
    followHost: Boolean,
    onFollowHost: () -> Unit,
    onAddPage: () -> Unit,
    hasVoice: Boolean,
    micOn: Boolean,
    onMic: () -> Unit,
    handRaised: Boolean,
    onHand: () -> Unit,
    raisedHands: Int,
    onPeople: () -> Unit,
    onLeave: () -> Unit,
) {
    val theme = LocalLiveTheme.current
    Row(
        Modifier.fillMaxWidth().background(theme.surface).horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (hasVoice) {
            ToolButton(if (micOn) Icons.Filled.Mic else Icons.Filled.MicOff, if (micOn) "Mute" else "Unmute", false, true, onMic)
        }
        ToolButton(Icons.Filled.PanTool, if (handRaised) "Lower hand" else "Raise hand", handRaised, true, onHand)
        Spacer(Modifier.width(12.dp))
        ToolButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous page", false, canGoBack, onBack)
        Text(pageLabel, color = theme.onSurface, fontSize = 13.sp)
        ToolButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next page", false, canGoForward, onForward)
        if (isHost) {
            ToolButton(Icons.Filled.Add, "Add a page", false, true, onAddPage)
        } else {
            FilterChip(
                selected = followHost,
                onClick = onFollowHost,
                label = { Text("Follow host") },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = theme.accent, selectedLabelColor = theme.onAccent),
            )
        }
        Spacer(Modifier.width(12.dp))
        Box {
            ToolButton(Icons.Filled.People, "People", false, true, onPeople)
            if (raisedHands > 0) {
                Text(
                    "$raisedHands",
                    color = Color(0xFF3D2A00),
                    fontSize = 10.sp,
                    modifier = Modifier.align(Alignment.TopEnd).clip(CircleShape).background(Color(0xFFFFC53D)).padding(horizontal = 5.dp),
                )
            }
        }
        IconButton(
            onClick = onLeave,
            colors = IconButtonDefaults.iconButtonColors(containerColor = theme.danger, contentColor = theme.onDanger),
        ) {
            Icon(Icons.Filled.CallEnd, contentDescription = if (isHost) "Leave or end" else "Leave")
        }
    }
}

@Composable
private fun TextEditor(draft: TextDraft, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var value by remember(draft) { mutableStateOf(draft.existing?.text ?: "") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (draft.existing == null) "Add text" else "Edit text") },
        text = {
            OutlinedTextField(value = value, onValueChange = { value = it }, minLines = 2, modifier = Modifier.fillMaxWidth())
        },
        confirmButton = { TextButton(onClick = { onSave(value) }) { Text(if (draft.existing != null && value.isBlank()) "Delete" else "Done") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun PeopleSheet(
    members: List<Member>,
    myUid: String?,
    isHost: Boolean,
    drawPolicy: String,
    penHolder: String?,
    onPolicy: (String, String?) -> Unit,
    onRemove: (String) -> Unit,
) {
    val theme = LocalLiveTheme.current
    var removing by remember { mutableStateOf<Member?>(null) }
    val people = members.groupBy { it.uid }.values.map { c -> c.first().copy(handRaised = c.any { it.handRaised }) }
        .sortedWith(compareByDescending<Member> { it.handRaised }.thenByDescending { it.isHost }.thenBy { it.name })
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
        Text("People (${people.size})", color = theme.onSurface, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        if (isHost) {
            Spacer(Modifier.height(12.dp))
            Text("Who can draw", color = theme.onSurfaceMuted, fontSize = 13.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = drawPolicy == DrawPolicy.EVERYONE, onClick = { onPolicy(DrawPolicy.EVERYONE, null) }, label = { Text("Everyone") })
                FilterChip(selected = drawPolicy == DrawPolicy.HOST, onClick = { onPolicy(DrawPolicy.HOST, null) }, label = { Text("Only me") })
                FilterChip(
                    selected = drawPolicy == DrawPolicy.PEN,
                    onClick = { onPolicy(DrawPolicy.PEN, penHolder) },
                    label = { Text("One person") },
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        LazyColumn {
            items(people, key = { it.uid }) { person ->
                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(36.dp).clip(CircleShape).background(memberColor(person.color, theme.accent)),
                        contentAlignment = Alignment.Center,
                    ) { Text(initials(person.name), color = Color.White, fontSize = 13.sp) }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            (if (person.uid == myUid) "${person.name} (you)" else person.name),
                            color = theme.onSurface,
                        )
                        val detail = listOfNotNull(
                            "Host".takeIf { person.isHost },
                            "Has the pen".takeIf { drawPolicy == DrawPolicy.PEN && penHolder == person.uid },
                            "Hand raised".takeIf { person.handRaised },
                        ).joinToString(" · ")
                        if (detail.isNotEmpty()) Text(detail, color = theme.onSurfaceMuted, fontSize = 12.sp)
                    }
                    if (isHost && !person.isHost) {
                        val holds = drawPolicy == DrawPolicy.PEN && penHolder == person.uid
                        TextButton(onClick = { if (holds) onPolicy(DrawPolicy.PEN, null) else onPolicy(DrawPolicy.PEN, person.uid) }) {
                            Text(if (holds) "Take pen" else "Give pen")
                        }
                        TextButton(onClick = { removing = person }) { Text("Remove", color = theme.danger) }
                    }
                }
            }
        }
    }
    removing?.let { person ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text("Remove ${person.name}?") },
            text = { Text("They leave the session and cannot join it again.") },
            confirmButton = {
                TextButton(onClick = {
                    onRemove(person.uid)
                    removing = null
                }) { Text("Remove", color = theme.danger) }
            },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } },
        )
    }
}
