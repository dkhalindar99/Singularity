# Real-time sync for a shared ink notebook (iPad Swift / Android Kotlin / web TS)

Research date: 2026-09-26. Package versions and dates for npm, crates.io and Maven were read directly from those registries on that date. Git tag dates come from `git ls-remote` and a bare clone of each public repo. Everything else is cited inline.

## Q1. CRDT libraries: maturity, last release, Swift, Kotlin and JS support, bundle size, licence

### Takeaway
All three CRDT families (Yjs/yrs, Automerge, Loro) are MIT-licensed, so closed-source commercial use is fine. None is AGPL or proprietary. The trouble is platform coverage. JS and Rust cores are active, with releases in September 2026. The Swift story is good for Loro (official, current), fair for Automerge (release Dec 2025), and weak for Yjs (y-uniffi/YSwift is marked WIP, last commit Jul 2024). Kotlin/Android is weak everywhere: Yjs's `ykt` is inactive, `automerge-java` is 0.0.x, and Loro has no official Kotlin binding. The only CRDT from the rejected tldraw/PenEcho pair that matters is tldraw sync, which is proprietary (see Q2).

### Cited Findings
**Yjs / y-crdt (yrs)**
- `yjs` on npm: latest 13.6.33, published 2026-09-23, licence MIT, unpacked 2.3 MB. Bundlephobia measures it at 93.7 kB minified and 28.2 kB gzip — [npm registry](https://registry.npmjs.org/yjs), [bundlephobia](https://bundlephobia.com/package/yjs)
- `yrs` (the Rust port) on crates.io: 0.28.0, updated 2026-09-17. It is still pre-1.0 — [crates.io yrs](https://crates.io/crates/yrs)
- y-crdt is "a collection of Rust libraries oriented around implementing Yjs algorithm and protocol with cross-language and cross-platform support in mind". Its bindings are yffi (C), ywasm, pycrdt, yrb, yr, ydotnet, yswift and ykt. Its feature-parity table shows that some features, such as weak links and move, are not in every port — [GitHub y-crdt](https://github.com/y-crdt/y-crdt)
- The y-crdt LICENSE is MIT — [LICENSE](https://raw.githubusercontent.com/y-crdt/y-crdt/main/LICENSE)
- **Swift:** YSwift, in the y-uniffi repo, says "This repository is WIP", does not expose every Yrs/Yjs feature, and needs Rust and Xcode to build. It is MIT, with about 91 stars — [GitHub y-uniffi](https://github.com/y-crdt/y-uniffi). Its last tag is 0.2.1 (2024-04-04) and its last commit is 2024-07-20 (git metadata, same repo).
- **Kotlin:** `ykt` says "This repository is currently not active. Consult y-uniffi for details". It has 3 commits and is MIT — [GitHub ykt](https://github.com/y-crdt/ykt). y-uniffi only mentions Kotlin as a future possibility — [GitHub y-uniffi](https://github.com/y-crdt/y-uniffi)
- **Undo:** Y.UndoManager tracks "all local changes that don't specify a transaction `origin`". `trackedOrigins` scopes it further, and edits inside `captureTimeout` (default 500 ms) are merged into one step — [Yjs docs: UndoManager](https://docs.yjs.dev/api/undo-manager)

**Automerge**
- `@automerge/automerge` on npm: 3.5.0, published 2026-09-16, MIT. The package ships a 3.6 MB `.wasm`, and Bundlephobia reports 4.9 MB minified / 1.64 MB gzip — [npm registry](https://registry.npmjs.org/@automerge/automerge), [bundlephobia](https://bundlephobia.com/package/@automerge/automerge)
- The Rust core `automerge` on crates.io: 0.12.0, updated 2026-09-16 — [crates.io automerge](https://crates.io/crates/automerge)
- **Swift:** automerge-swift is MIT and built on UniFFI over the Rust core. The Automerge Repo library adds pluggable network and storage, and the MeetingNotes showcase app runs over WebSocket and peer-to-peer — [GitHub automerge-swift](https://github.com/automerge/automerge-swift). Its latest tag is 0.7.2 (2025-12-20) and its last commit is 2026-04-02 (git metadata).
- **Kotlin/JVM:** automerge-java "wraps the Rust automerge implementation". It has an Android folder and an Android test app, 47 stars, and is still 0.0.x — [GitHub automerge-java](https://github.com/automerge/automerge-java). Maven Central's newest `org.automerge:automerge` / `androidnative` is 0.0.7 (Jan 2024). The repo has tags v0.0.8 (2025-11-04) and v0.0.9 (2026-04-21), which were not found on Maven Central search — [Maven Central search](https://search.maven.org/solrsearch/select?q=g:org.automerge&rows=5&wt=json). The GitHub page does not show its licence.

**Loro**
- `loro-crdt` on npm: 1.16.3, published 2026-09-21, MIT. The package ships a 3.3 MB `loro_wasm_bg.wasm` per target (browser/bundler/node), 20 MB unpacked — [npm registry](https://registry.npmjs.org/loro-crdt)
- The Rust `loro` crate: 1.16.2, updated 2026-09-21 — [crates.io loro](https://crates.io/crates/loro)
- Loro is MIT, reached 1.0, and has about 6.2k stars. Its languages are Rust, JS/TS (WASM) and Swift, with more through loro-ffi — [GitHub loro](https://github.com/loro-dev/loro)
- loro-ffi (UniFFI) lists these bindings: Swift (`loro-swift`, official), Python (official), React Native (official), C# (community) and Go (community), all MIT. **No Kotlin binding is listed** — [GitHub loro-ffi](https://github.com/loro-dev/loro-ffi). A search found no official Kotlin/Android binding either — [loro.dev](https://loro.dev/)
- loro-swift's latest tag is 1.16.2 (2026-09-21), in lockstep with the core (git metadata, [GitHub loro-swift](https://github.com/loro-dev/loro-swift)).

**Kotlin-native alternative**
- Synk is a Kotlin Multiplatform CRDT library for offline-first apps — [GitHub synk](https://github.com/CharlieTap/synk). It is not wire-compatible with the others.

### Inferences
- **Licence:** every CRDT candidate here is MIT and safe for closed-source use. The only licensing traps in this space are tldraw's SDK/sync (a commercial licence is needed for production) and PenEcho (AGPL), both already rejected in the project.
- **Using one CRDT on all three platforms means going through Rust + UniFFI:**
  - iOS and Android would each ship a Rust native library, several MB per ABI.
  - The web would need a 3.3–3.6 MB WASM for Loro or Automerge, against about 28 kB gzip for pure-JS Yjs.
  - Kotlin would need a binding the team maintains itself for Loro, or 0.0.x Automerge, or an inactive one for Yjs.
- **Yjs** has the best web story and the worst native-mobile story.
- **Loro** is the most active, with the best Swift support, but has no Kotlin binding. The team could generate one with UniFFI's Kotlin backend, but that is work for the team.

### Gaps
- Loro's own docs (loro.dev/docs/advanced/undo) returned HTTP 403, so this report cannot confirm the semantics of Loro's UndoManager.
- The automerge-java licence was not visible on its GitHub page. Its LICENSE file could not be fetched either.
- It is unknown why Automerge v0.0.8/0.0.9 are not on Maven Central search. They may have moved coordinates.
- Native binary sizes per iOS/Android ABI for yrs, Automerge and Loro were not measured.

## Q2. Is a full CRDT overkill for ink? Expert views on server-authoritative LWW-per-object vs CRDT

### Takeaway
The three best-known canvas products all chose **server-authoritative or version-reconciled per-object last-writer-wins**, not a general CRDT or OT:
- **Figma:** LWW per property, server-authoritative, explicitly rejecting OT and full CRDTs.
- **Excalidraw:** per-element version, versionNonce and tombstones.
- **tldraw sync:** a server-authoritative record store.

Ink strokes are immutable once finished, so the one case a CRDT handles well — concurrent edits inside the same object — hardly ever happens. A full CRDT is overkill for strokes. It is defensible only for rich text inside text boxes.

### Cited Findings
- Figma rejected OT as "unnecessarily complex for our problem space", because it creates "a combinatorial explosion of possible states which is very difficult to reason about" — [Figma blog](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)
- Figma skipped full CRDTs because it is centralised: "we can simplify our system by removing this extra overhead and benefit from a faster and leaner implementation" — [Figma blog](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)
- How Figma resolves conflicts:
  - The server keeps "the latest value that any client has sent for a given property on a given object". On conflict, "the document will just end up with the last value that was sent to the server" — [Figma blog](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)
  - A client discards incoming server changes that conflict with its own unacknowledged edits, which avoids flicker.
  - New object IDs include a unique client ID, so objects can be created offline without asking the server.
  - Reparenting is a property on the child. The server rejects parent updates that would create a cycle.
  - Ordering uses fractional indexing — [Figma blog](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)
- Excalidraw:
  - A merge takes the union of local and incoming elements and keeps the highest `version` of each.
  - Deletes are an `isDeleted` tombstone.
  - A tie is broken by the lower random `versionNonce`.
  - On concurrent edits to the same element: "We don't really care! We think this will be a pretty rare situation, and that users will tolerate some jankiness" — [Excalidraw blog](https://plus.excalidraw.com/blog/building-excalidraw-p2p-collaboration-feature)
- tldraw sync:
  - It is server-authoritative, and the server "relays changes between sync clients over WebSockets".
  - Rooms are backed by in-memory or SQLite storage with snapshots.
  - Sessions time out after 20 s by default, and hibernation (Cloudflare Durable Objects) is supported — [tldraw docs: sync](https://tldraw.dev/docs/sync)
  - It is "not a general purpose real-time data solution", and aims at "sending the minimal number of essential updates as quickly as possible, resolving conflicts with minimal overhead" — [tldraw announcement](https://tldraw.substack.com/p/announcing-tldraw-sync)
  - **Licence:** tldraw sync is included in commercial tldraw SDK licences, and only non-commercial use is free — [tldraw announcement](https://tldraw.substack.com/p/announcing-tldraw-sync). Its ideas are usable, its code is not.
- A 2026 survey of sync engines describes "server decides authoritative ordering but the client runs optimistically" as the shared pattern across tldraw, Notion and Figma. It also says Figma's domain-specific model brought memory and bandwidth wins over a general CRDT (secondary source) — [youngju.dev 2026 deep dive](https://www.youngju.dev/blog/culture/2026-05-16-pwa-offline-first-sync-2026-workbox-replicache-rxdb-yjs-automerge-livestore-electric-zero-ground-deep-dive.en)
- On undo: "The Only Undoable CRDTs are Counters" (PODC 2020 brief announcement) shows that undo is hard to get right in general CRDTs — [ACM](https://dl.acm.org/doi/10.1145/3382734.3405749), [arXiv](https://arxiv.org/pdf/2006.10494). Stewen & Kleppmann (PaPoC 2024) survey how mainstream collaboration apps handle undo, derive principles from that, and give an undo/redo algorithm for a multi-value register — [Kleppmann](https://martin.kleppmann.com/2024/04/22/undo-replicated-register.html), [arXiv 2404.11308](https://arxiv.org/pdf/2404.11308)

### Inferences
- **The shape of ink data maps straight onto an op log:**
  - A finished stroke never changes its points, so "create stroke" is a pure insert.
  - Erase is a tombstone on the stroke.
  - Move, recolour and resize are LWW property writes: a transform, or a replacement of the geometry, on a stroke ID.
  - Stacking order is a fractional index.
- This is exactly Figma's model. It needs no sequence CRDT (the part of Yjs, Automerge and Loro that costs the most), because strokes are a set, not a list of characters.
- **Keeping `PortableStroke` as the source of truth rules out a CRDT document as the primary store.** With a CRDT, the Yjs, Automerge or Loro document would become the real model, and `PortableStroke` would be a projection of it. That conflicts with the project's constraint that the Foundation-only JSON model stays canonical and portable (see the notebook CLAUDE.md). An op log whose payloads *are* `PortableStroke` JSON keeps that model canonical.
- **OT** is for sequences such as text characters. It adds nothing for a set of immutable strokes.

### Gaps
- tldraw's detailed protocol (push/rebase, version numbers per record) was not found in the public docs fetched here. Only the high-level design was confirmed.
- No ink-specific academic paper comparing CRDTs with an op log was found in this pass.

## Q3. Handling per-user undo, concurrent erase, concurrent lasso moves, late joiners and offline reconnect

### Takeaway
In a server-ordered op log, each case has a simple rule:
- **Undo** is a new *inverse op* issued only for your own ops.
- **Erase vs edit** is an idempotent tombstone that wins over later edits.
- **Concurrent moves** are LWW on the transform, by server sequence.
- **Late join** is a snapshot plus the tail of the log.
- **Offline** means a fresh snapshot, then re-applying queued ops (Figma's approach).

### Cited Findings
- Figma's undo principle: "if you undo a lot, copy something, and redo back to the present...the document should not change". Figma "modifies redo history at the time of the undo, and likewise a redo operation modifies undo history" — [Figma blog](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)
- Excalidraw never solved multiplayer undo. It clears the undo/redo stack whenever an update from a new peer arrives — [Excalidraw blog](https://plus.excalidraw.com/blog/building-excalidraw-p2p-collaboration-feature)
- Yjs scopes undo to local changes by transaction origin (`trackedOrigins`). Its default tracks local changes without an origin — [Yjs docs](https://docs.yjs.dev/api/undo-manager)
- Figma's offline handling: download a fresh copy, reapply offline edits on top of it, then resume syncing, which makes "connecting and reconnecting...very simple" — [Figma blog](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)
- Figma avoids ID collisions offline by putting the client ID inside each new object ID — [Figma blog](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)
- tldraw handles late join and restarts with room snapshots, persisted through an `onChange` callback — [tldraw docs](https://tldraw.dev/docs/sync)
- A low-bandwidth whiteboard author moved from sending state snapshots to sending ops (`add`, `update` with id, `remove` with id). The realisation was "I was sending information the other client already had" — [dev.to, Armando](https://dev.to/armando284/sharing-a-whiteboard-at-120-kbps-with-an-unstable-connection-5787)

### Inferences (proposed rules, derived from the sources above)
- **Op shape:** `{opId: "<clientId>:<counter>", author, clientSeq, serverSeq (assigned by the server), type: addStroke|tombstone|untombstone|setTransform|setProps, target, payload}`.
- **Idempotency:** opIds are unique because the client ID is part of them (the Figma pattern). The server dedupes by opId, so resends after a reconnect are safe.
- **Per-user undo:**
  - Each client keeps a local stack of *its own* opIds.
  - Undoing an `addStroke` sends a `tombstone`, and redo sends an `untombstone`.
  - Undoing a move sends a `setTransform` back to the previous value, but only if the current value is still the one you wrote. Otherwise skip it, or apply it relative to the current value. This follows Figma's rule that undo/redo must not destroy other people's later work.
  - Undo never touches ops by other authors.
- **Erase vs move/edit of the same stroke:**
  - Make the tombstone win. An edit arriving after a delete is ignored, which is how Excalidraw's `isDeleted` flag with the higher version behaves.
  - Erasing is how students cope with a mess, so resurrecting a stroke would surprise them.
  - Partial erase (the pixel eraser splits a stroke) = tombstone the original + `addStroke` for each fragment. Each fragment gets a new ID and `derivedFrom` points to the original.
- **Concurrent lasso moves:**
  - Send one op per stroke per gesture end, or one batched op per gesture with a list of targets, holding the absolute transform.
  - The server's order decides the winner (LWW).
  - While dragging, stream the transform as ephemeral presence, not as ops.
  - To avoid flicker, the client keeps its own pending value until the server acknowledges it (the Figma pattern).
- **Late joiner:**
  - Serve a snapshot at `serverSeq = N`: the notebook/page `PortablePage` JSON with tombstones compacted.
  - Then stream ops with `serverSeq > N`.
  - Compact the log into a new snapshot periodically.
  - Tombstones can be garbage-collected once every client's acknowledged seq has passed them. Keep them until then so offline clients converge.
- **Offline reconnect:**
  - Send `lastSeenServerSeq`. The server replies with the missing ops, or a snapshot if the gap is too big.
  - Then the client flushes its queued ops, which are idempotent by opId, in `clientSeq` order.
  - Stroke adds from offline never conflict. Only property writes can lose to LWW.

### Gaps
- No primary source was found that describes tldraw's undo scoping in multiplayer.
- The rules above are design inferences. No shipped ink app was found that documents them publicly.

## Q4. Wire format and bandwidth: streaming in-progress points vs committing whole strokes

### Takeaway
Use two channels:
- **An ephemeral "live ink" channel** streams in-progress points in batches every ~33–50 ms, as a quantised delta binary. Nothing persists.
- **A durable op** commits the whole `PortableStroke` on pen-up.

Bandwidth for one active drawer, estimated from first principles (not a measurement), is about 1–3 KB/s with a compact binary encoding and roughly 10–20 KB/s with naive JSON.

### Cited Findings
- Common whiteboard practice is to buffer points every 50–100 ms and send each batch as a single update, with curve interpolation on the receiving end. WebSocket frame headers (2–14 bytes) are a big share of a ~40-byte delta, so batching matters more than compression for small payloads. Binary encoding (MessagePack) instead of JSON cuts bandwidth by about 40%. These numbers come from a search-result aggregation of community blogs and repos, so treat them as indicative — [dev.to frontend system design](https://dev.to/harshattray/system-design-a-frontend-engineers-deep-dive-nh5), [Kanopy 2026](https://kanopylabs.com/blog/how-to-build-a-real-time-collaboration-whiteboard-app), [collaborative-canvas repo](https://github.com/ShubhPatel78/collaborative-canvas)
- One example streams in-progress points at about 11 Hz for live preview and commits the full stroke on pointer-up (community source) — [collaborative-canvas repo](https://github.com/ShubhPatel78/collaborative-canvas) (via search summary)
- A classroom whiteboard budget: ~120 kbps total link, ~40 kbps of it for audio, leaving ~80 kbps (~10 KB/s) for the whiteboard. Sending ops rather than state made that workable — [dev.to, Armando](https://dev.to/armando284/sharing-a-whiteboard-at-120-kbps-with-an-unstable-connection-5787)

### Inferences (calculations; assumptions stated)
- **Assumed input rate:** a pencil delivers ~120–240 points/s including coalesced touches. This rate is an assumption and was not verified in this pass.
- **Naive JSON:** a `PortableStroke` point `{"x":123.45,"y":678.9,"p":0.53,"t":1.234}` is about 45–60 B. At 240 pts/s that is ~11–14 KB/s per drawer.
- **Quantised delta binary:**
  - x and y as signed deltas in 1/8-pt units, zigzag-varint (1–2 B each).
  - Pressure as u8 (1 B).
  - dt in ms as u8 (1 B).
  - That comes to ≈4–6 B per point. At 240 pts/s that is ~1–1.5 KB/s. Batching at 30 Hz adds ~30 × (frame header + strokeId/seq ≈ 12–20 B) ≈ 0.4–0.6 KB/s.
  - Total ≈1.5–2 KB/s per active drawer, well inside the 80 kbps classroom budget above.
- **Decimation:** sending only every 2nd point live (the full-fidelity stroke still commits on pen-up) roughly halves that.
- **Commit on pen-up:**
  - Send the full `PortableStroke` JSON so it stays the canonical, portable model.
  - Optionally gzip it: a 2 s stroke at 240 pts/s is ~480 points ≈ 25 KB raw JSON, compressing to several KB.
  - Live batches are thrown away once the committed op arrives (keyed by strokeId).
  - If the drawer disconnects mid-stroke, the receivers drop the ephemeral preview after a timeout.
- **Quantisation must not change the source of truth:** only the live preview is quantised, and the committed stroke keeps full `Double` precision.

### Gaps
- No authoritative measurement of bytes/s per drawer in a production ink app (Figma, GoodNotes, Notability, tldraw) was found. The numbers above are calculations.
- Apple Pencil's exact sample and coalesced-touch rate on current iPads was not sourced in this pass.

## Q5. Recommendation for a small team on three platforms

### Takeaway
**Recommend a server-authoritative, append-only op log** (the Figma/tldraw-style pattern, implemented in-house). The details:
- Immutable `addStroke` ops carrying `PortableStroke` JSON, tombstone deletes, and LWW property ops for transform and style.
- A server `serverSeq` for ordering, client-namespaced opIds, snapshot + tail for late join, and resend-by-opId for offline.
- A separate ephemeral binary channel for in-progress points and lasso drags.

Do not adopt a general CRDT for strokes. If collaborative *rich text* inside text boxes is needed later, keep text boxes LWW at first, and reconsider only then. A per-text-box Yjs/Loro doc embedded as an opaque blob in the op is one option, but Kotlin support is the blocker.

### Cited Findings
- Figma, the largest real-time canvas, chose a centralised LWW model over OT and CRDTs for simplicity and speed — [Figma blog](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)
- Excalidraw's version/nonce/tombstone reconciliation shipped with the admitted gap of rare same-element jank — [Excalidraw blog](https://plus.excalidraw.com/blog/building-excalidraw-p2p-collaboration-feature)
- tldraw built its own purpose-built server-authoritative sync rather than use a general real-time solution — [tldraw announcement](https://tldraw.substack.com/p/announcing-tldraw-sync)
- The CRDT bindings for Kotlin are inactive (ykt), 0.0.x (automerge-java) or missing (Loro), and YSwift is WIP — [ykt](https://github.com/y-crdt/ykt), [automerge-java](https://github.com/automerge/automerge-java), [loro-ffi](https://github.com/loro-dev/loro-ffi), [y-uniffi](https://github.com/y-crdt/y-uniffi)
- A web bundle with Loro or Automerge WASM costs 3.3–3.6 MB of `.wasm`, against ~28 kB gzip for Yjs — [npm loro-crdt](https://registry.npmjs.org/loro-crdt), [npm @automerge/automerge](https://registry.npmjs.org/@automerge/automerge), [bundlephobia yjs](https://bundlephobia.com/package/yjs)

### Inferences
- **Why the op log wins for this project:**
  1. **Source of truth:** `PortableStroke` / `PortablePage` JSON stays canonical, and ops are just those JSON values plus metadata. There is no second model to project to Android, and no binary CRDT format that only Rust can read.
  2. **Portability:** the protocol is a small spec (roughly 6 op types plus JSON/binary framing) that Swift (`NotebookCore`), Kotlin (`android/core`) and TS can each implement in a few hundred lines. The project's existing `fixtures/notebook-format/` contract tests can be extended to cover op fixtures, so all three platforms stay in lockstep. No Rust toolchain or UniFFI binding has to be maintained.
  3. **Licence:** the code is entirely in-house, with nothing to flag.
  4. **Semantics fit ink:** strokes are an unordered set with rare same-object conflicts, where LWW + tombstones behave predictably. Per-user undo becomes "emit inverse ops for my own opIds", which is simpler than configuring a CRDT UndoManager across three bindings.
  5. **Server:** it can live beside the existing Cloud Run proxy. It needs WebSocket support (the proxy already relays WebSockets for `/realtime`) and a per-session store, such as Firestore, or a single instance per room with snapshots to GCS.
- **Costs the team takes on:**
  - Writing and testing the reconciliation rules (Q3).
  - Needing a server for any collaboration. There is no peer-to-peer or server-less merge, which is acceptable because accounts are already required.
  - LWW can lose one of two concurrent moves. Figma and Excalidraw accept this.
- **When a CRDT would be the better choice:** true peer-to-peer or long offline divergence with heavy same-object editing, or collaborative long-form rich text. In that case, Loro is the most active (MIT, Swift official, 1.16.x Sept 2026), but Android would need a UniFFI-generated Kotlin binding.
- **Room-scaling design point:** one Cloud Run instance per room needs session affinity, or a single-writer room actor. This is a design point, not something sourced here.

### Gaps
- No public figures were found on how GoodNotes or Notability implement collaboration, which would be the closest ink-specific precedent.
- Cloud Run WebSocket limits (request timeout, session affinity) for a room server were not researched in this pass.
