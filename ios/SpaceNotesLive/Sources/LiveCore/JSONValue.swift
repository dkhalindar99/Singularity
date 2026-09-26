// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// Any JSON value. Used to carry parts of a message this client does not
/// understand (an unknown op kind) so they can be sent back unchanged, and to
/// compare frames by value in tests.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// The same value with every `null` object field removed, recursively.
    /// The protocol says a missing field equals `null`, so comparisons go
    /// through this.
    public var droppingNulls: JSONValue {
        switch self {
        case .object(let fields):
            var kept: [String: JSONValue] = [:]
            for (key, value) in fields where value != .null { kept[key] = value.droppingNulls }
            return .object(kept)
        case .array(let values):
            return .array(values.map(\.droppingNulls))
        default:
            return self
        }
    }

    /// Protocol equality: by value, missing field == null.
    public func protocolEquals(_ other: JSONValue) -> Bool {
        droppingNulls == other.droppingNulls
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    /// Re-encodes any Encodable as a JSONValue.
    public init<T: Encodable>(encoding value: T) throws {
        let data = try LiveJSON.encoder.encode(value)
        self = try LiveJSON.decoder.decode(JSONValue.self, from: data)
    }

    /// Decodes a typed value from this JSON.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try LiveJSON.decoder.decode(type, from: LiveJSON.encoder.encode(self))
    }
}

/// The encoder and decoder every frame goes through. Sorted keys keep frames
/// stable, which makes logs and tests easier to read; the protocol itself
/// does not care about key order.
public enum LiveJSON {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static var decoder: JSONDecoder { JSONDecoder() }

    public static func encodeString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try decoder.decode(type, from: Data(text.utf8))
    }
}
