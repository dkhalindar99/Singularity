// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

// protocol/PROTOCOL.md, "Messages". Every frame is one JSON object with a
// `type`. Unknown types and unknown fields are ignored, so a newer server can
// talk to this client.

// MARK: - Shared pieces

/// Someone in the room, as the server lists them.
public struct Member: Codable, Hashable, Sendable, Identifiable {
    public var uid: String
    public var connectionId: String
    public var name: String
    public var role: String
    /// `#RRGGBB`, chosen by the server so everyone sees the same colour.
    public var color: String
    public var handRaised: Bool
    public var pageId: String?

    public init(uid: String, connectionId: String, name: String, role: String, color: String,
                handRaised: Bool = false, pageId: String? = nil) {
        self.uid = uid
        self.connectionId = connectionId
        self.name = name
        self.role = role
        self.color = color
        self.handRaised = handRaised
        self.pageId = pageId
    }

    enum CodingKeys: String, CodingKey { case uid, connectionId, name, role, color, handRaised, pageId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        connectionId = try c.decode(String.self, forKey: .connectionId)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(String.self, forKey: .role)
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#6B7280"
        handRaised = try c.decodeIfPresent(Bool.self, forKey: .handRaised) ?? false
        pageId = try c.decodeIfPresent(String.self, forKey: .pageId)
    }

    public var id: String { connectionId }
    public var isHost: Bool { role == "host" }
    public var participant: Participant { Participant(uid: uid, role: role) }
}

/// This connection, as the server sees it.
public struct You: Codable, Hashable, Sendable {
    public var uid: String
    public var connectionId: String
    public var name: String
    public var role: String
    public var color: String

    public init(uid: String, connectionId: String, name: String, role: String, color: String) {
        self.uid = uid
        self.connectionId = connectionId
        self.name = name
        self.role = role
        self.color = color
    }

    public var isHost: Bool { role == "host" }
    public var participant: Participant { Participant(uid: uid, role: role) }
}

public struct RoomInfo: Codable, Hashable, Sendable {
    public var id: String
    public var code: String
    public var title: String
    public var hostUid: String

    public init(id: String, code: String, title: String, hostUid: String) {
        self.id = id
        self.code = code
        self.title = title
        self.hostUid = hostUid
    }
}

// MARK: - Presence

/// Points of a stroke still being drawn.
public struct LiveInkPresence: Codable, Hashable, Sendable {
    public var pageId: String
    /// The stroke's future id.
    public var liveId: String
    public var ink: String
    public var color: LiveColor
    public var width: Double
    /// Flat `[x, y, w, x, y, w, …]`, only the points since the last message.
    public var p: [Double]
    public var done: Bool

    public init(pageId: String, liveId: String, ink: String, color: LiveColor, width: Double, p: [Double], done: Bool) {
        self.pageId = pageId
        self.liveId = liveId
        self.ink = ink
        self.color = color
        self.width = width
        self.p = p
        self.done = done
    }
}

public enum Presence: Hashable, Sendable {
    case inkLive(LiveInkPresence)
    case pointer(pageId: String, x: Double, y: Double, laser: Bool)
    case pointerHide
    case view(pageId: String)
    case hand(raised: Bool)
    /// A kind this build does not know, or a known kind it could not read.
    case unknown(kind: String?, raw: JSONValue)
}

extension Presence: Codable {
    enum CodingKeys: String, CodingKey { case kind, pageId, x, y, laser, raised }

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        let kind = raw["kind"]?.stringValue
        do {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch kind {
            case "ink.live":
                self = .inkLive(try LiveInkPresence(from: decoder))
            case "pointer":
                self = .pointer(pageId: try c.decode(String.self, forKey: .pageId),
                                x: try c.decode(Double.self, forKey: .x),
                                y: try c.decode(Double.self, forKey: .y),
                                laser: try c.decodeIfPresent(Bool.self, forKey: .laser) ?? false)
            case "pointer.hide":
                self = .pointerHide
            case "view":
                self = .view(pageId: try c.decode(String.self, forKey: .pageId))
            case "hand":
                self = .hand(raised: try c.decode(Bool.self, forKey: .raised))
            default:
                self = .unknown(kind: kind, raw: raw)
            }
        } catch {
            self = .unknown(kind: kind, raw: raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .unknown(_, let raw) = self {
            try raw.encode(to: encoder)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inkLive(let ink):
            try c.encode("ink.live", forKey: .kind)
            try ink.encode(to: encoder)
        case .pointer(let pageId, let x, let y, let laser):
            try c.encode("pointer", forKey: .kind)
            try c.encode(pageId, forKey: .pageId)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
            try c.encode(laser, forKey: .laser)
        case .pointerHide:
            try c.encode("pointer.hide", forKey: .kind)
        case .view(let pageId):
            try c.encode("view", forKey: .kind)
            try c.encode(pageId, forKey: .pageId)
        case .hand(let raised):
            try c.encode("hand", forKey: .kind)
            try c.encode(raised, forKey: .raised)
        case .unknown:
            break
        }
    }
}

// MARK: - Control

public enum Control: Hashable, Sendable {
    case remove(uid: String)
    case end
    case unknown(raw: JSONValue)
}

extension Control: Codable {
    enum CodingKeys: String, CodingKey { case kind, uid }

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        switch raw["kind"]?.stringValue {
        case "remove":
            if let uid = raw["uid"]?.stringValue { self = .remove(uid: uid) } else { self = .unknown(raw: raw) }
        case "end":
            self = .end
        default:
            self = .unknown(raw: raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .remove(let uid):
            try c.encode("remove", forKey: .kind)
            try c.encode(uid, forKey: .uid)
        case .end:
            try c.encode("end", forKey: .kind)
        case .unknown(let raw):
            try raw.encode(to: encoder)
        }
    }
}

// MARK: - Client → server

public struct Hello: Codable, Hashable, Sendable {
    public var `protocol`: Int
    public var token: String
    public var roomId: String
    public var name: String
    public var deviceId: String

    public init(protocol: Int = RoomState.protocolVersion, token: String, roomId: String, name: String, deviceId: String) {
        self.protocol = `protocol`
        self.token = token
        self.roomId = roomId
        self.name = name
        self.deviceId = deviceId
    }
}

public enum ClientMessage: Hashable, Sendable {
    case hello(Hello)
    case op(clientOpId: String, op: Op)
    case presence(Presence)
    case control(Control)
    case ping(t: Double)
    case unknown(type: String?, raw: JSONValue)
}

extension ClientMessage: Codable {
    enum CodingKeys: String, CodingKey { case type, clientOpId, op, presence, control, t }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "hello": self = .hello(try Hello(from: decoder))
        case "op": self = .op(clientOpId: try c.decode(String.self, forKey: .clientOpId), op: try c.decode(Op.self, forKey: .op))
        case "presence": self = .presence(try c.decode(Presence.self, forKey: .presence))
        case "control": self = .control(try c.decode(Control.self, forKey: .control))
        case "ping": self = .ping(t: try c.decode(Double.self, forKey: .t))
        default: self = .unknown(type: type, raw: try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let hello):
            try c.encode("hello", forKey: .type)
            try hello.encode(to: encoder)
        case .op(let clientOpId, let op):
            try c.encode("op", forKey: .type)
            try c.encode(clientOpId, forKey: .clientOpId)
            try c.encode(op, forKey: .op)
        case .presence(let presence):
            try c.encode("presence", forKey: .type)
            try c.encode(presence, forKey: .presence)
        case .control(let control):
            try c.encode("control", forKey: .type)
            try c.encode(control, forKey: .control)
        case .ping(let t):
            try c.encode("ping", forKey: .type)
            try c.encode(t, forKey: .t)
        case .unknown(_, let raw):
            try raw.encode(to: encoder)
        }
    }
}

// MARK: - Server → client

public struct Welcome: Codable, Hashable, Sendable {
    public var `protocol`: Int
    public var you: You
    public var room: RoomInfo
    public var state: RoomState
    public var members: [Member]

    public init(protocol: Int = RoomState.protocolVersion, you: You, room: RoomInfo, state: RoomState, members: [Member]) {
        self.protocol = `protocol`
        self.you = you
        self.room = room
        self.state = state
        self.members = members
    }
}

public struct PresenceSender: Codable, Hashable, Sendable {
    public var uid: String
    public var connectionId: String

    public init(uid: String, connectionId: String) {
        self.uid = uid
        self.connectionId = connectionId
    }
}

public enum ServerMessage: Hashable, Sendable {
    case welcome(Welcome)
    case op(SequencedOp)
    case reject(clientOpId: String, reason: String)
    case members([Member])
    case presence(from: PresenceSender, presence: Presence)
    case removed(reason: String)
    case error(code: String, message: String)
    case pong(t: Double)
    /// A type this build does not know. Ignored.
    case unknown(type: String?)

    public static let rejectDuplicate = "duplicate"
    public static let removedByHost = "removed-by-host"
    public static let roomEnded = "room-ended"
}

extension ServerMessage: Codable {
    enum CodingKeys: String, CodingKey { case type, clientOpId, reason, members, from, presence, code, message, t }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "welcome":
            self = .welcome(try Welcome(from: decoder))
        case "op":
            self = .op(try SequencedOp(from: decoder))
        case "reject":
            self = .reject(clientOpId: try c.decode(String.self, forKey: .clientOpId),
                           reason: try c.decodeIfPresent(String.self, forKey: .reason) ?? "")
        case "members":
            self = .members(try c.decode([Member].self, forKey: .members))
        case "presence":
            self = .presence(from: try c.decode(PresenceSender.self, forKey: .from),
                             presence: try c.decode(Presence.self, forKey: .presence))
        case "removed":
            self = .removed(reason: try c.decodeIfPresent(String.self, forKey: .reason) ?? "")
        case "error":
            self = .error(code: try c.decodeIfPresent(String.self, forKey: .code) ?? "",
                          message: try c.decodeIfPresent(String.self, forKey: .message) ?? "")
        case "pong":
            self = .pong(t: try c.decodeIfPresent(Double.self, forKey: .t) ?? 0)
        default:
            self = .unknown(type: type)
        }
    }

    /// Servers write these; the client encodes them only in tests and fakes.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .welcome(let welcome):
            try c.encode("welcome", forKey: .type)
            try welcome.encode(to: encoder)
        case .op(let op):
            try c.encode("op", forKey: .type)
            try op.encode(to: encoder)
        case .reject(let clientOpId, let reason):
            try c.encode("reject", forKey: .type)
            try c.encode(clientOpId, forKey: .clientOpId)
            try c.encode(reason, forKey: .reason)
        case .members(let members):
            try c.encode("members", forKey: .type)
            try c.encode(members, forKey: .members)
        case .presence(let from, let presence):
            try c.encode("presence", forKey: .type)
            try c.encode(from, forKey: .from)
            try c.encode(presence, forKey: .presence)
        case .removed(let reason):
            try c.encode("removed", forKey: .type)
            try c.encode(reason, forKey: .reason)
        case .error(let code, let message):
            try c.encode("error", forKey: .type)
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
        case .pong(let t):
            try c.encode("pong", forKey: .type)
            try c.encode(t, forKey: .t)
        case .unknown(let type):
            try c.encodeIfPresent(type, forKey: .type)
        }
    }
}
