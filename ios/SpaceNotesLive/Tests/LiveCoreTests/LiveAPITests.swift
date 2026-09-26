// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LiveCore

final class LiveAPITests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var requests: [URLRequest] = []
        var answer: (Int, String) = (200, "{}")
    }

    private func api(_ recorder: Recorder) -> LiveAPI {
        LiveAPI(baseURL: URL(string: "https://live.example.com")!, tokenProvider: { "tok" }, http: { request in
            recorder.requests.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: recorder.answer.0, httpVersion: nil, headerFields: nil)!
            return (Data(recorder.answer.1.utf8), response)
        })
    }

    func testCreateRoom() async throws {
        let recorder = Recorder()
        recorder.answer = (200, #"{"roomId":"r1","code":"K7QM3X","joinUrl":"https://web/join/K7QM3X"}"#)
        let page = LiveStartingPage(spec: LivePageSpec(id: "P1", width: 595, height: 842, background: .image(assetId: "a1")))
        let created = try await api(recorder).createRoom(title: "Cardiology", pages: [page], allowGuests: true)
        XCTAssertEqual(created.code, "K7QM3X")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://live.example.com/rooms")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["title"], .string("Cardiology"))
        XCTAssertEqual(body["allowGuests"], .bool(true))
        XCTAssertEqual(body["pages"], .array([.object([
            "id": .string("P1"), "width": .number(595), "height": .number(842),
            "background": .object(["kind": .string("image"), "assetId": .string("a1")]),
            "strokes": .array([]), "texts": .array([]),
        ])]))
    }

    func testLookupNormalisesTheCode() async throws {
        let recorder = Recorder()
        recorder.answer = (200, #"{"roomId":"r1","title":"T","hostName":"Host","allowGuests":false}"#)
        let lookup = try await api(recorder).lookup(code: " k7q-m3x ")
        XCTAssertEqual(lookup.roomId, "r1")
        XCTAssertEqual(recorder.requests.first?.url?.absoluteString, "https://live.example.com/rooms/code/K7QM3X")
    }

    func testVideoTokenIsNilWhenVideoIsUnavailable() async throws {
        let recorder = Recorder()
        recorder.answer = (503, #"{"error":"video-unavailable"}"#)
        let ticket = try await api(recorder).videoToken(roomId: "r1")
        XCTAssertNil(ticket)
        recorder.answer = (200, #"{"url":"wss://lk","token":"t"}"#)
        let real = try await api(recorder).videoToken(roomId: "r1")
        XCTAssertEqual(real, VideoTicket(url: "wss://lk", token: "t"))
    }

    func testErrorsCarryTheServerCode() async {
        let recorder = Recorder()
        recorder.answer = (404, #"{"error":"no-such-room"}"#)
        do {
            _ = try await api(recorder).snapshot(roomId: "r1")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LiveAPIError, .http(status: 404, code: "no-such-room"))
        }
    }

    func testUploadAndSnapshot() async throws {
        let recorder = Recorder()
        try await api(recorder).uploadAsset(roomId: "r1", assetId: "a1", data: Data([1, 2, 3]), contentType: "image/png")
        XCTAssertEqual(recorder.requests.last?.httpMethod, "PUT")
        XCTAssertEqual(recorder.requests.last?.url?.path, "/rooms/r1/assets/a1")
        XCTAssertEqual(recorder.requests.last?.value(forHTTPHeaderField: "Content-Type"), "image/png")

        recorder.answer = (200, #"{"protocol":1,"seq":3,"drawPolicy":"everyone","penHolder":null,"hostPageId":null,"pages":[]}"#)
        let state = try await api(recorder).snapshot(roomId: "r1")
        XCTAssertEqual(state.seq, 3)

        recorder.answer = (200, #"{"room":{"id":"r1"},"ended":false,"state":{"protocol":1,"seq":4,"drawPolicy":"everyone","penHolder":null,"hostPageId":null,"pages":[]}}"#)
        let wrapped = try await api(recorder).snapshot(roomId: "r1")
        XCTAssertEqual(wrapped.seq, 4)
    }

    func testCodeAlphabet() {
        XCTAssertEqual(LiveAPI.normalizeCode("o0i1abc"), "ABC")
    }
}
