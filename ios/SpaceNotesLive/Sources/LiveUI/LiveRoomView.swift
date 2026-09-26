// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI

/// The room: people along the top, the shared page in the middle, tools and
/// pages along the bottom.
public struct LiveRoomView: View {
    @ObservedObject private var client: RoomClient
    private let api: LiveAPI
    private let voice: LiveVoiceProviding?
    private let onFinish: (LiveSessionResult) -> Void

    @StateObject private var tools = LiveToolState(color: LiveTheme.standard.inkPalette[0])
    @StateObject private var assets: LiveAssetCache
    @StateObject private var voiceObserver: LiveVoiceObserver
    @State private var currentPageId: String?
    @State private var followHost = true
    @State private var showingParticipants = false
    @State private var confirmingLeave = false
    @State private var finishing = false
    @State private var refusal: String?
    /// When to leave voice to save money; nil until the room view appears.
    @State private var voicePolicy: VoiceIdlePolicy?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.liveTheme) private var theme

    /// - Parameters:
    ///   - client: a client for the room; the view connects it.
    ///   - voice: voice for the room, or nil for ink only.
    ///   - onFinish: called once, when the person leaves or the room ends,
    ///     with the notebook as it was so the host app can save it.
    public init(client: RoomClient, api: LiveAPI, voice: LiveVoiceProviding?,
                onFinish: @escaping (LiveSessionResult) -> Void) {
        _client = ObservedObject(wrappedValue: client)
        self.api = api
        self.voice = voice
        self.onFinish = onFinish
        _assets = StateObject(wrappedValue: LiveAssetCache(api: api, roomId: client.roomId))
        _voiceObserver = StateObject(wrappedValue: LiveVoiceObserver(provider: voice))
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            LiveParticipantStrip(members: client.members, me: client.me, voice: voiceObserver)
            ZStack(alignment: .top) {
                theme.background
                if let page = currentPage {
                    LivePageView(client: client, page: page, tools: tools, assets: assets)
                        .padding(16)
                } else {
                    ProgressView("Joining…")
                        .foregroundColor(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                statusBanner
            }
            LiveToolbar(tools: tools, canDraw: client.canDraw, canUndo: client.canUndo, canRedo: client.canRedo,
                        undo: client.undo, redo: client.redo)
            pageBar
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingParticipants) {
            LiveParticipantsSheet(client: client)
                .liveTheme(theme)
        }
        .confirmationDialog("Leave SpaceNotes Live?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            if client.isHost {
                Button("End for everyone", role: .destructive) { Task { await finish(endForEveryone: true) } }
            }
            Button(client.isHost ? "Leave, keep the room open" : "Leave") { Task { await finish(endForEveryone: false) } }
            Button("Cancel", role: .cancel) {}
        }
        .overlay { endedOverlay }
        .task {
            client.connect()
            voicePolicy = VoiceIdlePolicy(now: client.scheduler.now)
            await connectVoice(microphoneEnabled: true)
        }
        .task { await watchVoiceIdle() }
        .onChange(of: scenePhase) { _, phase in
            let now = client.scheduler.now
            switch phase {
            case .background:
                voicePolicy?.enteredBackground(at: now)
            case .active:
                if let action = voicePolicy?.becameActive(at: now) { perform(action) }
            default:
                break
            }
        }
        .onChange(of: client.status) { _, status in
            if status == .connected, currentPageId == nil {
                currentPageId = client.state.hostPageId ?? client.state.pages.first?.id
                if let currentPageId { client.sendView(pageId: currentPageId) }
            }
        }
        .onChange(of: client.lastRejection) { _, rejection in
            guard let rejection else { return }
            refusal = refusalText(rejection.reason)
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if refusal == refusalText(rejection.reason) { refusal = nil }
            }
        }
        .onChange(of: client.state.hostPageId) { _, hostPage in
            guard followHost, !client.isHost, let hostPage, hostPage != currentPageId else { return }
            show(hostPage, byHand: false)
        }
    }

    private var pages: [LivePage] { client.state.pages }

    private var currentPage: LivePage? {
        pages.first { $0.id == currentPageId } ?? pages.first
    }

    private var currentIndex: Int? {
        guard let page = currentPage else { return nil }
        return pages.firstIndex { $0.id == page.id }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(client.room?.title ?? "SpaceNotes Live")
                    .font(theme.title)
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                if let code = client.room?.code {
                    Text("Room code \(code)")
                        .font(theme.caption)
                        .foregroundColor(theme.secondaryText)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if voicePolicy?.state == .pausedQuiet, voice != nil {
                Button {
                    if let action = voicePolicy?.resume(at: client.scheduler.now) { perform(action) }
                } label: {
                    Label("Voice paused — tap to resume", systemImage: "speaker.slash")
                        .font(theme.label)
                        .foregroundColor(theme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(theme.raisedSurface))
                        .overlay(Capsule().stroke(theme.divider, lineWidth: 1))
                }
            } else if let provider = voiceObserver.provider, provider.isConnected {
                barButton(provider.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                          label: provider.isMicrophoneEnabled ? "Mute" : "Unmute",
                          tint: provider.isMicrophoneEnabled ? theme.primaryText : theme.danger) {
                    Task { try? await provider.setMicrophoneEnabled(!provider.isMicrophoneEnabled) }
                }
            }
            barButton(client.handRaised ? "hand.raised.fill" : "hand.raised",
                      label: client.handRaised ? "Lower hand" : "Raise hand",
                      tint: client.handRaised ? theme.handRaised : theme.primaryText) {
                client.setHandRaised(!client.handRaised)
            }
            Button {
                showingParticipants = true
            } label: {
                Label("\(client.members.count)", systemImage: "person.2.fill")
                    .font(theme.label)
                    .foregroundColor(theme.primaryText)
            }
            .accessibilityLabel("Participants")
            Button(role: .destructive) {
                confirmingLeave = true
            } label: {
                Text(client.isHost ? "End" : "Leave")
                    .font(theme.label)
                    .foregroundColor(theme.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(theme.danger))
            }
            .disabled(finishing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.surface)
    }

    private func barButton(_ symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .imageScale(.large)
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(label)
    }

    private var pageBar: some View {
        HStack(spacing: 12) {
            Button {
                if let index = currentIndex, index > 0 { show(pages[index - 1].id, byHand: true) }
            } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .disabled((currentIndex ?? 0) == 0)
            .accessibilityLabel("Previous page")

            Menu {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Button("Page \(index + 1)") { show(page.id, byHand: true) }
                }
            } label: {
                Text(pages.isEmpty ? "No pages" : "Page \((currentIndex ?? 0) + 1) of \(pages.count)")
                    .font(theme.label)
                    .foregroundColor(theme.primaryText)
            }

            Button {
                if let index = currentIndex, index + 1 < pages.count { show(pages[index + 1].id, byHand: true) }
            } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .disabled((currentIndex ?? 0) + 1 >= pages.count)
            .accessibilityLabel("Next page")

            if client.isHost {
                Button {
                    let page = LivePageSpec.a4(background: newPageBackground)
                    client.addPage(page, after: currentPage?.id)
                    show(page.id, byHand: true)
                } label: {
                    Label("Add page", systemImage: "plus.rectangle.on.rectangle")
                        .font(theme.label)
                }
            }

            Spacer()

            if !client.isHost {
                Toggle(isOn: $followHost) {
                    Text("Follow host").font(theme.label).foregroundColor(theme.primaryText)
                }
                .toggleStyle(.switch)
                .fixedSize()
                .onChange(of: followHost) { _, follow in
                    if follow, let hostPage = client.state.hostPageId { show(hostPage, byHand: false) }
                }
            }
        }
        .tint(theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(theme.surface)
    }

    /// A new page keeps the current page's ruling; after a picture, it is blank.
    private var newPageBackground: PageBackground {
        if case .template(let template) = currentPage?.background.resolved { return .template(template) }
        return .blank
    }

    private func refusalText(_ reason: String) -> String {
        switch reason {
        case "drawing-locked": return "The host has locked writing, so that change was undone."
        case "not-host": return "Only the host can do that."
        case RoomClient.tooLarge: return "That was too large to share, so it was not added."
        default: return "That change could not be shared."
        }
    }

    private var statusBanner: some View {
        VStack(spacing: 6) {
            switch client.status {
            case .reconnecting:
                banner("Reconnecting… your writing is kept and will be sent.", systemImage: "wifi.exclamationmark")
            case .connecting where !client.state.pages.isEmpty:
                banner("Connecting…", systemImage: "antenna.radiowaves.left.and.right")
            default:
                EmptyView()
            }
            if let refusal {
                banner(refusal, systemImage: "exclamationmark.circle")
            }
        }
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(theme.caption)
            .foregroundColor(theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.raisedSurface))
            .overlay(Capsule().stroke(theme.warning, lineWidth: 1))
            .padding(.top, 8)
    }

    @ViewBuilder
    private var endedOverlay: some View {
        if case .ended(let reason) = client.status, !finishing {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(endedTitle(reason))
                        .font(theme.title)
                        .foregroundColor(theme.primaryText)
                        .multilineTextAlignment(.center)
                    Button("Close") {
                        Task { await finish(endForEveryone: false) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: theme.cornerRadius).fill(theme.raisedSurface))
                .padding(40)
            }
        }
    }

    private func endedTitle(_ reason: String) -> String {
        switch reason {
        case ServerMessage.roomEnded: return "The host ended this room."
        case ServerMessage.removedByHost: return "The host removed you from this room."
        case "no-such-room": return "This room has ended."
        case "room-full": return "This room is full."
        case "guests-not-allowed": return "This room needs an account. Sign in to join."
        case "protocol-mismatch": return "Update SpaceNotes to join this room."
        case "unauthenticated": return "Sign in again to join this room."
        default: return "You have left the room."
        }
    }

    // MARK: Actions

    private func show(_ pageId: String, byHand: Bool) {
        currentPageId = pageId
        client.sendView(pageId: pageId)
        if client.isHost, client.state.hostPageId != pageId {
            client.setHostPage(pageId)
        }
        // Turning the page by hand stops following the host.
        if byHand, !client.isHost, pageId != client.state.hostPageId { followHost = false }
    }

    /// A fresh ticket each time: a rejoin may come long after the first.
    private func connectVoice(microphoneEnabled: Bool) async {
        guard let voice, !voice.isConnected, !client.status.isEnded else { return }
        guard let ticket = try? await api.voiceToken(roomId: client.roomId) else { return }
        try? await voice.connect(url: ticket.url, token: ticket.token, microphoneEnabled: microphoneEnabled)
    }

    private func perform(_ action: VoiceIdlePolicy.Action) {
        switch action {
        case .none:
            break
        case .leave:
            // Only voice: the notebook stays connected, and ink is nearly free.
            Task { await voice?.disconnect() }
        case .rejoin(let microphoneOn):
            Task { await connectVoice(microphoneEnabled: microphoneOn) }
        }
    }

    /// Every few seconds: anyone speaking, or any ink or text in the room,
    /// keeps voice on; otherwise the policy decides when to leave.
    private func watchVoiceIdle() async {
        guard let voice else { return }
        while !Task.isCancelled, !client.status.isEnded {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard var policy = voicePolicy else { continue }
            let now = client.scheduler.now
            policy.noteActivity(at: client.lastNotebookActivityAt)
            if voice.isConnected, voice.isAnyoneSpeaking { policy.noteActivity(at: now) }
            let action = policy.check(at: now, microphoneOn: voice.isMicrophoneEnabled)
            voicePolicy = policy
            perform(action)
        }
    }

    private func finish(endForEveryone: Bool) async {
        guard !finishing else { return }
        finishing = true
        let reason: String
        if case .ended(let ended) = client.status { reason = ended } else { reason = endForEveryone ? ServerMessage.roomEnded : "left" }
        var state = client.state
        // The host takes the server's copy (it may hold writing this device
        // never saw), unless this device still has writing to send.
        if client.isHost, client.pendingOps.isEmpty, let snapshot = try? await api.snapshot(roomId: client.roomId) {
            state = snapshot.state
        }
        if endForEveryone {
            client.endRoom()
            // Give the frame time to go out: the server answers with
            // `removed`, which ends the client.
            for _ in 0..<20 where !client.status.isEnded {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        let wasHost = client.isHost
        let title = client.room?.title ?? ""
        client.disconnect()
        await voice?.disconnect()
        onFinish(LiveSessionResult(roomId: client.roomId, title: title, wasHost: wasHost, reason: reason, state: state))
    }
}
#endif
