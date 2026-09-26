# SpaceNotes Live — iPad client

The Swift side of SpaceNotes Live: a study room where one student hosts a
shared notebook, friends join and talk, and everyone's ink and text appear
on everyone's page as it is written. It is ink and voice only: no cameras,
for cost and for privacy (India's DPDP Act); the server's LiveKit token only
lets a person publish their microphone. The contract with the
server and the web and Android clients is `protocol/PROTOCOL.md`; the files in
`fixtures/protocol/` are its executable form.

Two Swift packages and a demo app live here:

```
ios/
  SpaceNotesLive/          LiveCore + LiveUI (no third-party dependencies)
  SpaceNotesLiveVoice/     LiveVoice: LiveKit voice
  Demo/                    "SpaceNotes Live Demo", a small app for trying it on an iPad
```

## How to try it on your iPad

The demo app is SpaceNotes Live on its own, without the notebook: a screen
for the server address and your name, then the real lobby and room. It
installs from Xcode with a free Apple ID. You need a Mac with Xcode, an iPad
(or iPhone) with a cable, and both on the same Wi-Fi.

1. **Start the room server on the Mac.** In the repo's `server` folder, run
   `npm run dev` (Node 22). It prints lines like
   `http://192.168.1.23:8080`: that is the address the iPad will use. For
   voice as well as ink, start LiveKit first as described in the top-level
   `CLAUDE.md`, "Running it"; without it the room is ink only.
2. **Get XcodeGen.** Download `xcodegen.zip` from
   <https://github.com/yonaskolb/XcodeGen/releases> (2.46.0 is what CI uses)
   and unzip it, for example into your Downloads folder. Homebrew is not
   needed.
3. **Generate the Xcode project.** In Terminal, in this repo's `ios/Demo`
   folder, run `~/Downloads/xcodegen/bin/xcodegen generate` (use wherever you
   unzipped it). This writes `SpaceNotesLiveDemo.xcodeproj`. Run it again
   whenever `project.yml` changes; the project itself is never committed.
4. **Open the project.** Double-click `SpaceNotesLiveDemo.xcodeproj`. The
   first time, Xcode downloads LiveKit's Swift package; wait for it to finish.
   If your Apple ID is not in Xcode yet, add it in Xcode's Settings, under
   Accounts.
5. **Set your team.** Click the blue project icon at the top of the file
   list, then the "SpaceNotes Live Demo" target, then "Signing &
   Capabilities", and pick your "(Personal Team)". That is enough to run
   now. So it survives the next `xcodegen generate`, also copy
   `Local.xcconfig.example` to `Local.xcconfig` in `ios/Demo` and put your
   Team ID in it: with the team picked, open "Build Settings", search for
   "Development Team", and the ten-character code shown there is the ID.
   `Local.xcconfig` is gitignored.
6. **Plug in the iPad.** Unlock it and tap "Trust" on the iPad. If it asks,
   turn on Developer Mode in the iPad's Settings, under Privacy & Security,
   and let it restart.
7. **Run.** Choose the iPad at the top of the Xcode window and press Run (the
   triangle, or Command-R). The first time, the iPad refuses to open an app
   from a free Apple ID: on the iPad, go to Settings, General, VPN & Device
   Management, tap your Apple ID, and trust it. Then press Run again.
8. **Try it.** On the iPad, allow the local network and the microphone when
   asked. Type the address from step 1 and your name, leave "Dev token" on,
   and tap Continue. Start a room (three lined pages), then join it from
   another device with the six-character room code: a second iPad, an Android tablet,
   or a browser on the Mac at `http://localhost:8080`.

An app installed with a free Apple ID stops opening after seven days; run it
from Xcode again to renew it.

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
    client for good. An `error` ends it only for `bad-hello`, `no-such-room`,
    `room-full`, `guests-not-allowed` and `protocol-mismatch`; any other code
    (`rate-limited`, `unauthenticated`, `too-large`, unknown) reconnects with
    the growing backoff. Because a frame sent just before a close can be lost
    (it is, on Linux), the server's close reason is read too: a close whose
    reason is `room-ended`, `removed-by-host` or one of those five codes ends
    the client. The reason text is used, not the close code, since
    URLSession cannot represent the server's 4000-range codes.
  - clientOpId is `"<deviceId>:<counter>"`, the counter starting from the
    clock in milliseconds when the client is created (injectable for tests),
    so a relaunched app never repeats an earlier launch's ids.
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
  - One stroke is always one `stroke.add`. A stroke over 5,000 points is not
    sent; the canvas carries a long stroke on as new strokes from the last
    point (`LiveStroke.continuedAtMaximumPoints()`), as the web canvas does.
    Any op whose JSON is over 1,000 KiB is never sent: it is dropped locally
    (not pending, not an undo step) and reported as a rejection with reason
    `too-large`. Rejections reach `onReject` and `lastRejection`, and the
    room screen shows a short notice.
  - Presence out: `beginLiveInk(...)` returns a `LiveInkStreamer`, which
    sends the first batch of `ink.live` at once and then at most one message
    every 16 ms, one screen frame (points rounded to 0.1 the way
    JavaScript's `Math.round` does), then `done: true`, then `stroke.add` with
    the same id. `sendPointer` is throttled: a hovering pointer at most every
    100 ms and only after a move of 1 pt, the laser at most every 33 ms, the
    latest position sent when the wait ends; nothing is sent while a stroke is
    being drawn (a shown pointer is hidden when one starts). `hidePointer`,
    `sendView`, `setHandRaised`. Presence is not queued while offline.
  - `lastNotebookActivityAt`: when ink or text last happened in the room (a
    stroke, text or move op, or anyone's `ink.live`), for the voice idle
    policy.
  - Presence in, per connectionId: `remoteInk` (a preview stays after `done`
    until the `stroke.add` with its id swaps it out, and is dropped 1.5 s
    after `done` if that never comes, or when the member leaves), `pointers`,
    `views`; `view` and `hand` also update `members`. In-progress ink and
    pointers live in `client.presence` (`LivePresence`), observed on its own,
    so a friend's stroke redraws only the overlay, not the page.
  - Host controls: `remove(uid:)`, `endRoom()`.
  - Reconnect backoff 0.5, 1, 2, 4, then every 8 s; ping every 20 s.
- **`InkSmoothing`** — turns samples into quadratic curves through the
  midpoints of neighbouring points, each piece at its own point's width, so
  ink drawn outside PencilKit looks like a pen rather than straight segments.
- **`VoiceIdlePolicy`** — when to leave voice to save money (PROTOCOL.md,
  "Voice and cost"): after 2 minutes in the background (rejoining by itself,
  with the microphone as it was, when the app is active again), and after 15
  minutes in which nobody has spoken, drawn or written ("Voice paused — tap
  to resume"). Pure, with the clock passed in.
- **`LiveAPI`** — `createRoom`, `lookup(code:)`, `voiceToken` (the
  protocol's `POST /rooms/{id}/video-token` route; nil on 503),
  `uploadAsset`, `asset`, `snapshot` (`{ room, ended, state }`). Takes an injectable HTTP function.
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
  from the input canvas; one longer than 5,000 points is committed as
  several strokes, each carrying on from the last point (PencilKit owns the
  gesture, so this happens when the stroke ends, not mid-draw). A passive gesture recognizer on the input canvas
  watches the same touches (coalesced) to stream them with
  `LiveInkStreamer`. Remote strokes in progress, pointers and the fading
  laser are drawn in a SwiftUI `Canvas` overlay in each member's colour, with
  name labels. The overlay observes `client.presence` alone and draws with
  animations off, so each `ink.live` shows in the next frame, as smooth
  curves (`LiveInkRenderer`, from `InkSmoothing`); translucent ink is drawn
  opaque into one layer and faded as a whole, so a highlighter does not
  darken at its joints. Committed strokes are drawn by PencilKit, which
  smooths them itself. A hovering Pencil or trackpad sends a pointer. The eraser hit-tests against the state and sends
  `stroke.erase`; the text tool adds or edits a text box with a tap. Tools
  that change the notebook are greyed out when `canDraw` is false; the laser
  always works. A finger-drawing toggle switches between Pencil-only and any
  input.
- `LiveVoiceProviding` — what the tiles and the mute button use
  (`connect(url:token:microphoneEnabled:)`, `isMicrophoneOn(uid:)`,
  `isSpeaking(uid:)`, `isAnyoneSpeaking`, `setMicrophoneEnabled`), so
  LiveUI does not depend on LiveKit. A tile is the person's initials in their
  colour, their name, a host badge, their microphone state, a ring while they
  speak, and a raised hand. With no provider there is no voice: the tiles
  show who is here and the room is ink only. The room view runs
  `VoiceIdlePolicy` from `scenePhase` and a 5-second check, and leaving voice
  never leaves the room.
- `LiveTheme` — every colour and font in one struct (`.liveTheme(_:)`), with
  neutral defaults. Text on the page goes through `theme.pageText(size)`.

### `LiveVoice` (SpaceNotesLiveVoice) — LiveKit

`LiveKitVoiceProvider` implements `LiveVoiceProviding` on LiveKit's Swift SDK
(`https://github.com/livekit/client-sdk-swift`, `from: "2.17.0"`,
Apache-2.0). It joins with the microphone on (or as it was, on a rejoin),
mutes and unmutes it, and reads who is speaking from LiveKit (per person, and
`room.activeSpeakers` for the idle policy). The microphone is published with
LiveKit's speech preset (`AudioEncoding.presetSpeech`, 24 kbps) and DTX on.
LiveKit's RED (redundant audio, for lossy mobile networks) stays at its
default, on. It never publishes a camera. It is a separate
package so LiveCore's tests never resolve LiveKit. Before shipping, record
LiveKit and its licence in the notebook's `NOTICE.md`, and add
`NSMicrophoneUsageDescription` to the app's Info.plist (no camera usage
description: the app never asks for the camera).

Tiles are matched to voice participants by uid: the server must issue LiveKit
tokens whose participant identity is the Firebase uid.

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
`removed` / rejoin refused, error codes (terminal or reconnect with growing
backoff), close reasons, the clock-based op counter, too-large ops, undo/redo
pairs (including undo-then-redo of stroke.add), the live-ink throttle and
done ordering (first batch at once, then 16 ms), pointer throttling (hover
100 ms and 1 pt, laser 33 ms, none while drawing), notebook activity, that a
friend's ink changes only `client.presence`, finished previews expiring after
1.5 s, the 5,000-point rule, and presence cleanup; `InkSmoothing`; and every
`VoiceIdlePolicy` path (quiet pause and tap to resume, background leave and
rejoin with the microphone as it was, a brief trip to the background). Also `LiveAPI`, hit testing and the hosting seam.

### Against a real server

`LiveServerTests` (skipped unless `LIVE_SERVER_URL` is set) runs two real
`RoomClient`s over the real `URLSessionWebSocketTransport`, plus `LiveAPI`:

```sh
cd server && LIVE_DEV_AUTH=1 PORT=8791 node src/server.js &
cd ios/SpaceNotesLive && LIVE_SERVER_URL=http://localhost:8791 swift test --filter LiveServerTests
```

It covers: a stroke reaching the other person exactly as sent; undo then redo
reaching them; a live-ink preview replaced by its stroke; the host locking
drawing, the guest's stroke rejected and rolled back, then the pen given to
the guest; an op sent just before the socket drops (its answer held back)
delivered exactly once, answered `duplicate` on resend and not rolled back;
an op made while offline delivered exactly once on reconnect; the snapshot
matching the room; and ending the room ending both clients without
reconnecting. Each run uses fresh uids, because the server limits rooms
created per account per hour.

**On Linux** two things about swift-corelibs-foundation's WebSocket matter:

- Ubuntu 24.04's libcurl (8.5) is built without WebSocket support, and every
  connection fails with "WebSockets not supported by libcurl". Build libcurl
  8.11 or later with `--with-openssl --enable-versioned-symbols
  --enable-websockets` (the versioned symbols must be `CURL_OPENSSL_4`, which
  FoundationNetworking links against) and run with
  `LD_LIBRARY_PATH=<that build>/lib`.
- Even then it silently drops outgoing messages larger than somewhere between
  16 and 48 KB while the socket stays open (Node sends the same 797 KB frame
  to the same server without trouble). So
  `testAFullLengthStrokeCrossesInOneFrame` is skipped on Linux. It is a
  limitation of the Linux Foundation, not of the protocol or of Apple's
  URLSession, but it has not been tried on Apple's either (see below). The
  same stack also lost a data frame sent just before a close, which is why the
  client reads the close reason as well.

## How the notebook embeds it

Vendor `ios/SpaceNotesLive` (and `ios/SpaceNotesLiveVoice` when voice is
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
   indigo). `makeVoice: { LiveKitVoiceProvider() }` turns on voice; leave it
   nil for ink only.
5. **Save back.** `onFinish` receives a `LiveSessionResult` (nil if the
   person cancelled in the lobby). For the host, `state` is the server's
   snapshot when this device has nothing unsent; `result.pages` holds each
   page's visible strokes and texts to write into the notebook through the
   portable model.

## The demo app (`ios/Demo`)

`project.yml` (XcodeGen) makes one app target, "SpaceNotes Live Demo",
bundle id `com.spacenotes.live.demo`, iPadOS/iOS 17+, iPad and iPhone, using
LiveCore and LiveUI from `../SpaceNotesLive` and LiveVoice from
`../SpaceNotesLiveVoice`. Signing follows the notebook's pattern with one
change: `project.yml` points at a committed `Signing.xcconfig`, which does
`#include? "Local.xcconfig"`, so your gitignored `Local.xcconfig` (copied from
`Local.xcconfig.example`) sets `DEVELOPMENT_TEAM`, and CI and fresh clones
build without it. Info.plist carries the microphone and local network
descriptions, `NSAllowsLocalNetworking` (plain `http://` and `ws://` to a
192.168.x.x address only; everything else still needs https) and the
`audio` background mode.

The app: a setup screen (server address, remembered; your name; a dev-token
switch giving `dev:<uid>:<name>` with a uid kept per install, or a pasted
Firebase ID token), then `LiveSessionView` with a built-in `DemoNotebook` of
three lined A4 pages and `LiveKitVoiceProvider` (ink only when the server has
no LiveKit keys). No Firebase. CI generates the project with XcodeGen 2.46.0
and builds it for the simulator.

## What was and was not compiled or tested here

This machine is Linux (Ubuntu 24.04, x86_64) with the Swift 6.1.2 release
toolchain; there is no Xcode, UIKit, SwiftUI or PencilKit.

- **Compiled and tested:** `LiveCore` and `LiveCoreTests`: 74 offline tests,
  all passing, and a clean build under `-strict-concurrency=complete`. The 8
  live tests passed against the real room server (Node, dev auth) three runs
  in a row, over the real URLSession WebSocket transport, with one skipped on
  Linux as described above.
- **Compiled only in CI (Xcode on macOS), never run:** `LiveUI` and
  `SpaceNotesLiveVoice`, which CI built green for iOS at commit 419fa04 (the
  voice-only version). The latency and cost round after it (smooth overlay,
  hover pointer, `scenePhase` and the idle check, the speech preset, the
  `LiveVoiceProviding` changes) has not been through CI yet. None of it has
  run on an iPad: in particular the passive touch observer alongside
  PencilKit's drawing gesture, the zoomed canvases' geometry, text editing
  focus, Pencil hover, the microphone and speaking ring, and whether the app
  keeps running long enough in the background (it needs the `audio`
  background mode while in a call) for the 2-minute leave to fire; if iOS
  suspends it sooner, LiveKit's connection drops with it anyway.
- **The demo app:** its Foundation-only files (`DemoSettings.swift`,
  `DemoNotebook.swift`) were compiled here against LiveCore and checked in a
  throwaway test (settings round trip, address clean-up, the dev token
  matching the server's pattern, three lined pages). `project.yml` was run
  through XcodeGen 2.46.0 built from source on Linux: it generates the
  project, the shared "SpaceNotes Live Demo" scheme, both local packages and
  the Info.plist above. The SwiftUI screen (`DemoApp.swift`) and the app
  build itself were not compiled here; CI's demo step is their first build,
  and nothing has been installed on an iPad yet.
- **Not yet run on Apple's URLSession:** the live tests. Run them on a Mac
  (`swift test` with `LIVE_SERVER_URL`), where the large-frame test is not
  skipped.

## Disagreements with the spec

None open. Two raised earlier are now settled in PROTOCOL.md: the frame
limit is 1 MiB so a 5,000-point stroke fits one frame, and the snapshot route
returns `{ room, ended, state }`.

One suggestion: the server already puts the `removed` reason or `error` code
in its WebSocket close reason. PROTOCOL.md could say so, since clients rely on
it when the last frame is lost.
