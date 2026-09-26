// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CreatedRoom: Codable, Hashable, Sendable {
    public var roomId: String
    public var code: String
    public var joinUrl: String
}

public struct RoomLookup: Codable, Hashable, Sendable {
    public var roomId: String
    public var title: String
    public var hostName: String
    public var allowGuests: Bool
}

/// A LiveKit ticket for the room's video and voice.
public struct VideoTicket: Codable, Hashable, Sendable {
    public var url: String
    public var token: String
}

public enum LiveAPIError: Error, Equatable, Sendable {
    /// A non-2xx answer, with the server's error code when it gave one.
    case http(status: Int, code: String?)
    case badResponse
}

/// The room server's HTTP API (protocol/PROTOCOL.md, "HTTP API"). Every call
/// carries the Firebase ID token from `tokenProvider`.
public final class LiveAPI: @unchecked Sendable {
    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public let baseURL: URL
    private let tokenProvider: @Sendable () async throws -> String
    private let http: HTTP

    public init(baseURL: URL,
                tokenProvider: @escaping @Sendable () async throws -> String,
                http: HTTP? = nil) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.http = http ?? LiveAPI.urlSession(.shared)
    }

    /// Room codes use this alphabet (no 0, O, 1 or I).
    public static let codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    /// Upper-cases a typed code and keeps only valid characters.
    public static func normalizeCode(_ text: String) -> String {
        String(text.uppercased().filter { codeAlphabet.contains($0) }.prefix(6))
    }

    public func createRoom(title: String, pages: [LiveStartingPage], allowGuests: Bool) async throws -> CreatedRoom {
        struct Body: Encodable { var title: String; var pages: [LiveStartingPage]; var allowGuests: Bool }
        let body = try LiveJSON.encoder.encode(Body(title: title, pages: pages, allowGuests: allowGuests))
        let (data, _) = try await call("POST", "rooms", body: body, contentType: "application/json")
        return try decode(CreatedRoom.self, data)
    }

    public func lookup(code: String) async throws -> RoomLookup {
        let (data, _) = try await call("GET", "rooms/code/\(LiveAPI.normalizeCode(code))")
        return try decode(RoomLookup.self, data)
    }

    /// nil when the server has no video (503 `video-unavailable`): the room
    /// carries on with ink only.
    public func videoToken(roomId: String) async throws -> VideoTicket? {
        do {
            let (data, _) = try await call("POST", "rooms/\(escaped(roomId))/video-token")
            return try decode(VideoTicket.self, data)
        } catch LiveAPIError.http(status: 503, _) {
            return nil
        }
    }

    /// Host only: a page picture (PNG or JPEG, at most 8 MiB).
    public func uploadAsset(roomId: String, assetId: String, data: Data, contentType: String) async throws {
        _ = try await call("PUT", "rooms/\(escaped(roomId))/assets/\(escaped(assetId))", body: data, contentType: contentType)
    }

    public func asset(roomId: String, assetId: String) async throws -> Data {
        try await call("GET", "rooms/\(escaped(roomId))/assets/\(escaped(assetId))").0
    }

    /// Host only: the room as it is now, for saving back into the notebook.
    /// PROTOCOL.md says the body is the room state; the server wraps it as
    /// `{ room, ended, state }`. Both are read.
    public func snapshot(roomId: String) async throws -> RoomState {
        let (data, _) = try await call("GET", "rooms/\(escaped(roomId))/snapshot")
        struct Wrapped: Decodable { var state: RoomState }
        if let wrapped = try? LiveJSON.decoder.decode(Wrapped.self, from: data) { return wrapped.state }
        return try decode(RoomState.self, data)
    }

    // MARK: Plumbing

    private func escaped(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? component
    }

    private func call(_ method: String, _ path: String, body: Data? = nil, contentType: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        let (data, response) = try await http(request)
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? LiveJSON.decoder.decode(JSONValue.self, from: data))?["error"]?.stringValue
            throw LiveAPIError.http(status: response.statusCode, code: code)
        }
        return (data, response)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try LiveJSON.decoder.decode(type, from: data) } catch { throw LiveAPIError.badResponse }
    }

    /// URLSession through a continuation, which works the same on Apple
    /// platforms and Linux.
    public static func urlSession(_ session: URLSession) -> HTTP {
        { request in
            try await withCheckedThrowingContinuation { continuation in
                session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let response = response as? HTTPURLResponse {
                        continuation.resume(returning: (data ?? Data(), response))
                    } else {
                        continuation.resume(throwing: LiveAPIError.badResponse)
                    }
                }.resume()
            }
        }
    }
}
