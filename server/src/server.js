// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// The SpaceNotes Live room server: the HTTP API and the /live WebSocket from
// protocol/PROTOCOL.md, plus the web client's files so a friend can join from
// a browser. Dependency-free Node, like the notebook proxy.
//
// Environment:
//   PORT                   default 8080
//   FIREBASE_PROJECT_ID    verify Firebase ID tokens for this project
//   LIVE_DEV_AUTH=1        accept dev tokens instead (development only)
//   LIVE_BUCKET            keep rooms in this Cloud Storage bucket
//   LIVE_DATA_DIR          or in this directory (default: memory only)
//   LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET   voice and video
//   LIVE_PUBLIC_URL        base of join links (default: the request's host)
//   FIREBASE_WEB_API_KEY, FIREBASE_AUTH_DOMAIN   for the web app's sign-in

import http from "node:http";
import os from "node:os";
import { readFile } from "node:fs/promises";
import { extname, join, normalize, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { acceptUpgrade, rejectUpgrade } from "./websocket.js";
import { HttpError, devAuthenticator, firebaseAuthenticator } from "./auth.js";
import { liveKitToken } from "./livekit.js";
import { RoomRegistry } from "./rooms.js";
import { FileStore, GcsStore, MemoryStore } from "./store.js";
import { PROTOCOL_VERSION } from "../../web/src/core/reducer.js";
import { RateLimiter } from "./rateLimit.js";

const MAX_FRAME = 1024 * 1024; // a 5,000-point stroke is ~750 KB of JSON
const MAX_ROOM_BODY = 16 * 1024 * 1024;
const MAX_ASSET = 8 * 1024 * 1024;
const HELLO_TIMEOUT_MS = 10_000;
const MESSAGES_PER_SECOND = 120; // ink.live at 30 ms is ~33/s; this leaves room for pointers
const WEB_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "web");
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".json": "application/json" };

export function createLiveServer({
  authenticate,
  store = new MemoryStore(),
  liveKit = null, // { url, apiKey, apiSecret }
  publicUrl = null,
  log = (entry) => console.log(JSON.stringify(entry)),
  now = Date.now,
  roomsPerHour = 10,
  // What the web app needs to sign in: { auth: "dev" } or { auth: "firebase", firebase: {...} }.
  webConfig = { auth: "dev" },
} = {}) {
  if (!authenticate) throw new Error("createLiveServer needs an authenticate function");
  const registry = new RoomRegistry({ store, log });
  const createLimit = new RateLimiter({ capacity: roomsPerHour, refillPerSecond: roomsPerHour / 3600, now });
  const lookupLimit = new RateLimiter({ capacity: 20, refillPerSecond: 20 / 60, now }); // code guesses per person per minute
  const sweep = setInterval(() => registry.sweep(), 10 * 60_000);
  sweep.unref();

  const server = http.createServer((req, res) => {
    route(req, res).catch((err) => {
      const status = err instanceof HttpError ? err.status : 500;
      if (status === 500) log({ severity: "ERROR", message: err.stack || String(err) });
      sendJSON(res, status, { error: err.code || (status === 500 ? "internal" : "bad-request"), message: status === 500 ? "Something went wrong." : err.message });
    });
  });

  async function identify(req) {
    const header = req.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    return authenticate(token);
  }

  async function memberRoom(req, roomId) {
    const identity = await identify(req);
    const room = await registry.get(roomId);
    if (!room) throw new HttpError(404, "That room does not exist.", "no-such-room");
    return { identity, room };
  }

  async function route(req, res) {
    const url = new URL(req.url, "http://localhost");
    const path = url.pathname;
    setCors(req, res);
    if (req.method === "OPTIONS") return end(res, 204);

    if (req.method === "GET" && path === "/health") return end(res, 200, "ok", "text/plain");
    if (req.method === "GET" && path === "/config.json") return sendJSON(res, 200, webConfig);

    if (req.method === "POST" && path === "/rooms") {
      const identity = await identify(req);
      if (!createLimit.take(identity.uid)) throw new HttpError(429, "Too many rooms created; try again later.", "rate-limited");
      const body = await readJSON(req, MAX_ROOM_BODY);
      let room;
      try {
        room = await registry.create(body, identity);
      } catch (err) {
        if (err instanceof HttpError) throw err;
        throw new HttpError(400, err.message, "invalid-room");
      }
      log({ severity: "INFO", event: "room.create", room: room.id, pages: room.state.pages.length });
      return sendJSON(res, 201, { roomId: room.id, code: room.code, joinUrl: `${baseUrl(req)}/join/${room.code}` });
    }

    let match;
    if (req.method === "GET" && (match = /^\/rooms\/code\/([A-Za-z0-9]{6})$/.exec(path))) {
      const identity = await identify(req);
      if (!lookupLimit.take(identity.uid)) throw new HttpError(429, "Too many tries; wait a minute.", "rate-limited");
      const room = await registry.byCode(match[1]);
      if (!room || room.ended) throw new HttpError(404, "No room has that code.", "no-such-room");
      return sendJSON(res, 200, { roomId: room.id, title: room.title, hostName: room.hostName, allowGuests: room.allowGuests });
    }

    if ((match = /^\/rooms\/([A-Za-z0-9_-]+)\/assets\/([A-Za-z0-9_-]{1,80})$/.exec(path))) {
      const { identity, room } = await memberRoom(req, match[1]);
      if (req.method === "PUT") {
        if (identity.uid !== room.hostUid) throw new HttpError(403, "Only the host can add page pictures.", "not-host");
        const contentType = (req.headers["content-type"] || "").split(";")[0].trim();
        if (contentType !== "image/png" && contentType !== "image/jpeg") throw new HttpError(415, "Pictures must be PNG or JPEG.", "bad-type");
        const body = await readBody(req, MAX_ASSET);
        await store.putAsset(room.id, match[2], { contentType, body });
        return end(res, 204);
      }
      if (req.method === "GET") {
        if (!room.isMember(identity.uid)) throw new HttpError(403, "Join the room first.", "not-member");
        const asset = await store.getAsset(room.id, match[2]);
        if (!asset) throw new HttpError(404, "No such picture.", "no-such-asset");
        res.writeHead(200, { "Content-Type": asset.contentType, "Cache-Control": "private, max-age=86400" });
        return res.end(asset.body);
      }
    }

    if (req.method === "POST" && (match = /^\/rooms\/([A-Za-z0-9_-]+)\/video-token$/.exec(path))) {
      const { identity, room } = await memberRoom(req, match[1]);
      if (!room.isMember(identity.uid) || room.ended) throw new HttpError(403, "Join the room first.", "not-member");
      if (!liveKit) throw new HttpError(503, "Voice and video are not set up on this server.", "video-unavailable");
      const name = [...room.connections.values()].find((m) => m.uid === identity.uid)?.name || identity.name || "Guest";
      const token = liveKitToken({ ...liveKit, room: room.id, identity: identity.uid, name, nowSec: Math.floor(now() / 1000) });
      return sendJSON(res, 200, { url: liveKit.url, token });
    }

    if (req.method === "GET" && (match = /^\/rooms\/([A-Za-z0-9_-]+)\/snapshot$/.exec(path))) {
      const { identity, room } = await memberRoom(req, match[1]);
      if (identity.uid !== room.hostUid) throw new HttpError(403, "Only the host can save the room.", "not-host");
      return sendJSON(res, 200, { room: room.info(), ended: room.ended, state: room.state });
    }

    if (req.method === "GET") return serveWeb(path, res);
    throw new HttpError(404, "Not found.", "not-found");
  }

  function baseUrl(req) {
    if (publicUrl) return publicUrl.replace(/\/$/, "");
    const proto = req.headers["x-forwarded-proto"] || "http";
    return `${proto}://${req.headers.host}`;
  }

  server.on("upgrade", (req, socket, head) => {
    const path = new URL(req.url, "http://localhost").pathname;
    if (path !== "/live") return rejectUpgrade(socket, 404, "not found");
    const ws = acceptUpgrade(req, socket, head, { maxMessage: MAX_FRAME });
    if (ws) handleSocket(ws);
  });

  function handleSocket(ws) {
    const connection = {
      send: (message) => ws.sendJSON(message),
      sendText: (text) => ws.send(text),
      close: (code, reason) => ws.close(code, reason),
    };
    let room = null;
    let member = null;
    let helloSeen = false;
    // A large burst is allowed because a device coming back online resends
    // every op it drew while away, all at once.
    const limiter = new RateLimiter({ capacity: 2000, refillPerSecond: MESSAGES_PER_SECOND, now });
    const fail = (code, message) => {
      connection.send({ type: "error", code, message });
      connection.close(4002, code);
    };
    const helloTimer = setTimeout(() => fail("bad-hello", "Say hello first."), HELLO_TIMEOUT_MS);

    ws.on("message", async (data) => {
      if (typeof data !== "string") return fail("bad-hello", "Frames must be text.");
      if (!limiter.take("socket")) return fail("rate-limited", "Too many messages.");
      let message;
      try {
        message = JSON.parse(data);
      } catch {
        return; // a garbled frame is dropped, not fatal
      }
      if (member) return room.handle(member, message);
      if (helloSeen) return; // frames sent before welcome are dropped
      helloSeen = true;
      clearTimeout(helloTimer);
      if (message.type !== "hello") return fail("bad-hello", "Say hello first.");
      if (message.protocol !== PROTOCOL_VERSION) return fail("protocol-mismatch", `This server speaks protocol ${PROTOCOL_VERSION}.`);
      let identity;
      try {
        identity = await authenticate(message.token);
      } catch (err) {
        return fail("unauthenticated", err.message);
      }
      const found = await registry.get(message.roomId).catch(() => null);
      if (!found || !ws.isOpen) return found ? undefined : fail("no-such-room", "That room has ended or does not exist.");
      const joined = found.join(connection, identity, message);
      if (joined === "removed") {
        connection.send({ type: "removed", reason: "removed-by-host" });
        return connection.close(4001, "removed-by-host");
      }
      if (typeof joined === "string") return fail(joined, messageFor(joined));
      room = found;
      member = joined;
    });
    ws.on("close", () => {
      clearTimeout(helloTimer);
      if (room && member) room.leave(member);
    });
    ws.on("error", () => {});
  }

  async function serveWeb(path, res) {
    let file;
    if (path === "/" || path.startsWith("/join/")) file = "app/index.html";
    else if (path.startsWith("/app/") || path.startsWith("/src/") || path.startsWith("/vendor/")) file = path.slice(1);
    else throw new HttpError(404, "Not found.", "not-found");
    const full = normalize(join(WEB_ROOT, file));
    if (!full.startsWith(WEB_ROOT + "/")) throw new HttpError(404, "Not found.", "not-found");
    let body;
    try {
      body = await readFile(full);
    } catch {
      throw new HttpError(404, "Not found.", "not-found");
    }
    res.writeHead(200, { "Content-Type": TYPES[extname(full)] || "application/octet-stream", "Cache-Control": "no-cache" });
    res.end(body);
  }

  server.registry = registry;
  server.on("close", () => clearInterval(sweep));
  return server;
}

function messageFor(code) {
  return {
    "no-such-room": "That room has ended or does not exist.",
    "room-full": "This room is full.",
    "guests-not-allowed": "The host asked for signed-in friends only.",
  }[code] || code;
}

function setCors(req, res) {
  // Bearer tokens, never cookies, so any origin may call; the token is the gate.
  res.setHeader("Access-Control-Allow-Origin", req.headers.origin || "*");
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS");
}

function end(res, status, body = "", type) {
  res.writeHead(status, type ? { "Content-Type": type } : {});
  res.end(body);
}

function sendJSON(res, status, value) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(value));
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new HttpError(413, "That is too large.", "too-large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

async function readJSON(req, limit) {
  const body = await readBody(req, limit);
  try {
    return JSON.parse(body.toString("utf8"));
  } catch {
    throw new HttpError(400, "The body must be JSON.", "bad-json");
  }
}

function configFromEnv(env) {
  let authenticate;
  if (env.LIVE_DEV_AUTH === "1") {
    if (env.K_SERVICE) throw new Error("LIVE_DEV_AUTH must never be set on Cloud Run");
    authenticate = devAuthenticator();
  } else {
    authenticate = firebaseAuthenticator({ projectId: env.FIREBASE_PROJECT_ID });
  }
  const store = env.LIVE_BUCKET ? new GcsStore(env.LIVE_BUCKET) : env.LIVE_DATA_DIR ? new FileStore(env.LIVE_DATA_DIR) : new MemoryStore();
  const liveKit = env.LIVEKIT_URL && env.LIVEKIT_API_KEY && env.LIVEKIT_API_SECRET
    ? { url: env.LIVEKIT_URL, apiKey: env.LIVEKIT_API_KEY, apiSecret: env.LIVEKIT_API_SECRET }
    : null;
  const webConfig = env.LIVE_DEV_AUTH === "1"
    ? { auth: "dev" }
    : {
      auth: "firebase",
      firebase: { apiKey: env.FIREBASE_WEB_API_KEY, authDomain: env.FIREBASE_AUTH_DOMAIN || `${env.FIREBASE_PROJECT_ID}.firebaseapp.com`, projectId: env.FIREBASE_PROJECT_ID },
    };
  return { authenticate, store, liveKit, publicUrl: env.LIVE_PUBLIC_URL || null, webConfig };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const config = configFromEnv(process.env);
  const server = createLiveServer(config);
  const port = Number(process.env.PORT || 8080);
  server.listen(port, () => {
    console.log(JSON.stringify({ severity: "INFO", message: `SpaceNotes Live on :${port}`, voice: Boolean(config.liveKit), devAuth: process.env.LIVE_DEV_AUTH === "1" }));
    if (process.env.LIVE_DEV_AUTH === "1") {
      // For trying it on a real iPad or Android tablet on the same Wi-Fi.
      const addresses = Object.values(os.networkInterfaces()).flat()
        .filter((a) => a && a.family === "IPv4" && !a.internal).map((a) => `http://${a.address}:${port}`);
      console.log(`\nOpen http://localhost:${port} here, or type one of these into the demo apps on your Wi-Fi:\n  ${addresses.join("\n  ") || "(no network address found)"}\n`);
    }
  });
  const shutdown = async () => {
    // Cloud Run sends SIGTERM before stopping an instance: save every room.
    await Promise.all([...server.registry.rooms.values()].map((room) => room.saveNow()));
    process.exit(0);
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}
