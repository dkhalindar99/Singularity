# SpaceNotes Live — Android

The Android client of SpaceNotes Live: one student hosts a shared notebook,
friends join with camera and voice tiles, and everyone's ink and text appear
on everyone's page as it is drawn. The contract with the server and the other
clients is `../protocol/PROTOCOL.md`; `../fixtures/protocol/` is its
executable form, and the tests here read those files from disk.

## Modules

| Module | Kind | What it holds |
|---|---|---|
| `live-core` | Kotlin/JVM, no Android | Protocol types (JSON-identical to the notebook's `PortableStroke`), the reducer, permissions, `RoomClient` (WebSocket, optimistic ops, reconnect, undo/redo, presence), `LiveInkStreamer`, `LiveApi` (HTTP), and eraser/fit geometry. kotlinx.serialization, kotlinx.coroutines, OkHttp. |
| `live-ui` | Android library, Compose + Material 3, minSdk 26 | `LiveRoomScreen` (participant tiles, the shared page, toolbar, page navigation, Follow host, people sheet with host controls, raise hand, leave/end), `LivePageCanvas`, `LiveLobby` (join by code, host this notebook), `LiveTheme`, and the seams `LiveVideoProvider` and `LiveNotebookSource`. Does not depend on LiveKit. |
| `live-video` | Android library | `LiveKitVideoProvider`, the `LiveVideoProvider` over LiveKit's official Android SDK (`io.livekit:livekit-android` 2.29.0, Apache 2.0): mic on and camera off at the start, 180p or 360p capture, simulcast (a 180p layer under 360p), adaptive stream and dynacast, a `TextureViewRenderer` per tile. |

Versions follow the notebook's own catalogue (`notebook/android/gradle/libs.versions.toml`):
Gradle 9.6.0 (wrapper), AGP 9.4.1 with its built-in Kotlin, Kotlin 2.4.20,
kotlinx.serialization 1.11.0, coroutines 1.11.0, Compose BOM 2026.09.00,
OkHttp 5.2.1, compileSdk 37, JDK 21.

## Running the tests

```sh
cd android
./gradlew :live-core:test                  # no Android SDK needed
./gradlew :live-ui:testDebugUnitTest       # needs the SDK
./gradlew :live-ui:assembleDebug :live-video:assembleDebug
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
  a new action, a rejected undo dropping its entry; live ink sent at most
  every 30 ms, rounded to 0.1, `done` then `stroke.add` with the same id;
  pointer throttling; view and hand resent after a reconnect; remote
  previews growing, swapped for the committed stroke, cleared when their
  stroke never comes or their sender leaves; oversized ops refused locally;
- `LiveApi` against a local HTTP server (create, lookup and its 404, video
  ticket and its 503, asset upload and download, snapshot, errors);
- `LiveServerTest`: a host and a guest, both real `RoomClient`s over OkHttp
  WebSockets, against the real room server in `../server` (skipped unless
  `SPACENOTES_LIVE_SERVER` is set). Create and look up a room, starting ink,
  live ink then the committed stroke, undo and redo reaching the other
  person, a locked page rolling back the guest's stroke, raised hand, laser,
  snapshot, remove (and the refused rejoin), end:

  ```sh
  (cd ../server && LIVE_DEV_AUTH=1 PORT=18931 node src/server.js) &
  SPACENOTES_LIVE_SERVER=http://127.0.0.1:18931 ./gradlew :live-core:test
  ```

## Embedding in the notebook app

1. Put this directory next to the notebook (or vendor it) and include the
   modules from the notebook's `android/settings.gradle.kts`:

   ```kotlin
   include(":live-core", ":live-ui", ":live-video")
   project(":live-core").projectDir = file("../../Singularity/android/live-core")
   project(":live-ui").projectDir = file("../../Singularity/android/live-ui")
   project(":live-video").projectDir = file("../../Singularity/android/live-video")
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
   `LiveRoomScreen(client, api, onSessionEnded, videoProvider =
   LiveKitVideoProvider(context), theme = …)`. Build a `LiveTheme` from
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

- `./gradlew :live-core:test` — 53 tests pass, including `LiveServerTest`
  against `../server` run locally with dev tokens (run eight times in a row
  without a failure; it found, and now guards, a race where `Connected` was
  published a moment before the welcome's state).
- `./gradlew :live-ui:testDebugUnitTest` — passes (room codes, colours).
- `./gradlew :live-ui:assembleDebug :live-video:assembleDebug` — both AARs
  build with no compiler warnings; `lintDebug` reports no issues in either.

Not verified:

- Nothing was run on a device or emulator. The room screen's layout, touch
  and stylus input (historical points, pressure, hover, stylus-only), text
  editing, the people sheet and the permission prompts have been compiled
  but never seen or touched.
- `LiveKitVideoProvider` has never joined a LiveKit room: camera, microphone,
  simulcast, rendering and speaking indicators are unexercised.
- `RoomClient` has only met the local dev server, not a deployed one behind
  Cloud Run (its 60-minute socket limit and real Firebase tokens).
- No Compose UI tests or screenshot tests exist yet.
