// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import XCTest
@testable import LiveCore

@MainActor
final class RoomClientTests: XCTestCase {
    private var transports: [InMemoryTransport] = []
    private var scheduler: ManualScheduler!
    private var client: RoomClient!

    private let page = "P1"
    private let black = LiveColor(r: 0, g: 0, b: 0, a: 1)

    override func setUp() async throws {
        transports = []
        scheduler = ManualScheduler()
        client = RoomClient(serverURL: URL(string: "https://live.example.com")!, roomId: "room-1", name: "Asha",
                            deviceId: "dev", tokenProvider: { "token-1" },
                            transportFactory: { [unowned self] in
                                let transport = InMemoryTransport()
                                self.transports.append(transport)
                                return transport
                            },
                            scheduler: scheduler,
                            opCounterStart: 0)
    }

    // MARK: Helpers

    private var socket: InMemoryTransport { transports.last! }

    private func baseState(seq: Int = 0) -> RoomState {
        RoomState(seq: seq, hostPageId: page, pages: [LivePage(spec: LivePageSpec(id: page, width: 595, height: 842))])
    }

    private func welcome(_ state: RoomState? = nil, role: String = "guest", members: [Member]? = nil) -> ServerMessage {
        .welcome(Welcome(you: You(uid: "uid-asha", connectionId: "c2", name: "Asha", role: role, color: "#E4572E"),
                         room: RoomInfo(id: "room-1", code: "K7QM3X", title: "Cardiology", hostUid: "uid-host"),
                         state: state ?? baseState(),
                         members: members ?? [
                            Member(uid: "uid-host", connectionId: "c1", name: "Host", role: "host", color: "#3B5BDB"),
                            Member(uid: "uid-asha", connectionId: "c2", name: "Asha", role: role, color: "#E4572E"),
                            Member(uid: "uid-ravi", connectionId: "c3", name: "Ravi", role: "guest", color: "#12B886"),
                         ]))
    }

    private func connected(_ state: RoomState? = nil, role: String = "guest") async {
        client.connect()
        await client.openTask?.value
        socket.receive(welcome(state, role: role))
        socket.clearSent()
    }

    private func stroke(_ id: String, x: Double = 10) -> LiveStroke {
        LiveStroke(id: id, ink: .pen, color: black, width: 2, createdAt: "2026-01-02T03:04:05Z",
                   points: [LivePoint(x: x, y: 20, pressure: 1, timeOffset: 0, width: 2)])
    }

    private func sentOps(_ transport: InMemoryTransport? = nil) -> [(String, Op)] {
        (transport ?? socket).sentMessages.compactMap { message in
            if case .op(let id, let op) = message { return (id, op) }
            return nil
        }
    }

    private func sentPresence() -> [Presence] {
        socket.sentMessages.compactMap { message in
            if case .presence(let presence) = message { return presence }
            return nil
        }
    }

    /// The server numbers and echoes everything the client sent.
    private func echoAll(author: String = "uid-asha") {
        var seq = client.confirmed.seq
        for (id, op) in sentOps() {
            seq += 1
            socket.receive(.op(SequencedOp(seq: seq, author: author, clientOpId: id, op: op)))
        }
        socket.clearSent()
    }

    private func visibleStrokeIds() -> [String] {
        client.state.page(page)?.visibleStrokes.map(\.id) ?? []
    }

    // MARK: Connecting

    func testHelloAndWelcome() async throws {
        client.connect()
        XCTAssertEqual(client.status, .connecting)
        await client.openTask?.value
        XCTAssertEqual(socket.url?.absoluteString, "wss://live.example.com/live")
        XCTAssertEqual(socket.sentMessages, [.hello(Hello(token: "token-1", roomId: "room-1", name: "Asha", deviceId: "dev"))])
        socket.receive(welcome())
        XCTAssertEqual(client.status, .connected)
        XCTAssertEqual(client.me?.uid, "uid-asha")
        XCTAssertEqual(client.room?.code, "K7QM3X")
        XCTAssertEqual(client.members.count, 3)
        XCTAssertTrue(client.canDraw)
    }

    func testTheOpCounterStartsFromTheClock() async {
        let before = Int(Date().timeIntervalSince1970 * 1000)
        let fresh = RoomClient(serverURL: URL(string: "https://live.example.com")!, roomId: "room-1", name: "Asha",
                               deviceId: "dev", tokenProvider: { "t" }, transportFactory: { InMemoryTransport() },
                               scheduler: scheduler)
        let id = fresh.addStroke(pageId: page, stroke: stroke("S"))
        let counter = Int(id?.split(separator: ":").last ?? "") ?? 0
        XCTAssertGreaterThan(counter, before, "a relaunch never reuses an earlier launch's ids")
        XCTAssertLessThanOrEqual(counter, Int(Date().timeIntervalSince1970 * 1000) + 1)
        XCTAssertEqual(fresh.addStroke(pageId: page, stroke: stroke("T")), "dev:\(counter + 1)")
    }

    func testSocketURL() {
        XCTAssertEqual(RoomClient.socketURL(from: URL(string: "http://localhost:8080")!).absoluteString, "ws://localhost:8080/live")
        XCTAssertEqual(RoomClient.socketURL(from: URL(string: "https://x.run.app/")!).absoluteString, "wss://x.run.app/live")
        XCTAssertEqual(RoomClient.socketURL(from: URL(string: "wss://x.run.app/live")!).absoluteString, "wss://x.run.app/live")
    }

    // MARK: Optimistic ops

    func testOptimisticStrokeIsPendingUntilEchoed() async {
        await connected()
        client.addStroke(pageId: page, stroke: stroke("S1"))
        XCTAssertEqual(client.pendingOps.map(\.clientOpId), ["dev:1"])
        XCTAssertEqual(visibleStrokeIds(), ["S1"])
        XCTAssertEqual(client.state.page(page)?.strokes.first?.author, "uid-asha")
        XCTAssertEqual(client.state.page(page)?.strokes.first?.seq, 0)
        XCTAssertEqual(client.confirmed.page(page)?.strokes.count, 0)
        XCTAssertEqual(sentOps().map(\.0), ["dev:1"])

        echoAll()
        XCTAssertTrue(client.pendingOps.isEmpty)
        XCTAssertEqual(client.confirmed.seq, 1)
        XCTAssertEqual(client.confirmed.page(page)?.strokes.first?.seq, 1)
        XCTAssertEqual(client.state, client.confirmed)
    }

    func testOthersOpsApplyUnderPending() async {
        await connected()
        client.addStroke(pageId: page, stroke: stroke("MINE"))
        socket.receive(.op(SequencedOp(seq: 1, author: "uid-ravi", clientOpId: "r:1", op: .strokeAdd(pageId: page, stroke: stroke("RAVI")))))
        XCTAssertEqual(visibleStrokeIds(), ["RAVI", "MINE"])
        XCTAssertEqual(client.state.seq, 1)
    }

    func testOpsMadeBeforeWelcomeAreSentAfterIt() async {
        client.connect()
        await client.openTask?.value
        client.addStroke(pageId: page, stroke: stroke("EARLY"))
        XCTAssertTrue(sentOps().isEmpty)
        socket.receive(welcome())
        XCTAssertEqual(sentOps().map(\.0), ["dev:1"])
        XCTAssertEqual(visibleStrokeIds(), ["EARLY"])
    }

    func testPendingOpsAreResentWithTheSameIdAfterReconnect() async {
        await connected()
        client.addStroke(pageId: page, stroke: stroke("S1"))
        let first = socket
        first.drop()
        XCTAssertEqual(client.status, .reconnecting)
        XCTAssertEqual(visibleStrokeIds(), ["S1"], "the stroke stays on screen while offline")

        scheduler.advance(by: 0.5)
        await client.openTask?.value
        XCTAssertEqual(transports.count, 2)
        XCTAssertEqual(socket.sentMessages.first, .hello(Hello(token: "token-1", roomId: "room-1", name: "Asha", deviceId: "dev")))

        // Someone else drew while we were away.
        var state = baseState(seq: 4)
        state.pages[0].strokes = [LiveStrokeItem(author: "uid-ravi", seq: 4, stroke: stroke("RAVI"))]
        socket.receive(welcome(state))
        XCTAssertEqual(sentOps().map(\.0), ["dev:1"])
        XCTAssertEqual(visibleStrokeIds(), ["RAVI", "S1"])
        XCTAssertEqual(client.confirmed.seq, 4)
    }

    func testRejectRollsBack() async {
        await connected()
        client.addStroke(pageId: page, stroke: stroke("S1"))
        XCTAssertTrue(client.canUndo)
        socket.receive(.reject(clientOpId: "dev:1", reason: "drawing-locked"))
        XCTAssertTrue(client.pendingOps.isEmpty)
        XCTAssertEqual(visibleStrokeIds(), [])
        XCTAssertFalse(client.canUndo, "a rejected op leaves nothing to undo")
    }

    func testDuplicateRejectKeepsTheWelcomeStateAndTheUndo() async {
        await connected()
        client.addStroke(pageId: page, stroke: stroke("S1"))
        socket.drop()
        scheduler.advance(by: 0.5)
        await client.openTask?.value
        // The server had already sequenced dev:1 before the drop.
        var state = baseState(seq: 1)
        state.pages[0].strokes = [LiveStrokeItem(author: "uid-asha", seq: 1, stroke: stroke("S1"))]
        socket.receive(welcome(state))
        XCTAssertEqual(sentOps().map(\.0), ["dev:1"])
        socket.receive(.reject(clientOpId: "dev:1", reason: "duplicate"))
        XCTAssertTrue(client.pendingOps.isEmpty)
        XCTAssertEqual(visibleStrokeIds(), ["S1"], "nothing is rolled back")
        XCTAssertEqual(client.state, client.confirmed)
        XCTAssertTrue(client.canUndo)
    }

    func testSequenceGapReconnects() async {
        await connected()
        socket.receive(.op(SequencedOp(seq: 1, author: "uid-ravi", clientOpId: "r:1", op: .strokeAdd(pageId: page, stroke: stroke("A")))))
        let first = socket
        socket.receive(.op(SequencedOp(seq: 3, author: "uid-ravi", clientOpId: "r:3", op: .strokeAdd(pageId: page, stroke: stroke("C")))))
        XCTAssertTrue(first.isClosed)
        XCTAssertEqual(client.status, .reconnecting)
        XCTAssertEqual(client.confirmed.seq, 1, "the op after the gap is not applied")
        scheduler.advance(by: 0.5)
        await client.openTask?.value
        XCTAssertEqual(transports.count, 2)
    }

    func testBackoff() async {
        client.connect()
        await client.openTask?.value
        var delays: [Double] = []
        for _ in 0..<6 {
            socket.drop()
            delays.append(scheduler.pendingDelays.first ?? -1)
            scheduler.advance(by: delays.last!)
            await client.openTask?.value
        }
        XCTAssertEqual(delays, [0.5, 1, 2, 4, 8, 8])
        // A welcome resets the backoff.
        socket.receive(welcome())
        socket.drop()
        XCTAssertEqual(scheduler.pendingDelays.first, 0.5)
    }

    func testPingEveryTwentySeconds() async {
        await connected()
        scheduler.advance(by: 19.9)
        XCTAssertTrue(socket.sentMessages.isEmpty)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(socket.sentMessages.count, 1)
        if case .ping = socket.sentMessages[0] {} else { XCTFail("expected ping") }
        scheduler.advance(by: 20)
        XCTAssertEqual(socket.sentMessages.count, 2)
    }

    // MARK: Ending

    func testRemovedEndsWithoutReconnecting() async {
        await connected()
        socket.receive(.removed(reason: "removed-by-host"))
        XCTAssertEqual(client.status, .ended(reason: "removed-by-host"))
        XCTAssertTrue(socket.isClosed)
        scheduler.advance(by: 60)
        XCTAssertEqual(transports.count, 1)
    }

    func testRemovedInsteadOfWelcomeOnRejoin() async {
        client.connect()
        await client.openTask?.value
        socket.receive(.removed(reason: "removed-by-host"))
        XCTAssertEqual(client.status, .ended(reason: "removed-by-host"))
        socket.drop()
        scheduler.advance(by: 60)
        XCTAssertEqual(transports.count, 1)
        client.connect()
        XCTAssertEqual(client.status, .ended(reason: "removed-by-host"), "an ended client stays ended")
    }

    func testATerminalCloseReasonEndsEvenWithoutItsFrame() async {
        await connected()
        // As Linux reports the server's 4000 close: the code is lost, the
        // reason is not.
        socket.drop(code: 1003, reason: "room-ended")
        XCTAssertEqual(client.status, .ended(reason: "room-ended"))
        scheduler.advance(by: 60)
        XCTAssertEqual(transports.count, 1)
    }

    func testRateLimitedCloseAndOrdinaryDropsReconnect() async {
        await connected()
        socket.drop(code: 4002, reason: "rate-limited")
        XCTAssertEqual(client.status, .reconnecting)
        scheduler.advance(by: 0.5)
        await client.openTask?.value
        socket.receive(welcome())
        socket.drop(code: nil, reason: "The network connection was lost.")
        XCTAssertEqual(client.status, .reconnecting)
        scheduler.advance(by: 0.5)
        await client.openTask?.value
        socket.drop(code: 1003, reason: "no-such-room")
        XCTAssertEqual(client.status, .ended(reason: "no-such-room"))
    }

    func testErrors() async {
        await connected()
        // Recoverable codes reconnect, and the backoff keeps growing.
        var delays: [Double] = []
        for code in ["rate-limited", "unauthenticated", "too-large", "brand-new-code"] {
            socket.receive(.error(code: code, message: "…"))
            XCTAssertEqual(client.status, .reconnecting, code)
            delays.append(scheduler.pendingDelays.first ?? -1)
            scheduler.advance(by: delays.last!)
            await client.openTask?.value
        }
        XCTAssertEqual(delays, [0.5, 1, 2, 4])
        XCTAssertEqual(transports.count, 5)
        for code in ["bad-hello", "room-full", "guests-not-allowed", "protocol-mismatch"] {
            XCTAssertTrue(RoomClient.terminalErrorCodes.contains(code))
        }
        socket.receive(.error(code: "no-such-room", message: "gone"))
        XCTAssertEqual(client.status, .ended(reason: "no-such-room"))
        scheduler.advance(by: 60)
        XCTAssertEqual(transports.count, 5)
    }

    func testUnknownAndGarbageFramesAreIgnored() async {
        await connected()
        socket.receive(text: #"{"type":"confetti","colour":"gold"}"#)
        socket.receive(text: "not json")
        XCTAssertEqual(client.status, .connected)
    }

    func testDisconnect() async {
        await connected()
        client.disconnect()
        XCTAssertEqual(client.status, .ended(reason: "left"))
        XCTAssertTrue(socket.isClosed)
    }

    // MARK: Undo and redo

    func testUndoThenRedoOfStrokeAdd() async {
        await connected()
        client.addStroke(pageId: page, stroke: stroke("S1"))
        echoAll()

        client.undo()
        XCTAssertEqual(sentOps().map(\.1), [.strokeErase(pageId: page, strokeIds: ["S1"])])
        XCTAssertEqual(sentOps().map(\.0), ["dev:2"], "undo is a new op with a fresh id")
        XCTAssertEqual(visibleStrokeIds(), [])
        XCTAssertTrue(client.canRedo)
        echoAll()

        client.redo()
        XCTAssertEqual(sentOps().map(\.1), [.strokeRestore(pageId: page, strokeIds: ["S1"])])
        XCTAssertEqual(visibleStrokeIds(), ["S1"])
        echoAll()
        XCTAssertEqual(visibleStrokeIds(), ["S1"])
        XCTAssertTrue(client.canUndo)
        XCTAssertFalse(client.canRedo)
    }

    func testEraseUndoRestoresOnlyWhatItHid() async {
        var state = baseState(seq: 2)
        state.pages[0].strokes = [LiveStrokeItem(author: "uid-ravi", seq: 1, stroke: stroke("A")),
                                  LiveStrokeItem(author: "uid-ravi", seq: 2, erased: true, stroke: stroke("B"))]
        await connected(state)
        client.eraseStrokes(pageId: page, strokeIds: ["A", "B"])
        echoAll()
        client.undo()
        XCTAssertEqual(sentOps().map(\.1), [.strokeRestore(pageId: page, strokeIds: ["A"])])
        echoAll()
        client.redo()
        XCTAssertEqual(sentOps().map(\.1), [.strokeErase(pageId: page, strokeIds: ["A", "B"])])
    }

    func testRestoreUndoErases() async {
        var state = baseState(seq: 1)
        state.pages[0].strokes = [LiveStrokeItem(author: "uid-ravi", seq: 1, erased: true, stroke: stroke("A"))]
        await connected(state)
        client.restoreStrokes(pageId: page, strokeIds: ["A"])
        client.undo()
        XCTAssertEqual(sentOps().map(\.1).last, .strokeErase(pageId: page, strokeIds: ["A"]))
        client.redo()
        XCTAssertEqual(sentOps().map(\.1).last, .strokeRestore(pageId: page, strokeIds: ["A"]))
    }

    func testMoveUndo() async {
        await connected()
        client.addStroke(pageId: page, stroke: stroke("A", x: 10))
        client.moveItems(pageId: page, strokeIds: ["A"], dx: 5, dy: -2)
        XCTAssertEqual(client.state.page(page)?.strokes[0].stroke.points[0].x, 15)
        client.undo()
        XCTAssertEqual(sentOps().map(\.1).last, .itemsMove(pageId: page, strokeIds: ["A"], textIds: [], dx: -5, dy: 2))
        XCTAssertEqual(client.state.page(page)?.strokes[0].stroke.points[0].x, 10)
        client.redo()
        XCTAssertEqual(sentOps().map(\.1).last, .itemsMove(pageId: page, strokeIds: ["A"], textIds: [], dx: 5, dy: -2))
    }

    func testTextUndo() async {
        await connected()
        let first = LiveText(id: "T", text: "one", frame: LiveFrame(x: 0, y: 0, width: 100, height: 20), fontSize: 16, color: black)
        var second = first
        second.text = "two"

        client.upsertText(pageId: page, text: first)
        client.upsertText(pageId: page, text: second)
        client.eraseTexts(pageId: page, textIds: ["T"])
        XCTAssertEqual(client.state.page(page)?.visibleTexts, [])

        client.undo() // erase → upsert as it was
        XCTAssertEqual(sentOps().map(\.1).last, .textUpsert(pageId: page, text: second))
        client.undo() // edit → upsert of the previous text
        XCTAssertEqual(sentOps().map(\.1).last, .textUpsert(pageId: page, text: first))
        client.undo() // new text → erase
        XCTAssertEqual(sentOps().map(\.1).last, .textErase(pageId: page, textIds: ["T"]))
        XCTAssertEqual(client.state.page(page)?.visibleTexts, [])

        client.redo() // the same upsert
        XCTAssertEqual(sentOps().map(\.1).last, .textUpsert(pageId: page, text: first))
        client.redo()
        XCTAssertEqual(sentOps().map(\.1).last, .textUpsert(pageId: page, text: second))
        client.redo()
        XCTAssertEqual(sentOps().map(\.1).last, .textErase(pageId: page, textIds: ["T"]))
    }

    func testNewOpClearsRedoAndOthersOpsAreNotUndoable() async {
        await connected()
        socket.receive(.op(SequencedOp(seq: 1, author: "uid-ravi", clientOpId: "r:1", op: .strokeAdd(pageId: page, stroke: stroke("RAVI")))))
        XCTAssertFalse(client.canUndo)
        client.addStroke(pageId: page, stroke: stroke("A"))
        client.undo()
        XCTAssertTrue(client.canRedo)
        client.addStroke(pageId: page, stroke: stroke("B"))
        XCTAssertFalse(client.canRedo)
        client.undo()
        XCTAssertEqual(visibleStrokeIds(), ["RAVI"])
        XCTAssertFalse(client.canUndo)
    }

    func testRejectedUndoDropsTheEntry() async {
        await connected()
        client.addStroke(pageId: page, stroke: stroke("A"))
        echoAll()
        client.undo()
        let undoId = sentOps().last!.0
        socket.receive(.reject(clientOpId: undoId, reason: "drawing-locked"))
        XCTAssertFalse(client.canRedo)
        XCTAssertFalse(client.canUndo)
        XCTAssertEqual(visibleStrokeIds(), ["A"])
    }

    func testHostOpsAreNotUndoable() async {
        await connected(role: "host")
        client.addPage(LivePageSpec(id: "P2", width: 595, height: 842), after: page)
        client.setPolicy(.pen, penHolder: "uid-ravi")
        client.setHostPage("P2")
        XCTAssertFalse(client.canUndo)
        XCTAssertEqual(client.state.pages.map(\.id), [page, "P2"])
        XCTAssertEqual(client.state.drawPolicy, "pen")
        XCTAssertEqual(client.state.penHolder, "uid-ravi")
        XCTAssertEqual(client.state.hostPageId, "P2")
        XCTAssertEqual(sentOps().map(\.0), ["dev:1", "dev:2", "dev:3"])
    }

    func testCanDrawFollowsPolicy() async {
        await connected()
        socket.receive(.op(SequencedOp(seq: 1, author: "uid-host", op: .roomPolicy(drawPolicy: "host", penHolder: nil))))
        XCTAssertFalse(client.canDraw)
        socket.receive(.op(SequencedOp(seq: 2, author: "uid-host", op: .roomPolicy(drawPolicy: "pen", penHolder: "uid-asha"))))
        XCTAssertTrue(client.canDraw)
    }

    // MARK: Live ink

    func testLiveInkIsThrottledAndEndsWithDoneThenStroke() async {
        await connected()
        let streamer = client.beginLiveInk(pageId: page, ink: .pen, color: black, width: 2, strokeId: "LIVE")
        streamer.add(x: 10, y: 20, width: 2)           // t = 0: sent at once
        scheduler.advance(by: 0.01)
        streamer.add(x: 30.5, y: 41.25, width: 2.5)    // buffered
        scheduler.advance(by: 0.01)
        streamer.add(x: 31.04, y: 42, width: 2.5)      // buffered
        XCTAssertEqual(sentPresence().count, 1)
        scheduler.advance(by: 0.01)                    // t = 0.03: flushed together
        XCTAssertEqual(sentPresence().count, 2)
        streamer.add(x: 50, y: 60, width: 3)           // buffered (within 30 ms)
        streamer.finish(stroke("ANY-ID"))

        let presence = sentPresence()
        XCTAssertEqual(presence.count, 3)
        guard case .inkLive(let a) = presence[0], case .inkLive(let b) = presence[1], case .inkLive(let c) = presence[2] else {
            return XCTFail("expected ink.live")
        }
        XCTAssertEqual(a.p, [10, 20, 2])
        XCTAssertFalse(a.done)
        XCTAssertEqual(b.p, [30.5, 41.3, 2.5, 31, 42, 2.5])
        XCTAssertEqual(c.p, [50, 60, 3])
        XCTAssertTrue(c.done)
        XCTAssertEqual(a.liveId, "LIVE")

        // done comes before the stroke.add, which carries the same id.
        guard case .presence(.inkLive(let last)) = socket.sentMessages[socket.sentMessages.count - 2], last.done,
              case .op(_, .strokeAdd(_, let committed)) = socket.sentMessages.last! else {
            return XCTFail("expected done then stroke.add, got \(socket.sentMessages)")
        }
        XCTAssertEqual(committed.id, "LIVE")
        scheduler.advance(by: 1)
        XCTAssertEqual(sentPresence().count, 3, "nothing sent after finishing")
    }

    func testCancelledLiveInkSendsDone() async {
        await connected()
        let streamer = client.beginLiveInk(pageId: page, ink: .pen, color: black, width: 2)
        streamer.add(x: 1, y: 1, width: 1)
        streamer.add(x: 2, y: 2, width: 1)
        streamer.cancel()
        guard case .inkLive(let last) = sentPresence().last else { return XCTFail() }
        XCTAssertTrue(last.done)
        XCTAssertEqual(last.p, [])
        XCTAssertTrue(sentOps().isEmpty)
    }

    func testRounding() {
        XCTAssertEqual(LiveInkStreamer.round(41.25), 41.3)
        XCTAssertEqual(LiveInkStreamer.round(-1.25), -1.2, "as JavaScript's Math.round")
        XCTAssertEqual(LiveInkStreamer.round(0.04), 0)
    }

    func testAStrokeIsAlwaysOneOpAndOverlongStrokesAreNotSent() async {
        await connected()
        let points = (0..<5000).map { LivePoint(x: Double($0) + 0.123456789, y: 1.987654321, pressure: 0.123456789,
                                                 timeOffset: Double($0) / 240, width: 2.123456789,
                                                 azimuth: 0.987654321, altitude: 1.123456789) }
        var full = stroke("FULL")
        full.points = points
        XCTAssertNotNil(client.addStroke(pageId: page, stroke: full))
        XCTAssertEqual(socket.sent.count, 1)
        XCTAssertLessThan(socket.sent[0].utf8.count, 1024 * 1024, "a 5,000-point stroke fits one frame")

        var tooLong = full
        tooLong.id = "TOO-LONG"
        tooLong.points.append(points[0])
        XCTAssertNil(client.addStroke(pageId: page, stroke: tooLong))
        XCTAssertEqual(socket.sent.count, 1)
        XCTAssertEqual(visibleStrokeIds(), ["FULL"])

        let pieces = tooLong.continuedAtMaximumPoints()
        XCTAssertEqual(pieces.map(\.points.count), [5000, 2])
        XCTAssertEqual(pieces[0].id, "TOO-LONG", "the first keeps the live preview's id")
        XCTAssertNotEqual(pieces[1].id, "TOO-LONG")
        XCTAssertEqual(pieces[1].points[0].x, tooLong.points[4999].x, "carries on from the last point")
        XCTAssertEqual(pieces[1].points[0].timeOffset, 0)
        XCTAssertEqual(pieces[1].points[1], LivePoint(x: points[0].x, y: points[0].y, pressure: points[0].pressure,
                                                      timeOffset: points[0].timeOffset - points[4999].timeOffset,
                                                      width: points[0].width, azimuth: points[0].azimuth, altitude: points[0].altitude))
        XCTAssertEqual(full.continuedAtMaximumPoints(), [full])
        for piece in pieces { XCTAssertNotNil(client.addStroke(pageId: page, stroke: piece)) }
        XCTAssertEqual(socket.sent.count, 3, "one stroke.add each")
    }

    func testAnOpTooLargeToSendIsDroppedLocally() async {
        await connected()
        var rejected: [(String, String)] = []
        client.onReject = { rejected.append(($0, $1)) }
        let huge = LiveText(id: "BIG", text: String(repeating: "x", count: 1_100_000),
                            frame: LiveFrame(x: 0, y: 0, width: 100, height: 20), fontSize: 16, color: black)
        XCTAssertNil(client.upsertText(pageId: page, text: huge))
        XCTAssertTrue(sentOps().isEmpty, "never sent")
        XCTAssertTrue(client.pendingOps.isEmpty)
        XCTAssertEqual(client.state.page(page)?.visibleTexts, [])
        XCTAssertFalse(client.canUndo, "not an undo step")
        XCTAssertEqual(rejected.map(\.1), ["too-large"])
        XCTAssertEqual(client.lastRejection?.reason, "too-large")

        // The next op is unaffected, and nothing is resent on reconnect.
        XCTAssertEqual(client.addStroke(pageId: page, stroke: stroke("S")), "dev:2")
        socket.drop()
        scheduler.advance(by: 0.5)
        await client.openTask?.value
        socket.receive(welcome())
        XCTAssertEqual(sentOps().map(\.0), ["dev:2"])
    }

    func testServerRejectsAreReported() async {
        await connected()
        var reasons: [String] = []
        client.onReject = { _, reason in reasons.append(reason) }
        client.addStroke(pageId: page, stroke: stroke("A"))
        client.addStroke(pageId: page, stroke: stroke("B"))
        socket.receive(.reject(clientOpId: "dev:1", reason: "duplicate"))
        socket.receive(.reject(clientOpId: "dev:2", reason: "drawing-locked"))
        XCTAssertEqual(reasons, ["drawing-locked"], "a duplicate is not a refusal")
    }

    // MARK: Received presence

    private func from(_ connectionId: String = "c3", uid: String = "uid-ravi") -> PresenceSender {
        PresenceSender(uid: uid, connectionId: connectionId)
    }

    private func ink(_ id: String, _ p: [Double], done: Bool = false) -> Presence {
        .inkLive(LiveInkPresence(pageId: page, liveId: id, ink: "pen", color: black, width: 2, p: p, done: done))
    }

    func testRemoteInkPreviewLifecycle() async {
        await connected()
        socket.receive(.presence(from: from(), presence: ink("R1", [1, 2, 3])))
        socket.receive(.presence(from: from(), presence: ink("R1", [4, 5, 6, 7, 8, 9])))
        XCTAssertEqual(client.remoteInk["R1"]?.points.map(\.x), [1, 4, 7])
        XCTAssertEqual(client.remoteInk["R1"]?.connectionId, "c3")
        // done: the preview stays for its stroke, and goes after 1.5 s if the
        // stroke never comes (it was refused).
        socket.receive(.presence(from: from(), presence: ink("R1", [10, 11, 12], done: true)))
        XCTAssertEqual(client.remoteInk["R1"]?.points.map(\.x), [1, 4, 7, 10])
        XCTAssertEqual(client.remoteInk["R1"]?.isFinished, true)
        scheduler.advance(by: 1.4)
        XCTAssertNotNil(client.remoteInk["R1"])
        scheduler.advance(by: 0.1)
        XCTAssertNil(client.remoteInk["R1"])

        // Usually the committed stroke swaps the preview out first.
        socket.receive(.presence(from: from(), presence: ink("R2", [1, 2, 3])))
        socket.receive(.presence(from: from(), presence: ink("R2", [], done: true)))
        socket.receive(.op(SequencedOp(seq: 1, author: "uid-ravi", clientOpId: "r:1", op: .strokeAdd(pageId: page, stroke: stroke("R2")))))
        XCTAssertNil(client.remoteInk["R2"])
        XCTAssertEqual(visibleStrokeIds(), ["R2"])
        scheduler.advance(by: 2)

        // A late preview for a committed stroke is ignored.
        socket.receive(.presence(from: from(), presence: ink("R2", [1, 2, 3])))
        XCTAssertNil(client.remoteInk["R2"])
    }

    func testPointersViewsAndHands() async {
        await connected()
        socket.receive(.presence(from: from(), presence: .pointer(pageId: page, x: 1, y: 2, laser: true)))
        XCTAssertEqual(client.pointers["c3"]?.laser, true)
        socket.receive(.presence(from: from(), presence: .pointerHide))
        XCTAssertNil(client.pointers["c3"])
        socket.receive(.presence(from: from(), presence: .view(pageId: "P9")))
        XCTAssertEqual(client.views["c3"], "P9")
        XCTAssertEqual(client.members.first { $0.connectionId == "c3" }?.pageId, "P9")
        socket.receive(.presence(from: from(), presence: .hand(raised: true)))
        XCTAssertEqual(client.members.first { $0.connectionId == "c3" }?.handRaised, true)
    }

    func testPresenceOfALeavingMemberIsDropped() async {
        await connected()
        socket.receive(.presence(from: from(), presence: ink("R1", [1, 2, 3])))
        socket.receive(.presence(from: from(), presence: .pointer(pageId: page, x: 1, y: 2, laser: false)))
        socket.receive(.presence(from: from(), presence: .view(pageId: page)))
        socket.receive(.members([Member(uid: "uid-host", connectionId: "c1", name: "Host", role: "host", color: "#3B5BDB"),
                                 Member(uid: "uid-asha", connectionId: "c2", name: "Asha", role: "guest", color: "#E4572E")]))
        XCTAssertTrue(client.remoteInk.isEmpty)
        XCTAssertTrue(client.pointers.isEmpty)
        XCTAssertTrue(client.views.isEmpty)
    }

    func testOutgoingPresence() async {
        await connected()
        client.sendPointer(pageId: page, x: 10.04, y: 20.06, laser: true)
        client.hidePointer()
        client.sendView(pageId: page)
        client.setHandRaised(true)
        XCTAssertEqual(sentPresence(), [.pointer(pageId: page, x: 10, y: 20.1, laser: true), .pointerHide, .view(pageId: page), .hand(raised: true)])
        XCTAssertTrue(client.handRaised)
        client.remove(uid: "uid-ravi")
        client.endRoom()
        XCTAssertEqual(socket.sentMessages.suffix(2), [.control(.remove(uid: "uid-ravi")), .control(.end)])
    }

    func testPresenceIsNotQueuedWhileOffline() async {
        client.connect()
        await client.openTask?.value
        client.sendView(pageId: page)
        XCTAssertEqual(socket.sentMessages.count, 1, "only the hello")
    }
}
