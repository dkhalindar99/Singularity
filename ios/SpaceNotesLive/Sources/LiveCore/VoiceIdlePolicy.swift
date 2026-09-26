// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// When to leave voice to save money (PROTOCOL.md, "Voice and cost"). LiveKit
/// bills every connected minute, talking or not, so:
///
/// - after 2 minutes in the background, leave; rejoin by itself when the app
///   is active again, with the microphone as it was;
/// - after 15 minutes in which nobody has spoken, drawn or written, pause and
///   wait for a tap.
///
/// Leaving voice never leaves the room. Pure, with the clock passed in, so it
/// is tested without timers.
public struct VoiceIdlePolicy: Hashable, Sendable {
    public static let backgroundLimit: Double = 2 * 60
    public static let quietLimit: Double = 15 * 60

    public enum State: Hashable, Sendable {
        /// In voice (or trying to be).
        case active
        /// Left because the app was in the background; comes back by itself.
        case leftInBackground(microphoneWasOn: Bool)
        /// Left because the room was quiet; comes back on a tap.
        case pausedQuiet
    }

    public enum Action: Hashable, Sendable {
        case none
        case leave
        case rejoin(microphoneOn: Bool)
    }

    public private(set) var state: State = .active
    public private(set) var lastActivityAt: Double
    public private(set) var backgroundSince: Double?

    public init(now: Double) {
        lastActivityAt = now
    }

    /// Someone spoke, drew or wrote. Any ink keeps the room awake.
    public mutating func noteActivity(at now: Double) {
        lastActivityAt = max(lastActivityAt, now)
    }

    public mutating func enteredBackground(at now: Double) {
        if backgroundSince == nil { backgroundSince = now }
    }

    /// The app is active again. Rejoins if voice was left for the background.
    public mutating func becameActive(at now: Double) -> Action {
        backgroundSince = nil
        guard case .leftInBackground(let microphoneWasOn) = state else { return .none }
        state = .active
        // Coming back counts as activity: the quiet clock starts again.
        lastActivityAt = max(lastActivityAt, now)
        return .rejoin(microphoneOn: microphoneWasOn)
    }

    /// The person tapped "resume" on a paused voice.
    public mutating func resume(at now: Double) -> Action {
        guard state == .pausedQuiet else { return .none }
        state = .active
        lastActivityAt = max(lastActivityAt, now)
        return .rejoin(microphoneOn: true)
    }

    /// Called on a timer. `microphoneOn` is the current state, remembered for
    /// the rejoin after the background.
    public mutating func check(at now: Double, microphoneOn: Bool) -> Action {
        guard state == .active else { return .none }
        if let since = backgroundSince, now - since >= VoiceIdlePolicy.backgroundLimit {
            state = .leftInBackground(microphoneWasOn: microphoneOn)
            return .leave
        }
        if now - lastActivityAt >= VoiceIdlePolicy.quietLimit {
            state = .pausedQuiet
            return .leave
        }
        return .none
    }
}
