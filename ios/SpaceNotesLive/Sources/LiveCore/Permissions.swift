// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// Who is asking, for a permission check.
public struct LiveParticipant: Codable, Hashable, Sendable {
    public var uid: String
    public var role: String

    public init(uid: String, role: String) {
        self.uid = uid
        self.role = role
    }

    public var isHost: Bool { role == "host" }
}

/// protocol/PROTOCOL.md, "Permissions" — a port of web/src/core/permissions.js.
/// The server's answer is the one that counts; the client uses this only to
/// grey out its tools.
public enum Permissions {
    public static let notHost = "not-host"
    public static let drawingLocked = "drawing-locked"
    public static let invalidOp = "invalid-op"
    public static let maximumStrokePoints = 5000

    /// True if this member may change the notebook's content right now.
    public static func canDraw(state: RoomState, member: LiveParticipant) -> Bool {
        if member.isHost { return true }
        if state.drawPolicy == DrawPolicy.everyone.rawValue { return true }
        return state.drawPolicy == DrawPolicy.pen.rawValue && state.penHolder == member.uid
    }

    /// nil means allowed; otherwise `not-host`, `drawing-locked` or `invalid-op`.
    public static func authorize(state: RoomState, member: LiveParticipant, op: Op) -> String? {
        guard isValid(op) else { return invalidOp }
        switch op {
        case .roomPolicy, .hostPage, .pageAdd:
            return member.isHost ? nil : notHost
        default:
            return canDraw(state: state, member: member) ? nil : drawingLocked
        }
    }

    /// Checks what typed decoding cannot: non-empty strings, finite numbers,
    /// point counts, known policies. Missing and mistyped fields have already
    /// made the op `.invalid`.
    public static func isValid(_ op: Op) -> Bool {
        switch op {
        case .strokeAdd(let pageId, let stroke):
            return nonEmpty(pageId) && isValid(stroke)
        case .strokeErase(let pageId, let ids), .strokeRestore(let pageId, let ids), .textErase(let pageId, let ids):
            return nonEmpty(pageId) && ids.allSatisfy(nonEmpty)
        case .textUpsert(let pageId, let text):
            return nonEmpty(pageId) && isValid(text)
        case .itemsMove(let pageId, let strokeIds, let textIds, let dx, let dy):
            return nonEmpty(pageId) && dx.isFinite && dy.isFinite
                && strokeIds.allSatisfy(nonEmpty) && textIds.allSatisfy(nonEmpty)
        case .pageAdd(let page, let afterPageId):
            return isValid(page) && (afterPageId == nil || nonEmpty(afterPageId!))
        case .roomPolicy(let drawPolicy, let penHolder):
            return DrawPolicy(rawValue: drawPolicy) != nil && (penHolder == nil || nonEmpty(penHolder!))
        case .hostPage(let pageId):
            return nonEmpty(pageId)
        case .unknown, .invalid:
            return false
        }
    }

    public static func isValid(_ stroke: LiveStroke) -> Bool {
        guard nonEmpty(stroke.id), nonEmpty(stroke.ink), isValid(stroke.color), stroke.width.isFinite else { return false }
        guard !stroke.points.isEmpty, stroke.points.count <= maximumStrokePoints else { return false }
        return stroke.points.allSatisfy { p in
            p.x.isFinite && p.y.isFinite && p.pressure.isFinite && p.timeOffset.isFinite && p.width.isFinite
        }
    }

    public static func isValid(_ text: LiveText) -> Bool {
        nonEmpty(text.id) && text.fontSize.isFinite && isValid(text.color)
            && text.frame.x.isFinite && text.frame.y.isFinite && text.frame.width.isFinite && text.frame.height.isFinite
    }

    public static func isValid(_ page: LivePageSpec) -> Bool {
        nonEmpty(page.id) && page.width.isFinite && page.height.isFinite && page.width > 0 && page.height > 0
            && nonEmpty(page.background.kind)
    }

    private static func isValid(_ color: LiveColor) -> Bool {
        color.r.isFinite && color.g.isFinite && color.b.isFinite && color.a.isFinite
    }

    private static func nonEmpty(_ value: String) -> Bool { !value.isEmpty }
}
