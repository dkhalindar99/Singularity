# SpaceNotes Live — room protocol, version 1

This is the contract between the room server and the three clients (iPad,
Android, web). Every client must read and write exactly these messages, and
apply operations exactly as described in "The reducer". The JSON files in
`fixtures/protocol/` are the executable form of this document: each platform's
tests load them, and a platform that disagrees with a fixture is wrong.

## The idea in one paragraph

A **room** is one shared notebook. The host creates it with the pages they
want to share. Everyone connects to the room server over one WebSocket.
Anything that changes the notebook is an **op** (operation). A client sends an
op; the server checks the sender may do it, gives it the next **sequence
number** (`seq`), and sends it to everyone, the sender included. Every client
applies ops in `seq` order with the same pure function (the **reducer**), so
every copy of the notebook ends up identical. Things that do not change the
notebook — a stroke still being drawn, a pointer, which page someone is looking
at — are **presence** messages: relayed, never numbered, never stored.

Video and voice do not go through this server. They go through LiveKit; the
room server only issues the LiveKit ticket (see "HTTP API").

## Transport

- One WebSocket per client: `wss://<server>/live`.
- Text frames, one JSON object per frame, UTF-8.
- Every object has a `type` string. Unknown `type`s must be ignored, not
  treated as errors, so a newer server can talk to an older client.
- Unknown fields must be ignored. The server stores strokes and pages
  verbatim, unknown fields included; a client may drop fields it does not know.
- Maximum frame the server accepts: 256 KiB. Maximum stroke: 5,000 points.

## Identifiers

- `uid` — the Firebase user id of a person (anonymous users included).
- `connectionId` — the server's id for one connection. One person may be
  connected from two devices; presence is per connection.
- Stroke, text and page ids are UUID strings. Clients create them.
  Compare them as strings; do not change their case (Swift writes uppercase).
- `clientOpId` — `"<deviceId>:<counter>"`, unique per device. The server
  remembers the `clientOpId`s it has sequenced in a room and never sequences
  the same one twice, so a client may safely resend after a reconnect.

## Data types

### Stroke

Exactly the notebook's `PortableStroke` JSON (`NotebookCore`, schema v13):

```json
{
  "id": "00000051-0000-4000-8000-000000000000",
  "ink": "pen",
  "color": { "r": 0.1, "g": 0.2, "b": 0.3, "a": 1 },
  "width": 2.5,
  "createdAt": "2026-01-02T03:04:05Z",
  "points": [
    { "x": 10, "y": 20, "pressure": 0.5, "timeOffset": 0, "width": 2,
      "azimuth": 0.25, "altitude": 1.1 }
  ],
  "captureStamp": 1767322445.123456
}
```

Page-local coordinates in points, origin top-left. `azimuth`, `altitude` and
`captureStamp` are optional. `ink` is one of `pen`, `pencil`, `marker`,
`monoline`, `fountainPen`, `watercolor`, `crayon`, `reed`, `unknown`; a
reader treats any other value as `unknown`. The highlighter is `marker` with
`a` < 1. The server stores strokes verbatim.

### Text box

```json
{
  "id": "…",
  "text": "Lithium — narrow therapeutic index",
  "frame": { "x": 40, "y": 320, "width": 260, "height": 64 },
  "fontSize": 18,
  "color": { "r": 0.15, "g": 0.18, "b": 0.22, "a": 1 }
}
```

### Page

```json
{
  "id": "…",
  "width": 595, "height": 842,
  "background": { "kind": "blank" }
}
```

`background.kind` is one of:

- `blank`
- `template` with `"template": "lined" | "grid" | "dotted"`
- `image` with `"assetId": "…"` — the host uploaded a picture of the page (a
  PDF page rendered to PNG or JPEG) with `PUT /rooms/{roomId}/assets/{assetId}`.

A reader draws an unknown kind as `blank`.

### Room state (the snapshot)

What every client holds and what the reducer changes:

```json
{
  "protocol": 1,
  "seq": 12,
  "drawPolicy": "everyone",
  "penHolder": null,
  "hostPageId": "…",
  "pages": [
    {
      "id": "…", "width": 595, "height": 842,
      "background": { "kind": "blank" },
      "strokes": [
        { "author": "uid-a", "seq": 3, "erased": false, "stroke": { … } }
      ],
      "texts": [
        { "author": "uid-b", "seq": 7, "erased": false, "text": { … } }
      ]
    }
  ]
}
```

- `seq` — the `seq` of the last op applied. A fresh room starts at 0.
- `drawPolicy` — `everyone` (anyone may change the notebook), `host` (only
  the host), or `pen` (only the host and `penHolder`).
- `hostPageId` — the page the host is on; "Follow host" follows this.
- `strokes` and `texts` keep the order the items were first added. An erased
  item stays in the list with `"erased": true` so an undo can bring it back;
  it is not drawn and not saved into the notebook.
- The `seq` inside an item is the op that added it.

## The reducer

`apply(state, sequencedOp) -> state`. Pure and deterministic: same input,
same output, on every platform. It never fails; an op that does not fit the
state (unknown page, unknown item) changes nothing except `state.seq`. It does
**not** check permissions — the server does that before sequencing, and
clients trust the server's order.

A sequenced op is:

```json
{ "seq": 13, "author": "uid-a", "clientOpId": "dev1:42", "op": { "kind": "…", … } }
```

The reducer first sets `state.seq = seq`, then by `op.kind`:

| kind | fields | effect |
|---|---|---|
| `stroke.add` | `pageId`, `stroke` | If no item on that page has `stroke.id`, append `{author, seq, erased:false, stroke}`. If one exists, nothing (a resend). |
| `stroke.erase` | `pageId`, `strokeIds[]` | Set `erased: true` on each listed stroke that exists. |
| `stroke.restore` | `pageId`, `strokeIds[]` | Set `erased: false` on each listed stroke that exists. |
| `text.upsert` | `pageId`, `text` | If a text with `text.id` exists: replace its `text` and set `erased:false` (keep its `author` and `seq`). Otherwise append `{author, seq, erased:false, text}`. |
| `text.erase` | `pageId`, `textIds[]` | Set `erased: true` on each listed text that exists. |
| `items.move` | `pageId`, `strokeIds[]`, `textIds[]`, `dx`, `dy` | For each listed item that exists **and is not erased**: add `dx`,`dy` to every point's `x`,`y` (strokes) or to `frame.x`,`frame.y` (texts). Erased items are not moved: erase wins. |
| `page.add` | `page`, `afterPageId` (optional, may be null) | If no page has `page.id`: insert `{…page, strokes:[], texts:[]}` after `afterPageId`, or at the end if it is absent, null or unknown. |
| `room.policy` | `drawPolicy`, `penHolder` (optional) | Set `drawPolicy`; set `penHolder` to the value, or null if absent. |
| `host.page` | `pageId` | If the page exists, set `hostPageId`. |

Any other `kind`: only `state.seq` changes.

Moves are translations, and translations add up in any order, so two people
moving the same stroke at once both take effect, which is what a person
expects. There is no rotation or scaling in version 1.

### Numbers

Coordinates are IEEE-754 doubles. `x + dx` is computed once per op, in `seq`
order, so every platform gets the same bits. When writing JSON, write the
shortest representation that reads back to the same double (what
`JSONEncoder`, `kotlinx.serialization` and `JSON.stringify` do); integers
may be written without a decimal point. Fixture comparison is by value, not
by text, and a missing field equals `null`.

## Permissions (server-side)

`authorize(state, member, op) -> ok | reason`. Checked before sequencing.
`member` is `{ uid, role }` with `role` `host` or `guest`.

| op kind | allowed when |
|---|---|
| `room.policy`, `host.page`, `page.add` | role is `host` |
| every other kind | role is `host`; or `drawPolicy` is `everyone`; or `drawPolicy` is `pen` and `penHolder == uid` |

Reasons: `not-host`, `drawing-locked`, `invalid-op`. An op missing a
required field, with a field of the wrong type, or of a kind the server does
not know, is `invalid-op` for everyone, host included. Live
points (presence) follow the same drawing rule; the server drops them
silently when not allowed.

Clients use the same function to grey out their tools, but the server's
answer is the one that counts.

## Messages

### Client → server

`hello` — must be the first frame.

```json
{ "type": "hello", "protocol": 1, "token": "<Firebase ID token>",
  "roomId": "…", "name": "Asha", "deviceId": "ipad-7F3A" }
```

`op` — ask for a change.

```json
{ "type": "op", "clientOpId": "ipad-7F3A:42", "op": { "kind": "stroke.add", … } }
```

`presence` — relayed to everyone else in the room, never stored.

```json
{ "type": "presence", "presence": { "kind": "…", … } }
```

Presence kinds:

| kind | fields | meaning |
|---|---|---|
| `ink.live` | `pageId`, `liveId`, `ink`, `color`, `width`, `p` (flat `[x,y,w, x,y,w, …]`), `done` (bool) | Points of a stroke still being drawn, sent at most every 30 ms. `p` holds only the points since the last message. `done: true` ends it; the committed `stroke.add` follows. `liveId` is the stroke's future `id`, so a receiver swaps the preview for the stroke without a flicker. |
| `pointer` | `pageId`, `x`, `y`, `laser` (bool) | Where the person's pen or finger is. `laser: true` draws a fading laser dot. |
| `pointer.hide` | — | Pointer left the page. |
| `view` | `pageId` | The page this person is looking at. |
| `hand` | `raised` (bool) | Raise or lower a hand. |

`control` — host actions that are not notebook changes.

```json
{ "type": "control", "control": { "kind": "remove", "uid": "…" } }
{ "type": "control", "control": { "kind": "end" } }
```

`ping` — `{ "type": "ping", "t": 123 }`; the server answers `pong` with the same `t`.

### Server → client

`welcome` — after a valid `hello`.

```json
{
  "type": "welcome", "protocol": 1,
  "you": { "uid": "…", "connectionId": "c7", "name": "Asha", "role": "guest", "color": "#E4572E" },
  "room": { "id": "…", "code": "K7QM3X", "title": "Cardiology — lecture 4", "hostUid": "…" },
  "state": { …room state… },
  "members": [ …member… ]
}
```

A client replaces its whole state with `welcome.state`, then re-sends any op
it sent that has not come back yet (same `clientOpId`).

`op` — a sequenced op, sent to everyone including its author.

```json
{ "type": "op", "seq": 13, "author": "uid-a", "clientOpId": "ipad-7F3A:42", "op": { … } }
```

If `seq` is not `state.seq + 1`, the client missed something: it closes the
socket and reconnects (the `welcome` brings it up to date).

`reject` — the op was not sequenced.

```json
{ "type": "reject", "clientOpId": "ipad-7F3A:42", "reason": "drawing-locked" }
```

The client removes the op's local effect (it drew optimistically).

Reasons: `not-host`, `drawing-locked`, `invalid-op`, and `duplicate`. A
`duplicate` reject means the server had already sequenced that `clientOpId`
before this connection (the op was resent after a reconnect). The state in the
last `welcome` already contains it, so the client simply stops treating it as
pending; nothing is rolled back.

`members` — the full member list, sent whenever it changes.

```json
{ "type": "members", "members": [
  { "uid": "…", "connectionId": "c7", "name": "Asha", "role": "guest",
    "color": "#E4572E", "handRaised": false, "pageId": "…" }
] }
```

`presence` — someone else's presence, with who sent it.

```json
{ "type": "presence", "from": { "uid": "…", "connectionId": "c7" }, "presence": { … } }
```

`removed` — the host removed you, or ended the room. The server then closes.

```json
{ "type": "removed", "reason": "removed-by-host" | "room-ended" }
```

`error` — `{ "type": "error", "code": "…", "message": "…" }`, then close.
Codes: `bad-hello`, `unauthenticated`, `no-such-room`, `room-full`,
`guests-not-allowed`, `protocol-mismatch`, `too-large`, `rate-limited`.
A person the host removed who tries to join again gets `removed` with
`removed-by-host` instead of `welcome`.

`pong` — `{ "type": "pong", "t": 123 }`.

## Reconnecting

Cloud Run closes every WebSocket after at most 60 minutes, and phones drop
connections all the time, so reconnecting is normal, not an error. A client:

1. Reconnects with backoff (0.5 s, 1 s, 2 s, 4 s, then every 8 s).
2. Sends `hello` again with a fresh token.
3. Replaces its state with `welcome.state`.
4. Re-applies its own unacknowledged ops on top, locally, and re-sends them
   with their original `clientOpId`. The server skips any it already sequenced.

## HTTP API

Every route except `GET /health` needs `Authorization: Bearer <Firebase ID token>`.

| Route | Who | Does |
|---|---|---|
| `POST /rooms` | anyone signed in | Body `{ title, pages: [page with optional strokes[] and texts[]], allowGuests }`. Creates a room with the caller as host; the given strokes and texts become the room's starting content, authored by the host, at `seq` 0. Returns `{ roomId, code, joinUrl }`. |
| `GET /rooms/code/{code}` | anyone signed in | Returns `{ roomId, title, hostName, allowGuests }`. |
| `PUT /rooms/{roomId}/assets/{assetId}` | host | Body: PNG or JPEG, at most 8 MiB. |
| `GET /rooms/{roomId}/assets/{assetId}` | member | The picture. |
| `POST /rooms/{roomId}/video-token` | member | `{ url, token }` for LiveKit, or 503 `video-unavailable` when the server has no LiveKit keys; clients then carry on with ink only. |
| `GET /rooms/{roomId}/snapshot` | host | The current room state, for saving back into the notebook. |
| `GET /health` | anyone | `ok`. |

Room codes are six characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no
0, O, 1 or I). The join link is `https://<web host>/join/<code>`.

"Anonymous" Firebase users are guests; a room created with
`allowGuests: false` refuses them (`guests-not-allowed`).

## Versioning

`protocol` is 1. A server refuses a `hello` with another version
(`protocol-mismatch`). Adding a message type, an op kind or an optional field
is not a version change, because readers ignore what they do not know. Changing
what an existing op does is.
