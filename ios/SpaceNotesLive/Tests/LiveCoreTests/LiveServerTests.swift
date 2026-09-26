// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LiveCore

/// Runs two real clients against a running room server, over real
/// WebSockets. Skipped unless LIVE_SERVER_URL is set, for example:
///
///     cd server && LIVE_DEV_AUTH=1 PORT=8791 node src/server.js &
///     LIVE_SERVER_URL=http://localhost:8791 swift test --filter LiveServerTests
///
/// The server must accept dev tokens (`dev:<uid>:<name>`). On Linux,
/// URLSessionWebSocketTask needs a libcurl built with WebSocket support;
/// Ubuntu 24.04's is not (see ios/README.md).
@MainActor
final class LiveServerTests: XCTestCase {
    private var serverURL: URL!
    private var clients: [RoomClient] = []
    /// A fresh host and guest per test: the server limits rooms created per
    /// account, and repeated runs would otherwise hit it.
    private let hostUid = "host-\(UUID().uuidString.prefix(8))"
    private let guestUid = "asha-\(UUID().uuidString.prefix(8))"

    override func setUp() async throws {
        guard let text = ProcessInfo.processInfo.environment["LIVE_SERVER_URL"], let url = URL(string: text) else {
            throw XCTSkip("LIVE_SERVER_URL is not set")
        }
        serverURL = url
    }

    override func tearDown() async throws {
        for client in clients { client.disconnect() }
        clients = []
    }

    // MARK: Helpers

    private let page = "P1"
    private let black = LiveColor(r: 0, g: 0, b: 0, a: 1)

    private func api(_ token: String) -> LiveAPI {
        LiveAPI(baseURL: serverURL, tokenProvider: { token })
    }

    private func makeRoom() async throws -> String {
        let spec = LivePageSpec(id: page, width: 595, height: 842)
        let created = try await api("dev:\(hostUid):Host").createRoom(title: "Live test", pages: [LiveStartingPage(spec: spec)], allowGuests: true)
        XCTAssertEqual(created.code.count, 6)
        let lookup = try await api("dev:\(guestUid):Asha").lookup(code: created.code)
        XCTAssertEqual(lookup.roomId, created.roomId)
        return created.roomId
    }

    private func join(_ roomId: String, uid: String, name: String, device: String) -> (RoomClient, TransportLog) {
        let log = TransportLog()
        let client = RoomClient(serverURL: serverURL, roomId: roomId, name: name, deviceId: device,
                                tokenProvider: { "dev:\(uid):\(name)" },
                                transportFactory: {
                                    let transport = DroppableTransport(URLSessionWebSocketTransport(), log: log)
                                    log.current = transport
                                    return transport
                                })
        clients.append(client)
        client.connect()
        return (client, log)
    }

    private func waitUntil(_ what: String, timeout: Double = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func stroke(_ x: Double) -> LiveStroke {
        LiveStroke(ink: .pen, color: black, width: 2, createdAt: "2026-01-02T03:04:05Z", points: [
            LivePoint(x: x, y: 20, pressure: 1, timeOffset: 0, width: 2, azimuth: 0.25, altitude: 1.1),
            LivePoint(x: x + 30.5, y: 41.25, pressure: 0.5, timeOffset: 0.016, width: 2.5),
        ], captureStamp: 1767322445.123456)
    }

    private func visible(_ client: RoomClient) -> [String] {
        client.state.page(page)?.visibleStrokes.map(\.id) ?? []
    }

    private func connectedPair() async throws -> (host: RoomClient, guest: RoomClient, hostLog: TransportLog, guestLog: TransportLog) {
        let roomId = try await makeRoom()
        let (host, hostLog) = join(roomId, uid: hostUid, name: "Host", device: "ipad-host")
        let (guest, guestLog) = join(roomId, uid: guestUid, name: "Asha", device: "ipad-asha")
        try await waitUntil("both connected") { host.status == .connected && guest.status == .connected }
        try await waitUntil("both listed") { host.members.count == 2 && guest.members.count == 2 }
        XCTAssertTrue(host.isHost)
        XCTAssertFalse(guest.isHost)
        return (host, guest, hostLog, guestLog)
    }

    // MARK: Tests

    func testAStrokeReachesTheOtherPersonAndUndoRedoFollow() async throws {
        let (host, guest, _, _) = try await connectedPair()

        let s = stroke(10)
        guest.addStroke(pageId: page, stroke: s)
        try await waitUntil("host sees the stroke") { self.visible(host) == [s.id] }
        try await waitUntil("guest's stroke confirmed") { guest.pendingOps.isEmpty }
        XCTAssertEqual(host.state.page(page)?.strokes.first?.author, guestUid)
        XCTAssertEqual(host.state.page(page)?.strokes.first?.stroke, s, "the stroke arrives exactly as sent")
        XCTAssertEqual(host.confirmed, guest.confirmed)

        guest.undo()
        try await waitUntil("host sees the undo") { self.visible(host).isEmpty }
        guest.redo()
        try await waitUntil("host sees the redo") { self.visible(host) == [s.id] }
        try await waitUntil("both settle") { guest.pendingOps.isEmpty && host.confirmed == guest.confirmed }
        XCTAssertEqual(host.confirmed.seq, 3)
    }

    func testLiveInkPreviewThenStroke() async throws {
        let (host, guest, _, _) = try await connectedPair()
        let streamer = guest.beginLiveInk(pageId: page, ink: .pen, color: black, width: 2)
        streamer.add(x: 10, y: 20, width: 2)
        try await waitUntil("host sees the preview") { host.remoteInk[streamer.liveId]?.points.count == 1 }
        streamer.finish(stroke(10))
        try await waitUntil("preview replaced by the stroke") {
            host.remoteInk.isEmpty && self.visible(host) == [streamer.liveId]
        }
    }

    func testLockedDrawingIsRejectedAndRolledBack() async throws {
        let (host, guest, _, _) = try await connectedPair()
        host.setPolicy(.host)
        try await waitUntil("guest learns drawing is locked") { !guest.canDraw }

        let s = stroke(50)
        guest.addStroke(pageId: page, stroke: s)
        XCTAssertEqual(visible(guest), [s.id], "drawn at once, optimistically")
        try await waitUntil("rejected and rolled back") { guest.pendingOps.isEmpty && self.visible(guest).isEmpty }
        XCTAssertFalse(guest.canUndo)
        XCTAssertTrue(visible(host).isEmpty)
        XCTAssertEqual(host.confirmed, guest.confirmed)

        host.setPolicy(.pen, penHolder: guestUid)
        try await waitUntil("guest holds the pen") { guest.canDraw }
        guest.addStroke(pageId: page, stroke: s)
        try await waitUntil("host sees it now") { self.visible(host) == [s.id] }
    }

    /// The op reaches the server, the answer is lost with the socket, and the
    /// client resends it after reconnecting. The server must not sequence it
    /// twice, and the client must not roll it back.
    func testAnOpSentJustBeforeADropIsDeliveredExactlyOnce() async throws {
        let (host, guest, hostLog, guestLog) = try await connectedPair()

        guestLog.current?.holdIncoming = true
        let s = stroke(80)
        let clientOpId = try XCTUnwrap(guest.addStroke(pageId: page, stroke: s))
        try await waitUntil("the server sequenced it") { self.visible(host) == [s.id] }
        XCTAssertEqual(guest.pendingOps.map(\.clientOpId), [clientOpId], "the guest has not heard back")

        guestLog.current?.drop()
        XCTAssertEqual(guest.status, .reconnecting)
        try await waitUntil("reconnected and settled") { guest.status == .connected && guest.pendingOps.isEmpty }

        XCTAssertEqual(guestLog.connections, 2)
        XCTAssertTrue(guestLog.received.contains { if case .reject(clientOpId, "duplicate") = $0 { return true }; return false },
                      "the resend is answered as a duplicate")
        XCTAssertEqual(visible(guest), [s.id], "nothing rolled back")
        XCTAssertEqual(hostLog.sequenced(clientOpId), 1, "sequenced exactly once")
        XCTAssertEqual(host.confirmed, guest.confirmed)
        XCTAssertTrue(guest.canUndo)
    }

    /// Writing while offline is kept, drawn, and sent once on reconnect.
    func testAnOpMadeWhileOfflineIsDeliveredExactlyOnce() async throws {
        let (host, guest, hostLog, guestLog) = try await connectedPair()
        guestLog.blockConnections = true
        guestLog.current?.drop()
        XCTAssertEqual(guest.status, .reconnecting)

        let s = stroke(120)
        let clientOpId = try XCTUnwrap(guest.addStroke(pageId: page, stroke: s))
        XCTAssertEqual(visible(guest), [s.id])
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(visible(host).isEmpty)

        guestLog.blockConnections = false
        try await waitUntil("delivered after reconnect", timeout: 15) { self.visible(host) == [s.id] && guest.pendingOps.isEmpty }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(hostLog.sequenced(clientOpId), 1)
        XCTAssertEqual(host.confirmed, guest.confirmed)
    }

    func testAFullLengthStrokeCrossesInOneFrame() async throws {
        #if os(Linux)
        // swift-corelibs-foundation's WebSocket (over libcurl) silently drops
        // outgoing messages somewhere between 16 and 48 KB while the socket
        // stays open; Node sends the same 797 KB frame to this server fine.
        // Apple's URLSession is a different implementation.
        throw XCTSkip("URLSessionWebSocketTask on Linux cannot send large frames")
        #endif
        let (host, guest, _, _) = try await connectedPair()
        var long = stroke(0)
        long.points = (0..<5000).map { i in
            LivePoint(x: 10 + Double(i) * 0.1123456789, y: 20 + Double(i % 97) * 0.987654321, pressure: 0.723456789,
                      timeOffset: Double(i) / 240.123, width: 2.123456789, azimuth: 0.987654321, altitude: 1.123456789)
        }
        guest.addStroke(pageId: page, stroke: long)
        try await waitUntil("host has all 5,000 points") { host.state.page(self.page)?.visibleStrokes.first?.points.count == 5000 }
        XCTAssertEqual(host.state.page(page)?.visibleStrokes.first, long)
        XCTAssertEqual(guest.status, .connected)
    }

    func testSnapshotMatchesTheRoom() async throws {
        let (host, guest, _, _) = try await connectedPair()
        guest.addStroke(pageId: page, stroke: stroke(10))
        try await waitUntil("confirmed") { guest.pendingOps.isEmpty }
        try await waitUntil("host caught up") { host.confirmed.seq == guest.confirmed.seq }
        let snapshot = try await api("dev:\(hostUid):Host").snapshot(roomId: host.roomId)
        XCTAssertEqual(snapshot.state, host.confirmed)
        XCTAssertEqual(snapshot.room.id, host.roomId)
        XCTAssertFalse(snapshot.ended)
        // Voice is optional: a server without LiveKit keys answers nil.
        _ = try await api("dev:\(hostUid):Host").voiceToken(roomId: host.roomId)
    }

    func testEndingTheRoomEndsEveryone() async throws {
        let (host, guest, _, guestLog) = try await connectedPair()
        host.endRoom()
        try await waitUntil("guest ended") { guest.status == .ended(reason: "room-ended") }
        try await waitUntil("host ended") { host.status == .ended(reason: "room-ended") }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(guestLog.connections, 1, "an ended room is not rejoined")
    }
}

// MARK: - A real transport the test can cut

/// What happened on one client's sockets, across reconnects.
@MainActor
final class TransportLog {
    weak var current: DroppableTransport?
    var connections = 0
    var received: [ServerMessage] = []
    /// While set, new connections fail at once (the device is offline).
    var blockConnections = false

    /// How many times an op with this clientOpId was sequenced.
    func sequenced(_ clientOpId: String) -> Int {
        received.filter { if case .op(let op) = $0 { return op.clientOpId == clientOpId }; return false }.count
    }
}

/// Wraps the URLSession transport so a test can drop the connection the way a
/// network does, and hold back what the server sends.
@MainActor
final class DroppableTransport: WebSocketTransport {
    private let inner: URLSessionWebSocketTransport
    private let log: TransportLog
    private var onEvent: (@MainActor (TransportEvent) -> Void)?
    /// Frames from the server are swallowed while this is set.
    var holdIncoming = false

    init(_ inner: URLSessionWebSocketTransport, log: TransportLog) {
        self.inner = inner
        self.log = log
    }

    func connect(url: URL, onEvent: @escaping @MainActor (TransportEvent) -> Void) {
        self.onEvent = onEvent
        if log.blockConnections {
            Task { @MainActor in onEvent(.closed(code: nil, reason: "offline")) }
            return
        }
        log.connections += 1
        inner.connect(url: url) { [weak self] event in
            guard let self else { return }
            if case .message(let text) = event {
                if self.holdIncoming { return }
                if let message = try? LiveJSON.decode(ServerMessage.self, from: text) { self.log.received.append(message) }
            }
            self.onEvent?(event)
        }
    }

    func send(_ text: String) { inner.send(text) }

    func close() {
        onEvent = nil
        inner.close()
    }

    func drop() {
        let onEvent = self.onEvent
        close()
        onEvent?(.closed(code: nil, reason: "dropped"))
    }
}
