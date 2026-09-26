# Plugging SpaceNotes Live into the notebook

Phase 4 of the build plan (docs/research). Nothing here has been done in the
notebook repo yet; this is the plan, written so it can be done in one sitting.
It follows the TeachDraw pattern exactly: develop here, vendor a copy there.

## iPad

1. **Vendor.** Add `notebook/scripts/sync-spacenotes-live.sh`, a copy of
   `sync-teachdraw.sh` that copies `ios/SpaceNotesLive/` (and, separately,
   `ios/SpaceNotesLiveVideo/`) into `notebook/SpaceNotesLive/` and
   `notebook/SpaceNotesLiveVideo/`, plus `LICENSE`, `NOTICE.md`, the protocol
   and the fixtures (the package's tests read them by path), and records the
   commit in `VENDORED.md`.
2. **project.yml.** Add both as local `packages:` entries and the products
   `LiveCore`, `LiveUI` and `SpaceNotesLiveVideo` to the app target; run
   XcodeGen.
3. **Seams the notebook supplies** (all in `Notebook/Live/`, never inside the
   vendored folder):
   - **Token provider** — the same Firebase ID token the proxy already uses
     (`SageStateService.shared.lessonTokenProvider` pattern). Anonymous users
     are guests.
   - **`LiveNotebookSource`** — the notebook's title and the pages to share:
     `PortablePage` → `LivePage`. Strokes are the same JSON, so the adapter is
     `JSONDecoder().decode(LiveStroke.self, from: JSONEncoder().encode(portableStroke))`.
     PDF pages are rendered to JPEG (the renderer `PagePhotoCropper` already
     uses) and uploaded as page pictures.
   - **Saving back** — when the room ends, the host's app takes the final
     snapshot and writes each page's strokes and texts back through
     `NotebookStorage`, as a new page version (`PageVersionPolicy`), so the
     session can be undone as a whole. Guests get a "Save a copy" into a new
     notebook.
   - **Theme** — a `LiveTheme` built from `Theme.swift`'s tokens, and text
     through `Theme.Text` (the typography check applies to the notebook's
     files).
4. **Entry points** — "Study together" in a notebook's ⋯ menu (host), and
   "Join a room" in the library (code field). Universal Link
   `https://<live host>/join/<code>` opens the join sheet
   (`applinks:` entitlement plus an `apple-app-site-association` file served
   by the room server).

## Android

The same, with `android/live-core`, `live-ui` and `live-video` as Gradle
modules included from the notebook's `android/settings.gradle.kts`, and the
notebook's `core` `PortableStroke` mapped the same way (same JSON). App Links
need `assetlinks.json` served by the room server.

## Web

The room server already hosts the web app; nothing to vendor. The notebook's
Firebase project needs a Web app registered and its key restricted by HTTP
referrer (see `server/scripts/deploy-gcp.sh`).

## Before launch

- Age at sign-up and a parental-consent path for under-18s (India's DPDP
  rules, from 13 May 2027), and a recording policy if recording is ever added
  (off by default, everyone consents, deleted after a fixed time).
- Real-device checks: Apple Pencil pressure and latency on the shared page,
  palm rejection, and a 60-minute session crossing Cloud Run's WebSocket
  cut-off.
- Replace the cost estimates with a week of real usage logs.
