// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI

/// A room to enter, from the lobby.
public struct LiveRoomTicket: Hashable, Sendable {
    public var roomId: String
    public var title: String
    public var code: String
    /// The web link to share; known only to the host who created the room.
    public var joinUrl: String?
    public var isHost: Bool

    public init(roomId: String, title: String, code: String, joinUrl: String? = nil, isHost: Bool) {
        self.roomId = roomId
        self.title = title
        self.code = code
        self.joinUrl = joinUrl
        self.isHost = isHost
    }
}

/// Start a room from the notebook's pages, or join one with a code.
public struct LiveLobbyView: View {
    private let api: LiveAPI
    private let source: LiveNotebookSource?
    private let onEnter: (LiveRoomTicket) -> Void
    private let onCancel: () -> Void

    @State private var title: String
    @State private var allowGuests = true
    @State private var code: String
    @State private var busy = false
    @State private var message: String?
    @Environment(\.liveTheme) private var theme

    /// - Parameters:
    ///   - source: the notebook to share, or nil to offer joining only.
    ///   - initialCode: a code from a join link, if the app was opened by one.
    public init(api: LiveAPI, source: LiveNotebookSource?, initialCode: String = "",
                onEnter: @escaping (LiveRoomTicket) -> Void, onCancel: @escaping () -> Void) {
        self.api = api
        self.source = source
        self.onEnter = onEnter
        self.onCancel = onCancel
        _title = State(initialValue: source?.title ?? "")
        _code = State(initialValue: LiveAPI.normalizeCode(initialCode))
    }

    public var body: some View {
        NavigationStack {
            Form {
                if source != nil {
                    Section {
                        TextField("Room title", text: $title)
                        Toggle("Let people join without an account", isOn: $allowGuests)
                        Button {
                            Task { await start() }
                        } label: {
                            Label("Start SpaceNotes Live", systemImage: "person.2.wave.2")
                                .font(theme.label)
                        }
                        .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
                    } header: {
                        Text("Share this notebook")
                    } footer: {
                        Text("Friends join with the room code and write on the same pages. You keep control of who can write.")
                            .font(theme.caption)
                    }
                }
                Section {
                    TextField("Room code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(theme.title)
                        .onChange(of: code) { _, typed in
                            let normalized = LiveAPI.normalizeCode(typed)
                            if normalized != typed { code = normalized }
                        }
                    Button {
                        Task { await join() }
                    } label: {
                        Label("Join", systemImage: "arrow.right.circle")
                            .font(theme.label)
                    }
                    .disabled(busy || code.count != 6)
                } header: {
                    Text("Join a room")
                }
                if busy {
                    Section { ProgressView() }
                }
                if let message {
                    Section {
                        Text(message)
                            .font(theme.body)
                            .foregroundColor(theme.danger)
                    }
                }
            }
            .navigationTitle("SpaceNotes Live")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .tint(theme.accent)
    }

    private func start() async {
        guard let source else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let created = try await LiveRoomHosting.createRoom(from: source, api: api, title: title, allowGuests: allowGuests)
            onEnter(LiveRoomTicket(roomId: created.roomId, title: title, code: created.code, joinUrl: created.joinUrl, isHost: true))
        } catch {
            message = describe(error)
        }
    }

    private func join() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            let found = try await api.lookup(code: code)
            onEnter(LiveRoomTicket(roomId: found.roomId, title: found.title, code: code, isHost: false))
        } catch {
            message = describe(error)
        }
    }

    private func describe(_ error: Error) -> String {
        guard let apiError = error as? LiveAPIError else {
            return "Could not reach SpaceNotes Live. Check your connection and try again."
        }
        switch apiError {
        case .http(404, _): return "No room has that code. Check it with the host."
        case .http(403, .some("guests-not-allowed")): return "This room needs an account. Sign in to join."
        case .http(413, _): return "A page picture is too large to share."
        case .http(let status, let code): return "The room server said no (\(code ?? String(status)))."
        case .badResponse: return "The room server sent something this version cannot read."
        }
    }
}

/// What the host app provides once, for every room.
public struct LiveConfiguration {
    /// The room server's https base URL.
    public var serverURL: URL
    public var displayName: String
    /// A stable id for this device, used in clientOpIds.
    public var deviceId: String
    /// A fresh Firebase ID token on every call.
    public var tokenProvider: @Sendable () async throws -> String
    /// Camera and voice for a room, or nil for ink only.
    public var makeVideo: (@MainActor () -> LiveVideoProviding)?

    public init(serverURL: URL, displayName: String, deviceId: String,
                tokenProvider: @escaping @Sendable () async throws -> String,
                makeVideo: (@MainActor () -> LiveVideoProviding)? = nil) {
        self.serverURL = serverURL
        self.displayName = displayName
        self.deviceId = deviceId
        self.tokenProvider = tokenProvider
        self.makeVideo = makeVideo
    }
}

/// Lobby, then room: the one view the notebook presents.
public struct LiveSessionView: View {
    private final class ActiveRoom {
        let ticket: LiveRoomTicket
        let client: RoomClient
        let video: LiveVideoProviding?

        @MainActor
        init(ticket: LiveRoomTicket, configuration: LiveConfiguration) {
            self.ticket = ticket
            client = RoomClient(serverURL: configuration.serverURL, roomId: ticket.roomId,
                                name: configuration.displayName, deviceId: configuration.deviceId,
                                tokenProvider: configuration.tokenProvider)
            video = configuration.makeVideo?()
        }
    }

    private let configuration: LiveConfiguration
    private let source: LiveNotebookSource?
    private let initialCode: String
    private let api: LiveAPI
    private let onFinish: (LiveSessionResult?) -> Void
    @State private var active: ActiveRoom?

    /// `onFinish` gets the session's result, or nil if the person cancelled
    /// in the lobby.
    public init(configuration: LiveConfiguration, source: LiveNotebookSource?, initialCode: String = "",
                onFinish: @escaping (LiveSessionResult?) -> Void) {
        self.configuration = configuration
        self.source = source
        self.initialCode = initialCode
        self.onFinish = onFinish
        api = LiveAPI(baseURL: configuration.serverURL, tokenProvider: configuration.tokenProvider)
    }

    public var body: some View {
        if let active {
            LiveRoomView(client: active.client, api: api, video: active.video) { result in
                self.active = nil
                onFinish(result)
            }
        } else {
            LiveLobbyView(api: api, source: source, initialCode: initialCode,
                          onEnter: { ticket in active = ActiveRoom(ticket: ticket, configuration: configuration) },
                          onCancel: { onFinish(nil) })
        }
    }
}
#endif
