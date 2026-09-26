// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Writes fixtures/protocol/. Every `expected` below is written out by hand
// from protocol/PROTOCOL.md, never computed by a reducer, so the fixtures
// check the reducers rather than echo one of them.
//
//   node fixtures/tools/make-fixtures.mjs

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "protocol");
const write = (path, value) => {
  const file = join(root, path);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
};

// Ids are uppercase where Swift would write them, lowercase elsewhere, so
// every port learns to compare them as plain strings.
const PAGE1 = "00000001-0000-4000-8000-000000000001";
const PAGE2 = "00000001-0000-4000-8000-000000000002";
const PAGE3 = "00000001-0000-4000-8000-000000000003";
const S1 = "0000000A-0000-4000-8000-000000000001";
const S2 = "0000000a-0000-4000-8000-000000000002";
const S3 = "0000000A-0000-4000-8000-000000000003";
const T1 = "0000000B-0000-4000-8000-000000000001";
const HOST = "uid-host";
const ASHA = "uid-asha";
const RAVI = "uid-ravi";

const blankPage = (id, extra = {}) => ({ id, width: 595, height: 842, background: { kind: "blank" }, ...extra });
const color = (r, g, b, a = 1) => ({ r, g, b, a });

const stroke1 = () => ({
  id: S1,
  ink: "pen",
  color: color(0.1, 0.2, 0.3),
  width: 2.5,
  createdAt: "2026-01-02T03:04:05Z",
  points: [
    { x: 10, y: 20, pressure: 0.5, timeOffset: 0, width: 2, azimuth: 0.25, altitude: 1.1 },
    { x: 30.5, y: 41.25, pressure: 1.75, timeOffset: 0.016, width: 2.5, azimuth: 0.3, altitude: 1.2 },
    { x: 50, y: 60, pressure: 0.25, timeOffset: 0.032, width: 3 },
  ],
  captureStamp: 1767322445.123456,
});
const stroke2 = () => ({
  id: S2,
  ink: "marker",
  color: color(1, 0.9, 0.2, 0.35),
  width: 12,
  createdAt: "2026-01-02T03:04:06Z",
  points: [
    { x: 0.1, y: 100, pressure: 1, timeOffset: 0, width: 12 },
    { x: 200, y: 100.5, pressure: 1, timeOffset: 0.1, width: 12 },
  ],
});
const stroke3 = () => ({
  id: S3,
  ink: "pencil",
  color: color(0, 0, 0),
  width: 1,
  createdAt: "2026-01-02T03:04:07Z",
  points: [{ x: 5, y: 5, pressure: 0.8, timeOffset: 0, width: 1 }],
});
const text1 = (overrides = {}) => ({
  id: T1,
  text: "Lithium — narrow therapeutic index",
  frame: { x: 40, y: 320, width: 260, height: 64 },
  fontSize: 18,
  color: color(0.15, 0.18, 0.22),
  ...overrides,
});

const state = (fields) => ({
  protocol: 1,
  seq: 0,
  drawPolicy: "everyone",
  penHolder: null,
  hostPageId: PAGE1,
  pages: [],
  ...fields,
});
const page = (id, strokes = [], texts = [], extra = {}) => ({ ...blankPage(id, extra), strokes, texts });
const op = (seq, author, clientOpId, body) => ({ seq, author, clientOpId, op: body });

const scenarios = [
  {
    name: "add-strokes",
    description: "Two people add strokes. A resent stroke.add with an id already on the page changes nothing but seq.",
    initial: state({ pages: [page(PAGE1)] }),
    ops: [
      op(1, ASHA, "a:1", { kind: "stroke.add", pageId: PAGE1, stroke: stroke1() }),
      op(2, RAVI, "r:1", { kind: "stroke.add", pageId: PAGE1, stroke: stroke2() }),
      op(3, ASHA, "a:2", { kind: "stroke.add", pageId: PAGE1, stroke: { ...stroke1(), width: 99 } }),
    ],
    expected: state({
      seq: 3,
      pages: [page(PAGE1, [
        { author: ASHA, seq: 1, erased: false, stroke: stroke1() },
        { author: RAVI, seq: 2, erased: false, stroke: stroke2() },
      ])],
    }),
  },
  {
    name: "erase-and-restore",
    description: "Erase keeps the stroke as a tombstone; restore brings it back. Unknown ids are skipped.",
    initial: state({
      seq: 2,
      pages: [page(PAGE1, [
        { author: ASHA, seq: 1, erased: false, stroke: stroke1() },
        { author: RAVI, seq: 2, erased: false, stroke: stroke2() },
      ])],
    }),
    ops: [
      op(3, RAVI, "r:2", { kind: "stroke.erase", pageId: PAGE1, strokeIds: [S1, S2, "no-such-stroke"] }),
      op(4, RAVI, "r:3", { kind: "stroke.restore", pageId: PAGE1, strokeIds: [S2] }),
    ],
    expected: state({
      seq: 4,
      pages: [page(PAGE1, [
        { author: ASHA, seq: 1, erased: true, stroke: stroke1() },
        { author: RAVI, seq: 2, erased: false, stroke: stroke2() },
      ])],
    }),
  },
  {
    name: "move-adds-up-and-erase-wins",
    description: "Two moves of the same stroke add up. An erased stroke is not moved. 0.1 + 0.2 must give the same double everywhere.",
    initial: state({
      seq: 3,
      pages: [page(PAGE1, [
        { author: ASHA, seq: 1, erased: false, stroke: stroke1() },
        { author: RAVI, seq: 2, erased: false, stroke: stroke2() },
        { author: RAVI, seq: 3, erased: false, stroke: stroke3() },
      ], [
        { author: HOST, seq: 0, erased: false, text: text1() },
      ])],
    }),
    ops: [
      op(4, ASHA, "a:3", { kind: "items.move", pageId: PAGE1, strokeIds: [S1, S2], textIds: [T1], dx: 0.2, dy: -3.25 }),
      op(5, RAVI, "r:4", { kind: "items.move", pageId: PAGE1, strokeIds: [S1], textIds: [], dx: 10, dy: 10 }),
      op(6, RAVI, "r:5", { kind: "stroke.erase", pageId: PAGE1, strokeIds: [S3] }),
      op(7, ASHA, "a:4", { kind: "items.move", pageId: PAGE1, strokeIds: [S3], dx: 100, dy: 100 }),
    ],
    expected: state({
      seq: 7,
      pages: [page(PAGE1, [
        {
          author: ASHA, seq: 1, erased: false, stroke: {
            ...stroke1(),
            points: [
              { x: 20.2, y: 26.75, pressure: 0.5, timeOffset: 0, width: 2, azimuth: 0.25, altitude: 1.1 },
              { x: 40.7, y: 48, pressure: 1.75, timeOffset: 0.016, width: 2.5, azimuth: 0.3, altitude: 1.2 },
              { x: 60.2, y: 66.75, pressure: 0.25, timeOffset: 0.032, width: 3 },
            ],
          },
        },
        {
          author: RAVI, seq: 2, erased: false, stroke: {
            ...stroke2(),
            points: [
              { x: 0.30000000000000004, y: 96.75, pressure: 1, timeOffset: 0, width: 12 },
              { x: 200.2, y: 97.25, pressure: 1, timeOffset: 0.1, width: 12 },
            ],
          },
        },
        { author: RAVI, seq: 3, erased: true, stroke: stroke3() },
      ], [
        { author: HOST, seq: 0, erased: false, text: text1({ frame: { x: 40.2, y: 316.75, width: 260, height: 64 } }) },
      ])],
    }),
  },
  {
    name: "text-upsert-and-erase",
    description: "An edit by someone else keeps the original author and seq. Upserting an erased text brings it back.",
    initial: state({ pages: [page(PAGE1)] }),
    ops: [
      op(1, ASHA, "a:1", { kind: "text.upsert", pageId: PAGE1, text: text1() }),
      op(2, RAVI, "r:1", { kind: "text.upsert", pageId: PAGE1, text: text1({ text: "Lithium — check levels", fontSize: 20 }) }),
      op(3, RAVI, "r:2", { kind: "text.erase", pageId: PAGE1, textIds: [T1] }),
      op(4, ASHA, "a:2", { kind: "text.upsert", pageId: PAGE1, text: text1({ text: "Lithium — back again" }) }),
    ],
    expected: state({
      seq: 4,
      pages: [page(PAGE1, [], [
        { author: ASHA, seq: 1, erased: false, text: text1({ text: "Lithium — back again" }) },
      ])],
    }),
  },
  {
    name: "pages-and-policy",
    description: "Pages insert after the named page, or at the end. Duplicate pages are ignored. host.page ignores unknown pages. room.policy without penHolder clears it.",
    initial: state({ pages: [page(PAGE1), page(PAGE2)] }),
    ops: [
      op(1, HOST, "h:1", { kind: "page.add", page: blankPage(PAGE3, { background: { kind: "template", template: "grid" } }), afterPageId: PAGE1 }),
      op(2, HOST, "h:2", { kind: "page.add", page: blankPage(PAGE3, { width: 1 }), afterPageId: null }),
      op(3, HOST, "h:3", { kind: "host.page", pageId: PAGE3 }),
      op(4, HOST, "h:4", { kind: "host.page", pageId: "no-such-page" }),
      op(5, HOST, "h:5", { kind: "room.policy", drawPolicy: "pen", penHolder: ASHA }),
      op(6, HOST, "h:6", { kind: "room.policy", drawPolicy: "host" }),
    ],
    expected: state({
      seq: 6,
      drawPolicy: "host",
      penHolder: null,
      hostPageId: PAGE3,
      pages: [
        page(PAGE1),
        page(PAGE3, [], [], { background: { kind: "template", template: "grid" } }),
        page(PAGE2),
      ],
    }),
  },
  {
    name: "page-add-unknown-anchor",
    description: "An afterPageId that does not exist appends at the end.",
    initial: state({ pages: [page(PAGE1)] }),
    ops: [
      op(1, HOST, "h:1", { kind: "page.add", page: blankPage(PAGE2, { background: { kind: "image", assetId: "asset-7" } }), afterPageId: "missing" }),
    ],
    expected: state({
      seq: 1,
      pages: [page(PAGE1), page(PAGE2, [], [], { background: { kind: "image", assetId: "asset-7" } })],
    }),
  },
  {
    name: "unknown-kind-and-page",
    description: "Ops for an unknown page, and unknown op kinds, change only seq.",
    initial: state({ pages: [page(PAGE1)] }),
    ops: [
      op(1, ASHA, "a:1", { kind: "stroke.add", pageId: "no-such-page", stroke: stroke1() }),
      op(2, ASHA, "a:2", { kind: "shape.add", pageId: PAGE1, shape: { circle: true } }),
      op(3, ASHA, "a:3", { kind: "text.erase", pageId: PAGE1, textIds: [T1] }),
    ],
    expected: state({ seq: 3, pages: [page(PAGE1)] }),
  },
];

for (const scenario of scenarios) write(`scenarios/${scenario.name}.json`, scenario);

// Permissions: one file, many cases.
const policyState = (drawPolicy, penHolder = null) => state({ drawPolicy, penHolder, pages: [page(PAGE1)] });
const host = { uid: HOST, role: "host" };
const asha = { uid: ASHA, role: "guest" };
const ravi = { uid: RAVI, role: "guest" };
const add = { kind: "stroke.add", pageId: PAGE1, stroke: stroke1() };
const cases = [
  ["guest draws when everyone may", policyState("everyone"), asha, add, null],
  ["guest drawing locked to host", policyState("host"), asha, add, "drawing-locked"],
  ["host draws when locked", policyState("host"), host, add, null],
  ["pen holder draws", policyState("pen", ASHA), asha, add, null],
  ["other guest while someone holds the pen", policyState("pen", ASHA), ravi, add, "drawing-locked"],
  ["host draws while a guest holds the pen", policyState("pen", ASHA), host, add, null],
  ["guest erases when locked", policyState("host"), asha, { kind: "stroke.erase", pageId: PAGE1, strokeIds: [S1] }, "drawing-locked"],
  ["guest moves when everyone may", policyState("everyone"), asha, { kind: "items.move", pageId: PAGE1, strokeIds: [S1], dx: 1, dy: 2 }, null],
  ["guest adds a page", policyState("everyone"), asha, { kind: "page.add", page: blankPage(PAGE2) }, "not-host"],
  ["guest sets policy", policyState("everyone"), asha, { kind: "room.policy", drawPolicy: "everyone" }, "not-host"],
  ["guest moves the host page", policyState("everyone"), asha, { kind: "host.page", pageId: PAGE1 }, "not-host"],
  ["host sets pen policy", policyState("everyone"), host, { kind: "room.policy", drawPolicy: "pen", penHolder: RAVI }, null],
  ["host sets an unknown policy", policyState("everyone"), host, { kind: "room.policy", drawPolicy: "chaos" }, "invalid-op"],
  ["stroke without points", policyState("everyone"), asha, { kind: "stroke.add", pageId: PAGE1, stroke: { ...stroke1(), points: [] } }, "invalid-op"],
  ["stroke with a string coordinate", policyState("everyone"), asha, { kind: "stroke.add", pageId: PAGE1, stroke: { ...stroke1(), points: [{ x: "1", y: 2, pressure: 1, timeOffset: 0, width: 1 }] } }, "invalid-op"],
  ["move without dx", policyState("everyone"), asha, { kind: "items.move", pageId: PAGE1, strokeIds: [S1], dy: 2 }, "invalid-op"],
  ["unknown kind", policyState("everyone"), host, { kind: "shape.add", pageId: PAGE1 }, "invalid-op"],
  ["text with no frame", policyState("everyone"), asha, { kind: "text.upsert", pageId: PAGE1, text: { id: T1, text: "x", fontSize: 12, color: color(0, 0, 0) } }, "invalid-op"],
  ["text by a guest", policyState("everyone"), asha, { kind: "text.upsert", pageId: PAGE1, text: text1() }, null],
];
write("permissions/cases.json", {
  description: "authorize(state, member, op): null means allowed, otherwise the reason. See protocol/PROTOCOL.md, Permissions.",
  cases: cases.map(([name, st, member, o, expected]) => ({ name, state: st, member, op: o, expected })),
});

// Messages: examples of every frame, for decode/encode round trips.
const member = (uid, connectionId, name, role, colorHex, extra = {}) => ({
  uid, connectionId, name, role, color: colorHex, handRaised: false, pageId: PAGE1, ...extra,
});
const serverMessages = {
  "welcome": {
    type: "welcome",
    protocol: 1,
    you: { uid: ASHA, connectionId: "c2", name: "Asha", role: "guest", color: "#E4572E" },
    room: { id: "room-1", code: "K7QM3X", title: "Cardiology — lecture 4", hostUid: HOST },
    state: state({ seq: 1, pages: [page(PAGE1, [{ author: HOST, seq: 1, erased: false, stroke: stroke1() }], [{ author: HOST, seq: 0, erased: false, text: text1() }])] }),
    members: [member(HOST, "c1", "Host", "host", "#3B5BDB"), member(ASHA, "c2", "Asha", "guest", "#E4572E")],
  },
  "op": { type: "op", seq: 13, author: ASHA, clientOpId: "ipad-7F3A:42", op: { kind: "stroke.erase", pageId: PAGE1, strokeIds: [S1] } },
  "reject": { type: "reject", clientOpId: "ipad-7F3A:43", reason: "drawing-locked" },
  "members": { type: "members", members: [member(HOST, "c1", "Host", "host", "#3B5BDB", { handRaised: true, pageId: PAGE2 })] },
  "presence-ink-live": {
    type: "presence",
    from: { uid: ASHA, connectionId: "c2" },
    presence: { kind: "ink.live", pageId: PAGE1, liveId: S1, ink: "pen", color: color(0.1, 0.2, 0.3), width: 2.5, p: [10, 20, 2, 30.5, 41.3, 2.5], done: false },
  },
  "presence-pointer": { type: "presence", from: { uid: RAVI, connectionId: "c3" }, presence: { kind: "pointer", pageId: PAGE1, x: 120.5, y: 300, laser: true } },
  "presence-pointer-hide": { type: "presence", from: { uid: RAVI, connectionId: "c3" }, presence: { kind: "pointer.hide" } },
  "presence-view": { type: "presence", from: { uid: RAVI, connectionId: "c3" }, presence: { kind: "view", pageId: PAGE2 } },
  "presence-hand": { type: "presence", from: { uid: RAVI, connectionId: "c3" }, presence: { kind: "hand", raised: true } },
  "removed": { type: "removed", reason: "removed-by-host" },
  "error": { type: "error", code: "no-such-room", message: "That room has ended." },
  "pong": { type: "pong", t: 123 },
  "unknown-type": { type: "confetti", colour: "gold" },
  "welcome-with-extra-fields": {
    type: "welcome",
    protocol: 1,
    futureTopLevel: { anything: [1, 2, 3] },
    you: { uid: ASHA, connectionId: "c2", name: "Asha", role: "guest", color: "#E4572E", futureFlag: true },
    room: { id: "room-1", code: "K7QM3X", title: "Extra fields", hostUid: HOST, futureRoomField: 5 },
    state: state({ seq: 0, pages: [page(PAGE1, [], [], { background: { kind: "hologram", depth: 3 } })] }),
    members: [],
  },
};
const clientMessages = {
  "hello": { type: "hello", protocol: 1, token: "eyJhbGciOi.test.token", roomId: "room-1", name: "Asha", deviceId: "ipad-7F3A" },
  "op-stroke-add": { type: "op", clientOpId: "ipad-7F3A:42", op: { kind: "stroke.add", pageId: PAGE1, stroke: stroke1() } },
  "op-items-move": { type: "op", clientOpId: "ipad-7F3A:44", op: { kind: "items.move", pageId: PAGE1, strokeIds: [S1], textIds: [T1], dx: -4.5, dy: 12 } },
  "op-text-upsert": { type: "op", clientOpId: "web-1:1", op: { kind: "text.upsert", pageId: PAGE1, text: text1() } },
  "op-page-add": { type: "op", clientOpId: "web-1:2", op: { kind: "page.add", page: blankPage(PAGE2, { background: { kind: "template", template: "lined" } }), afterPageId: PAGE1 } },
  "op-room-policy": { type: "op", clientOpId: "web-1:3", op: { kind: "room.policy", drawPolicy: "pen", penHolder: ASHA } },
  "presence-ink-live-done": { type: "presence", presence: { kind: "ink.live", pageId: PAGE1, liveId: S1, ink: "pen", color: color(0.1, 0.2, 0.3), width: 2.5, p: [50, 60, 3], done: true } },
  "presence-view": { type: "presence", presence: { kind: "view", pageId: PAGE1 } },
  "control-remove": { type: "control", control: { kind: "remove", uid: RAVI } },
  "control-end": { type: "control", control: { kind: "end" } },
  "ping": { type: "ping", t: 123 },
};
write("messages/server-to-client.json", {
  description: "Every server frame a client must decode. 'unknown-type' must be ignored without error; extra fields must be ignored.",
  messages: serverMessages,
});
write("messages/client-to-server.json", {
  description: "Every client frame. A client's encoder must produce each of these (by value) from its own types, and its decoder must read them back.",
  messages: clientMessages,
});

console.log(`Wrote ${scenarios.length} scenarios, ${cases.length} permission cases, ` +
  `${Object.keys(serverMessages).length + Object.keys(clientMessages).length} messages to ${root}`);
