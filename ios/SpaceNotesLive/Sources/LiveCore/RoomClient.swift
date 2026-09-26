// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation
#if canImport(Combine)
import Combine
#endif

/// One person's connection to a room. Holds the server's state (`confirmed`),
/// this device's ops the server has not numbered yet (`pendingOps`), and the
/// state the screen draws (`state`: confirmed with pending applied on top).
///
/// The same API is implemented by the web and Android clients.
@MainActor
public final class RoomClient {
    public enum Status: Hashable, Sendable {
        case idle
        case connecting
        case connected
        case reconnecting
        case ended(reason: String)

        public var isEnded: Bool {
            if case .ended = self { return true }
            return false
        }
    }

    public struct PendingOp: Hashable, Sendable {
        public var clientOpId: String
        public var op: Op
    }

    /// A point of a stroke someone else is still drawing.
    public struct PreviewPoint: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
    }

    /// A stroke someone else is still drawing.
    public struct RemoteInk: Hashable, Sendable, Identifiable {
        public var liveId: String
        public var connectionId: String
        public var uid: String
        public var pageId: String
        public var ink: String
        public var color: LiveColor
        public var width: Double
        public var points: [PreviewPoint]
        /// The sender has lifted the pen; the stroke itself should follow.
        public var isFinished = false
        public var id: String { liveId }
    }

    public struct RemotePointer: Hashable, Sendable {
        public var connectionId: String
        public var uid: String
        public var pageId: String
        public var x: Double
        public var y: Double
        public var laser: Bool
        /// Scheduler time it arrived, so a laser dot can fade.
        public var updatedAt: Double
    }

    struct UndoEntry {
        var pair: UndoPair
        /// clientOpIds of the most recent send of this entry, so a reject can
        /// find it.
        var sentIds: [String]
    }

    /// An op the server refused, or one too large to send.
    public struct Rejection: Hashable, Sendable {
        public var clientOpId: String
        public var reason: String
    }

    /// Under the server's 1 MiB frame, leaving room for the envelope. The
    /// same figure as the web client.
    public static let maximumOpBytes = 1000 * 1024
    public static let tooLarge = "too-large"

    /// `error` codes that end the session; every other code reconnects.
    public static let terminalErrorCodes: Set<String> = [
        "bad-hello", "no-such-room", "room-full", "guests-not-allowed", "protocol-mismatch",
    ]

    /// Close reasons after which reconnecting cannot help: the `removed`
    /// reasons and the terminal error codes.
    public static let terminalCloseReasons: Set<String> =
        terminalErrorCodes.union([ServerMessage.roomEnded, ServerMessage.removedByHost])

    /// A finished preview whose stroke has not arrived by then was refused.
    public static let finishedPreviewLifetime: Double = 1.5

    /// Reconnect delays, in seconds: 0.5, 1, 2, 4, then every 8.
    public static let backoff: [Double] = [0.5, 1, 2, 4, 8]
    public static let pingInterval: Double = 20
    /// One screen frame: a friend sees the line grow as it is drawn.
    public static let liveInkInterval: Double = 0.016
    /// A hovering pointer, at most this often, and only after moving 1 pt.
    public static let pointerInterval: Double = 0.1
    public static let pointerMinimumMove: Double = 1
    /// The laser, at most this often.
    public static let laserInterval: Double = 0.033

    // MARK: Observable state

    public private(set) var status: Status = .idle { didSet { changed() } }
    public private(set) var confirmed = RoomState.empty
    public private(set) var state = RoomState.empty
    public private(set) var pendingOps: [PendingOp] = []
    public private(set) var members: [Member] = [] { didSet { changed() } }
    public private(set) var me: You?
    public private(set) var room: RoomInfo?
    /// Fast-changing presence (ink being drawn, pointers) lives in its own
    /// observable object, so a friend's stroke redraws only the overlay that
    /// shows it, not the whole page.
    public let presence = LivePresence()
    /// Strokes others are drawing, keyed by their future stroke id.
    public var remoteInk: [String: RemoteInk] { presence.remoteInk }
    /// Pointers by connectionId.
    public var pointers: [String: RemotePointer] { presence.pointers }
    /// Scheduler time of the last ink or text seen in the room: a sequenced
    /// stroke, text or move op, or someone's ink.live. Voice uses it to tell
    /// a quiet room from a busy one.
    public private(set) var lastNotebookActivityAt: Double = 0
    /// The page each connection is looking at, by connectionId.
    public private(set) var views: [String: String] = [:] { didSet { changed() } }
    public private(set) var handRaised = false { didSet { changed() } }

    /// Called after any change, for hosts without Combine (Linux, tests).
    public var onChange: (() -> Void)?
    /// Called when an op of this device's is refused (not for `duplicate`,
    /// which is not a refusal), so the screen can say why.
    public var onReject: ((_ clientOpId: String, _ reason: String) -> Void)?
    public private(set) var lastRejection: Rejection? { didSet { changed() } }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Whether this person may change the notebook right now. The server has
    /// the final say.
    public var canDraw: Bool {
        guard let me else { return false }
        return Permissions.canDraw(state: state, member: me.participant)
    }

    public var isHost: Bool { me?.isHost ?? false }

    // MARK: Configuration

    public let serverURL: URL
    public let roomId: String
    public let name: String
    public let deviceId: String
    public let scheduler: LiveScheduler
    private let tokenProvider: () async throws -> String
    private let transportFactory: @MainActor () -> WebSocketTransport

    // MARK: Connection

    private var transport: WebSocketTransport?
    private var generation = 0
    private var attempt = 0
    private var stopped = false
    private var reconnectTimer: LiveCancellable?
    private var pingTimer: LiveCancellable?
    private var opCounter = 0
    private var undoStack: [UndoEntry] = []
    private var lastPointer: (pointer: OutgoingPointer, at: Double)?
    private var pendingPointer: OutgoingPointer?
    private var pointerTimer: LiveCancellable?
    private var activeStrokes = 0
    private var redoStack: [UndoEntry] = []
    /// The token fetch for the current attempt; tests await it.
    var openTask: Task<Void, Never>?

    public init(serverURL: URL,
                roomId: String,
                name: String,
                deviceId: String,
                tokenProvider: @escaping () async throws -> String,
                transportFactory: @escaping @MainActor () -> WebSocketTransport = { URLSessionWebSocketTransport() },
                scheduler: LiveScheduler? = nil,
                opCounterStart: Int? = nil) {
        self.serverURL = serverURL
        self.roomId = roomId
        self.name = name
        self.deviceId = deviceId
        self.tokenProvider = tokenProvider
        self.transportFactory = transportFactory
        self.scheduler = scheduler ?? TaskScheduler()
        lastNotebookActivityAt = self.scheduler.now
        // deviceId survives app launches, so the counter must never repeat:
        // it starts from the clock in milliseconds, not from 1, or a
        // relaunched app's first ops would be refused as duplicates.
        opCounter = opCounterStart ?? Int(Date().timeIntervalSince1970 * 1000)
    }

    /// `wss://<server>/live`, from the server's https base URL.
    public var socketURL: URL { RoomClient.socketURL(from: serverURL) }

    public static func socketURL(from server: URL) -> URL {
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return server }
        switch components.scheme {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: break
        }
        if !components.path.hasSuffix("/live") {
            let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
            components.path = base + "/live"
        }
        return components.url ?? server
    }

    /// Starts connecting. Does nothing if already started or ended: an ended
    /// client is not reused.
    public func connect() {
        guard status == .idle else { return }
        stopped = false
        attempt = 0
        status = .connecting
        open()
    }

    /// Leaves the room. The notebook stays as it was on screen.
    public func disconnect() {
        stopped = true
        closeTransport()
        reconnectTimer?.cancel()
        status = .ended(reason: "left")
        clearPresence()
    }

    private func open() {
        closeTransport()
        generation += 1
        let current = generation
        openTask = Task { [weak self] in
            guard let self else { return }
            let token: String
            do {
                token = try await self.tokenProvider()
            } catch {
                guard current == self.generation else { return }
                self.connectionLost()
                return
            }
            guard current == self.generation, !self.stopped else { return }
            let transport = self.transportFactory()
            self.transport = transport
            transport.connect(url: self.socketURL) { [weak self] event in
                self?.handle(event, generation: current, token: token)
            }
        }
    }

    private func closeTransport() {
        pingTimer?.cancel()
        pingTimer = nil
        transport?.close()
        transport = nil
    }

    private func connectionLost() {
        closeTransport()
        guard !stopped, !status.isEnded else { return }
        status = .reconnecting
        let delay = RoomClient.backoff[min(attempt, RoomClient.backoff.count - 1)]
        attempt += 1
        generation += 1
        reconnectTimer?.cancel()
        reconnectTimer = scheduler.schedule(after: delay) { [weak self] in
            guard let self, !self.stopped, !self.status.isEnded else { return }
            self.open()
        }
    }

    private func end(_ reason: String) {
        stopped = true
        closeTransport()
        reconnectTimer?.cancel()
        status = .ended(reason: reason)
        clearPresence()
    }

    private func handle(_ event: TransportEvent, generation: Int, token: String) {
        guard generation == self.generation else { return }
        switch event {
        case .open:
            send(.hello(Hello(token: token, roomId: roomId, name: name, deviceId: deviceId)))
        case .message(let text):
            guard let message = try? LiveJSON.decode(ServerMessage.self, from: text) else { return }
            handle(message)
        case .closed(_, let reason):
            // The server also puts the reason in the close frame, so a
            // `removed` or `error` frame lost just before the close (Linux's
            // libcurl WebSockets do lose it) still ends the session. The
            // reason text is used, not the code: URLSession cannot represent
            // the server's 4000-range codes.
            if let reason, RoomClient.terminalCloseReasons.contains(reason) {
                end(reason)
            } else {
                connectionLost()
            }
        }
    }

    // MARK: Server messages

    func handle(_ message: ServerMessage) {
        switch message {
        case .welcome(let welcome):
            me = welcome.you
            room = welcome.room
            confirmed = welcome.state
            attempt = 0
            members = welcome.members
            pruneStalePresence()
            status = .connected
            // Resend everything not yet numbered, with the same clientOpIds;
            // the server skips any it already sequenced.
            for pending in pendingOps { send(.op(clientOpId: pending.clientOpId, op: pending.op)) }
            recompute()
            schedulePing()

        case .op(let sequenced):
            guard status == .connected else { return }
            guard sequenced.seq == confirmed.seq + 1 else {
                // Missed something: the next welcome brings us up to date.
                connectionLost()
                return
            }
            confirmed = Reducer.apply(confirmed, sequenced)
            switch sequenced.op {
            case .strokeAdd, .strokeErase, .strokeRestore, .textUpsert, .textErase, .itemsMove:
                lastNotebookActivityAt = scheduler.now
            default:
                break
            }
            if let clientOpId = sequenced.clientOpId {
                pendingOps.removeAll { $0.clientOpId == clientOpId }
            }
            if case .strokeAdd(_, let stroke) = sequenced.op, remoteInk[stroke.id] != nil {
                presence.remoteInk[stroke.id] = nil
            }
            recompute()

        case .reject(let clientOpId, let reason):
            if reason != ServerMessage.rejectDuplicate {
                lastRejection = Rejection(clientOpId: clientOpId, reason: reason)
                onReject?(clientOpId, reason)
            }
            pendingOps.removeAll { $0.clientOpId == clientOpId }
            if reason != ServerMessage.rejectDuplicate {
                // The op never happened, so there is nothing to undo or redo.
                undoStack.removeAll { $0.sentIds.contains(clientOpId) }
                redoStack.removeAll { $0.sentIds.contains(clientOpId) }
            }
            // A duplicate is already in the welcome state; only the pending
            // copy goes.
            recompute()

        case .members(let list):
            members = list
            if let me, let mine = list.first(where: { $0.connectionId == me.connectionId }) {
                handRaised = mine.handRaised
            }
            pruneStalePresence()

        case .presence(let from, let presence):
            handlePresence(presence, from: from)

        case .removed(let reason):
            end(reason)

        case .error(let code, _):
            // Only these cannot be helped by trying again; anything else (an
            // expired token, rate limits, a code this build does not know)
            // reconnects with the growing backoff.
            if RoomClient.terminalErrorCodes.contains(code) {
                end(code)
            } else {
                connectionLost()
            }

        case .pong, .unknown:
            break
        }
    }

    private func handlePresence(_ presence: Presence, from: PresenceSender) {
        switch presence {
        case .inkLive(let ink):
            lastNotebookActivityAt = scheduler.now
            // A committed stroke with this id is already on the page.
            if state.page(ink.pageId)?.strokes.contains(where: { $0.stroke.id == ink.liveId }) == true { return }
            var points: [PreviewPoint] = []
            var i = 0
            while i + 2 < ink.p.count {
                points.append(PreviewPoint(x: ink.p[i], y: ink.p[i + 1], width: ink.p[i + 2]))
                i += 3
            }
            if var existing = remoteInk[ink.liveId] {
                existing.points.append(contentsOf: points)
                existing.isFinished = existing.isFinished || ink.done
                self.presence.remoteInk[ink.liveId] = existing
            } else if !points.isEmpty {
                self.presence.remoteInk[ink.liveId] = RemoteInk(liveId: ink.liveId, connectionId: from.connectionId, uid: from.uid,
                                                  pageId: ink.pageId, ink: ink.ink, color: ink.color, width: ink.width,
                                                  points: points, isFinished: ink.done)
            }
            if ink.done {
                // The preview stays until its stroke.add swaps it out without
                // a flicker. If that never comes, the stroke was refused.
                let liveId = ink.liveId
                scheduler.schedule(after: RoomClient.finishedPreviewLifetime) { [weak self] in
                    guard let self, self.remoteInk[liveId]?.isFinished == true else { return }
                    self.presence.remoteInk[liveId] = nil
                }
            }

        case .pointer(let pageId, let x, let y, let laser):
            self.presence.pointers[from.connectionId] = RemotePointer(connectionId: from.connectionId, uid: from.uid, pageId: pageId,
                                                        x: x, y: y, laser: laser, updatedAt: scheduler.now)
        case .pointerHide:
            self.presence.pointers[from.connectionId] = nil

        case .view(let pageId):
            views[from.connectionId] = pageId
            if let index = members.firstIndex(where: { $0.connectionId == from.connectionId }) {
                members[index].pageId = pageId
            }

        case .hand(let raised):
            if let index = members.firstIndex(where: { $0.connectionId == from.connectionId }) {
                members[index].handRaised = raised
            }

        case .unknown:
            break
        }
    }

    /// Drops previews, pointers and views of connections that have left.
    private func pruneStalePresence() {
        let present = Set(members.map(\.connectionId))
        let ink = remoteInk.filter { present.contains($0.value.connectionId) }
        if ink.count != remoteInk.count { presence.remoteInk = ink }
        let pointers = self.pointers.filter { present.contains($0.key) }
        if pointers.count != self.pointers.count { presence.pointers = pointers }
        let views = self.views.filter { present.contains($0.key) }
        if views.count != self.views.count { self.views = views }
    }

    private func clearPresence() {
        presence.remoteInk = [:]
        presence.pointers = [:]
        views = [:]
    }

    private func schedulePing() {
        pingTimer?.cancel()
        pingTimer = scheduler.schedule(after: RoomClient.pingInterval) { [weak self] in
            guard let self, self.status == .connected else { return }
            self.send(.ping(t: (self.scheduler.now * 1000).rounded()))
            self.schedulePing()
        }
    }

    // MARK: Sending

    private func send(_ message: ClientMessage) {
        guard let transport, let text = try? LiveJSON.encodeString(message) else { return }
        transport.send(text)
    }

    private func nextClientOpId() -> String {
        opCounter += 1
        return "\(deviceId):\(opCounter)"
    }

    /// Queues an op, draws it at once, and sends it when connected. Returns
    /// nil for an op too large to send.
    @discardableResult
    private func submit(_ op: Op) -> String? {
        let clientOpId = nextClientOpId()
        let size = (try? LiveJSON.encoder.encode(op).count) ?? 0
        guard size <= RoomClient.maximumOpBytes else {
            // The server would close the socket, and every resend after
            // reconnecting would close it again. Refuse it here instead.
            lastRejection = Rejection(clientOpId: clientOpId, reason: RoomClient.tooLarge)
            onReject?(clientOpId, RoomClient.tooLarge)
            return nil
        }
        pendingOps.append(PendingOp(clientOpId: clientOpId, op: op))
        if status == .connected { send(.op(clientOpId: clientOpId, op: op)) }
        recompute()
        return clientOpId
    }

    /// A new op of this person's own: records its undo pair and clears redo.
    @discardableResult
    private func perform(_ op: Op) -> String? {
        let pair = UndoInverse.pair(for: op, in: state)
        guard let id = submit(op) else { return nil }
        if let pair {
            undoStack.append(UndoEntry(pair: pair, sentIds: [id]))
            redoStack.removeAll()
            changed()
        }
        return id
    }

    private func recompute() {
        let author = me?.uid ?? ""
        var next = confirmed
        for pending in pendingOps {
            Reducer.applyInPlace(&next, SequencedOp(seq: confirmed.seq, author: author, clientOpId: pending.clientOpId, op: pending.op))
        }
        state = next
        changed()
    }

    private func changed() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
        onChange?()
    }

    // MARK: Notebook ops

    /// Adds a finished stroke as one `stroke.add`. A stroke over the
    /// protocol's 5,000 points is not sent (the server would refuse it); the
    /// canvas breaks long strokes up first with `continuedAtMaximumPoints()`.
    @discardableResult
    public func addStroke(pageId: String, stroke: LiveStroke) -> String? {
        guard stroke.points.count <= Permissions.maximumStrokePoints else { return nil }
        return perform(.strokeAdd(pageId: pageId, stroke: stroke))
    }

    @discardableResult
    public func eraseStrokes(pageId: String, strokeIds: [String]) -> String? {
        guard !strokeIds.isEmpty else { return nil }
        return perform(.strokeErase(pageId: pageId, strokeIds: strokeIds))
    }

    @discardableResult
    public func restoreStrokes(pageId: String, strokeIds: [String]) -> String? {
        guard !strokeIds.isEmpty else { return nil }
        return perform(.strokeRestore(pageId: pageId, strokeIds: strokeIds))
    }

    @discardableResult
    public func moveItems(pageId: String, strokeIds: [String] = [], textIds: [String] = [], dx: Double, dy: Double) -> String? {
        guard !(strokeIds.isEmpty && textIds.isEmpty) else { return nil }
        return perform(.itemsMove(pageId: pageId, strokeIds: strokeIds, textIds: textIds, dx: dx, dy: dy))
    }

    @discardableResult
    public func upsertText(pageId: String, text: LiveText) -> String? {
        perform(.textUpsert(pageId: pageId, text: text))
    }

    @discardableResult
    public func eraseTexts(pageId: String, textIds: [String]) -> String? {
        guard !textIds.isEmpty else { return nil }
        return perform(.textErase(pageId: pageId, textIds: textIds))
    }

    /// Host only. Not undoable.
    @discardableResult
    public func addPage(_ page: LivePageSpec, after afterPageId: String?) -> String? {
        submit(.pageAdd(page: page, afterPageId: afterPageId))
    }

    /// Host only. `penHolder` is used with `.pen`.
    @discardableResult
    public func setPolicy(_ policy: DrawPolicy, penHolder: String? = nil) -> String? {
        submit(.roomPolicy(drawPolicy: policy.rawValue, penHolder: policy == .pen ? penHolder : nil))
    }

    /// Host only: the page "Follow host" follows.
    @discardableResult
    public func setHostPage(_ pageId: String) -> String? {
        submit(.hostPage(pageId: pageId))
    }

    // MARK: Undo

    /// Takes back this person's own last change by sending its inverse.
    public func undo() {
        guard var entry = undoStack.popLast() else { return }
        let ids = entry.pair.undo.map { submit($0) }
        entry.sentIds = ids.compactMap { $0 }
        // An undo too large to send drops the entry, as a reject would.
        if !ids.contains(nil) { redoStack.append(entry) }
        changed()
    }

    public func redo() {
        guard var entry = redoStack.popLast() else { return }
        let ids = entry.pair.redo.map { submit($0) }
        entry.sentIds = ids.compactMap { $0 }
        if !ids.contains(nil) { undoStack.append(entry) }
        changed()
    }

    // MARK: Presence

    /// Starts streaming a stroke as it is drawn. Call `finish` with the
    /// finished stroke (it takes the streamer's id) or `cancel`.
    public func beginLiveInk(pageId: String, ink: LiveInk, color: LiveColor, width: Double,
                             strokeId: String = LiveIDs.make()) -> LiveInkStreamer {
        strokeBegan()
        return LiveInkStreamer(client: self, pageId: pageId, liveId: strokeId, ink: ink.rawValue, color: color, width: width)
    }

    func sendPresence(_ presence: Presence) {
        guard status == .connected else { return }
        send(.presence(presence))
    }

    /// Where this person's pen or finger is. Throttled: a hovering pointer
    /// at most every 100 ms and only after a move of 1 pt, the laser at most
    /// every 33 ms, the latest position sent when the wait is over. Nothing
    /// is sent while a stroke is being drawn: its ink.live shows the pen.
    public func sendPointer(pageId: String, x: Double, y: Double, laser: Bool) {
        guard status == .connected, activeStrokes == 0 else { return }
        let next = OutgoingPointer(pageId: pageId, x: LiveInkStreamer.round(x), y: LiveInkStreamer.round(y), laser: laser)
        let now = scheduler.now
        if let last = lastPointer {
            if !laser, !last.pointer.laser, last.pointer.pageId == pageId,
               hypot(next.x - last.pointer.x, next.y - last.pointer.y) < RoomClient.pointerMinimumMove {
                pendingPointer = nil
                return
            }
            let interval = laser ? RoomClient.laserInterval : RoomClient.pointerInterval
            if now - last.at < interval {
                pendingPointer = next
                if pointerTimer == nil {
                    pointerTimer = scheduler.schedule(after: last.at + interval - now) { [weak self] in
                        guard let self else { return }
                        self.pointerTimer = nil
                        if let pending = self.pendingPointer, self.activeStrokes == 0 { self.emitPointer(pending) }
                        self.pendingPointer = nil
                    }
                }
                return
            }
        }
        emitPointer(next)
    }

    public func hidePointer() {
        clearPendingPointer()
        guard lastPointer != nil else { return }
        lastPointer = nil
        sendPresence(.pointerHide)
    }

    private struct OutgoingPointer {
        var pageId: String
        var x: Double
        var y: Double
        var laser: Bool
    }

    private func emitPointer(_ pointer: OutgoingPointer) {
        lastPointer = (pointer, scheduler.now)
        sendPresence(.pointer(pageId: pointer.pageId, x: pointer.x, y: pointer.y, laser: pointer.laser))
    }

    private func clearPendingPointer() {
        pointerTimer?.cancel()
        pointerTimer = nil
        pendingPointer = nil
    }

    /// A stroke has started: no pointer while it is drawn.
    func strokeBegan() {
        activeStrokes += 1
        hidePointer()
    }

    func strokeEnded() {
        activeStrokes = max(0, activeStrokes - 1)
    }

    public func sendView(pageId: String) {
        sendPresence(.view(pageId: pageId))
    }

    public func setHandRaised(_ raised: Bool) {
        handRaised = raised
        if let me, let index = members.firstIndex(where: { $0.connectionId == me.connectionId }) {
            members[index].handRaised = raised
        }
        sendPresence(.hand(raised: raised))
    }

    // MARK: Host controls

    public func remove(uid: String) {
        send(.control(.remove(uid: uid)))
    }

    /// Ends the room for everyone. The server answers with `removed`.
    public func endRoom() {
        send(.control(.end))
    }

    /// The member for a uid, for names and colours.
    public func member(uid: String) -> Member? {
        members.first { $0.uid == uid }
    }
}

#if canImport(Combine)
extension RoomClient: ObservableObject {}
extension LivePresence: ObservableObject {}
#endif

/// Others' strokes in progress and their pointers. Changes many times a
/// second while someone draws, so it is observed on its own.
@MainActor
public final class LivePresence {
    /// Strokes others are drawing, keyed by their future stroke id.
    public internal(set) var remoteInk: [String: RoomClient.RemoteInk] = [:] { didSet { changed() } }
    /// Pointers by connectionId.
    public internal(set) var pointers: [String: RoomClient.RemotePointer] = [:] { didSet { changed() } }
    /// Called after any change, for hosts without Combine.
    public var onChange: (() -> Void)?

    nonisolated init() {}

    private func changed() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
        onChange?()
    }
}

/// Streams one stroke's points while it is drawn: the first batch at once,
/// then at most one message every 16 ms (one screen frame).
@MainActor
public final class LiveInkStreamer {
    public let pageId: String
    public let liveId: String
    public let ink: String
    public let color: LiveColor
    public let width: Double
    private weak var client: RoomClient?
    private var buffer: [Double] = []
    private var lastSentAt: Double?
    private var flushTimer: LiveCancellable?
    public private(set) var isFinished = false

    init(client: RoomClient, pageId: String, liveId: String, ink: String, color: LiveColor, width: Double) {
        self.client = client
        self.pageId = pageId
        self.liveId = liveId
        self.ink = ink
        self.color = color
        self.width = width
    }

    /// Rounds to 0.1 the way JavaScript's Math.round does, so every platform
    /// sends the same numbers.
    public static func round(_ value: Double) -> Double {
        (value * 10 + 0.5).rounded(.down) / 10
    }

    public func add(x: Double, y: Double, width: Double) {
        guard !isFinished, let client else { return }
        buffer.append(contentsOf: [Self.round(x), Self.round(y), Self.round(width)])
        let now = client.scheduler.now
        if let lastSentAt, now - lastSentAt < RoomClient.liveInkInterval {
            guard flushTimer == nil else { return }
            flushTimer = client.scheduler.schedule(after: lastSentAt + RoomClient.liveInkInterval - now) { [weak self] in
                self?.flushTimer = nil
                self?.flush()
            }
        } else {
            flush()
        }
    }

    private func flush() {
        guard !isFinished, !buffer.isEmpty, let client else { return }
        client.sendPresence(.inkLive(message(done: false)))
        buffer.removeAll()
        lastSentAt = client.scheduler.now
    }

    private func message(done: Bool) -> LiveInkPresence {
        LiveInkPresence(pageId: pageId, liveId: liveId, ink: ink, color: color, width: width, p: buffer, done: done)
    }

    /// Ends the preview and commits the stroke under the streamer's id.
    @discardableResult
    public func finish(_ stroke: LiveStroke) -> String? {
        guard !isFinished, let client else { return nil }
        end(client)
        var committed = stroke
        committed.id = liveId
        return client.addStroke(pageId: pageId, stroke: committed)
    }

    /// Ends the preview without a stroke (the touch was cancelled).
    public func cancel() {
        guard !isFinished, let client else { return }
        buffer.removeAll()
        end(client)
    }

    private func end(_ client: RoomClient) {
        client.strokeEnded()
        flushTimer?.cancel()
        flushTimer = nil
        client.sendPresence(.inkLive(message(done: true)))
        buffer.removeAll()
        isFinished = true
    }
}
