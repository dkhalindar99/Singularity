// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation
import XCTest
@testable import LiveCore

/// The shared protocol fixtures, read from disk so every platform tests the
/// same files. Once vendored elsewhere, point SPACENOTES_LIVE_FIXTURES at a
/// copy of `fixtures/protocol`.
enum Fixtures {
    static var root: URL {
        if let override = ProcessInfo.processInfo.environment["SPACENOTES_LIVE_FIXTURES"] {
            return URL(fileURLWithPath: override)
        }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures/protocol")
    }

    static func json(_ path: String) throws -> JSONValue {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func files(in directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .map { "\(directory)/\($0)" }
    }
}

func assertProtocolEqual(_ actual: JSONValue, _ expected: JSONValue, _ message: String,
                         file: StaticString = #filePath, line: UInt = #line) {
    if !actual.protocolEquals(expected) {
        let a = (try? LiveJSON.encodeString(actual.droppingNulls)) ?? "?"
        let e = (try? LiveJSON.encodeString(expected.droppingNulls)) ?? "?"
        XCTFail("\(message)\nactual:   \(a)\nexpected: \(e)", file: file, line: line)
    }
}
