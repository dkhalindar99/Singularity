// swift-tools-version:5.9
// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.
import PackageDescription

let package = Package(
    name: "SpaceNotesLive",
    platforms: [
        .iOS(.v17),
        // macOS only so `swift test` runs from the command line; iPadOS is the
        // real target. LiveCore also builds and tests on Linux.
        .macOS(.v14),
    ],
    products: [
        .library(name: "LiveCore", targets: ["LiveCore"]),
        .library(name: "LiveUI", targets: ["LiveUI"]),
    ],
    targets: [
        // Foundation only: the protocol types, reducer, permissions, room
        // client and HTTP client.
        .target(name: "LiveCore"),
        // SwiftUI + PencilKit. Every file is wrapped in
        // `#if canImport(UIKit) && canImport(PencilKit)`, so elsewhere this
        // compiles to an empty module.
        .target(name: "LiveUI", dependencies: ["LiveCore"]),
        // Protocol fixtures are read from disk by path (../../fixtures), not
        // bundled, so every platform tests against the same files.
        .testTarget(name: "LiveCoreTests", dependencies: ["LiveCore"]),
    ]
)
