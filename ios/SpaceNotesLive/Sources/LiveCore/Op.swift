// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// A change to the notebook (protocol/PROTOCOL.md, "The reducer").
///
/// Decoding never throws for a well-formed JSON object: a kind this build does
/// not know becomes `.unknown`, and a known kind with a missing or mistyped
/// field becomes `.invalid`. Both keep the original JSON so they encode back
/// unchanged, both are no-ops in the reducer, and both are `invalid-op` to
/// `Permissions.authorize`.
public enum Op: Hashable, Sendable {
    case strokeAdd(pageId: String, stroke: LiveStroke)
    case strokeErase(pageId: String, strokeIds: [String])
    case strokeRestore(pageId: String, strokeIds: [String])
    case textUpsert(pageId: String, text: LiveText)
    case textErase(pageId: String, textIds: [String])
    case itemsMove(pageId: String, strokeIds: [String], textIds: [String], dx: Double, dy: Double)
    case pageAdd(page: LivePageSpec, afterPageId: String?)
    case roomPolicy(drawPolicy: String, penHolder: String?)
    case hostPage(pageId: String)
    case unknown(kind: String, raw: JSONValue)
    case invalid(kind: String?, raw: JSONValue)

    public enum Kind: String, CaseIterable, Sendable {
        case strokeAdd = "stroke.add"
        case strokeErase = "stroke.erase"
        case strokeRestore = "stroke.restore"
        case textUpsert = "text.upsert"
        case textErase = "text.erase"
        case itemsMove = "items.move"
        case pageAdd = "page.add"
        case roomPolicy = "room.policy"
        case hostPage = "host.page"
    }

    public var kind: String? {
        switch self {
        case .strokeAdd: return Kind.strokeAdd.rawValue
        case .strokeErase: return Kind.strokeErase.rawValue
        case .strokeRestore: return Kind.strokeRestore.rawValue
        case .textUpsert: return Kind.textUpsert.rawValue
        case .textErase: return Kind.textErase.rawValue
        case .itemsMove: return Kind.itemsMove.rawValue
        case .pageAdd: return Kind.pageAdd.rawValue
        case .roomPolicy: return Kind.roomPolicy.rawValue
        case .hostPage: return Kind.hostPage.rawValue
        case .unknown(let kind, _): return kind
        case .invalid(let kind, _): return kind
        }
    }

    public var pageId: String? {
        switch self {
        case .strokeAdd(let pageId, _), .strokeErase(let pageId, _), .strokeRestore(let pageId, _),
             .textUpsert(let pageId, _), .textErase(let pageId, _), .itemsMove(let pageId, _, _, _, _),
             .hostPage(let pageId):
            return pageId
        default:
            return nil
        }
    }
}

extension Op: Codable {
    enum CodingKeys: String, CodingKey {
        case kind, pageId, stroke, strokeIds, text, textIds, dx, dy, page, afterPageId, drawPolicy, penHolder
    }

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        guard case .object = raw, let kindName = raw["kind"]?.stringValue else {
            self = .invalid(kind: nil, raw: raw)
            return
        }
        guard let kind = Kind(rawValue: kindName) else {
            self = .unknown(kind: kindName, raw: raw)
            return
        }
        do {
            self = try Op.decodeTyped(kind, from: decoder.container(keyedBy: CodingKeys.self))
        } catch {
            self = .invalid(kind: kindName, raw: raw)
        }
    }

    private static func decodeTyped(_ kind: Kind, from c: KeyedDecodingContainer<CodingKeys>) throws -> Op {
        switch kind {
        case .strokeAdd:
            return .strokeAdd(pageId: try c.decode(String.self, forKey: .pageId),
                              stroke: try c.decode(LiveStroke.self, forKey: .stroke))
        case .strokeErase:
            return .strokeErase(pageId: try c.decode(String.self, forKey: .pageId),
                                strokeIds: try c.decode([String].self, forKey: .strokeIds))
        case .strokeRestore:
            return .strokeRestore(pageId: try c.decode(String.self, forKey: .pageId),
                                  strokeIds: try c.decode([String].self, forKey: .strokeIds))
        case .textUpsert:
            return .textUpsert(pageId: try c.decode(String.self, forKey: .pageId),
                               text: try c.decode(LiveText.self, forKey: .text))
        case .textErase:
            return .textErase(pageId: try c.decode(String.self, forKey: .pageId),
                              textIds: try c.decode([String].self, forKey: .textIds))
        case .itemsMove:
            // The id lists may be absent, but not null (as in the reference
            // validator).
            return .itemsMove(pageId: try c.decode(String.self, forKey: .pageId),
                              strokeIds: try optionalList(c, .strokeIds),
                              textIds: try optionalList(c, .textIds),
                              dx: try c.decode(Double.self, forKey: .dx),
                              dy: try c.decode(Double.self, forKey: .dy))
        case .pageAdd:
            return .pageAdd(page: try c.decode(LivePageSpec.self, forKey: .page),
                            afterPageId: try c.decodeIfPresent(String.self, forKey: .afterPageId))
        case .roomPolicy:
            return .roomPolicy(drawPolicy: try c.decode(String.self, forKey: .drawPolicy),
                               penHolder: try c.decodeIfPresent(String.self, forKey: .penHolder))
        case .hostPage:
            return .hostPage(pageId: try c.decode(String.self, forKey: .pageId))
        }
    }

    private static func optionalList(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [String] {
        guard c.contains(key) else { return [] }
        return try c.decode([String].self, forKey: key)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .unknown(_, let raw), .invalid(_, let raw):
            try raw.encode(to: encoder)
            return
        default:
            break
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .strokeAdd(let pageId, let stroke):
            try c.encode(pageId, forKey: .pageId)
            try c.encode(stroke, forKey: .stroke)
        case .strokeErase(let pageId, let ids), .strokeRestore(let pageId, let ids):
            try c.encode(pageId, forKey: .pageId)
            try c.encode(ids, forKey: .strokeIds)
        case .textUpsert(let pageId, let text):
            try c.encode(pageId, forKey: .pageId)
            try c.encode(text, forKey: .text)
        case .textErase(let pageId, let ids):
            try c.encode(pageId, forKey: .pageId)
            try c.encode(ids, forKey: .textIds)
        case .itemsMove(let pageId, let strokeIds, let textIds, let dx, let dy):
            try c.encode(pageId, forKey: .pageId)
            try c.encode(strokeIds, forKey: .strokeIds)
            try c.encode(textIds, forKey: .textIds)
            try c.encode(dx, forKey: .dx)
            try c.encode(dy, forKey: .dy)
        case .pageAdd(let page, let afterPageId):
            try c.encode(page, forKey: .page)
            try c.encodeIfPresent(afterPageId, forKey: .afterPageId)
        case .roomPolicy(let drawPolicy, let penHolder):
            try c.encode(drawPolicy, forKey: .drawPolicy)
            try c.encodeIfPresent(penHolder, forKey: .penHolder)
        case .hostPage(let pageId):
            try c.encode(pageId, forKey: .pageId)
        case .unknown, .invalid:
            break
        }
    }
}

/// An op as the server numbered it.
public struct SequencedOp: Codable, Hashable, Sendable {
    public var seq: Int
    public var author: String
    public var clientOpId: String?
    public var op: Op

    public init(seq: Int, author: String, clientOpId: String? = nil, op: Op) {
        self.seq = seq
        self.author = author
        self.clientOpId = clientOpId
        self.op = op
    }
}
