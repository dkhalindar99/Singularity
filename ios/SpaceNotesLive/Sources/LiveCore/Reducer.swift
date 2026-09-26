// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// protocol/PROTOCOL.md, "The reducer" — a port of web/src/core/reducer.js.
/// Pure and deterministic; it never fails, and does not check permissions
/// (the server does that before sequencing).
public enum Reducer {
    public static func apply(_ state: RoomState, _ sequenced: SequencedOp) -> RoomState {
        var next = state
        applyInPlace(&next, sequenced)
        return next
    }

    public static func apply(_ state: RoomState, seq: Int, author: String, op: Op) -> RoomState {
        apply(state, SequencedOp(seq: seq, author: author, op: op))
    }

    public static func applyInPlace(_ state: inout RoomState, _ sequenced: SequencedOp) {
        let seq = sequenced.seq
        let author = sequenced.author
        state.seq = seq
        let pageIndex = sequenced.op.pageId.flatMap { id in state.pages.firstIndex { $0.id == id } }

        switch sequenced.op {
        case .strokeAdd(_, let stroke):
            guard let index = pageIndex else { return }
            if state.pages[index].strokes.contains(where: { $0.stroke.id == stroke.id }) { return }
            state.pages[index].strokes.append(LiveStrokeItem(author: author, seq: seq, erased: false, stroke: stroke))

        case .strokeErase(_, let ids), .strokeRestore(_, let ids):
            guard let index = pageIndex else { return }
            let erased: Bool
            if case .strokeErase = sequenced.op { erased = true } else { erased = false }
            let wanted = Set(ids)
            for i in state.pages[index].strokes.indices where wanted.contains(state.pages[index].strokes[i].stroke.id) {
                state.pages[index].strokes[i].erased = erased
            }

        case .textUpsert(_, let text):
            guard let index = pageIndex else { return }
            if let existing = state.pages[index].texts.firstIndex(where: { $0.text.id == text.id }) {
                state.pages[index].texts[existing].text = text
                state.pages[index].texts[existing].erased = false
            } else {
                state.pages[index].texts.append(LiveTextItem(author: author, seq: seq, erased: false, text: text))
            }

        case .textErase(_, let ids):
            guard let index = pageIndex else { return }
            let wanted = Set(ids)
            for i in state.pages[index].texts.indices where wanted.contains(state.pages[index].texts[i].text.id) {
                state.pages[index].texts[i].erased = true
            }

        case .itemsMove(_, let strokeIds, let textIds, let dx, let dy):
            guard let index = pageIndex else { return }
            let strokes = Set(strokeIds)
            let texts = Set(textIds)
            // Erased items are not moved: erase wins.
            for i in state.pages[index].strokes.indices {
                let item = state.pages[index].strokes[i]
                guard !item.erased, strokes.contains(item.stroke.id) else { continue }
                for p in state.pages[index].strokes[i].stroke.points.indices {
                    state.pages[index].strokes[i].stroke.points[p].x += dx
                    state.pages[index].strokes[i].stroke.points[p].y += dy
                }
            }
            for i in state.pages[index].texts.indices {
                let item = state.pages[index].texts[i]
                guard !item.erased, texts.contains(item.text.id) else { continue }
                state.pages[index].texts[i].text.frame.x += dx
                state.pages[index].texts[i].text.frame.y += dy
            }

        case .pageAdd(let page, let afterPageId):
            if state.pages.contains(where: { $0.id == page.id }) { return }
            let entry = LivePage(spec: page)
            if let afterPageId, let anchor = state.pages.firstIndex(where: { $0.id == afterPageId }) {
                state.pages.insert(entry, at: anchor + 1)
            } else {
                state.pages.append(entry)
            }

        case .roomPolicy(let drawPolicy, let penHolder):
            state.drawPolicy = drawPolicy
            state.penHolder = penHolder

        case .hostPage:
            if let index = pageIndex { state.hostPageId = state.pages[index].id }

        case .unknown, .invalid:
            return
        }
    }
}
