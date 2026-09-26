// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.voice

import android.content.Context
import app.spacenotes.live.ui.LiveVoiceParticipant
import app.spacenotes.live.ui.LiveVoiceProvider
import app.spacenotes.live.ui.LiveVoiceStatus
import io.livekit.android.LiveKit
import io.livekit.android.RoomOptions
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * [LiveVoiceProvider] over LiveKit's Android SDK. Voice only: this client
 * never turns a camera on (and the server's ticket would refuse one). The
 * microphone starts on when the person allowed it.
 */
public class LiveKitVoiceProvider(context: Context) : LiveVoiceProvider {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var room: Room? = null
    private var eventsJob: Job? = null

    private val _status = MutableStateFlow<LiveVoiceStatus>(LiveVoiceStatus.Off)
    private val _participants = MutableStateFlow<Map<String, LiveVoiceParticipant>>(emptyMap())
    private val _microphoneOn = MutableStateFlow(false)

    override val status: StateFlow<LiveVoiceStatus> = _status.asStateFlow()
    override val participants: StateFlow<Map<String, LiveVoiceParticipant>> = _participants.asStateFlow()
    override val microphoneOn: StateFlow<Boolean> = _microphoneOn.asStateFlow()

    override suspend fun connect(url: String, token: String, microphone: Boolean) {
        if (room != null) return
        _status.value = LiveVoiceStatus.Connecting
        val created = LiveKit.create(appContext, RoomOptions())
        room = created
        // Every room event (joins, leaves, mutes, active speakers) can change
        // what the tiles show, so each one re-reads the participants.
        eventsJob = scope.launch { created.events.events.collect { refresh() } }
        try {
            created.connect(url, token)
            if (microphone) created.localParticipant.setMicrophoneEnabled(true)
            _status.value = LiveVoiceStatus.Connected
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _status.value = LiveVoiceStatus.Failed(e.message ?: "Could not join the call")
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
        _status.value = LiveVoiceStatus.Off
    }

    override fun setMicrophone(on: Boolean) {
        val room = room ?: return
        scope.launch {
            runCatching { room.localParticipant.setMicrophoneEnabled(on) }
            refresh()
        }
    }

    private fun refresh() {
        val room = room ?: return
        val everyone: List<Participant> = listOf(room.localParticipant) + room.remoteParticipants.values
        _participants.value = everyone.associate { participant ->
            val identity = participant.identity?.value ?: ""
            identity to LiveVoiceParticipant(
                identity = identity,
                microphoneOn = participant.isMicrophoneEnabled,
                speaking = participant.isSpeaking,
                isLocal = participant === room.localParticipant,
            )
        }
        _microphoneOn.value = room.localParticipant.isMicrophoneEnabled
    }
}
