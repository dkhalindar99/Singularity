// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.ui

import app.spacenotes.live.core.CreatedRoom
import app.spacenotes.live.core.LiveApi
import app.spacenotes.live.core.LiveStroke
import app.spacenotes.live.core.LiveText
import app.spacenotes.live.core.PageBackground
import app.spacenotes.live.core.RoomState
import app.spacenotes.live.core.StartingPage
import java.util.UUID

/** A picture of a page (a PDF page rendered by the host app), PNG or JPEG. */
public class LivePageImage(public val bytes: ByteArray, public val contentType: String)

/** One notebook page offered to a room, with the ink already on it. */
public data class LiveSourcePage(
    val id: String,
    val width: Double,
    val height: Double,
    /** Blank or a template. Replaced by the uploaded picture when [image] is set. */
    val background: PageBackground = PageBackground.blank,
    val strokes: List<LiveStroke> = emptyList(),
    val texts: List<LiveText> = emptyList(),
    val image: LivePageImage? = null,
)

/**
 * What the notebook app hands the room when someone hosts: the title and the
 * pages to share. Converting its own page model to these types is the
 * notebook's job; the stroke JSON is already the same.
 */
public interface LiveNotebookSource {
    public val title: String

    public suspend fun pages(): List<LiveSourcePage>
}

/** How a session ended, and the notebook as it was, for saving back. */
public data class LiveSessionResult(
    val roomId: String,
    /** `left`, `room-ended`, `removed-by-host`, or an error code. */
    val reason: String,
    val wasHost: Boolean,
    /**
     * The room's final state. For the host it is the server's copy when it
     * could be fetched; otherwise this device's own. Erased items are still in
     * it; `visibleOnly()` drops them.
     */
    val snapshot: RoomState,
)

/**
 * Creates a room from [source]: page pictures get asset ids first (a page
 * must name its picture when the room is created), then are uploaded once the
 * room exists. A guest who joins in between sees a blank page until the
 * picture arrives.
 */
public suspend fun LiveApi.hostRoom(source: LiveNotebookSource, allowGuests: Boolean = true): CreatedRoom {
    val pages = source.pages()
    val uploads = mutableListOf<Pair<String, LivePageImage>>()
    val starting = pages.map { page ->
        val background = page.image?.let { image ->
            val assetId = UUID.randomUUID().toString()
            uploads += assetId to image
            PageBackground.image(assetId)
        } ?: page.background
        StartingPage(page.id, page.width, page.height, background, page.strokes, page.texts)
    }
    val room = createRoom(source.title, starting, allowGuests)
    for ((assetId, image) in uploads) uploadAsset(room.roomId, assetId, image.bytes, image.contentType)
    return room
}
