// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import XCTest
@testable import LiveCore

final class InkSmoothingTests: XCTestCase {
    private func s(_ x: Double, _ y: Double, _ w: Double = 2) -> InkSample { InkSample(x: x, y: y, width: w) }

    func testShortStrokes() {
        XCTAssertEqual(InkSmoothing.segments([]), [])
        let dot = InkSmoothing.segments([s(1, 2, 3)])
        XCTAssertEqual(dot, [InkSegment(start: s(1, 2, 3), control: nil, end: s(1, 2, 3), width: 3)], "a dot still shows")
        let line = InkSmoothing.segments([s(0, 0, 2), s(10, 0, 4)])
        XCTAssertEqual(line, [InkSegment(start: s(0, 0, 2), control: nil, end: s(10, 0, 4), width: 3)])
    }

    func testCurvesThroughMidpointsKeepingWidths() {
        let points = [s(0, 0, 1), s(10, 0, 2), s(10, 10, 3), s(0, 10, 4)]
        let segments = InkSmoothing.segments(points)
        XCTAssertEqual(segments.count, 4)
        // Starts and ends exactly on the sampled ends.
        XCTAssertEqual(segments.first?.start, points[0])
        XCTAssertEqual(segments.last?.end, points[3])
        // Straight half-segments at the ends, curves in between, each bending
        // around its sampled point and keeping that point's width.
        XCTAssertNil(segments[0].control)
        XCTAssertEqual(segments[0].end, s(5, 0, 1.5))
        XCTAssertEqual(segments[1].control, points[1])
        XCTAssertEqual(segments[1].start, s(5, 0, 1.5))
        XCTAssertEqual(segments[1].end, s(10, 5, 2.5))
        XCTAssertEqual(segments[1].width, 2)
        XCTAssertEqual(segments[2].control, points[2])
        XCTAssertEqual(segments[2].width, 3)
        XCTAssertNil(segments[3].control)
        XCTAssertEqual(segments[3].width, 4)
        // Continuous: each piece starts where the last ended.
        for i in 1..<segments.count { XCTAssertEqual(segments[i].start, segments[i - 1].end) }
    }

    func testFromAStroke() {
        let stroke = LiveStroke(id: "S", ink: .pen, color: LiveColor(r: 0, g: 0, b: 0, a: 1), width: 2, points: [
            LivePoint(x: 0, y: 0, pressure: 1, timeOffset: 0, width: 1),
            LivePoint(x: 4, y: 4, pressure: 1, timeOffset: 0.01, width: 3),
            LivePoint(x: 8, y: 0, pressure: 1, timeOffset: 0.02, width: 5),
        ])
        XCTAssertEqual(InkSmoothing.segments(stroke).map(\.width), [1, 3, 5])
    }
}

final class VoiceIdlePolicyTests: XCTestCase {
    func testStaysInVoiceWhileActive() {
        var policy = VoiceIdlePolicy(now: 0)
        XCTAssertEqual(policy.check(at: 60, microphoneOn: true), .none)
        policy.noteActivity(at: 800)
        XCTAssertEqual(policy.check(at: 1_600, microphoneOn: true), .none, "ink at 800 s keeps it awake until 1,700 s")
        XCTAssertEqual(policy.state, .active)
    }

    func testAQuietRoomPausesAndResumesOnATap() {
        var policy = VoiceIdlePolicy(now: 0)
        XCTAssertEqual(policy.check(at: 899, microphoneOn: true), .none)
        XCTAssertEqual(policy.check(at: 900, microphoneOn: true), .leave)
        XCTAssertEqual(policy.state, .pausedQuiet)
        XCTAssertEqual(policy.check(at: 2_000, microphoneOn: true), .none, "left once")
        XCTAssertEqual(policy.becameActive(at: 2_000), .none, "a quiet pause waits for a tap, not for the app")
        policy.noteActivity(at: 2_100)
        XCTAssertEqual(policy.state, .pausedQuiet, "ink alone does not rejoin; it shows the tap to resume")
        XCTAssertEqual(policy.resume(at: 2_200), .rejoin(microphoneOn: true))
        XCTAssertEqual(policy.state, .active)
        XCTAssertEqual(policy.check(at: 2_200 + 899, microphoneOn: true), .none, "the quiet clock restarts")
        XCTAssertEqual(policy.resume(at: 2_300), .none)
    }

    func testTheBackgroundLeavesAfterTwoMinutesAndRejoinsWithTheMicAsItWas() {
        var policy = VoiceIdlePolicy(now: 0)
        policy.enteredBackground(at: 10)
        policy.enteredBackground(at: 50) // repeated notices keep the first time
        XCTAssertEqual(policy.check(at: 129, microphoneOn: false), .none)
        XCTAssertEqual(policy.check(at: 130, microphoneOn: false), .leave)
        XCTAssertEqual(policy.state, .leftInBackground(microphoneWasOn: false))
        XCTAssertEqual(policy.becameActive(at: 600), .rejoin(microphoneOn: false))
        XCTAssertEqual(policy.state, .active)
        XCTAssertNil(policy.backgroundSince)
        XCTAssertEqual(policy.check(at: 600 + 899, microphoneOn: true), .none, "coming back counts as activity")
    }

    func testABriefTripToTheBackgroundChangesNothing() {
        var policy = VoiceIdlePolicy(now: 0)
        policy.enteredBackground(at: 10)
        XCTAssertEqual(policy.becameActive(at: 60), .none)
        XCTAssertEqual(policy.check(at: 200, microphoneOn: true), .none)
    }

    func testSpeakingInTheBackgroundStillLeavesAfterTwoMinutes() {
        var policy = VoiceIdlePolicy(now: 0)
        policy.enteredBackground(at: 0)
        policy.noteActivity(at: 119)
        XCTAssertEqual(policy.check(at: 120, microphoneOn: true), .leave)
    }
}
