// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import XCTest
@testable import LiveCore

final class PermissionFixtureTests: XCTestCase {
    func testEveryCase() throws {
        guard case .array(let cases) = try XCTUnwrap(Fixtures.json("permissions/cases.json")["cases"]) else {
            return XCTFail("cases.json has no cases")
        }
        XCTAssertEqual(cases.count, 19)
        for testCase in cases {
            let name = testCase["name"]?.stringValue ?? "?"
            let state = try XCTUnwrap(testCase["state"]).decode(RoomState.self)
            let member = try XCTUnwrap(testCase["member"]).decode(LiveParticipant.self)
            // Decoded from raw JSON, as the server would receive it.
            let op = try XCTUnwrap(testCase["op"]).decode(Op.self)
            let expected = testCase["expected"]?.stringValue
            XCTAssertEqual(Permissions.authorize(state: state, member: member, op: op), expected, name)
        }
    }

    func testCanDraw() {
        var state = RoomState()
        let guest = LiveParticipant(uid: "g", role: "guest")
        XCTAssertTrue(Permissions.canDraw(state: state, member: guest))
        state.drawPolicy = "host"
        XCTAssertFalse(Permissions.canDraw(state: state, member: guest))
        XCTAssertTrue(Permissions.canDraw(state: state, member: LiveParticipant(uid: "h", role: "host")))
        state.drawPolicy = "pen"
        state.penHolder = "g"
        XCTAssertTrue(Permissions.canDraw(state: state, member: guest))
        XCTAssertFalse(Permissions.canDraw(state: state, member: LiveParticipant(uid: "x", role: "guest")))
    }

    func testMalformedOpsDecodeAsInvalidAndEncodeBack() throws {
        let raw = try LiveJSON.decode(JSONValue.self, from: #"{"kind":"items.move","pageId":"p","strokeIds":null,"dx":1,"dy":2}"#)
        let op = try raw.decode(Op.self)
        guard case .invalid(let kind, _) = op else { return XCTFail("expected invalid, got \(op)") }
        XCTAssertEqual(kind, "items.move")
        assertProtocolEqual(try JSONValue(encoding: op), raw, "invalid op encodes back")

        let unknown = try LiveJSON.decode(JSONValue.self, from: #"{"kind":"shape.add","shape":{"circle":true}}"#)
        let decoded = try unknown.decode(Op.self)
        XCTAssertEqual(decoded.kind, "shape.add")
        if case .unknown = decoded {} else { XCTFail("expected unknown") }
        XCTAssertEqual(try JSONValue(encoding: decoded), unknown)
    }
}
