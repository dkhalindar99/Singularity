// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI
import UIKit

/// Page pictures (PDF backgrounds) for one room, fetched once each.
@MainActor
final class LiveAssetCache: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    private var loading: Set<String> = []
    private let api: LiveAPI
    private let roomId: String

    init(api: LiveAPI, roomId: String) {
        self.api = api
        self.roomId = roomId
    }

    func image(_ assetId: String) -> UIImage? { images[assetId] }

    /// Loads a picture, retrying a few times: a guest can join while the host
    /// is still uploading.
    func load(_ assetId: String) async {
        guard images[assetId] == nil, !loading.contains(assetId) else { return }
        loading.insert(assetId)
        defer { loading.remove(assetId) }
        for attempt in 0..<5 {
            if let data = try? await api.asset(roomId: roomId, assetId: assetId), let image = UIImage(data: data) {
                images[assetId] = image
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(1 << attempt) * 1_000_000_000)
            if Task.isCancelled { return }
        }
    }
}
#endif
