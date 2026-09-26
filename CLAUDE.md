# SpaceNotes Live — Project Context

Read this before doing anything else in this repo. The product name is
**SpaceNotes Live**; never put the owner's personal name in the app, its
identifiers or its copy (the licence headers are the one place it belongs).

## What this is

A Zoom-like study room around one shared notebook. A host opens a room with
their notebook's pages; friends join by a six-character code or a link, from
iPad, Android or the web; everyone sees the same page, can write on it, and
sees ink while it is being drawn. Voice by default, cameras optional.

It is a **plugin**, built here and vendored into the SpaceNotes notebook app
(`github.com/dkhalindar99/notebook`) the way TeachDraw is
(`docs/NOTEBOOK_INTEGRATION.md`). Development happens here, not in the
notebook's copy.

The research behind every choice: `docs/research/Shared live notebook sessions.md`
(with its notes). In short: a server-ordered op log, not a CRDT (no usable
Kotlin CRDT; a CRDT would displace `PortableStroke` as the source of truth);
LiveKit for voice and video (Apache-2.0, Swift/Kotlin/JS SDKs, India region,
cheapest per minute); Firestore is wrong for ink (cost and write limits).

## The contract

`protocol/PROTOCOL.md` is the contract; `fixtures/protocol/` is its executable
form. **Every platform runs the same fixtures** — the JS reference
(`web/src/core`), Swift (`ios/SpaceNotesLive/Sources/LiveCore`) and Kotlin
(`android/live-core`). Change the protocol in this order: PROTOCOL.md, then
`fixtures/tools/make-fixtures.mjs` (expected values are written **by hand**,
never computed by a reducer — that is what makes them a check), regenerate,
then all three ports. CI fails if the generated fixtures differ from the
committed ones.

Rules that were learned the hard way, all in the spec:

- **`clientOpId` counters start from the clock**, not 1. The deviceId
  survives relaunches, and the server drops repeated ids as `duplicate`, so a
  counter that restarts loses a relaunched app's first ops silently. (Found in
  the web and iPad clients by the Android port's review.)
- **Redo of a stroke is `stroke.restore`, never a second `stroke.add`** — the
  reducer ignores an add whose id exists. The undo/redo table is in the spec.
- **A `duplicate` reject is not a rollback**: the op is already in the
  `welcome` state; the client only stops waiting for it.
- **Frames are at most 1 MiB**; a stroke at most 5,000 points (~750 KB). A
  client never sends an oversized frame (the server would close the socket
  and every resend would close it again): it refuses the op locally as
  `too-large`. Canvases carry on with a new stroke at 5,000 points.
- **Which `error` codes end a session** (bad-hello, no-such-room, room-full,
  guests-not-allowed, protocol-mismatch) and which reconnect with backoff
  (everything else, e.g. an expired token).
- Erase wins over move; moves are translations and add up.

## Layout

| Folder | What | How to test |
|---|---|---|
| `server/` | Room server, dependency-free Node 22. Rooms in memory, saved to memory / a folder / GCS. | `cd server && npm test` |
| `web/` | Reference reducer, `RoomClient`, canvas, LiveKit video (vendored `livekit-client` 2.22.3), and the web app the server hosts | `cd web && npm test`; `web/e2e` for two real browsers |
| `ios/SpaceNotesLive` | `LiveCore` (Foundation, builds on Linux), `LiveUI` (SwiftUI + PencilKit) | `swift test` (Linux or macOS) |
| `ios/SpaceNotesLiveVideo` | LiveKit Swift SDK behind `LiveVideoProviding` | Xcode only (CI) |
| `android/` | `live-core` (pure Kotlin), `live-ui` (Compose), `live-video` (LiveKit) | `./gradlew :live-core:test` etc.; needs `ANDROID_HOME` for the Android modules |

Versions in `android/` match the notebook's `android/gradle/libs.versions.toml`
on purpose; keep them in step.

## Running it

```sh
cd server && npm run dev   # LIVE_DEV_AUTH=1: dev tokens "dev:<uid>:<name>"; never on Cloud Run (refused there)
```

Voice/video locally: build `livekit-server` from Go's module proxy (GitHub
release downloads may be blocked in cloud sessions) and run
`livekit-server --dev --bind 127.0.0.1` (keys `devkey` / `secret`), then start
the room server with `LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey
LIVEKIT_API_SECRET=secret`. `web/e2e/video-call.mjs` drives two Chromiums with
fake cameras through it.

## What has been verified, and what has not (2026-09-26)

- **Verified here:** the reducer and permissions on all three platforms; the
  server over real WebSockets; the web client against the server; two real
  browsers through ink, text, pointers, follow-the-host, locking, undo and
  ending; a real video call through a local LiveKit (video 640×360, audio,
  data saver, mute); the Kotlin and Swift room clients against the real server
  (live tests, skipped unless `LIVE_SERVER_URL` is set).
- **Compiled but never run on a device:** the Compose screen and the Android
  LiveKit provider.
- **Never compiled here:** `LiveUI` and `SpaceNotesLiveVideo` (no Xcode on
  Linux). The macOS CI job is their first compile; expect a round of fixes.
- **Never tested:** real Apple Pencil or stylus input, a deployed server with
  real Firebase tokens, Cloud Run's 60-minute WebSocket cut-off.
- **Not deployed.** `server/scripts/deploy-gcp.sh` (asia-south1, one
  instance, GCS bucket) waits for the owner: it creates billed resources and
  needs a LiveKit project and a Firebase Web app key first.

## Conventions

- Every source file starts with the two-line copyright notice (see any file).
- Third-party code is recorded in `NOTICE.md` with its licence. Never tldraw
  (proprietary) or PenEcho (AGPL) code.
- Small, shippable steps, each verified end to end before the next.
- Never commit secrets; LiveKit keys live in Secret Manager
  (`livekit-api-key`, `livekit-api-secret`).
- `gcloud`: always `--project spacenotes-notebook`.
