// swift-tools-version:5.9
// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.
import PackageDescription

// Kept apart from SpaceNotesLive so LiveCore's tests never resolve LiveKit.
let package = Package(
    name: "SpaceNotesLiveVideo",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "LiveVideo", targets: ["LiveVideo"]),
    ],
    dependencies: [
        .package(path: "../SpaceNotesLive"),
        // LiveKit's official Swift SDK, Apache-2.0.
        .package(url: "https://github.com/livekit/client-sdk-swift", from: "2.17.0"),
    ],
    targets: [
        .target(
            name: "LiveVideo",
            dependencies: [
                .product(name: "LiveUI", package: "SpaceNotesLive"),
                .product(name: "LiveKit", package: "client-sdk-swift"),
            ]
        ),
    ]
)
