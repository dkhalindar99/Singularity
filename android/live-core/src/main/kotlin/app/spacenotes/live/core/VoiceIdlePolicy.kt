// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

/**
 * When to leave voice to save money (PROTOCOL.md, "Voice and cost"). LiveKit
 * bills every connected minute, talking or not, so voice is left:
 *
 * - after the app has been in the background for [backgroundLimitMs]
 *   (2 minutes), and rejoined by itself when it comes back;
 * - after [quietLimitMs] (15 minutes) in which nobody spoke, drew or wrote,
 *   until the person taps to resume.
 *
 * Leaving voice never leaves the room. The host app reports what happens
 * ([activity], [hidden], [visible], [resume]) and calls [check] from time to
 * time; the clock is injected so tests can move time.
 */
public class VoiceIdlePolicy(
    private val clock: () -> Long,
    public val backgroundLimitMs: Long = 2 * 60_000L,
    public val quietLimitMs: Long = 15 * 60_000L,
) {
    public enum class Reason { Background, Quiet }

    private var lastActivity = clock()
    private var hiddenSince: Long? = null

    /** Why voice is paused now, or null while it should be on. */
    public var paused: Reason? = null
        private set

    /** Someone spoke, drew or wrote. */
    public fun activity() {
        lastActivity = clock()
    }

    /** The app went to the background. */
    public fun hidden() {
        if (hiddenSince == null) hiddenSince = clock()
    }

    /**
     * The app is visible again. True if voice was left for being in the
     * background and should now rejoin (with the microphone as it was).
     */
    public fun visible(): Boolean {
        hiddenSince = null
        if (paused != Reason.Background) return false
        paused = null
        lastActivity = clock() // coming back counts as being here
        return true
    }

    /** The person tapped "resume". */
    public fun resume() {
        paused = null
        lastActivity = clock()
    }

    /**
     * Whether voice should be left now, and why. Returns a reason once, when
     * the pause starts; null while voice should stay, or is already paused.
     */
    public fun check(): Reason? {
        if (paused != null) return null
        val now = clock()
        val reason = when {
            hiddenSince?.let { now - it >= backgroundLimitMs } == true -> Reason.Background
            now - lastActivity >= quietLimitMs -> Reason.Quiet
            else -> null
        }
        paused = reason
        return reason
    }
}
