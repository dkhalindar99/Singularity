// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import app.spacenotes.live.core.VoiceIdlePolicy.Reason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceIdlePolicyTest {
    private var now = 1_000_000L
    private val policy = VoiceIdlePolicy({ now })
    private val minute = 60_000L

    @Test
    fun aQuietRoomPausesAfterFifteenMinutes() {
        now += 15 * minute - 1
        assertNull(policy.check())
        now += 1
        assertEquals(Reason.Quiet, policy.check())
        assertEquals(Reason.Quiet, policy.paused)
        assertNull("reported once", policy.check())
    }

    @Test
    fun anyActivityKeepsTheRoomAwake() {
        now += 14 * minute
        policy.activity()
        now += 14 * minute
        assertNull(policy.check())
        now += minute
        assertEquals(Reason.Quiet, policy.check())
    }

    @Test
    fun resumeStartsTheQuietClockAgain() {
        now += 15 * minute
        assertEquals(Reason.Quiet, policy.check())
        policy.resume()
        assertNull(policy.paused)
        now += 15 * minute - 1
        assertNull(policy.check())
    }

    @Test
    fun theBackgroundPausesAfterTwoMinutesAndRejoinsOnReturn() {
        policy.hidden()
        now += 2 * minute - 1
        assertNull(policy.check())
        now += 1
        assertEquals(Reason.Background, policy.check())
        now += 30 * minute
        assertNull(policy.check())
        assertTrue("rejoins by itself", policy.visible())
        assertNull(policy.paused)
        assertNull("coming back counts as activity", policy.check())
    }

    @Test
    fun aShortTripToTheBackgroundChangesNothing() {
        policy.hidden()
        now += minute
        assertFalse(policy.visible())
        now += 2 * minute
        assertNull(policy.check())
    }

    @Test
    fun aQuietPauseIsNotUndoneByComingBack() {
        now += 15 * minute
        assertEquals(Reason.Quiet, policy.check())
        policy.hidden()
        now += 5 * minute
        assertFalse("still waits for a tap", policy.visible())
        assertEquals(Reason.Quiet, policy.paused)
    }
}
