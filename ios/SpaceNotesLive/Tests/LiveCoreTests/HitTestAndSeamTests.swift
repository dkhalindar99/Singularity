// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LiveCore

final class HitTestAndSeamTests: XCTestCase {
    private let black = LiveColor(r: 0, g: 0, b: 0, a: 1)

    private func line(_ id: String, erased: Bool = false) -> LiveStrokeItem {
        LiveStrokeItem(author: "a", seq: 1, erased: erased, stroke: LiveStroke(id: id, ink: .pen, color: black, width: 4, points: [
            LivePoint(x: 0, y: 0, pressure: 1, timeOffset: 0, width: 4),
            LivePoint(x: 100, y: 0, pressure: 1, timeOffset: 0.1, width: 4),
        ]))
    }

    func testStrokeHits() {
        let page = LivePage(spec: LivePageSpec(id: "p", width: 200, height: 200), strokes: [line("A"), line("B", erased: true)])
        XCTAssertEqual(LiveHitTest.strokes(on: page, x: 50, y: 5, radius: 4), ["A"], "within radius + half width; erased ignored")
        XCTAssertEqual(LiveHitTest.strokes(on: page, x: 50, y: 7, radius: 4), [])
        XCTAssertEqual(LiveHitTest.strokes(on: page, x: 105, y: 0, radius: 4), ["A"], "past the end, within reach")
    }

    func testTextHits() {
        let text = LiveText(id: "T", text: "x", frame: LiveFrame(x: 10, y: 10, width: 50, height: 20), fontSize: 12, color: black)
        let page = LivePage(spec: LivePageSpec(id: "p", width: 200, height: 200), texts: [LiveTextItem(author: "a", seq: 1, text: text)])
        XCTAssertEqual(LiveHitTest.text(on: page, x: 20, y: 20)?.id, "T")
        XCTAssertNil(LiveHitTest.text(on: page, x: 70, y: 20))
    }

    private final class Source: LiveNotebookSource {
        let title = "Cardiology"
        func livePages() async throws -> [LiveSourcePage] {
            [LiveSourcePage(spec: LivePageSpec(id: "P1", width: 595, height: 842), backgroundImage: Data([9, 9]), backgroundImageType: "image/png"),
             LiveSourcePage(spec: LivePageSpec(id: "P2", width: 595, height: 842, background: .template(.grid)))]
        }
    }

    private final class Recorder: @unchecked Sendable { var requests: [URLRequest] = [] }

    func testHostingCreatesTheRoomThenUploadsPictures() async throws {
        let recorder = Recorder()
        let api = LiveAPI(baseURL: URL(string: "https://live.example.com")!, tokenProvider: { "tok" }, http: { request in
            recorder.requests.append(request)
            let body = request.httpMethod == "POST" ? #"{"roomId":"r1","code":"K7QM3X","joinUrl":"j"}"# : ""
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let created = try await LiveRoomHosting.createRoom(from: Source(), api: api, allowGuests: false)
        XCTAssertEqual(created.roomId, "r1")
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["POST", "PUT"])
        let body = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(recorder.requests[0].httpBody))
        guard case .array(let pages) = body["pages"] else { return XCTFail() }
        let assetId = try XCTUnwrap(pages[0]["background"]?["assetId"]?.stringValue)
        XCTAssertEqual(pages[0]["background"]?["kind"], .string("image"))
        XCTAssertEqual(pages[1]["background"]?["template"], .string("grid"))
        XCTAssertEqual(recorder.requests[1].url?.path, "/rooms/r1/assets/\(assetId)")
        XCTAssertEqual(recorder.requests[1].httpBody, Data([9, 9]))
    }

    func testSessionResultDropsErasedItems() {
        let state = RoomState(pages: [LivePage(spec: LivePageSpec(id: "p", width: 1, height: 1), strokes: [line("A"), line("B", erased: true)])])
        let result = LiveSessionResult(roomId: "r", title: "t", wasHost: true, reason: "left", state: state)
        XCTAssertEqual(result.pages[0].strokes.map(\.id), ["A"])
    }
}
