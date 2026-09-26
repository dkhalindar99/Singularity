// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI

/// Voice for the room. SpaceNotes Live is ink and voice only: there are no
/// cameras, for cost and for privacy. LiveUI does not depend on any audio
/// SDK: the SpaceNotesLiveVoice package implements this with LiveKit, and a
/// room without voice simply passes nil.
///
/// People are matched by uid: the voice server's participant identity is the
/// person's Firebase uid.
@MainActor
public protocol LiveVoiceProviding: AnyObject {
    /// Called whenever anything below changes, so the tiles redraw.
    var onChange: (() -> Void)? { get set }
    var isConnected: Bool { get }
    var isMicrophoneEnabled: Bool { get }

    /// Joins with the microphone on.
    func connect(url: String, token: String) async throws
    func disconnect() async
    func setMicrophoneEnabled(_ enabled: Bool) async throws

    /// nil when the person is not in the call at all.
    func isMicrophoneOn(uid: String) -> Bool?
    func isSpeaking(uid: String) -> Bool
}

/// Bridges a provider's `onChange` into SwiftUI.
@MainActor
final class LiveVoiceObserver: ObservableObject {
    let provider: LiveVoiceProviding?

    init(provider: LiveVoiceProviding?) {
        self.provider = provider
        provider?.onChange = { [weak self] in self?.objectWillChange.send() }
    }
}
#endif
