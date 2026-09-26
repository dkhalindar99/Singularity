# SpaceNotes Live

Study on one notebook, together. One student opens a room with their
notebook's pages; friends join with a six-letter code or a link, from an
iPad, an Android tablet or a web browser. Everyone sees the same page, everyone
can write on it, and the ink appears while it is being drawn, and everyone can
talk, like a call built around a shared page. **Ink and voice only — no
cameras**: that keeps the cost low and carries no faces (India's DPDP rules).

It is a **plugin**: this repository builds the pieces, and the SpaceNotes
notebook app embeds them, as it does TeachDraw.

## How it works

```
 iPad (Swift)      Android (Kotlin)      Web (JS)
      │                  │                  │
      ├──── one WebSocket each: ops, live ink, pointers ────┐
      │                  │                  │               ▼
      │                  │                  │      room server (Node, Cloud Run)
      │                  │                  │      orders every change, checks
      │                  │                  │      permissions, keeps the room
      └──── voice only: LiveKit (India region) ───────────────► LiveKit
```

- **Every change to the notebook is an op.** The server numbers it, checks
  the sender may make it, and sends it to everyone. Every device applies ops
  in the same order with the same small function, the *reducer*, so every copy
  of the notebook is identical. This is the approach Figma and tldraw use;
  why it beat CRDT libraries for ink is in `docs/research`.
- **Strokes are the notebook's own `PortableStroke` JSON**, so nothing is
  converted on the way in or out.
- **Ink appears while it is drawn**: the points of a stroke still being drawn
  go out every 30 ms as throwaway "presence"; the finished stroke follows as
  an op.
- **Undo only undoes your own work**, by sending the opposite op.
- **The host decides who may write**: everyone, only the host, or one person
  at a time ("pass the pen"). The host can remove someone and end the room.
- **Follow the host**: guests follow the host's page until they turn the page
  themselves; a chip brings them back.

`protocol/PROTOCOL.md` is the full contract. `fixtures/protocol/` is its
executable form: every platform's tests run the same files.

## What is here

| Folder | What | Tests |
|---|---|---|
| `protocol/` | The protocol, version 1 | — |
| `fixtures/protocol/` | Reducer scenarios, permission cases, every message; regenerate with `node fixtures/tools/make-fixtures.mjs` | run by every platform |
| `server/` | The room server: dependency-free Node 22 | `cd server && npm test` |
| `web/` | The web package (reducer, room client, canvas, LiveKit voice) and the web app the server hosts | `cd web && npm test`; browser runs in `web/e2e` |
| `ios/` | Swift packages: `LiveCore`, `LiveUI` (SwiftUI + PencilKit), and `SpaceNotesLiveVideo` (LiveKit) | see `ios/README.md` |
| `android/` | Gradle modules: `live-core`, `live-ui` (Compose), `live-video` (LiveKit) | see `android/README.md` |
| `docs/research/` | The research report behind every choice here, with its notes | — |

## Run it on your computer

```sh
cd server
npm run dev            # LIVE_DEV_AUTH=1: sign-in is skipped, for development only
# open http://localhost:8080 in two browser windows
```

For voice, run a LiveKit dev server (`livekit-server --dev`) and
start the room server with `LIVEKIT_URL=ws://127.0.0.1:7880
LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret`.

## Deploying

`server/scripts/deploy-gcp.sh` deploys to Cloud Run in Mumbai (asia-south1)
in the `spacenotes-notebook` project, with a Cloud Storage bucket for rooms.
It has **not been run**: it creates billed resources, and it needs a LiveKit
project and a Firebase Web app key first (listed at the top of the script).

## Cost, in short

Ink is almost free (well under ₹0.5 per student-hour). Voice is the bill:
about ₹2.5–4 per student-hour, or roughly ₹15 a month for a student who
spends five hours in rooms. Cameras would have cost ₹5–15 per student-hour
and carried faces, so the owner chose ink and voice only (2026-09-26). The
details are in `docs/research/Shared live notebook sessions.md`.

## Licence

Proprietary. See `LICENSE` and `NOTICE.md`.
