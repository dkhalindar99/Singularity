# SpaceNotes Live — Android

The Android client of SpaceNotes Live: one student hosts a shared notebook,
friends join by voice (no cameras: ink and voice only, for cost and privacy), and everyone's ink and text appear
on everyone's page as it is drawn. The contract with the server and the other
clients is `../protocol/PROTOCOL.md`; `../fixtures/protocol/` is its
executable form, and the tests here read those files from disk.

## Modules

| Module | Kind | What it holds |
|---|---|---|
| `live-core` | Kotlin/JVM, no Android | Protocol types (JSON-identical to the notebook's `PortableStroke`), the reducer, permissions, `RoomClient` (WebSocket, optimistic ops, reconnect, undo/redo, presence), `LiveInkStreamer`, `LiveApi` (HTTP), and eraser/fit geometry. kotlinx.serialization, kotlinx.coroutines, OkHttp. |
| `live-ui` | Android library, Compose + Material 3, minSdk 26 | `LiveRoomScreen` (participant tiles, the shared page, toolbar, page navigation, Follow host, people sheet with host controls, raise hand, leave/end), `LivePageCanvas`, `LiveLobby` (join by code, host this notebook), `LiveTheme`, and the seams `LiveVoiceProvider` and `LiveNotebookSource`. Does not depend on LiveKit. |
| `live-demo` | Android app | "SpaceNotes Live Demo" (`app.spacenotes.live.demo`), for trying the room on a real tablet against a development server: server address and name, then the lobby (host 3 blank lined pages, or join by code) and the room, with voice when the server has LiveKit. Dev tokens only (`dev:<uid>:<name>`), no Firebase; plain `http://` is allowed in the debug build only. |
| `live-voice` | Android library | `LiveKitVoiceProvider`, the `LiveVoiceProvider` over LiveKit's official Android SDK (`io.livekit:livekit-android` 2.29.0, Apache 2.0): voice only, microphone on at the start when allowed, mute, who is speaking. Never publishes a camera (the server's ticket allows only a microphone), and its manifest removes the camera and screen-sharing permissions LiveKit's own manifest asks for. |

Versions follow the notebook's own catalogue (`notebook/android/gradle/libs.versions.toml`):
Gradle 9.6.0 (wrapper), AGP 9.4.1 with its built-in Kotlin, Kotlin 2.4.20,
kotlinx.serialization 1.11.0, coroutines 1.11.0, Compose BOM 2026.09.00,
OkHttp 5.2.1, compileSdk 37, JDK 21.

## Running the tests

```sh
cd android
./gradlew :live-core:test                  # no Android SDK needed
./gradlew :live-ui:testDebugUnitTest       # needs the SDK
./gradlew :live-ui:assembleDebug :live-voice:assembleDebug
```

The Android modules need an SDK with `platforms;android-37.0`: set
`ANDROID_HOME`, or write `sdk.dir=…` into a `local.properties` (ignored by git).

What `live-core`'s tests cover:

- every file in `fixtures/protocol/scenarios/` through `Reducer.apply`,
  compared by value (missing equals null, numbers as doubles), and that the
  input state is untouched;
- all 19 cases in `fixtures/protocol/permissions/cases.json`, validated from
  the raw JSON (a string coordinate is `invalid-op`), and the typed path
  agreeing wherever the raw op is valid;
- every server frame decoded (the unknown type and extra fields ignored, an
  unknown background drawn as blank), known frames re-encoded to the same
  value, and every client frame built from this client's own types and
  compared by value with the fixture;
- `RoomClient` against a fake transport, on virtual time: hello and welcome;
  optimistic pending ops under others' ops; resend with the same `clientOpId`
  after a reconnect; reject rollback; `duplicate` rejects that only stop the
  waiting; the seq-gap reconnect; the 0.5/1/2/4/8 s backoff and its reset;
  `removed` (also instead of `welcome`) ending for good; fatal and retryable
  errors; pings every 20 s; undo/redo of strokes (erase/restore pairs, and
  redo of `stroke.add` as `stroke.restore`), moves and texts, redo cleared by
  a new action, a rejected undo dropping its entry; live ink sent at once, then at most
  every 16 ms, rounded to 0.1, `done` then `stroke.add` with the same id;
  pointer throttling (hover every 100 ms after a move of 1 pt, laser every 33 ms, none while drawing); view and hand resent after a reconnect; remote
  previews growing, swapped for the committed stroke, cleared when their
  stroke never comes or their sender leaves; an op over ~1,000 KiB dropped
  locally as a `too-large` reject (never pending, never an undo step), while
  a full 5,000-point stroke still fits one frame;
- `VoiceIdlePolicy` on an injected clock (voice left after 2 minutes in
  the background and rejoined on return; after 15 quiet minutes until a
  tap; any ink or speech keeps it), and the smoothed-curve pieces the canvas
  draws;
- `LiveApi` against a local HTTP server (create, lookup and its 404, voice
  ticket and its 503, asset upload and download, snapshot, errors);
- `LiveServerTest`: a host and a guest, both real `RoomClient`s over OkHttp
  WebSockets, against the real room server in `../server` (skipped unless
  `LIVE_SERVER_URL` is set). Create and look up a room, starting ink, live
  ink then the committed stroke, undo and redo reaching the other person,
  reconnecting delivering a pending op exactly once (both when the server
  had already numbered it and its echo was lost — answered `duplicate` —
  and when it was drawn while the line was down), a locked page rolling
  back the guest's stroke, raised hand, laser, snapshot, remove (and the
  refused rejoin), end:

  ```sh
  (cd ../server && LIVE_DEV_AUTH=1 PORT=8792 node src/server.js) &
  LIVE_SERVER_URL=http://127.0.0.1:8792 ./gradlew :live-core:test
  ```

## How to try it on your Android tablet

The demo app talks to a room server running on your Mac, over your home Wi-Fi.

1. **Start the room server on the Mac.** In the repository:
   `cd server && npm run dev`. It listens on port 8080 and accepts the demo's
   dev sign-in. If macOS asks whether Node may accept incoming connections,
   say Allow. (Voice needs a LiveKit server too — see the top-level
   `CLAUDE.md`, "Voice locally". For a tablet, run LiveKit bound to the Wi-Fi
   rather than `127.0.0.1`, e.g. `livekit-server --dev --bind 0.0.0.0
   --node-ip <Mac's address>`, and start the room server with
   `LIVEKIT_URL=ws://<Mac's address>:7880`, because the tablet is handed that
   address. Without LiveKit the room works with ink only.)
2. **Find the Mac's Wi-Fi address.** In Terminal: `ipconfig getifaddr en0`.
   It looks like `192.168.1.23`. The tablet must be on the same Wi-Fi.
3. **Get the app (APK).** Either build it:
   `cd android && ANDROID_HOME=<your Android SDK> ./gradlew :live-demo:assembleDebug`,
   which writes `android/live-demo/build/outputs/apk/debug/live-demo-debug.apk`;
   or download `SpaceNotesLiveDemo-debug-apk` from the latest CI run on
   GitHub (Actions → the run → Artifacts) and unzip it.
4. **Copy the APK to the tablet** (USB, Google Drive, or email to yourself)
   and open it in the tablet's Files app.
5. **Allow installing from this source.** Android asks the first time: tap
   Settings, turn on "Allow from this source" for the app you opened it
   with, go back, and tap Install. If an older copy was installed from a
   different build, uninstall it first (each machine signs debug builds with
   its own key, and Android refuses to mix them).
6. **Open "SpaceNotes Live Demo".** Enter the server address as
   `http://` + the Mac's address + `:8080`, for example
   `http://192.168.1.23:8080`, and your name. Tap Continue. Both are
   remembered.
7. **Start a room** (three blank lined pages) or **join one** with the
   six-character code shown in another device's room header. Allow the
   microphone when asked if you want to talk.
8. To try it with two people, open the same server in a browser on the Mac
   (`http://localhost:8080`) or install the app on a second device.

The demo signs in with dev tokens, which only a server started with
`LIVE_DEV_AUTH=1` accepts. It is for testing at home, never for a real
server.

## Embedding in the notebook app

1. Put this directory next to the notebook (or vendor it) and include the
   modules from the notebook's `android/settings.gradle.kts`:

   ```kotlin
   include(":live-core", ":live-ui", ":live-voice")
   project(":live-core").projectDir = file("../../Singularity/android/live-core")
   project(":live-ui").projectDir = file("../../Singularity/android/live-ui")
   project(":live-voice").projectDir = file("../../Singularity/android/live-voice")
   ```

   and add to its `dependencyResolutionManagement.repositories` the JitPack
   entry from `settings.gradle.kts` here (LiveKit's audio routing library is
   published only there; the entry is limited to that one group). The
   version catalogue here names nothing the notebook's does not already
   have, apart from `livekit` and `activityCompose` (which it has).

2. Strokes need no conversion logic: `LiveStroke` writes the same JSON as
   `com.spacenotes.core.model.PortableStroke`, so the notebook converts by
   encoding one and decoding the other. Implement `LiveNotebookSource` over
   the open notebook (title, pages, starting strokes and text boxes; PDF
   pages rendered to PNG or JPEG as `LivePageImage`, uploaded as room
   assets by `LiveApi.hostRoom`).

3. Show `LiveLobby(api, source, onJoin, onHosted, theme = …)`, then
   `LiveRoomScreen(client, api, onSessionEnded, voiceProvider =
   LiveKitVoiceProvider(context), theme = …)`. Build a `LiveTheme` from
   `Theme.swift`'s faded-indigo tokens as the notebook's own Compose theme
   has them. Hold the `RoomClient` in a ViewModel so a rotation does not
   leave the room (`rememberRoomClient` is the simple version that does).

4. `onSessionEnded` gets a `LiveSessionResult`: the reason, whether this
   person was the host, and the final `RoomState` (the server's copy for the
   host). `snapshot.visibleOnly()` drops erased items; save its pages back
   into the notebook.

`RoomClient` needs a Firebase ID token provider (`suspend () -> String`,
fresh per call) and a stable device id; its `clientOpId` counter starts from
the clock so ops after an app relaunch are never mistaken for resends.

## What was and was not verified here

Built and tested on Linux with JDK 21, Gradle 9.6.0 and Android SDK platform
37.0 / build-tools 37.0.0 installed from Google's command-line tools:

- `./gradlew :live-core:test` — 66 tests; all pass. `LiveServerTest` (one
  of them) is skipped without `LIVE_SERVER_URL`; it was run against
  `../server` started locally with dev tokens, ten times in a row without a
  failure. It found, and now guards, a race where `Connected` was
  published a moment before the welcome's state.
- `./gradlew :live-ui:testDebugUnitTest` — passes (room codes, colours).
- `./gradlew :live-ui:assembleDebug :live-voice:assembleDebug :live-demo:assembleDebug`
  — both AARs and the demo APK (debug-signed, minSdk 26, no camera
  permission in it) build with no compiler warnings; `lintDebug` reports no
  issues in any of the three.

Not verified:

- Nothing was run on a device or emulator. The room screen's layout, touch
  and stylus input (historical points, pressure, hover, stylus-only), text
  editing, the people sheet and the permission prompts have been compiled
  but never seen or touched.
- `LiveKitVoiceProvider` has never joined a LiveKit room: the microphone,
  mute and speaking indicators are unexercised.
- `RoomClient` has only met the local dev server, not a deployed one behind
  Cloud Run (its 60-minute socket limit and real Firebase tokens).
- No Compose UI tests or screenshot tests exist yet.
