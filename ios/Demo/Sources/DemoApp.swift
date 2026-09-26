// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import LiveUI
import LiveVoice
import SwiftUI

@main
struct SpaceNotesLiveDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoRootView()
        }
    }
}

/// The server and who you are, then SpaceNotes Live's own lobby and room.
struct DemoRootView: View {
    @State private var settings = DemoSettings.load()
    @State private var session: DemoSession?
    @State private var lastResult: String?

    var body: some View {
        if let session {
            LiveSessionView(configuration: session.configuration, source: DemoNotebook()) { result in
                lastResult = result.map(Self.describe)
                self.session = nil
            }
        } else {
            DemoSetupView(settings: $settings, lastResult: lastResult) {
                settings.save()
                session = DemoSession(settings: settings)
            }
        }
    }

    private static func describe(_ result: LiveSessionResult) -> String {
        let strokes = result.pages.reduce(0) { $0 + $1.strokes.count }
        let texts = result.pages.reduce(0) { $0 + $1.texts.count }
        let ending: String
        switch result.reason {
        case "room-ended": ending = "The room ended."
        case "removed-by-host": ending = "The host removed you."
        case "left": ending = "You left the room."
        default: ending = "The session ended (\(result.reason))."
        }
        return "\(ending) \(result.pages.count) pages, \(strokes) strokes and \(texts) text boxes when it closed."
    }
}

/// One visit to the lobby and room, with the settings it started with.
struct DemoSession {
    let configuration: LiveConfiguration

    init?(settings: DemoSettings) {
        guard let url = settings.serverURL else { return nil }
        configuration = LiveConfiguration(
            serverURL: url,
            displayName: settings.trimmedName,
            deviceId: settings.deviceId,
            tokenProvider: settings.tokenProvider,
            // Voice when the server has LiveKit keys; the room stays ink only
            // when it answers 503.
            makeVoice: { LiveKitVoiceProvider() }
        )
    }
}

struct DemoSetupView: View {
    @Binding var settings: DemoSettings
    let lastResult: String?
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.10:8080", text: $settings.serverAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server address")
                } footer: {
                    Text("The room server on your computer, on the same Wi-Fi. Start it with `npm run dev` in the server folder: it prints the address to type here.")
                }

                Section("Your name") {
                    TextField("Name", text: $settings.name)
                        .textContentType(.name)
                }

                Section {
                    Toggle("Dev token", isOn: $settings.usesDevToken)
                    if settings.usesDevToken {
                        LabeledContent("Signs in as", value: settings.devToken)
                            .font(.footnote)
                    } else {
                        TextField("Firebase ID token", text: $settings.pastedToken, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote.monospaced())
                            .lineLimit(1...4)
                    }
                } header: {
                    Text("Sign-in")
                } footer: {
                    Text("A dev token works only with a server started with LIVE_DEV_AUTH=1. The same person each time you open the app.")
                }

                Section {
                    Button("Continue", action: onContinue)
                        .disabled(settings.problem != nil)
                } footer: {
                    if let problem = settings.problem {
                        Text(problem)
                    }
                }

                if let lastResult {
                    Section("Last session") {
                        Text(lastResult)
                    }
                }
            }
            .navigationTitle("SpaceNotes Live Demo")
        }
    }
}
