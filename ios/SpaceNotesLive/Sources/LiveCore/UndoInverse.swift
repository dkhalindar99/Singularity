// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// One undoable step: what undo sends and what redo sends. Both are fixed when
/// the op is first sent, against the state just before it. Undo and redo go
/// out as new ops, so they are shared and ordered by the server like
/// everything else.
public struct UndoPair: Hashable, Sendable {
    public var undo: [Op]
    public var redo: [Op]

    public init(undo: [Op], redo: [Op]) {
        self.undo = undo
        self.redo = redo
    }
}

public enum UndoInverse {
    /// The undo/redo pair for an op, or nil when it is not undoable or would
    /// undo nothing.
    public static func pair(for op: Op, in state: RoomState) -> UndoPair? {
        guard let undo = of(op, in: state), !undo.isEmpty else { return nil }
        switch op {
        case .strokeAdd(let pageId, let stroke):
            // Re-sending stroke.add would do nothing: the undone stroke is
            // still on the page, erased. Redo restores it.
            return UndoPair(undo: undo, redo: [.strokeRestore(pageId: pageId, strokeIds: [stroke.id])])
        default:
            return UndoPair(undo: undo, redo: [op])
        }
    }

    /// nil when the op is not undoable (pages, policy, host page); an empty
    /// list when it would change nothing.
    public static func of(_ op: Op, in state: RoomState) -> [Op]? {
        switch op {
        case .strokeAdd(let pageId, let stroke):
            return [.strokeErase(pageId: pageId, strokeIds: [stroke.id])]

        case .strokeErase(let pageId, let ids):
            // Only what this op actually hid: a stroke someone else had already
            // erased stays erased after the undo.
            guard let page = state.page(pageId) else { return [] }
            let hidden = ids.filter { id in page.strokes.contains { $0.stroke.id == id && !$0.erased } }
            return hidden.isEmpty ? [] : [.strokeRestore(pageId: pageId, strokeIds: hidden)]

        case .strokeRestore(let pageId, let ids):
            guard let page = state.page(pageId) else { return [] }
            let shown = ids.filter { id in page.strokes.contains { $0.stroke.id == id && $0.erased } }
            return shown.isEmpty ? [] : [.strokeErase(pageId: pageId, strokeIds: shown)]

        case .itemsMove(let pageId, let strokeIds, let textIds, let dx, let dy):
            return [.itemsMove(pageId: pageId, strokeIds: strokeIds, textIds: textIds, dx: -dx, dy: -dy)]

        case .textUpsert(let pageId, let text):
            if let existing = state.page(pageId)?.texts.first(where: { $0.text.id == text.id }), !existing.erased {
                return [.textUpsert(pageId: pageId, text: existing.text)]
            }
            return [.textErase(pageId: pageId, textIds: [text.id])]

        case .textErase(let pageId, let ids):
            guard let page = state.page(pageId) else { return [] }
            return ids.compactMap { id in
                guard let item = page.texts.first(where: { $0.text.id == id && !$0.erased }) else { return nil }
                return .textUpsert(pageId: pageId, text: item.text)
            }

        case .pageAdd, .roomPolicy, .hostPage, .unknown, .invalid:
            return nil
        }
    }
}
