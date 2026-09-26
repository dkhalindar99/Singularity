# SpaceNotes Live — iPad client

The Swift side of SpaceNotes Live: a study room where one student hosts a
shared notebook, friends join with camera and voice tiles, and everyone's ink
and text appear on everyone's page as it is written. The contract with the
server and the web and Android clients is `protocol/PROTOCOL.md`; the files in
`fixtures/protocol/` are its executable form.

Two Swift packages live here:

```
ios/
  SpaceNotesLive/          LiveCore + LiveUI (no third-party dependencies)
  SpaceNotesLiveVideo/     LiveVideo: LiveKit camera and voice
```

## What each target is

### `LiveCore` (SpaceNotesLive) — Foundation only, builds on Linux

- **Protocol types** — `RoomState`, `LivePage` (with `LiveStrokeItem` /
  `LiveTextItem`: author, seq, erased), `LiveStroke` / `LivePoint` /
  `LiveColor` (the notebook's `PortableStroke` JSON, field for field),
  `LiveText`, `PageBackground` (an unknown kind keeps its raw name and draws as
  blank), `Op`, `SequencedOp`, `Presence`, `Control`, `ClientMessage`,
  `ServerMessage`, `Member`, `You`, `RoomInfo`, and `JSONValue`.
  - `Op` never fails to decode from a JSON object. An unknown kind becomes
    `.unknown(kind:raw:)`; a known kind with a missing or mistyped field (a
    string coordinate, a move without `dx`) becomes `.invalid(kind:raw:)`.
    Both keep their JSON and encode back unchanged, both are no-ops in the
    reducer, and both are `invalid-op` to `Permissions.authorize`.
  - An unknown server `type` decodes to `ServerMessage.unknown` and is
    ignored; an unknown presence kind to `Presence.unknown`.
  - `LiveStroke.ink` is the raw string (so `"quill"` survives a round trip);
    `inkType` reads it, defaulting to `.unknown`. `createdAt` is kept as the
    ISO-8601 text. Absent optionals (`azimuth`, `altitude`, `captureStamp`)
    are omitted when encoding.
- **`Reducer.apply`** — a faithful port of `web/src/core/reducer.js`.
- **`Permissions.authorize` / `canDraw`** — a port of
  `web/src/core/permissions.js`. The member type is `LiveParticipant`
  (`uid`, `role`); it is not called `Participant` because LiveKit has a type
  of that name.
- **`RoomClient`** (`@MainActor`, an `ObservableObject` wherever Combine
  exists, plus an `onChange` callback for Linux and tests):
  - `status`: idle → connecting → connected / reconnecting → ended(reason).
  - `confirmed` is the server's state; `state` is confirmed with this
    device's unacknowledged ops applied on top (author = my uid, seq =
    confirmed.seq), recomputed on every change.
  - `op` with a seq other than confirmed.seq + 1 → close and reconnect. On
    `welcome`: replace confirmed and resend pending ops with their original
    `clientOpId`. On `reject`: drop the pending op; for any reason but
    `duplicate` its undo/redo entry goes too. A `duplicate` reject only stops
    treating the op as pending, since the welcome state already has it.
  - `removed` (including when a removed person tries to rejoin) ends the
    client for good; `error` ends it too, except `rate-limited`, which
    reconnects with backoff.
  - clientOpId is `"<deviceId>:<counter>"`.
  - Ops: `addStroke`, `eraseStrokes`, `restoreStrokes`, `moveItems`,
    `upsertText`, `eraseTexts`, `addPage(_:after:)`, `setPolicy(_:penHolder:)`,
    `setHostPage`.
  - Undo/redo of this person's own ops, as fixed pairs recorded when the op
    is first sent: stroke.add → erase / restore; stroke.erase → restore (only
    what it hid) / the same erase; stroke.restore → erase / restore; move →
    move(-dx,-dy) / move(dx,dy); text.upsert → erase or the previous text /
    the same upsert; text.erase → upsert as it was / the same erase. Undo and
    redo go out as new ops with fresh clientOpIds. Pages, policy and host page
    are not undoable.
  - A stroke past 5,000 points or a 240 KiB frame is sent as several strokes
    that share their joining points and undo together (see "Disagreements"
    below for why).
  - Presence out: `beginLiveInk(...)` returns a `LiveInkStreamer`, which
    sends `ink.live` at most every 30 ms (points rounded to 0.1 the way
    JavaScript's `Math.round` does), then `done: true`, then `stroke.add` with
    the same id. `sendPointer`, `hidePointer`, `sendView`, `setHandRaised`.
    Presence is not queued while offline.
  - Presence in, per connectionId: `remoteInk` (previews dropped on `done`,
    on the `stroke.add` with that id, or when the member leaves), `pointers`,
    `views`; `view` and `hand` also update `members`.
  - Host controls: `remove(uid:)`, `endRoom()`.
  - Reconnect backoff 0.5, 1, 2, 4, then every 8 s; ping every 20 s.
- **`LiveAPI`** — `createRoom`, `lookup(code:)`, `videoToken` (nil on 503),
  `uploadAsset`, `asset`, `snapshot`. Takes an injectable HTTP function.
- **Transport** — `WebSocketTransport` with `URLSessionWebSocketTransport`
  (real) and `InMemoryTransport` (tests, previews); `LiveScheduler` with
  `TaskScheduler` (real) and `ManualScheduler` (tests).
- **`LiveHitTest`** — strokes near a point and the text under it (eraser and
  text tool).
- **Notebook seam** — `LiveNotebookSource`, `LiveSourcePage`,
  `LiveRoomHosting.createRoom(from:api:allowGuests:)` (creates the room, then
  uploads each page picture under the asset id its page already names), and
  `LiveSessionResult` (its `pages` drop erased items).

### `LiveUI` (SpaceNotesLive) — SwiftUI + PencilKit

Every file is wrapped in `#if canImport(UIKit) && canImport(PencilKit)`, so on
Linux and macOS the module is empty. It re-exports LiveCore.

- `LiveSessionView(configuration:source:initialCode:onFinish:)` — the one
  view the notebook presents: lobby, then room.
- `LiveLobbyView` — start a room from the notebook's pages, or join with a
  code.
- `LiveRoomView` — participant tiles along the top, the shared page in the
  middle, toolbar and page bar along the bottom; participants sheet with the
  host's controls (who can write: everyone / only me / pen holder; give the
  pen; remove), raise hand, leave / end for everyone, "Follow host".
- The page (`LivePageView`, `LivePageCanvas`): two PencilKit canvases zoomed
  to fit, so page coordinates equal PencilKit's drawing coordinates and ink
  stays sharp. The lower one shows every committed stroke from `client.state`,
  rebuilt with `transform: .identity`; the upper one takes the local pen, so
  drawing feels exactly like the notebook. When a stroke ends it is converted
  (transform baked in, as `extractPortableStrokes` does), sent, and removed
  from the input canvas. A passive gesture recognizer on the input canvas
  watches the same touches (coalesced) to stream them with
  `LiveInkStreamer`. Remote strokes in progress, pointers and the fading
  laser are drawn in a SwiftUI `Canvas` overlay in each member's colour, with
  name labels. The eraser hit-tests against the state and sends
  `stroke.erase`; the text tool adds or edits a text box with a tap. Tools
  that change the notebook are greyed out when `canDraw` is false; the laser
  always works. A finger-drawing toggle switches between Pencil-only and any
  input.
- `LiveVideoProviding` — the protocol the tiles use (`videoView(uid:)`,
  `isMicrophoneOn(uid:)`, `isSpeaking(uid:)`, mic and camera switches), so
  LiveUI does not depend on LiveKit. With no provider, a tile is a coloured
  circle with initials.
- `LiveTheme` — every colour and font in one struct (`.liveTheme(_:)`), with
  neutral defaults. Text on the page goes through `theme.pageText(size)`.

### `LiveVideo` (SpaceNotesLiveVideo) — LiveKit

`LiveKitVideoProvider` implements `LiveVideoProviding` on LiveKit's Swift SDK
(`https://github.com/livekit/client-sdk-swift`, `from: "2.17.0"`,
Apache-2.0). It joins with the microphone on and the camera off; the camera
captures 360p at 20 fps and publishes simulcast 180p and 360p layers; adaptive
stream and dynacast are on; tiles use LiveKit's `SwiftUIVideoView`. It is a
separate package so LiveCore's tests never resolve LiveKit. Before shipping,
record LiveKit and its licence in the notebook's `NOTICE.md`, and add
`NSMicrophoneUsageDescription` and `NSCameraUsageDescription` to the app's
Info.plist.

Tiles are matched to video by uid: the server must issue LiveKit tokens whose
participant identity is the Firebase uid.

## Running the tests

```sh
cd ios/SpaceNotesLive
swift test
```

The tests read the shared fixtures from disk (`../../fixtures/protocol`,
found from `#filePath`), not from a bundle. Once vendored somewhere else, set
`SPACENOTES_LIVE_FIXTURES=/path/to/fixtures/protocol`.

What they cover: every reducer scenario (final state compared by value,
missing field == null, plus a round trip of each initial state); all 19
permission cases, with ops decoded from the raw fixture JSON; every
server-to-client message decoded (the unknown type ignored, extra fields
ignored); every client-to-server message both built from Swift values and
round-tripped, compared by value; and `RoomClient` against the in-memory
transport and manual clock — optimistic pending ops, resend after welcome,
reject rollback, `duplicate` reject, seq-gap reconnect, backoff, ping,
`removed` / rejoin refused, errors, undo/redo pairs (including undo-then-redo
of stroke.add), the live-ink throttle and done ordering, long-stroke
splitting, and presence cleanup. Also `LiveAPI`, hit testing and the hosting
seam.

## How the notebook embeds it

Vendor `ios/SpaceNotesLive` (and `ios/SpaceNotesLiveVideo` when video is
wanted) into the notebook repo as local path packages, the way TeachDraw is,
and add them to `project.yml` under `packages:`. Then:

1. **Source.** A notebook-side type conforming to `LiveNotebookSource` gives
   the title and the pages to share. For each page: a `LivePageSpec` (size in
   points, background), its strokes and text boxes, and, for a PDF page, a
   rendered PNG or JPEG in `backgroundImage` (at most 8 MiB), which is
   uploaded as a room asset.
2. **Strokes.** `PortableStroke` ↔ `LiveStroke` is a straight JSON re-encode:
   encode with the notebook's storage encoder (`.iso8601` dates, so
   `createdAt` is whole-second ISO text) and decode as `LiveStroke`, and back
   the same way. `LiveStroke.createdAt` is optional because the protocol does
   not require it; fill it in when converting back if it is missing.
   Coordinates are already absolute on both sides, so no transform is
   involved.
3. **Tokens.** `LiveConfiguration.tokenProvider` returns a fresh Firebase ID
   token (the same anonymous-or-signed-in account the proxy uses); it is
   called on every connect and every HTTP call.
4. **Present** `LiveSessionView(configuration:source:onFinish:)`, with
   `.liveTheme(...)` built from `Theme.swift` / `Typography.swift` (faded
   indigo). `makeVideo: { LiveKitVideoProvider() }` turns on camera and
   voice; leave it nil for ink only.
5. **Save back.** `onFinish` receives a `LiveSessionResult` (nil if the
   person cancelled in the lobby). For the host, `state` is the server's
   snapshot when this device has nothing unsent; `result.pages` holds each
   page's visible strokes and texts to write into the notebook through the
   portable model.

## What was and was not compiled or tested here

This machine is Linux (Ubuntu 24.04, x86_64) with the Swift 6.1.2 release
toolchain; there is no Xcode, UIKit, SwiftUI or PencilKit.

- **Compiled and tested:** `LiveCore` and `LiveCoreTests` — 56 tests, all
  passing, and a clean build under `-strict-concurrency=complete`. The
  URLSession WebSocket transport compiles (FoundationNetworking) but was not
  run against a live server; the server was not written yet.
- **Compiled as an empty module only:** `LiveUI`. None of its SwiftUI,
  UIKit or PencilKit code has been compiled or run. It was written against
  the iOS 17 SDK APIs with care (PencilKit calls mirror the notebook's own
  `PortableStrokeMapping.swift`), but expect a round of compile fixes in
  Xcode, and it needs trying on an iPad: in particular the passive touch
  observer alongside PencilKit's drawing gesture, the zoomed canvases'
  geometry, and text editing focus.
- **Not compiled at all:** `SpaceNotesLiveVideo`. It was written against
  LiveKit Swift SDK 2.17.0's source (`Room`, `RoomOptions`,
  `CameraCaptureOptions`, `VideoPublishOptions`, `VideoParameters` presets,
  `RoomDelegate`, `SwiftUIVideoView`), read directly from the repository, but
  never built.

## Disagreements with the spec

- **A 5,000-point stroke does not fit in a 256 KiB frame.** A stroke point
  with azimuth and altitude at full double precision is about 150 bytes of
  JSON, so a frame fills up at roughly 1,700 points. The client therefore
  splits by encoded size as well as by point count. The spec may want to say
  so, or lower the point limit, so the other clients do the same.
