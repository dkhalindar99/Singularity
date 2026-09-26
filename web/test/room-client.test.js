// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// The web RoomClient against the real room server, over real WebSockets.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createLiveServer } from "../../server/src/server.js";
import { devAuthenticator } from "../../server/src/auth.js";
import { RoomClient, LiveInkStreamer } from "../src/client/room-client.js";
import { LiveApi } from "../src/client/api.js";

const PAGE1 = "page-1";
let server, base;

before(async () => {
  server = createLiveServer({ authenticate: devAuthenticator(), log: () => {}, roomsPerHour: 1000 });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const stroke = (id, x = 10) => ({
  id, ink: "pen", color: { r: 0, g: 0, b: 0, a: 1 }, width: 2, createdAt: "2026-09-26T10:00:00Z",
  points: [{ x, y: 20, pressure: 1, timeOffset: 0, width: 2 }, { x: x + 5, y: 25, pressure: 1, timeOffset: 0.01, width: 2 }],
});

function until(client, predicate, ms = 2000) {
  return new Promise((resolve, reject) => {
    if (predicate()) return resolve();
    const timer = setTimeout(() => { client.removeEventListener("change", check); reject(new Error("timed out")); }, ms);
    function check() {
      if (!predicate()) return;
      clearTimeout(timer);
      client.removeEventListener("change", check);
      resolve();
    }
    client.addEventListener("change", check);
  });
}

async function room() {
  const api = new LiveApi({ serverUrl: base, getToken: async () => "dev:host:Host" });
  return api.createRoom({ title: "Pharmacology", pages: [{ id: PAGE1, width: 595, height: 842, background: { kind: "blank" } }] });
}

function client(roomId, uid, name) {
  return new RoomClient({ serverUrl: base, roomId, name, deviceId: `${uid}-dev`, getToken: async () => `dev:${uid}:${name}` });
}

const strokes = (c) => c.state.pages[0].strokes;
const visible = (c) => strokes(c).filter((s) => !s.erased).map((s) => s.stroke.id);

test("ink drawn on one device appears on the other; own ink shows before the server answers", async () => {
  const { roomId } = await room();
  const host = client(roomId, "host", "Host");
  const asha = client(roomId, "asha", "Asha");
  host.connect();
  asha.connect();
  await until(host, () => host.status === "connected");
  await until(asha, () => asha.status === "connected" && asha.members.length === 2);

  asha.addStroke(PAGE1, stroke("s1"));
  assert.deepEqual(visible(asha), ["s1"], "optimistic");
  assert.equal(asha.pending.length, 1);
  await until(host, () => visible(host).includes("s1"));
  await until(asha, () => asha.pending.length === 0);
  assert.equal(host.state.seq, 1);
  assert.equal(strokes(host)[0].author, "asha");
  host.disconnect();
  asha.disconnect();
});

test("undo and redo only touch your own work, and redo restores rather than re-adds", async () => {
  const { roomId } = await room();
  const host = client(roomId, "host", "Host");
  const asha = client(roomId, "asha", "Asha");
  host.connect();
  asha.connect();
  await until(asha, () => asha.status === "connected" && asha.members.length === 2);
  await until(host, () => host.status === "connected");

  host.addStroke(PAGE1, stroke("h1"));
  asha.addStroke(PAGE1, stroke("a1"));
  await until(asha, () => visible(asha).length === 2 && asha.pending.length === 0);
  await until(host, () => visible(host).length === 2 && host.pending.length === 0);

  asha.undo();
  await until(host, () => visible(host).join() === "h1");
  asha.redo();
  await until(host, () => visible(host).join() === "h1,a1");
  assert.equal(asha.canRedo, false);
  assert.equal(asha.canUndo, true);

  host.moveItems(PAGE1, { strokeIds: ["a1"] }, 5, 0);
  await until(asha, () => strokes(asha)[1].stroke.points[0].x === 15);
  host.undo();
  await until(asha, () => strokes(asha)[1].stroke.points[0].x === 10);

  host.eraseStrokes(PAGE1, ["a1"]);
  await until(asha, () => visible(asha).join() === "h1");
  host.undo();
  await until(asha, () => visible(asha).join() === "h1,a1");
  host.disconnect();
  asha.disconnect();
});

test("texts: add, edit, undo the edit, erase and undo the erase", async () => {
  const { roomId } = await room();
  const asha = client(roomId, "asha", "Asha");
  asha.connect();
  await until(asha, () => asha.status === "connected");
  const text = { id: "t1", text: "ACE inhibitors", frame: { x: 10, y: 10, width: 200, height: 40 }, fontSize: 16, color: { r: 0, g: 0, b: 0, a: 1 } };
  asha.upsertText(PAGE1, text);
  asha.upsertText(PAGE1, { ...text, text: "ACE inhibitors — cough" });
  await until(asha, () => asha.pending.length === 0);
  const texts = () => asha.state.pages[0].texts;
  assert.equal(texts()[0].text.text, "ACE inhibitors — cough");
  asha.undo();
  await until(asha, () => asha.pending.length === 0 && texts()[0].text.text === "ACE inhibitors");
  asha.eraseTexts(PAGE1, ["t1"]);
  await until(asha, () => asha.pending.length === 0 && texts()[0].erased);
  asha.undo();
  await until(asha, () => asha.pending.length === 0 && !texts()[0].erased);
  asha.undo();
  await until(asha, () => asha.pending.length === 0 && texts()[0].erased, 2000);
  asha.disconnect();
});

test("a locked room rejects a guest's stroke and it disappears again", async () => {
  const { roomId } = await room();
  const host = client(roomId, "host", "Host");
  const ravi = client(roomId, "ravi", "Ravi");
  host.connect();
  ravi.connect();
  await until(host, () => host.status === "connected");
  await until(ravi, () => ravi.status === "connected");
  host.setPolicy("host");
  await until(ravi, () => ravi.state.drawPolicy === "host");
  assert.equal(ravi.canDraw, false);
  assert.equal(host.canDraw, true);

  const rejected = new Promise((r) => ravi.addEventListener("reject", (e) => r(e.detail), { once: true }));
  ravi.addStroke(PAGE1, stroke("r1"));
  assert.deepEqual(visible(ravi), ["r1"]);
  assert.equal((await rejected).reason, "drawing-locked");
  assert.deepEqual(visible(ravi), []);
  assert.equal(ravi.canUndo, false, "a rejected step is dropped");

  host.setPolicy("pen", "ravi");
  await until(ravi, () => ravi.canDraw);
  host.disconnect();
  ravi.disconnect();
});

test("live ink streams to others and is replaced by the committed stroke", async () => {
  const { roomId } = await room();
  const host = client(roomId, "host", "Host");
  const asha = client(roomId, "asha", "Asha");
  host.connect();
  asha.connect();
  await until(host, () => host.status === "connected" && host.members.length === 2);
  await until(asha, () => asha.status === "connected");

  const streamer = new LiveInkStreamer(asha, { intervalMs: 10 });
  streamer.begin({ pageId: PAGE1, liveId: "s-live", ink: "pen", color: { r: 1, g: 0, b: 0, a: 1 }, width: 2 });
  streamer.add(1.04, 2, 2);
  streamer.add(3, 4.26, 2.5);
  await until(host, () => host.live.size === 1 && [...host.live.values()][0].points.length === 2);
  const preview = [...host.live.values()][0];
  assert.deepEqual(preview.points, [[1, 2, 2], [3, 4.3, 2.5]]);
  assert.equal(preview.uid, "asha");
  streamer.add(5, 6, 2);
  streamer.end();
  asha.addStroke(PAGE1, stroke("s-live"));
  await until(host, () => visible(host).includes("s-live") && host.live.size === 0);

  asha.sendPointer(PAGE1, 100.04, 200, true);
  await until(host, () => host.activePointers().length === 1);
  assert.deepEqual({ ...host.activePointers()[0][1], at: 0 }, { uid: "asha", pageId: PAGE1, x: 100, y: 200, laser: true, at: 0 });
  asha.disconnect();
  await until(host, () => host.members.length === 1 && host.pointers.size === 0);
  host.disconnect();
});

test("after a dropped connection, unsent work is delivered exactly once", async () => {
  const { roomId } = await room();
  const asha = client(roomId, "asha", "Asha");
  asha.connect();
  await until(asha, () => asha.status === "connected");
  asha.addStroke(PAGE1, stroke("before"));
  await until(asha, () => asha.pending.length === 0);

  // Cut the socket from under the client, then draw while it is away.
  asha.socket.close();
  await until(asha, () => asha.status === "reconnecting");
  asha.addStroke(PAGE1, stroke("while-away"));
  assert.deepEqual(visible(asha), ["before", "while-away"]);
  await until(asha, () => asha.status === "connected" && asha.pending.length === 0, 4000);
  assert.deepEqual(visible(asha), ["before", "while-away"]);
  assert.equal(asha.confirmed.seq, 2);

  const snapshot = await new LiveApi({ serverUrl: base, getToken: async () => "dev:host:Host" }).snapshot(roomId);
  assert.deepEqual(snapshot.state.pages[0].strokes.map((s) => s.stroke.id), ["before", "while-away"]);
  asha.disconnect();
});

test("follow host: the host's page change reaches everyone; removal ends the session", async () => {
  const { roomId } = await room();
  const host = client(roomId, "host", "Host");
  const ravi = client(roomId, "ravi", "Ravi");
  host.connect();
  ravi.connect();
  await until(host, () => host.status === "connected" && host.members.length === 2);
  await until(ravi, () => ravi.status === "connected");
  host.addPage({ id: "page-2", width: 595, height: 842, background: { kind: "template", template: "lined" } }, PAGE1);
  host.setHostPage("page-2");
  await until(ravi, () => ravi.state.hostPageId === "page-2" && ravi.state.pages.length === 2);

  ravi.setHandRaised(true);
  await until(host, () => host.members.find((m) => m.uid === "ravi")?.handRaised === true);

  host.removeMember("ravi");
  await until(ravi, () => ravi.status === "ended");
  assert.equal(ravi.endedReason, "removed-by-host");
  host.endRoom();
  await until(host, () => host.status === "ended");
  assert.equal(host.endedReason, "room-ended");
});

test("the API: lookup by code, video unavailable without keys", async () => {
  const api = new LiveApi({ serverUrl: base, getToken: async () => "dev:host:Host" });
  const { roomId, code } = await room();
  const found = await api.lookup(code.toLowerCase());
  assert.equal(found.roomId, roomId);
  assert.equal(await api.lookup("ZZZZZ9"), null);
  assert.equal(await api.videoToken(roomId), null);
});

test("an op too large for one frame is refused locally, never sent", async () => {
  const { roomId } = await room();
  const asha = client(roomId, "asha", "Asha");
  asha.connect();
  await until(asha, () => asha.status === "connected");
  const huge = stroke("huge");
  huge.points = Array.from({ length: 4000 }, (_, i) => ({ x: i, y: i, pressure: 1, timeOffset: i, width: 2, padding: "x".repeat(300) }));
  const rejected = new Promise((r) => asha.addEventListener("reject", (e) => r(e.detail), { once: true }));
  asha.addStroke(PAGE1, huge);
  assert.equal((await rejected).reason, "too-large");
  assert.equal(asha.pending.length, 0);
  assert.equal(asha.canUndo, false);
  asha.addStroke(PAGE1, stroke("small"));
  await until(asha, () => asha.pending.length === 0 && asha.confirmed.seq === 1);
  assert.equal(asha.status, "connected");
  asha.disconnect();
});

test("op ids never repeat across a reload of the same device", async () => {
  const { roomId } = await room();
  const first = client(roomId, "asha", "Asha");
  first.connect();
  await until(first, () => first.status === "connected");
  first.addStroke(PAGE1, stroke("one"));
  await until(first, () => first.pending.length === 0);
  first.disconnect();
  await new Promise((r) => setTimeout(r, 5));
  const reloaded = client(roomId, "asha", "Asha"); // same deviceId, as after a page reload
  reloaded.connect();
  await until(reloaded, () => reloaded.status === "connected");
  reloaded.addStroke(PAGE1, stroke("two"));
  await until(reloaded, () => reloaded.pending.length === 0);
  assert.deepEqual(visible(reloaded), ["one", "two"]);
  reloaded.disconnect();
});

test("a stroke the server refuses stops being previewed for others", async () => {
  const { roomId } = await room();
  const host = client(roomId, "host", "Host");
  const ravi = client(roomId, "ravi", "Ravi");
  host.connect();
  ravi.connect();
  await until(host, () => host.status === "connected" && host.members.length === 2);
  await until(ravi, () => ravi.status === "connected");
  host.setPolicy("pen", "ravi");
  await until(ravi, () => ravi.canDraw);
  const streamer = new LiveInkStreamer(ravi, { intervalMs: 5 });
  streamer.begin({ pageId: PAGE1, liveId: "never", ink: "pen", color: { r: 0, g: 0, b: 0, a: 1 }, width: 2 });
  streamer.add(1, 1, 2);
  await until(host, () => host.live.size === 1);
  streamer.end(); // and no stroke.add follows
  await new Promise((r) => setTimeout(r, 300));
  assert.equal(host.live.size, 1, "kept while the stroke may still arrive");
  await until(host, () => host.live.size === 0, 3000);
  host.disconnect();
  ravi.disconnect();
});
