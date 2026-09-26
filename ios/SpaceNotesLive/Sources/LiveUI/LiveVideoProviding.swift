// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI

/// Camera and voice for the participant tiles. LiveUI does not depend on any
/// video SDK: the SpaceNotesLiveVideo package implements this with LiveKit,
/// and a room without video simply passes nil.
///
/// Participants are matched by uid: the video server's participant identity
/// is the person's Firebase uid.
@MainActor
public protocol LiveVideoProviding: AnyObject {
    /// Called whenever anything below changes, so the tiles redraw.
    var onChange: (() -> Void)? { get set }
    var isConnected: Bool { get }
    var isMicrophoneEnabled: Bool { get }
    var isCameraEnabled: Bool { get }

    func connect(url: String, token: String) async throws
    func disconnect() async
    func setMicrophoneEnabled(_ enabled: Bool) async throws
    func setCameraEnabled(_ enabled: Bool) async throws

    /// A live video view for this person, or nil when their camera is off.
    func videoView(uid: String) -> AnyView?
    /// nil when the person is not in the call at all.
    func isMicrophoneOn(uid: String) -> Bool?
    func isSpeaking(uid: String) -> Bool
}

/// Bridges a provider's `onChange` into SwiftUI.
@MainActor
final class LiveVideoObserver: ObservableObject {
    let provider: LiveVideoProviding?

    init(provider: LiveVideoProviding?) {
        self.provider = provider
        provider?.onChange = { [weak self] in self?.objectWillChange.send() }
    }
}
#endif
