// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit)
import LiveKit
import LiveUI
import SwiftUI

/// Voice for SpaceNotes Live, on LiveKit.
///
/// Ink and voice only: nothing here ever publishes a camera, and the server's
/// token only allows the microphone, so LiveKit would refuse one anyway. A
/// person joins with the microphone on and can mute.
///
/// The microphone is published with LiveKit's speech preset (24 kbps) and
/// silence suppression (DTX), which halves the data of the default music
/// preset; voice is most of what a room costs.
///
/// People are matched to tiles by LiveKit participant identity, which the
/// room server sets to the person's Firebase uid when it issues the ticket.
@MainActor
public final class LiveKitVoiceProvider: LiveVoiceProviding {
    public var onChange: (() -> Void)?
    public let room: Room
    private let observer: RoomObserver

    public init() {
        observer = RoomObserver()
        let speech = AudioPublishOptions(encoding: AudioEncoding.presetSpeech, dtx: true)
        room = Room(delegate: observer, roomOptions: RoomOptions(defaultAudioPublishOptions: speech))
        observer.changed = { [weak self] in
            Task { @MainActor in self?.onChange?() }
        }
    }

    public var isConnected: Bool { room.connectionState == .connected || room.connectionState == .reconnecting }
    public var isMicrophoneEnabled: Bool { room.localParticipant.isMicrophoneEnabled() }

    public func connect(url: String, token: String, microphoneEnabled: Bool) async throws {
        try await room.connect(url: url, token: token)
        // A failure here (permission refused) leaves the person in the
        // call, muted.
        if microphoneEnabled {
            _ = try? await room.localParticipant.setMicrophone(enabled: true)
        }
        onChange?()
    }

    public var isAnyoneSpeaking: Bool { !room.activeSpeakers.isEmpty }

    public func disconnect() async {
        await room.disconnect()
        onChange?()
    }

    public func setMicrophoneEnabled(_ enabled: Bool) async throws {
        try await room.localParticipant.setMicrophone(enabled: enabled)
        onChange?()
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
