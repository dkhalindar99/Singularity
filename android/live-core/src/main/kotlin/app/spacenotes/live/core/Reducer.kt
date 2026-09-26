// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

/**
 * The room reducer, protocol/PROTOCOL.md "The reducer", ported from
 * web/src/core/reducer.js. Pure: the state is immutable data, so the input is
 * never changed. It never fails; an op that does not fit changes only `seq`.
 * It does not check permissions — the server did that before numbering it.
 */
public object Reducer {
    public fun apply(state: RoomState, sequenced: SequencedOp): RoomState {
        val next = state.copy(seq = sequenced.seq)
        val author = sequenced.author
        val seq = sequenced.seq
        return when (val op = sequenced.op) {
            is Op.StrokeAdd -> next.updatePage(op.pageId) { page ->
                if (page.strokes.any { it.stroke.id == op.stroke.id }) {
                    page // a resend
                } else {
                    page.copy(strokes = page.strokes + StrokeItem(author, seq, false, op.stroke))
                }
            }
            is Op.StrokeErase -> next.updatePage(op.pageId) { it.settingErased(op.strokeIds.toSet(), true) }
            is Op.StrokeRestore -> next.updatePage(op.pageId) { it.settingErased(op.strokeIds.toSet(), false) }
            is Op.TextUpsert -> next.updatePage(op.pageId) { page ->
                val index = page.texts.indexOfFirst { it.text.id == op.text.id }
                if (index >= 0) {
                    // An edit keeps the original author and seq.
                    page.copy(texts = page.texts.replacing(index) { it.copy(text = op.text, erased = false) })
                } else {
                    page.copy(texts = page.texts + TextItem(author, seq, false, op.text))
                }
            }
            is Op.TextErase -> next.updatePage(op.pageId) { page ->
                val ids = op.textIds.toSet()
                page.copy(texts = page.texts.map { if (it.text.id in ids) it.copy(erased = true) else it })
            }
            is Op.ItemsMove -> next.updatePage(op.pageId) { page -> page.moving(op) }
            is Op.PageAdd -> {
                if (next.pages.any { it.id == op.page.id }) {
                    next
                } else {
                    val entry = LivePage(op.page.id, op.page.width, op.page.height, op.page.background)
                    val anchor = op.afterPageId?.let { id -> next.pages.indexOfFirst { it.id == id } } ?: -1
                    val pages = next.pages.toMutableList()
                    if (anchor == -1) pages.add(entry) else pages.add(anchor + 1, entry)
                    next.copy(pages = pages)
                }
            }
            is Op.RoomPolicy -> next.copy(drawPolicy = op.drawPolicy, penHolder = op.penHolder)
            is Op.HostPage -> if (next.pages.any { it.id == op.pageId }) next.copy(hostPageId = op.pageId) else next
            is Op.Unknown -> next
        }
    }

    /** Applies several ops in order. */
    public fun applyAll(state: RoomState, ops: Iterable<SequencedOp>): RoomState =
        ops.fold(state) { current, op -> apply(current, op) }

    private inline fun RoomState.updatePage(pageId: String, change: (LivePage) -> LivePage): RoomState {
        val index = pages.indexOfFirst { it.id == pageId }
        if (index < 0) return this
        return copy(pages = pages.replacing(index, change))
    }

    private fun LivePage.settingErased(ids: Set<String>, erased: Boolean): LivePage =
        copy(strokes = strokes.map { if (it.stroke.id in ids) it.copy(erased = erased) else it })

    private fun LivePage.moving(op: Op.ItemsMove): LivePage {
        val strokeIds = op.strokeIds.toSet()
        val textIds = op.textIds.toSet()
        // Erased items are not moved: erase wins. `x + dx` once per op, in seq
        // order, so every platform lands on the same double.
        return copy(
            strokes = strokes.map { item ->
                if (item.erased || item.stroke.id !in strokeIds) {
                    item
                } else {
                    item.copy(
                        stroke = item.stroke.copy(
                            points = item.stroke.points.map { it.copy(x = it.x + op.dx, y = it.y + op.dy) },
                        ),
                    )
                }
            },
            texts = texts.map { item ->
                if (item.erased || item.text.id !in textIds) {
                    item
                } else {
                    val frame = item.text.frame
                    item.copy(text = item.text.copy(frame = frame.copy(x = frame.x + op.dx, y = frame.y + op.dy)))
                }
            },
        )
    }

    private inline fun <T> List<T>.replacing(index: Int, change: (T) -> T): List<T> =
        toMutableList().also { it[index] = change(it[index]) }
}
