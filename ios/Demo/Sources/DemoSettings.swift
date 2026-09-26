// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// What the demo remembers between launches: the server to use, the name to
/// show, and how to sign in. No Firebase here: with a dev server
/// (LIVE_DEV_AUTH=1) the token is `dev:<uid>:<name>`; otherwise a Firebase ID
/// token can be pasted in.
struct DemoSettings: Equatable {
    static let defaultServer = "http://192.168.1.10:8080"

    var serverAddress: String
    var name: String
    var usesDevToken: Bool
    var pastedToken: String
    /// Stable for this install, so rejoining a room is the same person.
    let uid: String
    /// Stable for this install; the room client adds a counter to it.
    let deviceId: String

    private enum Key {
        static let server = "demo.serverAddress"
        static let name = "demo.name"
        static let devToken = "demo.usesDevToken"
        static let pastedToken = "demo.pastedToken"
        static let uid = "demo.uid"
        static let deviceId = "demo.deviceId"
    }

    static func load(from defaults: UserDefaults = .standard) -> DemoSettings {
        func stored(_ key: String, orMake make: () -> String) -> String {
            if let value = defaults.string(forKey: key), !value.isEmpty { return value }
            let value = make()
            defaults.set(value, forKey: key)
            return value
        }
        let short = { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased() }
        return DemoSettings(
            serverAddress: defaults.string(forKey: Key.server) ?? defaultServer,
            name: defaults.string(forKey: Key.name) ?? "",
            usesDevToken: defaults.object(forKey: Key.devToken) as? Bool ?? true,
            pastedToken: defaults.string(forKey: Key.pastedToken) ?? "",
            uid: stored(Key.uid) { "ipad-\(short())" },
            deviceId: stored(Key.deviceId) { "ipad-\(short())" }
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(serverAddress, forKey: Key.server)
        defaults.set(name, forKey: Key.name)
        defaults.set(usesDevToken, forKey: Key.devToken)
        defaults.set(pastedToken, forKey: Key.pastedToken)
    }

    /// The server as a URL: `192.168.1.10:8080` gains `http://`, a trailing
    /// slash goes. nil if it cannot be a server address.
    var serverURL: URL? {
        var text = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The name as the dev server accepts it: no colons, at most 60 characters.
    var devName: String {
        String(trimmedName.replacingOccurrences(of: ":", with: " ").prefix(60))
    }

    var devToken: String { "dev:\(uid):\(devName)" }

    /// Why the form cannot continue yet, or nil.
    var problem: String? {
        if serverURL == nil { return "Enter the server address, like \(DemoSettings.defaultServer)." }
        if trimmedName.isEmpty { return "Enter your name." }
        if !usesDevToken, pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Paste a Firebase ID token, or turn on the dev token."
        }
        return nil
    }

    /// Returns the same token on every call. A dev token never expires; a
    /// pasted Firebase token lasts an hour, which is enough for a test.
    var tokenProvider: @Sendable () async throws -> String {
        let token = usesDevToken ? devToken : pastedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return { token }
    }
}
