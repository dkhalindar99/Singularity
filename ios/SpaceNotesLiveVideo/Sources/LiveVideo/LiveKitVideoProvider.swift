// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit)
import LiveKit
import LiveUI
import SwiftUI

/// Camera and voice for SpaceNotes Live, on LiveKit.
///
/// Joins with the microphone on and the camera off. Video is small on
/// purpose: the page is the point of the room, and the tiles are 132 points
/// wide, so the camera captures 360p and publishes simulcast layers of 180p
/// and 360p; adaptive stream and dynacast mean each viewer receives only the
/// layer its tile needs, and nobody pays for layers nobody watches.
///
/// People are matched to tiles by LiveKit participant identity, which the
/// room server sets to the person's Firebase uid when it issues the ticket.
@MainActor
public final class LiveKitVideoProvider: LiveVideoProviding {
    public var onChange: (() -> Void)?
    public let room: Room
    private let observer: RoomObserver

    public init() {
        let publish = VideoPublishOptions(
            encoding: VideoParameters.presetH360_169.encoding,
            simulcast: true,
            simulcastLayers: [VideoParameters.presetH180_169, VideoParameters.presetH360_169]
        )
        let options = RoomOptions(
            defaultCameraCaptureOptions: CameraCaptureOptions(position: .front, dimensions: .h360_169, fps: 20),
            defaultVideoPublishOptions: publish,
            adaptiveStream: true,
            dynacast: true
        )
        observer = RoomObserver()
        room = Room(delegate: observer, roomOptions: options)
        observer.changed = { [weak self] in
            Task { @MainActor in self?.onChange?() }
        }
    }

    public var isConnected: Bool { room.connectionState == .connected || room.connectionState == .reconnecting }
    public var isMicrophoneEnabled: Bool { room.localParticipant.isMicrophoneEnabled() }
    public var isCameraEnabled: Bool { room.localParticipant.isCameraEnabled() }

    public func connect(url: String, token: String) async throws {
        try await room.connect(url: url, token: token)
        // The microphone is on by default; a failure here (permission
        // refused) leaves the person in the room, muted.
        _ = try? await room.localParticipant.setMicrophone(enabled: true)
        onChange?()
    }

    public func disconnect() async {
        await room.disconnect()
        onChange?()
    }

    public func setMicrophoneEnabled(_ enabled: Bool) async throws {
        try await room.localParticipant.setMicrophone(enabled: enabled)
        onChange?()
    }

    public func setCameraEnabled(_ enabled: Bool) async throws {
        try await room.localParticipant.setCamera(enabled: enabled)
        onChange?()
    }

    public func videoView(uid: String) -> AnyView? {
        guard let track = participant(uid: uid)?.firstCameraVideoTrack else { return nil }
        return AnyView(SwiftUIVideoView(track, layoutMode: .fill))
    }

    public func isMicrophoneOn(uid: String) -> Bool? {
        guard isConnected, let participant = participant(uid: uid) else { return nil }
        return participant.isMicrophoneEnabled()
    }

    public func isSpeaking(uid: String) -> Bool {
        participant(uid: uid)?.isSpeaking ?? false
    }

    private func participant(uid: String) -> Participant? {
        if room.localParticipant.identity?.stringValue == uid { return room.localParticipant }
        return room.remoteParticipants.values.first { $0.identity?.stringValue == uid }
    }
}

/// Turns the room's delegate calls, which arrive off the main thread, into
/// one "something changed" signal.
final class RoomObserver: NSObject, RoomDelegate, @unchecked Sendable {
    var changed: (() -> Void)?

    private func notify() { changed?() }

    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) { notify() }
    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) { notify() }
    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) { notify() }
    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) { notify() }
    func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) { notify() }
    func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) { notify() }
    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) { notify() }
    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) { notify() }
    func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) { notify() }
}
#endif
