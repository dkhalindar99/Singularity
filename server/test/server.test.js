// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { createLiveServer } from "../src/server.js";
import { devAuthenticator } from "../src/auth.js";
import { MemoryStore } from "../src/store.js";
import { connect } from "../src/websocket.js";

const PAGE1 = "00000001-0000-4000-8000-000000000001";
const PAGE2 = "00000001-0000-4000-8000-000000000002";
const LIVEKIT = { url: "wss://example.livekit.cloud", apiKey: "APIkey123", apiSecret: "secret-that-is-long-enough-000000" };

const stroke = (id, x = 10) => ({
  id, ink: "pen", color: { r: 0, g: 0, b: 0, a: 1 }, width: 2, createdAt: "2026-09-26T10:00:00Z",
  points: [{ x, y: 20, pressure: 1, timeOffset: 0, width: 2 }, { x: x + 5, y: 25, pressure: 1, timeOffset: 0.01, width: 2 }],
});

let server, base, store;

async function start(options = {}) {
  const s = createLiveServer({ authenticate: devAuthenticator(), store: options.store ?? new MemoryStore(), log: () => {}, roomsPerHour: 1000, ...options });
  await new Promise((resolve) => s.listen(0, "127.0.0.1", resolve));
  return { server: s, base: `http://127.0.0.1:${s.address().port}` };
}

before(async () => {
  store = new MemoryStore();
  ({ server, base } = await start({ store, liveKit: LIVEKIT }));
});
after(() => server.close());

async function api(method, path, token, body, headers = {}) {
  const response = await fetch(base + path, {
    method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body && !(body instanceof Buffer) ? { "Content-Type": "application/json" } : {}), ...headers },
    body: body instanceof Buffer ? body : body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let json = null;
  try { json = JSON.parse(text); } catch {}
  return { status: response.status, json, text, headers: response.headers };
}

async function createRoom(token = "dev:host:Host", extra = {}) {
  const res = await api("POST", "/rooms", token, {
    title: "Cardiology — lecture 4",
    pages: [
      { id: PAGE1, width: 595, height: 842, background: { kind: "blank" }, strokes: [stroke("start-1")] },
      { id: PAGE2, width: 842, height: 595, background: { kind: "template", template: "grid" } },
    ],
    ...extra,
  });
  assert.equal(res.status, 201, res.text);
  return res.json;
}

/** A test participant: a real WebSocket plus an inbox. */
async function join(roomId, token, name, { protocol = 1, baseUrl = base } = {}) {
  const ws = await connect(baseUrl.replace("http", "ws") + "/live");
  const inbox = [];
  const taken = new WeakSet();
  const waiters = [];
  ws.on("message", (text) => {
    const message = JSON.parse(text);
    inbox.push(message);
    for (const w of [...waiters]) if (w.match(message)) { waiters.splice(waiters.indexOf(w), 1); w.resolve(message); }
  });
  let closed = false;
  ws.on("close", () => { closed = true; });
  const client = {
    ws, inbox,
    get closed() { return closed; },
    send: (m) => ws.sendJSON(m),
    next(match, ms = 2000) {
      const found = inbox.find((m) => match(m) && !taken.has(m));
      if (found) { taken.add(found); return Promise.resolve(found); }
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("timed out waiting for a message")), ms);
        waiters.push({ match, resolve: (m) => { clearTimeout(timer); taken.add(m); resolve(m); } });
      });
    },
    type: (type, ms) => client.next((m) => m.type === type, ms),
    close: () => ws.close(),
  };
  client.send({ type: "hello", protocol, token, roomId, name, deviceId: `${name}-device` });
  return client;
}

const quiet = (ms = 150) => new Promise((r) => setTimeout(r, ms));

test("health", async () => {
  const res = await api("GET", "/health");
  assert.equal(res.status, 200);
  assert.equal(res.text, "ok");
});

test("routes need a token", async () => {
  assert.equal((await api("POST", "/rooms", null, { title: "x", pages: [] })).status, 401);
  assert.equal((await api("GET", "/rooms/code/ABCDEF", "not-a-token")).status, 401);
});

test("creating a room validates its pages", async () => {
  const bad = await api("POST", "/rooms", "dev:host:Host", { title: "x", pages: [{ id: "p", width: 0, height: 1, background: { kind: "blank" } }] });
  assert.equal(bad.status, 400);
  const badStroke = await api("POST", "/rooms", "dev:host:Host", { title: "x", pages: [{ id: "p", width: 10, height: 10, background: { kind: "blank" }, strokes: [{ id: "s" }] }] });
  assert.equal(badStroke.status, 400);
});

test("create, look up by code, join and share ink", async () => {
  const { roomId, code, joinUrl } = await createRoom();
  assert.match(code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/);
  assert.equal(joinUrl, `${base}/join/${code}`);

  const lookup = await api("GET", `/rooms/code/${code.toLowerCase()}`, "dev:asha:Asha");
  assert.equal(lookup.status, 200);
  assert.deepEqual(lookup.json, { roomId, title: "Cardiology — lecture 4", hostName: "Host", allowGuests: true });

  const host = await join(roomId, "dev:host:Host", "Host");
  const hostWelcome = await host.type("welcome");
  assert.equal(hostWelcome.you.role, "host");
  assert.equal(hostWelcome.state.seq, 0);
  assert.equal(hostWelcome.state.hostPageId, PAGE1);
  assert.equal(hostWelcome.state.pages[0].strokes[0].author, "host");
  assert.equal(hostWelcome.room.code, code);

  const asha = await join(roomId, "dev:asha:Asha", "Asha");
  const ashaWelcome = await asha.type("welcome");
  assert.equal(ashaWelcome.you.role, "guest");
  assert.notEqual(ashaWelcome.you.color, hostWelcome.you.color);
  const members = await host.next((m) => m.type === "members" && m.members.length === 2);
  assert.deepEqual(members.members.map((m) => m.name).sort(), ["Asha", "Host"]);

  asha.send({ type: "op", clientOpId: "asha-device:1", op: { kind: "stroke.add", pageId: PAGE1, stroke: stroke("s-asha") } });
  const toHost = await host.type("op");
  const toAsha = await asha.type("op");
  assert.equal(toHost.seq, 1);
  assert.equal(toHost.author, "asha");
  assert.equal(toHost.clientOpId, "asha-device:1");
  assert.deepEqual(toAsha, toHost);

  const snapshot = await api("GET", `/rooms/${roomId}/snapshot`, "dev:host:Host");
  assert.equal(snapshot.status, 200);
  assert.equal(snapshot.json.state.seq, 1);
  assert.equal(snapshot.json.state.pages[0].strokes.length, 2);
  assert.equal((await api("GET", `/rooms/${roomId}/snapshot`, "dev:asha:Asha")).status, 403);

  host.close();
  asha.close();
});

test("the host locks drawing; guests are rejected and their live ink is dropped", async () => {
  const { roomId } = await createRoom();
  const host = await join(roomId, "dev:host:Host", "Host");
  await host.type("welcome");
  const asha = await join(roomId, "dev:asha:Asha", "Asha");
  await asha.type("welcome");
  const ravi = await join(roomId, "dev:ravi:Ravi", "Ravi");
  await ravi.type("welcome");

  asha.send({ type: "op", clientOpId: "a:1", op: { kind: "room.policy", drawPolicy: "host" } });
  assert.deepEqual(await asha.type("reject"), { type: "reject", clientOpId: "a:1", reason: "not-host" });

  host.send({ type: "op", clientOpId: "h:1", op: { kind: "room.policy", drawPolicy: "pen", penHolder: "ravi" } });
  assert.equal((await asha.type("op")).op.drawPolicy, "pen");

  asha.send({ type: "op", clientOpId: "a:2", op: { kind: "stroke.add", pageId: PAGE1, stroke: stroke("s-a") } });
  assert.equal((await asha.type("reject")).reason, "drawing-locked");

  ravi.send({ type: "op", clientOpId: "r:1", op: { kind: "stroke.add", pageId: PAGE1, stroke: stroke("s-r") } });
  assert.equal((await asha.type("op")).author, "ravi");

  asha.send({ type: "presence", presence: { kind: "ink.live", pageId: PAGE1, liveId: "live-a", ink: "pen", color: { r: 0, g: 0, b: 0, a: 1 }, width: 2, p: [1, 2, 2], done: false } });
  ravi.send({ type: "presence", presence: { kind: "ink.live", pageId: PAGE1, liveId: "live-r", ink: "pen", color: { r: 0, g: 0, b: 0, a: 1 }, width: 2, p: [1, 2, 2], done: false } });
  const live = await host.next((m) => m.type === "presence" && m.presence.kind === "ink.live");
  assert.equal(live.presence.liveId, "live-r");
  assert.equal(live.from.uid, "ravi");
  await quiet();
  assert.equal(host.inbox.filter((m) => m.type === "presence" && m.presence.liveId === "live-a").length, 0);
  assert.equal(ravi.inbox.filter((m) => m.type === "presence" && m.presence.liveId === "live-r").length, 0, "presence is not echoed");

  asha.send({ type: "op", clientOpId: "a:3", op: { kind: "stroke.add", pageId: PAGE1, stroke: { ...stroke("s-bad"), points: [] } } });
  assert.equal((await asha.type("reject")).reason, "invalid-op");

  for (const c of [host, asha, ravi]) c.close();
});

test("a resent op is not sequenced twice", async () => {
  const { roomId } = await createRoom();
  const asha = await join(roomId, "dev:asha:Asha", "Asha");
  await asha.type("welcome");
  const op = { type: "op", clientOpId: "asha-device:7", op: { kind: "stroke.add", pageId: PAGE1, stroke: stroke("s-1") } };
  asha.send(op);
  assert.equal((await asha.type("op")).seq, 1);
  asha.close();
  await quiet();

  const again = await join(roomId, "dev:asha:Asha", "Asha");
  const welcome = await again.type("welcome");
  assert.equal(welcome.state.seq, 1);
  again.send(op);
  assert.deepEqual(await again.type("reject"), { type: "reject", clientOpId: "asha-device:7", reason: "duplicate" });
  await quiet();
  assert.equal(again.inbox.filter((m) => m.type === "op").length, 0);
  again.close();
});

test("presence: pointers, views and raised hands", async () => {
  const { roomId } = await createRoom();
  const host = await join(roomId, "dev:host:Host", "Host");
  await host.type("welcome");
  const asha = await join(roomId, "dev:asha:Asha", "Asha");
  await asha.type("welcome");

  asha.send({ type: "presence", presence: { kind: "pointer", pageId: PAGE1, x: 10, y: 20, laser: true } });
  const pointer = await host.next((m) => m.type === "presence" && m.presence.kind === "pointer");
  assert.deepEqual(pointer.presence, { kind: "pointer", pageId: PAGE1, x: 10, y: 20, laser: true });

  asha.send({ type: "presence", presence: { kind: "view", pageId: PAGE2 } });
  await host.next((m) => m.type === "presence" && m.presence.kind === "view");
  asha.send({ type: "presence", presence: { kind: "hand", raised: true } });
  const members = await host.next((m) => m.type === "members" && m.members.some((x) => x.uid === "asha" && x.handRaised));
  const ashaMember = members.members.find((x) => x.uid === "asha");
  assert.equal(ashaMember.pageId, PAGE2);

  asha.send({ type: "ping", t: 42 });
  assert.deepEqual(await asha.type("pong"), { type: "pong", t: 42 });
  host.close();
  asha.close();
});

test("the host removes someone, who cannot come back", async () => {
  const { roomId } = await createRoom();
  const host = await join(roomId, "dev:host:Host", "Host");
  await host.type("welcome");
  const ravi = await join(roomId, "dev:ravi:Ravi", "Ravi");
  await ravi.type("welcome");

  ravi.send({ type: "control", control: { kind: "remove", uid: "host" } }); // guests cannot
  host.send({ type: "control", control: { kind: "remove", uid: "ravi" } });
  assert.deepEqual(await ravi.type("removed"), { type: "removed", reason: "removed-by-host" });
  await host.next((m) => m.type === "members" && m.members.length === 1);

  const back = await join(roomId, "dev:ravi:Ravi", "Ravi");
  assert.equal((await back.type("removed")).reason, "removed-by-host");
  assert.equal((await api("POST", `/rooms/${roomId}/video-token`, "dev:ravi:Ravi")).status, 403);
  host.close();
});

test("ending the room sends everyone away and retires the code", async () => {
  const { roomId, code } = await createRoom();
  const host = await join(roomId, "dev:host:Host", "Host");
  await host.type("welcome");
  const asha = await join(roomId, "dev:asha:Asha", "Asha");
  await asha.type("welcome");
  host.send({ type: "control", control: { kind: "end" } });
  assert.equal((await asha.type("removed")).reason, "room-ended");
  assert.equal((await host.type("removed")).reason, "room-ended");
  server.registry.sweep();
  assert.equal((await api("GET", `/rooms/code/${code}`, "dev:asha:Asha")).status, 404);
  const late = await join(roomId, "dev:asha:Asha", "Asha");
  assert.equal((await late.type("error")).code, "no-such-room");
  const snapshot = await api("GET", `/rooms/${roomId}/snapshot`, "dev:host:Host");
  assert.equal(snapshot.json.ended, true);
});

test("hello is checked: protocol, token, room, guests", async () => {
  const { roomId } = await createRoom("dev:host:Host", { allowGuests: false });
  const wrongProtocol = await join(roomId, "dev:asha:Asha", "Asha", { protocol: 2 });
  assert.equal((await wrongProtocol.type("error")).code, "protocol-mismatch");
  const badToken = await join(roomId, "nonsense", "Asha");
  assert.equal((await badToken.type("error")).code, "unauthenticated");
  const noRoom = await join("no-such-room-id", "dev:asha:Asha", "Asha");
  assert.equal((await noRoom.type("error")).code, "no-such-room");
  const guest = await join(roomId, "dev:anon1:Visitor:guest", "Visitor");
  assert.equal((await guest.type("error")).code, "guests-not-allowed");
  const signedIn = await join(roomId, "dev:asha:Asha", "Asha");
  assert.equal((await signedIn.type("welcome")).you.uid, "asha");
  signedIn.close();
});

test("video tokens are signed LiveKit tickets for members only", async () => {
  const { roomId } = await createRoom();
  assert.equal((await api("POST", `/rooms/${roomId}/video-token`, "dev:stranger:S")).status, 403);
  const asha = await join(roomId, "dev:asha:Asha", "Asha Rao");
  await asha.type("welcome");
  const res = await api("POST", `/rooms/${roomId}/video-token`, "dev:asha:Asha");
  assert.equal(res.status, 200);
  assert.equal(res.json.url, LIVEKIT.url);
  const [h, p, sig] = res.json.token.split(".");
  const expected = crypto.createHmac("sha256", LIVEKIT.apiSecret).update(`${h}.${p}`).digest("base64url");
  assert.equal(sig, expected);
  const payload = JSON.parse(Buffer.from(p, "base64url").toString());
  assert.equal(payload.iss, LIVEKIT.apiKey);
  assert.equal(payload.sub, "asha");
  assert.equal(payload.name, "Asha Rao");
  assert.deepEqual(payload.video, { room: roomId, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: false });
  assert.ok(payload.exp > payload.nbf);
  asha.close();
});

test("without LiveKit keys, video is unavailable and ink carries on", async () => {
  const other = await start();
  try {
    const created = await fetch(other.base + "/rooms", {
      method: "POST",
      headers: { Authorization: "Bearer dev:host:Host", "Content-Type": "application/json" },
      body: JSON.stringify({ title: "t", pages: [{ id: PAGE1, width: 10, height: 10, background: { kind: "blank" } }] }),
    }).then((r) => r.json());
    const res = await fetch(`${other.base}/rooms/${created.roomId}/video-token`, { method: "POST", headers: { Authorization: "Bearer dev:host:Host" } });
    assert.equal(res.status, 503);
    assert.equal((await res.json()).error, "video-unavailable");
  } finally {
    other.server.close();
  }
});

test("page pictures: the host uploads, members read", async () => {
  const { roomId } = await createRoom();
  const png = Buffer.from("89504e470d0a1a0a0000000d49484452", "hex");
  assert.equal((await api("PUT", `/rooms/${roomId}/assets/page-1`, "dev:asha:Asha", png, { "Content-Type": "image/png" })).status, 403);
  assert.equal((await api("PUT", `/rooms/${roomId}/assets/page-1`, "dev:host:Host", png, { "Content-Type": "text/plain" })).status, 415);
  assert.equal((await api("PUT", `/rooms/${roomId}/assets/page-1`, "dev:host:Host", png, { "Content-Type": "image/png" })).status, 204);
  assert.equal((await api("GET", `/rooms/${roomId}/assets/page-1`, "dev:asha:Asha")).status, 403, "not joined yet");
  const asha = await join(roomId, "dev:asha:Asha", "Asha");
  await asha.type("welcome");
  const res = await fetch(`${base}/rooms/${roomId}/assets/page-1`, { headers: { Authorization: "Bearer dev:asha:Asha" } });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "image/png");
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), png);
  asha.close();
});

test("a room survives a restart through its store", async () => {
  const shared = new MemoryStore();
  const first = await start({ store: shared });
  const created = await fetch(first.base + "/rooms", {
    method: "POST",
    headers: { Authorization: "Bearer dev:host:Host", "Content-Type": "application/json" },
    body: JSON.stringify({ title: "t", pages: [{ id: PAGE1, width: 10, height: 10, background: { kind: "blank" } }] }),
  }).then((r) => r.json());
  const host = await join(created.roomId, "dev:host:Host", "Host", { baseUrl: first.base });
  await host.type("welcome");
  host.send({ type: "op", clientOpId: "h:1", op: { kind: "stroke.add", pageId: PAGE1, stroke: stroke("kept") } });
  await host.type("op");
  host.close();
  await quiet(); // the last one out saves the room
  first.server.close();

  const second = await start({ store: shared });
  try {
    const again = await join(created.roomId, "dev:host:Host", "Host", { baseUrl: second.base });
    const welcome = await again.type("welcome");
    assert.equal(welcome.state.seq, 1);
    assert.equal(welcome.state.pages[0].strokes[0].stroke.id, "kept");
    again.send({ type: "op", clientOpId: "h:1", op: { kind: "stroke.add", pageId: PAGE1, stroke: stroke("kept") } });
    assert.equal((await again.type("reject")).reason, "duplicate", "remembered op ids survive too");
    again.close();
  } finally {
    second.server.close();
  }
});

test("code lookups are rate limited", async () => {
  let limited = 0;
  for (let i = 0; i < 25; i++) {
    const res = await api("GET", "/rooms/code/ZZZZZZ", "dev:guesser:G");
    if (res.status === 429) limited++;
  }
  assert.ok(limited >= 4, `expected 429s, got ${limited}`);
});

test("the web client is served, including join links", async () => {
  const home = await api("GET", "/");
  assert.equal(home.status, 200);
  const join = await api("GET", "/join/K7QM3X");
  assert.equal(join.status, 200);
  assert.equal(join.text, home.text);
  const reducer = await api("GET", "/src/core/reducer.js");
  assert.equal(reducer.status, 200);
  assert.match(reducer.headers.get("content-type"), /javascript/);
  const livekit = await api("GET", "/vendor/livekit-client/livekit-client.esm.mjs");
  assert.equal(livekit.status, 200);
  assert.match(livekit.headers.get("content-type"), /javascript/);
  assert.deepEqual(await api("GET", "/config.json").then((r) => r.json), { auth: "dev" });
  assert.equal((await api("GET", "/src/../../server/src/auth.js")).status, 404);
  assert.equal((await api("GET", "/package.json")).status, 404);
});
