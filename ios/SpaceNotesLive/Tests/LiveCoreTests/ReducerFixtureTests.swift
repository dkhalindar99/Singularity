// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import XCTest
@testable import LiveCore

final class ReducerFixtureTests: XCTestCase {
    func testEveryScenario() throws {
        let files = try Fixtures.files(in: "scenarios")
        XCTAssertGreaterThanOrEqual(files.count, 7, "scenario fixtures not found at \(Fixtures.root.path)")
        for file in files {
            let scenario = try Fixtures.json(file)
            let initial = try XCTUnwrap(scenario["initial"]).decode(RoomState.self)
            let ops = try XCTUnwrap(scenario["ops"]).decode([SequencedOp].self)
            let expected = try XCTUnwrap(scenario["expected"])

            // The initial state survives a round trip through the Swift types.
            assertProtocolEqual(try JSONValue(encoding: initial), try XCTUnwrap(scenario["initial"]), "\(file): initial round trip")

            var state = initial
            for op in ops { state = Reducer.apply(state, op) }
            assertProtocolEqual(try JSONValue(encoding: state), expected, "\(file): final state")
        }
    }

    func testApplyDoesNotChangeItsInput() throws {
        let scenario = try Fixtures.json("scenarios/move-adds-up-and-erase-wins.json")
        let initial = try XCTUnwrap(scenario["initial"]).decode(RoomState.self)
        let ops = try XCTUnwrap(scenario["ops"]).decode([SequencedOp].self)
        let copy = initial
        _ = Reducer.apply(initial, ops[0])
        XCTAssertEqual(initial, copy)
    }

    func testMovesAddUpToTheSameDouble() {
        var state = RoomState(pages: [LivePage(spec: LivePageSpec(id: "p", width: 10, height: 10))])
        let stroke = LiveStroke(id: "s", ink: .pen, color: LiveColor(r: 0, g: 0, b: 0, a: 1), width: 1,
                                points: [LivePoint(x: 0.1, y: 0, pressure: 1, timeOffset: 0, width: 1)])
        state = Reducer.apply(state, seq: 1, author: "a", op: .strokeAdd(pageId: "p", stroke: stroke))
        state = Reducer.apply(state, seq: 2, author: "a", op: .itemsMove(pageId: "p", strokeIds: ["s"], textIds: [], dx: 0.2, dy: 0))
        XCTAssertEqual(state.pages[0].strokes[0].stroke.points[0].x, 0.30000000000000004)
    }
}
