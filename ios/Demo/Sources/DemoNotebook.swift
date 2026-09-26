// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation
import LiveCore

/// The notebook the demo shares when you start a room: three blank lined A4
/// pages. In the SpaceNotes app, the notebook supplies its own pages here.
final class DemoNotebook: LiveNotebookSource {
    let title: String
    let pageCount: Int

    init(title: String = "Study room", pageCount: Int = 3) {
        self.title = title
        self.pageCount = pageCount
    }

    func livePages() async throws -> [LiveSourcePage] {
        (0..<pageCount).map { _ in LiveSourcePage(spec: .a4(background: .template(.lined))) }
    }
}
