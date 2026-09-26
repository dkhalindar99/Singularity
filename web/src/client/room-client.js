// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// The web room client: one WebSocket to the room server, the room state, the
// people in it and what they are doing right now. protocol/PROTOCOL.md
// describes the behaviour; the Swift and Kotlin RoomClients follow the same
// rules, so read them side by side when changing one.
//
// What the screen draws is `client.state`: the server's confirmed state with
// this device's not-yet-acknowledged ops applied on top. So your own ink
// appears at once, and if the server says no, it disappears again.

import { apply, applyInPlace, cloneState, emptyState, PROTOCOL_VERSION } from "../core/reducer.js";
import { canDraw } from "../core/permissions.js";

const BACKOFF_MS = [500, 1000, 2000, 4000, 8000];
const PING_MS = 20_000;
const POINTER_TTL_MS = 5000;
const DONE_PREVIEW_TTL_MS = 1500;
const FATAL_ERRORS = new Set(["bad-hello", "no-such-room", "room-full", "guests-not-allowed", "protocol-mismatch"]);
const MAX_OP_BYTES = 1000 * 1024; // under the server's 1 MiB frame, leaving room for the envelope

export class RoomClient extends EventTarget {
  /**
   * @param {object} o
   * @param {string} o.serverUrl  e.g. "https://live.example.com" (ws URL is derived)
   * @param {string} o.roomId
   * @param {string} o.name       shown to the others
   * @param {string} o.deviceId   stable per device; prefixes clientOpIds
   * @param {() => Promise<string>} o.getToken  a fresh Firebase ID token
   */
  constructor({ serverUrl, roomId, name, deviceId, getToken, WebSocketImpl = globalThis.WebSocket, timers = globalThis }) {
    super();
    this.serverUrl = serverUrl.replace(/\/$/, "");
    this.roomId = roomId;
    this.name = name;
    this.deviceId = deviceId;
    this.getToken = getToken;
    this.WebSocketImpl = WebSocketImpl;
    this.timers = timers;

    this.status = "idle"; // idle | connecting | connected | reconnecting | ended
    this.endedReason = null;
    this.me = null;
    this.room = null;
    this.members = [];
    this.confirmed = emptyState();
    this.state = this.confirmed;
    this.pending = []; // [{ clientOpId, op }]
    this.undoStack = [];
    this.redoStack = [];
    this.untracked = new Set(); // clientOpIds of undo/redo ops
    this.stepFor = new Map(); // clientOpId -> undo step, to drop it on reject
    this.live = new Map(); // `${connectionId}/${liveId}` -> preview
    this.pointers = new Map(); // connectionId -> { pageId, x, y, laser, at }
    this.views = new Map(); // connectionId -> pageId
    // Never restarts, even across page reloads with the same deviceId
    // (PROTOCOL.md, Identifiers): a repeated clientOpId would be dropped.
    this.counter = Date.now();
    this.socket = null;
    this.attempt = 0;
    this.retryTimer = null;
    this.pingTimer = null;
  }

  // ---- connection -------------------------------------------------------

  connect() {
    if (this.status === "ended") return;
    this.#setStatus(this.attempt === 0 ? "connecting" : "reconnecting");
    this.#open();
  }

  disconnect() {
    this.#end("left");
  }

  async #open() {
    let token;
    try {
      token = await this.getToken();
    } catch {
      return this.#retry();
    }
    if (this.status === "ended") return;
    const socket = new this.WebSocketImpl(this.serverUrl.replace(/^http/, "ws") + "/live");
    this.socket = socket;
    socket.onopen = () => {
      socket.send(JSON.stringify({ type: "hello", protocol: PROTOCOL_VERSION, token, roomId: this.roomId, name: this.name, deviceId: this.deviceId }));
    };
    socket.onmessage = (event) => {
      if (this.socket !== socket) return;
      let message;
      try {
        message = JSON.parse(typeof event.data === "string" ? event.data : String(event.data));
      } catch {
        return;
      }
      this.#receive(message);
    };
    socket.onclose = () => {
      if (this.socket !== socket) return;
      this.socket = null;
      this.timers.clearInterval(this.pingTimer);
      if (this.status !== "ended") this.#retry();
    };
    socket.onerror = () => {};
  }

  #retry() {
    if (this.status === "ended") return;
    this.#setStatus("reconnecting");
    const delay = BACKOFF_MS[Math.min(this.attempt, BACKOFF_MS.length - 1)];
    this.attempt += 1;
    this.timers.clearTimeout(this.retryTimer);
    this.retryTimer = this.timers.setTimeout(() => this.#open(), delay);
  }

  /** Drops the socket and reconnects at once (used when an op was missed). */
  #resync() {
    const socket = this.socket;
    this.socket = null;
    socket?.close();
    this.timers.clearInterval(this.pingTimer);
    this.attempt = 0;
    this.#retry();
  }

  #end(reason) {
    if (this.status === "ended") return;
    this.endedReason = reason;
    this.#setStatus("ended");
    this.timers.clearTimeout(this.retryTimer);
    this.timers.clearInterval(this.pingTimer);
    const socket = this.socket;
    this.socket = null;
    socket?.close();
  }

  #send(message) {
    if (this.socket && this.socket.readyState === 1 && this.status === "connected") {
      this.socket.send(JSON.stringify(message));
      return true;
    }
    return false;
  }

  // ---- incoming -----------------------------------------------------------

  #receive(message) {
    switch (message.type) {
      case "welcome": {
        this.attempt = 0;
        this.me = message.you;
        this.room = message.room;
        this.members = message.members ?? [];
        this.confirmed = message.state;
        this.live.clear();
        this.pointers.clear();
        this.views.clear();
        for (const m of this.members) if (m.pageId) this.views.set(m.connectionId, m.pageId);
        this.#setStatus("connected");
        this.timers.clearInterval(this.pingTimer);
        this.pingTimer = this.timers.setInterval(() => this.#send({ type: "ping", t: Date.now() }), PING_MS);
        for (const { clientOpId, op } of this.pending) this.#send({ type: "op", clientOpId, op });
        this.#recompute();
        this.#emit("members");
        this.#emit("presence");
        return;
      }
      case "op": {
        if (message.seq !== this.confirmed.seq + 1) return this.#resync();
        applyInPlace(this.confirmed, message);
        this.pending = this.pending.filter((p) => p.clientOpId !== message.clientOpId);
        this.stepFor.delete(message.clientOpId);
        this.untracked.delete(message.clientOpId);
        if (message.op?.kind === "stroke.add") this.#dropPreviewsFor(message.op.stroke?.id);
        this.#recompute();
        this.#emit("op", message);
        return;
      }
      case "reject": {
        const wasPending = this.pending.some((p) => p.clientOpId === message.clientOpId);
        this.pending = this.pending.filter((p) => p.clientOpId !== message.clientOpId);
        this.untracked.delete(message.clientOpId);
        if (message.reason !== "duplicate") {
          // The step can no longer be undone or redone as recorded.
          const step = this.stepFor.get(message.clientOpId);
          if (step) {
            this.undoStack = this.undoStack.filter((s) => s !== step);
            this.redoStack = this.redoStack.filter((s) => s !== step);
          }
        }
        this.stepFor.delete(message.clientOpId);
        if (wasPending) this.#recompute();
        this.#emit("reject", message);
        return;
      }
      case "members": {
        this.members = message.members ?? [];
        const present = new Set(this.members.map((m) => m.connectionId));
        for (const key of [...this.live.keys()]) if (!present.has(key.split("/")[0])) this.live.delete(key);
        for (const id of [...this.pointers.keys()]) if (!present.has(id)) this.pointers.delete(id);
        for (const id of [...this.views.keys()]) if (!present.has(id)) this.views.delete(id);
        this.#emit("members");
        this.#emit("presence");
        return;
      }
      case "presence":
        return this.#receivePresence(message.from, message.presence);
      case "removed":
        return this.#end(message.reason || "removed-by-host");
      case "error":
        if (FATAL_ERRORS.has(message.code)) return this.#end(message.code);
        // An expired token, a rate limit: the server closes the socket and
        // the close handler reconnects with growing backoff.
        return;
      default:
        return; // pong and anything newer than this client
    }
  }

  #receivePresence(from, presence) {
    if (!from || !presence) return;
    const id = from.connectionId;
    switch (presence.kind) {
      case "ink.live": {
        const key = `${id}/${presence.liveId}`;
        if (presence.done) {
          // Keep drawing it until the committed stroke arrives, so it never blinks.
          const preview = this.live.get(key);
          if (preview) {
            appendPoints(preview, presence.p);
            preview.done = true;
            // If the stroke never comes (the server refused it), stop drawing it.
            this.timers.setTimeout(() => {
              if (this.live.get(key) === preview) {
                this.live.delete(key);
                this.#emit("presence");
              }
            }, DONE_PREVIEW_TTL_MS);
          }
          break;
        }
        let preview = this.live.get(key);
        if (!preview) {
          if (this.#hasStroke(presence.pageId, presence.liveId)) break; // it already landed
          preview = { connectionId: id, uid: from.uid, pageId: presence.pageId, liveId: presence.liveId, ink: presence.ink, color: presence.color, width: presence.width, points: [], done: false };
          this.live.set(key, preview);
        }
        appendPoints(preview, presence.p);
        break;
      }
      case "pointer":
        this.pointers.set(id, { uid: from.uid, pageId: presence.pageId, x: presence.x, y: presence.y, laser: presence.laser === true, at: Date.now() });
        break;
      case "pointer.hide":
        this.pointers.delete(id);
        break;
      case "view":
        this.views.set(id, presence.pageId);
        break;
      case "hand":
        break; // the members list carries it
      default:
        return;
    }
    this.#emit("presence");
  }

  #hasStroke(pageId, strokeId) {
    const page = this.confirmed.pages.find((p) => p.id === pageId);
    return !!page?.strokes.some((s) => s.stroke.id === strokeId);
  }

  #dropPreviewsFor(strokeId) {
    if (!strokeId) return;
    for (const [key, preview] of this.live) if (preview.liveId === strokeId) this.live.delete(key);
  }

  /** Pointers that have not moved for a while are hidden. */
  activePointers(now = Date.now()) {
    return [...this.pointers.entries()].filter(([, p]) => now - p.at < POINTER_TTL_MS);
  }

  // ---- state --------------------------------------------------------------

  #recompute() {
    const uid = this.me?.uid ?? "";
    let state = this.confirmed;
    if (this.pending.length) {
      state = cloneState(this.confirmed);
      for (const { op } of this.pending) applyInPlace(state, { seq: this.confirmed.seq, author: uid, op });
    }
    this.state = state;
    this.#emit("state");
  }

  get canDraw() {
    return !!this.me && canDraw(this.state, this.me);
  }

  get isHost() {
    return this.me?.role === "host";
  }

  #nextId() {
    this.counter += 1;
    return `${this.deviceId}:${this.counter}`;
  }

  /** Queues an op, draws it at once, and sends it if connected. */
  #submit(op, { step = null, untracked = false } = {}) {
    const clientOpId = this.#nextId();
    if (JSON.stringify(op).length > MAX_OP_BYTES) {
      // The server would close the socket, and a resend after reconnecting
      // would close it again, for ever. Refuse it here instead.
      this.#emit("reject", { clientOpId, reason: "too-large" });
      return null;
    }
    this.pending.push({ clientOpId, op });
    if (step) this.stepFor.set(clientOpId, step);
    if (untracked) this.untracked.add(clientOpId);
    this.#send({ type: "op", clientOpId, op });
    this.#recompute();
    return clientOpId;
  }

  /** An undoable op: records how to undo and redo it, from the state before it. */
  #submitUndoable(op, undo, redo) {
    const step = { undo, redo };
    if (this.#submit(op, { step }) === null) return;
    this.undoStack.push(step);
    if (this.undoStack.length > 200) this.undoStack.shift();
    this.redoStack = [];
    this.#emit("history");
  }

  #page(pageId) {
    return this.state.pages.find((p) => p.id === pageId);
  }

  // ---- ops ----------------------------------------------------------------

  addStroke(pageId, stroke) {
    const ids = [stroke.id];
    this.#submitUndoable(
      { kind: "stroke.add", pageId, stroke },
      { kind: "stroke.erase", pageId, strokeIds: ids },
      { kind: "stroke.restore", pageId, strokeIds: ids },
    );
  }

  eraseStrokes(pageId, strokeIds) {
    const page = this.#page(pageId);
    const live = strokeIds.filter((id) => page?.strokes.some((s) => s.stroke.id === id && !s.erased));
    if (!live.length) return;
    this.#submitUndoable(
      { kind: "stroke.erase", pageId, strokeIds: live },
      { kind: "stroke.restore", pageId, strokeIds: live },
      { kind: "stroke.erase", pageId, strokeIds: live },
    );
  }

  restoreStrokes(pageId, strokeIds) {
    this.#submitUndoable(
      { kind: "stroke.restore", pageId, strokeIds },
      { kind: "stroke.erase", pageId, strokeIds },
      { kind: "stroke.restore", pageId, strokeIds },
    );
  }

  moveItems(pageId, { strokeIds = [], textIds = [] }, dx, dy) {
    if (!dx && !dy) return;
    this.#submitUndoable(
      { kind: "items.move", pageId, strokeIds, textIds, dx, dy },
      { kind: "items.move", pageId, strokeIds, textIds, dx: -dx, dy: -dy },
      { kind: "items.move", pageId, strokeIds, textIds, dx, dy },
    );
  }

  upsertText(pageId, text) {
    const previous = this.#page(pageId)?.texts.find((t) => t.text.id === text.id);
    const op = { kind: "text.upsert", pageId, text };
    const undo = previous && !previous.erased
      ? { kind: "text.upsert", pageId, text: structuredClone(previous.text) }
      : { kind: "text.erase", pageId, textIds: [text.id] };
    this.#submitUndoable(op, undo, op);
  }

  eraseTexts(pageId, textIds) {
    const page = this.#page(pageId);
    const items = (page?.texts ?? []).filter((t) => textIds.includes(t.text.id) && !t.erased);
    if (!items.length) return;
    // One undo step per text keeps each inverse a single op.
    for (const item of items) {
      this.#submitUndoable(
        { kind: "text.erase", pageId, textIds: [item.text.id] },
        { kind: "text.upsert", pageId, text: structuredClone(item.text) },
        { kind: "text.erase", pageId, textIds: [item.text.id] },
      );
    }
  }

  addPage(page, afterPageId = null) {
    this.#submit({ kind: "page.add", page, afterPageId });
  }

  setPolicy(drawPolicy, penHolder = null) {
    this.#submit({ kind: "room.policy", drawPolicy, ...(penHolder ? { penHolder } : {}) });
  }

  setHostPage(pageId) {
    if (this.isHost && this.state.hostPageId !== pageId) this.#submit({ kind: "host.page", pageId });
  }

  get canUndo() { return this.undoStack.length > 0; }
  get canRedo() { return this.redoStack.length > 0; }

  undo() {
    const step = this.undoStack.pop();
    if (!step) return;
    this.redoStack.push(step);
    this.#submit(step.undo, { step, untracked: true });
    this.#emit("history");
  }

  redo() {
    const step = this.redoStack.pop();
    if (!step) return;
    this.undoStack.push(step);
    this.#submit(step.redo, { step, untracked: true });
    this.#emit("history");
  }

  // ---- presence and control ---------------------------------------------

  sendPresence(presence) {
    return this.#send({ type: "presence", presence });
  }

  sendPointer(pageId, x, y, laser = false) {
    this.sendPresence({ kind: "pointer", pageId, x: round1(x), y: round1(y), laser });
  }

  hidePointer() {
    this.sendPresence({ kind: "pointer.hide" });
  }

  sendView(pageId) {
    this.sendPresence({ kind: "view", pageId });
  }

  setHandRaised(raised) {
    this.sendPresence({ kind: "hand", raised });
  }

  removeMember(uid) {
    this.#send({ type: "control", control: { kind: "remove", uid } });
  }

  endRoom() {
    this.#send({ type: "control", control: { kind: "end" } });
  }

  // ---- events ---------------------------------------------------------------

  #setStatus(status) {
    this.status = status;
    this.#emit("status");
  }

  #emit(kind, detail = null) {
    this.dispatchEvent(new CustomEvent(kind, { detail }));
    this.dispatchEvent(new CustomEvent("change", { detail: { kind } }));
  }
}

function appendPoints(preview, p) {
  if (!Array.isArray(p)) return;
  for (let i = 0; i + 2 < p.length; i += 3) preview.points.push([p[i], p[i + 1], p[i + 2]]);
}

export const round1 = (n) => Math.round(n * 10) / 10;

/**
 * Batches the points of a stroke being drawn into `ink.live` messages, at
 * most one every `intervalMs`. The finished stroke is committed separately
 * (addStroke) with the same id, so receivers swap preview for stroke.
 */
export class LiveInkStreamer {
  constructor(client, { intervalMs = 30, timers = globalThis } = {}) {
    this.client = client;
    this.intervalMs = intervalMs;
    this.timers = timers;
    this.current = null;
  }

  begin({ pageId, liveId, ink, color, width }) {
    this.current = { pageId, liveId, ink, color, width, buffer: [], timer: null, lastSent: 0 };
  }

  add(x, y, w) {
    const c = this.current;
    if (!c) return;
    c.buffer.push(round1(x), round1(y), round1(w));
    if (c.timer) return;
    const wait = Math.max(0, c.lastSent + this.intervalMs - Date.now());
    c.timer = this.timers.setTimeout(() => this.#flush(false), wait);
  }

  end() {
    const c = this.current;
    if (!c) return;
    this.timers.clearTimeout(c.timer);
    this.#flush(true);
    this.current = null;
  }

  #flush(done) {
    const c = this.current;
    if (!c) return;
    c.timer = null;
    if (!c.buffer.length && !done) return;
    this.client.sendPresence({ kind: "ink.live", pageId: c.pageId, liveId: c.liveId, ink: c.ink, color: c.color, width: c.width, p: c.buffer, done });
    c.buffer = [];
    c.lastSent = Date.now();
  }
}

export { apply };
