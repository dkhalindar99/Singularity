// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.video

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.spacenotes.live.ui.LiveVideoParticipant
import app.spacenotes.live.ui.LiveVideoProvider
import app.spacenotes.live.ui.LiveVideoStatus
import io.livekit.android.LiveKit
import io.livekit.android.RoomOptions
import io.livekit.android.renderer.TextureViewRenderer
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.participant.VideoTrackPublishDefaults
import io.livekit.android.room.track.LocalVideoTrackOptions
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.VideoPreset169
import io.livekit.android.room.track.VideoTrack
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** The video quality this device sends. Both keep a phone's upload modest in a group call. */
public enum class LiveVideoQuality(internal val preset: VideoPreset169) {
    /** 320x180: several tiles on a phone. */
    Low(VideoPreset169.H180),

    /** 640x360: the default; simulcast adds a 180p layer for small tiles. */
    Standard(VideoPreset169.H360),
}

/**
 * [LiveVideoProvider] over LiveKit's Android SDK. The microphone starts on
 * (when allowed) and the camera off, as in most study calls. Video is sent
 * with simulcast and received with adaptive stream and dynacast, so a small
 * tile never pulls a large picture.
 */
public class LiveKitVideoProvider(
    context: Context,
    private val quality: LiveVideoQuality = LiveVideoQuality.Standard,
) : LiveVideoProvider {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var room: Room? = null
    private var eventsJob: Job? = null

    private val _status = MutableStateFlow<LiveVideoStatus>(LiveVideoStatus.Off)
    private val _participants = MutableStateFlow<Map<String, LiveVideoParticipant>>(emptyMap())
    private val _microphoneOn = MutableStateFlow(false)
    private val _cameraOn = MutableStateFlow(false)

    /** Bumped on every room event, so a tile re-reads its track. */
    private val revision = MutableStateFlow(0)

    override val status: StateFlow<LiveVideoStatus> = _status.asStateFlow()
    override val participants: StateFlow<Map<String, LiveVideoParticipant>> = _participants.asStateFlow()
    override val microphoneOn: StateFlow<Boolean> = _microphoneOn.asStateFlow()
    override val cameraOn: StateFlow<Boolean> = _cameraOn.asStateFlow()

    override suspend fun connect(url: String, token: String, microphone: Boolean) {
        if (room != null) return
        _status.value = LiveVideoStatus.Connecting
        val lowLayer = VideoPreset169.H180
        val options = RoomOptions(
            adaptiveStream = true,
            dynacast = true,
            videoTrackCaptureDefaults = LocalVideoTrackOptions(captureParams = quality.preset.capture),
            videoTrackPublishDefaults = VideoTrackPublishDefaults(
                videoEncoding = quality.preset.encoding,
                simulcast = true,
                simulcastLayers = if (quality.preset == lowLayer) emptyList() else listOf(lowLayer),
            ),
        )
        val created = LiveKit.create(appContext, options)
        room = created
        eventsJob = scope.launch {
            created.events.events.collect { refresh() }
        }
        try {
            created.connect(url, token)
            created.localParticipant.setCameraEnabled(false)
            if (microphone) created.localParticipant.setMicrophoneEnabled(true)
            _status.value = LiveVideoStatus.Connected
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _status.value = LiveVideoStatus.Failed(e.message ?: "Could not join the call")
        }
        refresh()
    }

    override fun disconnect() {
        eventsJob?.cancel()
        eventsJob = null
        room?.let {
            it.disconnect()
            it.release()
        }
        room = null
        _participants.value = emptyMap()
        _microphoneOn.value = false
        _cameraOn.value = false
        _status.value = LiveVideoStatus.Off
    }

    override fun setMicrophone(on: Boolean) {
        val room = room ?: return
        scope.launch {
            runCatching { room.localParticipant.setMicrophoneEnabled(on) }
            refresh()
        }
    }

    override fun setCamera(on: Boolean) {
        val room = room ?: return
        scope.launch {
            runCatching { room.localParticipant.setCameraEnabled(on) }
            refresh()
        }
    }

    private fun refresh() {
        val room = room ?: return
        val everyone: List<Participant> = listOf(room.localParticipant) + room.remoteParticipants.values
        _participants.value = everyone.associate { participant ->
            val identity = participant.identity?.value ?: ""
            identity to LiveVideoParticipant(
                identity = identity,
                hasVideo = cameraTrack(participant) != null,
                microphoneOn = participant.isMicrophoneEnabled,
                speaking = participant.isSpeaking,
                isLocal = participant === room.localParticipant,
            )
        }
        _microphoneOn.value = room.localParticipant.isMicrophoneEnabled
        _cameraOn.value = room.localParticipant.isCameraEnabled
        revision.value++
    }

    private fun cameraTrack(participant: Participant): VideoTrack? {
        val publication = participant.getTrackPublication(Track.Source.CAMERA) ?: return null
        if (publication.muted) return null
        return publication.track as? VideoTrack
    }

    private fun participant(identity: String): Participant? {
        val room = room ?: return null
        if (room.localParticipant.identity?.value == identity) return room.localParticipant
        return room.remoteParticipants.values.firstOrNull { it.identity?.value == identity }
    }

    @Composable
    override fun Video(identity: String, modifier: Modifier) {
        val current = room ?: return
        val version by revision.collectAsStateWithLifecycle()
        val participant = remember(identity, version) { participant(identity) } ?: return
        val track = remember(identity, version) { cameraTrack(participant) } ?: return
        val context = LocalContext.current
        val isLocal = participant === current.localParticipant
        val renderer = remember(current) {
            TextureViewRenderer(context).also { current.initVideoRenderer(it) }
        }
        DisposableEffect(renderer) { onDispose { renderer.release() } }
        DisposableEffect(track, renderer) {
            track.addRenderer(renderer)
            onDispose { track.removeRenderer(renderer) }
        }
        AndroidView(
            factory = { renderer },
            update = { it.setMirror(isLocal) },
            modifier = modifier,
        )
    }
}
