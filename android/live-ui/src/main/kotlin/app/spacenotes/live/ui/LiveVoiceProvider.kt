// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.ui

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** One person in the call, keyed by the same uid the room uses. */
public data class LiveVoiceParticipant(
    val identity: String,
    val microphoneOn: Boolean,
    val speaking: Boolean,
    val isLocal: Boolean,
)

public sealed interface LiveVoiceStatus {
    /** Not started, or the server has no voice: the room carries on with ink only. */
    public data object Off : LiveVoiceStatus
    public data object Connecting : LiveVoiceStatus
    public data object Connected : LiveVoiceStatus
    public data class Failed(val message: String) : LiveVoiceStatus
}

/**
 * Voice, supplied by the host app. SpaceNotes Live is ink and voice only —
 * no cameras, for cost and privacy — and the server's ticket lets a
 * participant publish only a microphone. The room screen needs only this
 * interface, so it does not depend on LiveKit; `live-voice` implements it.
 */
public interface LiveVoiceProvider {
    public val status: StateFlow<LiveVoiceStatus>

    /** Everyone in the call, including this device, by identity (uid). */
    public val participants: StateFlow<Map<String, LiveVoiceParticipant>>
    public val microphoneOn: StateFlow<Boolean>

    /** Joins the call. [microphone] is false when the person did not allow recording. */
    public suspend fun connect(url: String, token: String, microphone: Boolean)

    public fun disconnect()

    public fun setMicrophone(on: Boolean)
}

/** Ink only: for servers without voice, previews and tests. */
public object NoVoice : LiveVoiceProvider {
    override val status: StateFlow<LiveVoiceStatus> = MutableStateFlow(LiveVoiceStatus.Off)
    override val participants: StateFlow<Map<String, LiveVoiceParticipant>> = MutableStateFlow(emptyMap())
    override val microphoneOn: StateFlow<Boolean> = MutableStateFlow(false)

    override suspend fun connect(url: String, token: String, microphone: Boolean): Unit = Unit

    override fun disconnect(): Unit = Unit

    override fun setMicrophone(on: Boolean): Unit = Unit
}
