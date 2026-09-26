// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

// How the notebook app hands pages to a room and takes the result back.

/// One notebook page offered to a room.
public struct LiveSourcePage: Sendable {
    public var spec: LivePageSpec
    public var strokes: [LiveStroke]
    public var texts: [LiveText]
    /// A picture of the page's PDF background (PNG or JPEG, at most 8 MiB).
    /// When set, it is uploaded as a room asset and the page's background
    /// becomes that image.
    public var backgroundImage: Data?
    public var backgroundImageType: String

    public init(spec: LivePageSpec, strokes: [LiveStroke] = [], texts: [LiveText] = [],
                backgroundImage: Data? = nil, backgroundImageType: String = "image/jpeg") {
        self.spec = spec
        self.strokes = strokes
        self.texts = texts
        self.backgroundImage = backgroundImage
        self.backgroundImageType = backgroundImageType
    }
}

/// What the notebook shares. It builds the pages; this package never reads
/// the notebook's files.
public protocol LiveNotebookSource: AnyObject {
    var title: String { get }
    func livePages() async throws -> [LiveSourcePage]
}

/// How a session ended, with the notebook as it was, so the notebook can save
/// it back.
public struct LiveSessionResult: Sendable {
    public var roomId: String
    public var title: String
    public var wasHost: Bool
    /// "left", "room-ended", "removed-by-host", or a server error code.
    public var reason: String
    public var state: RoomState

    public init(roomId: String, title: String, wasHost: Bool, reason: String, state: RoomState) {
        self.roomId = roomId
        self.title = title
        self.wasHost = wasHost
        self.reason = reason
        self.state = state
    }

    /// Each page with only what is still drawn: erased items are not saved.
    public var pages: [LiveStartingPage] {
        state.pages.map { LiveStartingPage(spec: $0.spec, strokes: $0.visibleStrokes, texts: $0.visibleTexts) }
    }
}

public enum LiveRoomHosting {
    /// Creates a room from the notebook's pages, then uploads each page
    /// picture under the asset id the page already names.
    public static func createRoom(from source: LiveNotebookSource, api: LiveAPI, title: String? = nil,
                                  allowGuests: Bool) async throws -> CreatedRoom {
        let pages = try await source.livePages()
        var starting: [LiveStartingPage] = []
        var uploads: [(assetId: String, data: Data, type: String)] = []
        for page in pages {
            var spec = page.spec
            if let data = page.backgroundImage {
                let assetId = LiveIDs.make()
                spec.background = .image(assetId: assetId)
                uploads.append((assetId, data, page.backgroundImageType))
            }
            starting.append(LiveStartingPage(spec: spec, strokes: page.strokes, texts: page.texts))
        }
        let created = try await api.createRoom(title: title ?? source.title, pages: starting, allowGuests: allowGuests)
        for upload in uploads {
            try await api.uploadAsset(roomId: created.roomId, assetId: upload.assetId, data: upload.data, contentType: upload.type)
        }
        return created
    }
}
