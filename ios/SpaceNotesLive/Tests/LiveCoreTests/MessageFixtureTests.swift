// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import XCTest
@testable import LiveCore

final class MessageFixtureTests: XCTestCase {
    private func messages(_ file: String) throws -> [String: JSONValue] {
        guard case .object(let messages) = try XCTUnwrap(Fixtures.json(file)["messages"]) else {
            XCTFail("\(file) has no messages")
            return [:]
        }
        return messages
    }

    private let page1 = "00000001-0000-4000-8000-000000000001"
    private let stroke1 = "0000000A-0000-4000-8000-000000000001"

    // MARK: Server → client

    func testEveryServerMessageDecodes() throws {
        let all = try messages("messages/server-to-client.json")
        XCTAssertFalse(all.isEmpty)
        for (name, value) in all {
            let text = try LiveJSON.encodeString(value)
            let message = try LiveJSON.decode(ServerMessage.self, from: text)
            switch (name, message) {
            case ("welcome", .welcome(let welcome)):
                XCTAssertEqual(welcome.you.uid, "uid-asha")
                XCTAssertEqual(welcome.you.connectionId, "c2")
                XCTAssertEqual(welcome.room.code, "K7QM3X")
                XCTAssertEqual(welcome.state.seq, 1)
                XCTAssertEqual(welcome.state.pages[0].strokes[0].stroke.points.count, 3)
                XCTAssertEqual(welcome.state.pages[0].texts[0].seq, 0)
                XCTAssertEqual(welcome.members.count, 2)
                // The state inside survives a round trip.
                assertProtocolEqual(try JSONValue(encoding: welcome.state), try XCTUnwrap(value["state"]), "welcome state")
            case ("welcome-with-extra-fields", .welcome(let welcome)):
                XCTAssertEqual(welcome.room.title, "Extra fields")
                XCTAssertEqual(welcome.state.pages[0].background.kind, "hologram")
                XCTAssertEqual(welcome.state.pages[0].background.resolved, .blank)
            case ("op", .op(let op)):
                XCTAssertEqual(op.seq, 13)
                XCTAssertEqual(op.author, "uid-asha")
                XCTAssertEqual(op.clientOpId, "ipad-7F3A:42")
                XCTAssertEqual(op.op, .strokeErase(pageId: page1, strokeIds: [stroke1]))
            case ("reject", .reject(let clientOpId, let reason)):
                XCTAssertEqual(clientOpId, "ipad-7F3A:43")
                XCTAssertEqual(reason, "drawing-locked")
            case ("members", .members(let members)):
                XCTAssertEqual(members.count, 1)
                XCTAssertTrue(members[0].handRaised)
                XCTAssertEqual(members[0].pageId, "00000001-0000-4000-8000-000000000002")
            case ("presence-ink-live", .presence(let from, .inkLive(let ink))):
                XCTAssertEqual(from.connectionId, "c2")
                XCTAssertEqual(ink.p, [10, 20, 2, 30.5, 41.3, 2.5])
                XCTAssertFalse(ink.done)
                XCTAssertEqual(ink.liveId, stroke1)
            case ("presence-pointer", .presence(let from, .pointer(let pageId, let x, let y, let laser))):
                XCTAssertEqual(from.uid, "uid-ravi")
                XCTAssertEqual(pageId, page1)
                XCTAssertEqual(x, 120.5)
                XCTAssertEqual(y, 300)
                XCTAssertTrue(laser)
            case ("presence-pointer-hide", .presence(_, .pointerHide)):
                break
            case ("presence-view", .presence(_, .view(let pageId))):
                XCTAssertEqual(pageId, "00000001-0000-4000-8000-000000000002")
            case ("presence-hand", .presence(_, .hand(let raised))):
                XCTAssertTrue(raised)
            case ("removed", .removed(let reason)):
                XCTAssertEqual(reason, "removed-by-host")
            case ("error", .error(let code, let message)):
                XCTAssertEqual(code, "no-such-room")
                XCTAssertEqual(message, "That room has ended.")
            case ("pong", .pong(let t)):
                XCTAssertEqual(t, 123)
            case ("unknown-type", .unknown(let type)):
                XCTAssertEqual(type, "confetti")
            default:
                XCTFail("\(name) decoded as \(message)")
            }
        }
    }

    // MARK: Client → server

    func testEveryClientMessageRoundTrips() throws {
        let all = try messages("messages/client-to-server.json")
        XCTAssertFalse(all.isEmpty)
        for (name, value) in all {
            let message = try value.decode(ClientMessage.self)
            if case .unknown = message { XCTFail("\(name) decoded as unknown") }
            if case .op(_, let op) = message {
                switch op {
                case .unknown, .invalid: XCTFail("\(name): op did not decode as a known kind")
                default: break
                }
            }
            assertProtocolEqual(try JSONValue(encoding: message), value, name)
        }
    }

    /// Builds each fixture frame from Swift values, not from the fixture.
    func testClientMessagesBuiltFromTypes() throws {
        let all = try messages("messages/client-to-server.json")
        let color = LiveColor(r: 0.1, g: 0.2, b: 0.3, a: 1)
        let stroke = LiveStroke(id: stroke1, ink: .pen, color: color, width: 2.5, createdAt: "2026-01-02T03:04:05Z", points: [
            LivePoint(x: 10, y: 20, pressure: 0.5, timeOffset: 0, width: 2, azimuth: 0.25, altitude: 1.1),
            LivePoint(x: 30.5, y: 41.25, pressure: 1.75, timeOffset: 0.016, width: 2.5, azimuth: 0.3, altitude: 1.2),
            LivePoint(x: 50, y: 60, pressure: 0.25, timeOffset: 0.032, width: 3),
        ], captureStamp: 1767322445.123456)
        let text = LiveText(id: "0000000B-0000-4000-8000-000000000001", text: "Lithium — narrow therapeutic index",
                            frame: LiveFrame(x: 40, y: 320, width: 260, height: 64), fontSize: 18,
                            color: LiveColor(r: 0.15, g: 0.18, b: 0.22, a: 1))
        let built: [String: ClientMessage] = [
            "hello": .hello(Hello(token: "eyJhbGciOi.test.token", roomId: "room-1", name: "Asha", deviceId: "ipad-7F3A")),
            "op-stroke-add": .op(clientOpId: "ipad-7F3A:42", op: .strokeAdd(pageId: page1, stroke: stroke)),
            "op-items-move": .op(clientOpId: "ipad-7F3A:44", op: .itemsMove(pageId: page1, strokeIds: [stroke1],
                                                                            textIds: ["0000000B-0000-4000-8000-000000000001"], dx: -4.5, dy: 12)),
            "op-text-upsert": .op(clientOpId: "web-1:1", op: .textUpsert(pageId: page1, text: text)),
            "op-page-add": .op(clientOpId: "web-1:2", op: .pageAdd(page: LivePageSpec(id: "00000001-0000-4000-8000-000000000002", width: 595, height: 842,
                                                                                     background: .template(.lined)), afterPageId: page1)),
            "op-room-policy": .op(clientOpId: "web-1:3", op: .roomPolicy(drawPolicy: "pen", penHolder: "uid-asha")),
            "presence-ink-live-done": .presence(.inkLive(LiveInkPresence(pageId: page1, liveId: stroke1, ink: "pen", color: color,
                                                                         width: 2.5, p: [50, 60, 3], done: true))),
            "presence-view": .presence(.view(pageId: page1)),
            "control-remove": .control(.remove(uid: "uid-ravi")),
            "control-end": .control(.end),
            "ping": .ping(t: 123),
        ]
        XCTAssertEqual(Set(built.keys), Set(all.keys), "every fixture frame is built here")
        for (name, message) in built {
            assertProtocolEqual(try JSONValue(encoding: message), try XCTUnwrap(all[name]), name)
        }
    }

    // MARK: Strokes

    func testStrokeOmitsAbsentOptionalsAndKeepsUnknownInk() throws {
        let json = #"{"id":"s","ink":"quill","color":{"r":0,"g":0,"b":0,"a":1},"width":1,"createdAt":"2026-01-02T03:04:05Z","points":[{"x":1,"y":2,"pressure":1,"timeOffset":0,"width":1}]}"#
        let stroke = try LiveJSON.decode(LiveStroke.self, from: json)
        XCTAssertEqual(stroke.inkType, .unknown)
        XCTAssertEqual(stroke.ink, "quill")
        let encoded = try LiveJSON.encodeString(stroke)
        XCTAssertFalse(encoded.contains("azimuth"))
        XCTAssertFalse(encoded.contains("altitude"))
        XCTAssertFalse(encoded.contains("captureStamp"))
        XCTAssertEqual(try LiveJSON.decode(JSONValue.self, from: encoded), try LiveJSON.decode(JSONValue.self, from: json))
    }

    func testBackgrounds() {
        XCTAssertEqual(PageBackground(kind: "template", template: "grid").resolved, .template(.grid))
        XCTAssertEqual(PageBackground(kind: "template", template: "hex").resolved, .blank)
        XCTAssertEqual(PageBackground.image(assetId: "a").resolved, .image(assetId: "a"))
        XCTAssertEqual(PageBackground(kind: "hologram").resolved, .blank)
    }

    func testUnknownPresenceAndGarbage() throws {
        let message = try LiveJSON.decode(ServerMessage.self, from: #"{"type":"presence","from":{"uid":"u","connectionId":"c"},"presence":{"kind":"emoji","e":"👋"}}"#)
        guard case .presence(_, .unknown(let kind, _)) = message else { return XCTFail("\(message)") }
        XCTAssertEqual(kind, "emoji")
    }
}
