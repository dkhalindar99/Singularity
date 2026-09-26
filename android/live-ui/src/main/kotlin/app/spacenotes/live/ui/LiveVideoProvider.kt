// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** One person in the call, keyed by the same uid the room uses. */
public data class LiveVideoParticipant(
    val identity: String,
    val hasVideo: Boolean,
    val microphoneOn: Boolean,
    val speaking: Boolean,
    val isLocal: Boolean,
)

public sealed interface LiveVideoStatus {
    /** Not started, or the server has no video: the room carries on with ink only. */
    public data object Off : LiveVideoStatus
    public data object Connecting : LiveVideoStatus
    public data object Connected : LiveVideoStatus
    public data class Failed(val message: String) : LiveVideoStatus
}

/**
 * Camera and voice, supplied by the host app. The room screen only needs this
 * interface, so it does not depend on LiveKit; `live-video` implements it.
 */
public interface LiveVideoProvider {
    public val status: StateFlow<LiveVideoStatus>

    /** Everyone in the call, including this device, by identity (uid). */
    public val participants: StateFlow<Map<String, LiveVideoParticipant>>
    public val microphoneOn: StateFlow<Boolean>
    public val cameraOn: StateFlow<Boolean>

    /** Joins the call. [microphone] is false when the person did not allow recording. */
    public suspend fun connect(url: String, token: String, microphone: Boolean)

    public fun disconnect()

    public fun setMicrophone(on: Boolean)

    public fun setCamera(on: Boolean)

    /** The video of [identity], filling [modifier]. Draws nothing when there is none. */
    @Composable
    public fun Video(identity: String, modifier: Modifier)
}

/** Ink only: for servers without video, previews and tests. */
public object NoVideo : LiveVideoProvider {
    override val status: StateFlow<LiveVideoStatus> = MutableStateFlow(LiveVideoStatus.Off)
    override val participants: StateFlow<Map<String, LiveVideoParticipant>> = MutableStateFlow(emptyMap())
    override val microphoneOn: StateFlow<Boolean> = MutableStateFlow(false)
    override val cameraOn: StateFlow<Boolean> = MutableStateFlow(false)

    override suspend fun connect(url: String, token: String, microphone: Boolean): Unit = Unit

    override fun disconnect(): Unit = Unit

    override fun setMicrophone(on: Boolean): Unit = Unit

    override fun setCamera(on: Boolean): Unit = Unit

    @Composable
    override fun Video(identity: String, modifier: Modifier): Unit = Unit
}
