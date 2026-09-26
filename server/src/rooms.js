// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Rooms: protocol/PROTOCOL.md made real. A room holds the authoritative
// state, numbers every op, checks permissions before it does, and relays
// presence. It knows nothing about HTTP or sockets beyond `send`/`close` on
// each connection, so the tests drive it directly.

import crypto from "node:crypto";
import { applyInPlace, emptyState, PROTOCOL_VERSION } from "../../web/src/core/reducer.js";
import { authorize, canDraw, isValidPage, isValidStroke, isValidText } from "../../web/src/core/permissions.js";

export const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export const MAX_MEMBERS = 12;
const MEMBER_COLORS = ["#3B5BDB", "#E4572E", "#2B9348", "#9C36B5", "#F08C00", "#0B7285", "#C2255C", "#5C940D", "#1971C2", "#862E9C", "#D9480F", "#087F5B"];
const PRESENCE_KINDS = new Set(["ink.live", "pointer", "pointer.hide", "view", "hand"]);
const MAX_LIVE_NUMBERS = 3000; // 1,000 points per ink.live batch is far more than 30 ms of pen
const REMEMBERED_OP_IDS = 50_000;
const SAVE_DELAY_MS = 3000;

export function randomCode(random = crypto.randomInt) {
  let code = "";
  for (let i = 0; i < 6; i++) code += CODE_ALPHABET[random(CODE_ALPHABET.length)];
  return code;
}

export class Room {
  constructor(record, { store, log = () => {} }) {
    this.id = record.id;
    this.code = record.code;
    this.title = record.title;
    this.hostUid = record.hostUid;
    this.hostName = record.hostName;
    this.allowGuests = record.allowGuests;
    this.ended = record.ended ?? false;
    this.removed = new Set(record.removed ?? []);
    this.colors = new Map(Object.entries(record.colors ?? {}));
    this.state = record.state;
    this.store = store;
    this.log = log;
    this.connections = new Map(); // connectionId -> member
    this.opIds = new Set(record.opIds ?? []);
    this.opIdOrder = [...this.opIds];
    this.saveTimer = null;
    this.saving = Promise.resolve();
    this.nextConnection = 1;
    this.lastActive = Date.now();
  }

  /** Builds a new room from `POST /rooms`. Starting content is authored by the host at seq 0. */
  static create({ id, code, title, host, pages, allowGuests }, options) {
    const state = emptyState();
    for (const page of pages) {
      const { strokes = [], texts = [], ...rest } = page;
      state.pages.push({
        ...structuredClone(rest),
        strokes: strokes.map((stroke) => ({ author: host.uid, seq: 0, erased: false, stroke: structuredClone(stroke) })),
        texts: texts.map((text) => ({ author: host.uid, seq: 0, erased: false, text: structuredClone(text) })),
      });
    }
    state.hostPageId = state.pages[0]?.id ?? null;
    return new Room({ id, code, title, hostUid: host.uid, hostName: host.name, allowGuests, state }, options);
  }

  record() {
    return {
      id: this.id,
      code: this.code,
      title: this.title,
      hostUid: this.hostUid,
      hostName: this.hostName,
      allowGuests: this.allowGuests,
      ended: this.ended,
      removed: [...this.removed],
      colors: Object.fromEntries(this.colors),
      opIds: this.opIdOrder,
      state: this.state,
    };
  }

  info() {
    return { id: this.id, code: this.code, title: this.title, hostUid: this.hostUid };
  }

  /** Everyone who may use the room's HTTP routes: the host and anyone who has joined. */
  isMember(uid) {
    return !this.removed.has(uid) && (uid === this.hostUid || this.colors.has(uid));
  }

  #colorFor(uid) {
    if (!this.colors.has(uid)) this.colors.set(uid, MEMBER_COLORS[this.colors.size % MEMBER_COLORS.length]);
    return this.colors.get(uid);
  }

  members() {
    return [...this.connections.values()].map((m) => ({
      uid: m.uid,
      connectionId: m.connectionId,
      name: m.name,
      role: m.role,
      color: m.color,
      handRaised: m.handRaised,
      pageId: m.pageId,
    }));
  }

  /**
   * Admits a connection that has sent a valid `hello`. Returns an error code,
   * or null once `welcome` has been sent.
   */
  join(connection, identity, hello) {
    if (this.ended) return "no-such-room";
    if (this.removed.has(identity.uid)) return "removed";
    if (identity.isAnonymous && !this.allowGuests && identity.uid !== this.hostUid) return "guests-not-allowed";
    const alreadyIn = [...this.connections.values()].some((m) => m.uid === identity.uid);
    if (!alreadyIn && new Set([...this.connections.values()].map((m) => m.uid)).size >= MAX_MEMBERS) return "room-full";

    const member = {
      connection,
      connectionId: `c${this.nextConnection++}`,
      uid: identity.uid,
      name: cleanName(hello.name) || identity.name || "Guest",
      role: identity.uid === this.hostUid ? "host" : "guest",
      color: this.#colorFor(identity.uid),
      handRaised: false,
      pageId: this.state.hostPageId,
    };
    this.connections.set(member.connectionId, member);
    this.lastActive = Date.now();
    connection.send({
      type: "welcome",
      protocol: PROTOCOL_VERSION,
      you: { uid: member.uid, connectionId: member.connectionId, name: member.name, role: member.role, color: member.color },
      room: this.info(),
      state: this.state,
      members: this.members(),
    });
    this.#broadcastMembers(member.connectionId);
    this.#scheduleSave(); // a new member's colour is part of the record
    return member;
  }

  leave(member) {
    if (!this.connections.delete(member.connectionId)) return;
    this.lastActive = Date.now();
    this.#broadcastMembers();
    if (this.connections.size === 0) this.saveNow();
  }

  /** One parsed frame from a joined member. */
  handle(member, message) {
    this.lastActive = Date.now();
    switch (message.type) {
      case "op": return this.#handleOp(member, message);
      case "presence": return this.#handlePresence(member, message.presence);
      case "control": return this.#handleControl(member, message.control);
      case "ping": return member.connection.send({ type: "pong", t: message.t });
      default: return undefined; // unknown types are ignored (PROTOCOL.md, Transport)
    }
  }

  #handleOp(member, { clientOpId, op }) {
    if (typeof clientOpId !== "string" || !clientOpId) return;
    if (this.opIds.has(clientOpId)) {
      // A resend after a reconnect. The state the client got in `welcome`
      // already contains it, so it only needs to stop waiting.
      member.connection.send({ type: "reject", clientOpId, reason: "duplicate" });
      return;
    }
    const reason = authorize(this.state, member, op);
    if (reason) {
      member.connection.send({ type: "reject", clientOpId, reason });
      return;
    }
    const sequenced = { seq: this.state.seq + 1, author: member.uid, clientOpId, op };
    applyInPlace(this.state, sequenced);
    this.#rememberOpId(clientOpId);
    this.#broadcast({ type: "op", ...sequenced });
    this.#scheduleSave();
  }

  #rememberOpId(id) {
    this.opIds.add(id);
    this.opIdOrder.push(id);
    if (this.opIdOrder.length > REMEMBERED_OP_IDS) this.opIds.delete(this.opIdOrder.shift());
  }

  #handlePresence(member, presence) {
    if (!presence || !PRESENCE_KINDS.has(presence.kind)) return;
    let relay;
    switch (presence.kind) {
      case "ink.live": {
        if (!canDraw(this.state, member)) return; // dropped silently (PROTOCOL.md, Permissions)
        const { pageId, liveId, ink, color, width, p, done } = presence;
        if (typeof pageId !== "string" || typeof liveId !== "string" || !Array.isArray(p) || p.length > MAX_LIVE_NUMBERS) return;
        if (!p.every((n) => typeof n === "number" && Number.isFinite(n))) return;
        relay = { kind: "ink.live", pageId, liveId, ink, color, width, p, done: done === true };
        break;
      }
      case "pointer": {
        const { pageId, x, y, laser } = presence;
        if (typeof pageId !== "string" || !Number.isFinite(x) || !Number.isFinite(y)) return;
        relay = { kind: "pointer", pageId, x, y, laser: laser === true };
        break;
      }
      case "pointer.hide":
        relay = { kind: "pointer.hide" };
        break;
      case "view":
        if (typeof presence.pageId !== "string") return;
        member.pageId = presence.pageId;
        relay = { kind: "view", pageId: presence.pageId };
        break;
      case "hand":
        member.handRaised = presence.raised === true;
        relay = { kind: "hand", raised: member.handRaised };
        this.#broadcast({ type: "presence", from: from(member), presence: relay }, member.connectionId);
        this.#broadcastMembers();
        return;
    }
    this.#broadcast({ type: "presence", from: from(member), presence: relay }, member.connectionId);
  }

  #handleControl(member, control) {
    if (member.role !== "host" || !control) return;
    if (control.kind === "remove" && typeof control.uid === "string" && control.uid !== this.hostUid) {
      this.removed.add(control.uid);
      for (const other of [...this.connections.values()]) {
        if (other.uid !== control.uid) continue;
        other.connection.send({ type: "removed", reason: "removed-by-host" });
        other.connection.close(4001, "removed-by-host");
        this.connections.delete(other.connectionId);
      }
      this.#broadcastMembers();
      this.saveNow();
    } else if (control.kind === "end") {
      this.end();
    }
  }

  /** Ends the room for everyone and keeps its final state. */
  end() {
    if (this.ended) return;
    this.ended = true;
    for (const other of this.connections.values()) {
      other.connection.send({ type: "removed", reason: "room-ended" });
      other.connection.close(4000, "room-ended");
    }
    this.connections.clear();
    this.saveNow();
  }

  #broadcast(message, exceptConnectionId) {
    const text = JSON.stringify(message);
    for (const m of this.connections.values()) {
      if (m.connectionId !== exceptConnectionId) m.connection.sendText(text);
    }
  }

  #broadcastMembers(exceptConnectionId) {
    this.#broadcast({ type: "members", members: this.members() }, exceptConnectionId);
  }

  #scheduleSave() {
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => this.saveNow(), SAVE_DELAY_MS);
    this.saveTimer.unref?.();
  }

  /** Saves now (after any save already running). Resolves when written. */
  saveNow() {
    clearTimeout(this.saveTimer);
    this.saveTimer = null;
    const record = structuredClone(this.record());
    this.saving = this.saving
      .then(() => this.store.saveRoom(record))
      .catch((err) => this.log({ severity: "ERROR", message: `saving room ${this.id} failed: ${err.message}` }));
    return this.saving;
  }
}

function from(member) {
  return { uid: member.uid, connectionId: member.connectionId };
}

function cleanName(name) {
  return typeof name === "string" ? name.replace(/\s+/g, " ").trim().slice(0, 40) : "";
}

/** All rooms this process holds, plus lookup by code. */
export class RoomRegistry {
  constructor({ store, log = () => {}, idleMs = 24 * 3600_000 }) {
    this.store = store;
    this.log = log;
    this.idleMs = idleMs;
    this.rooms = new Map();
    this.codes = new Map(); // code -> roomId, active rooms only
  }

  /** Validates `POST /rooms` and creates the room. Throws a message on bad input. */
  async create({ title, pages, allowGuests }, host) {
    if (typeof title !== "string" || !title.trim()) throw new Error("title is required");
    if (!Array.isArray(pages) || pages.length === 0 || pages.length > 500) throw new Error("pages must hold 1 to 500 pages");
    const ids = new Set();
    for (const page of pages) {
      if (!isValidPage(page)) throw new Error("a page is missing its id, size or background");
      if (ids.has(page.id)) throw new Error(`page ${page.id} appears twice`);
      ids.add(page.id);
      if (page.strokes !== undefined && !(Array.isArray(page.strokes) && page.strokes.every(isValidStroke))) {
        throw new Error(`page ${page.id} has an invalid stroke`);
      }
      if (page.texts !== undefined && !(Array.isArray(page.texts) && page.texts.every(isValidText))) {
        throw new Error(`page ${page.id} has an invalid text box`);
      }
    }
    let code;
    do code = randomCode(); while (this.codes.has(code));
    const id = crypto.randomBytes(12).toString("base64url");
    const room = Room.create({ id, code, title: title.trim().slice(0, 120), host, pages, allowGuests: allowGuests !== false }, { store: this.store, log: this.log });
    this.rooms.set(id, room);
    this.codes.set(code, id);
    await room.saveNow();
    return room;
  }

  /** The room, from memory or the store (after a restart). */
  async get(id) {
    if (typeof id !== "string" || !/^[A-Za-z0-9_-]{1,80}$/.test(id)) return null;
    if (this.rooms.has(id)) return this.rooms.get(id);
    const record = await this.store.loadRoom(id);
    if (!record) return null;
    if (this.rooms.has(id)) return this.rooms.get(id); // loaded meanwhile
    const room = new Room(record, { store: this.store, log: this.log });
    this.rooms.set(id, room);
    if (!room.ended) this.codes.set(room.code, id);
    return room;
  }

  async byCode(code) {
    const id = this.codes.get(String(code || "").toUpperCase());
    return id ? this.get(id) : null;
  }

  /** Drops ended or long-idle rooms from memory; their records stay in the store. */
  sweep(now = Date.now()) {
    for (const [id, room] of this.rooms) {
      if (room.connections.size > 0) continue;
      if (room.ended || now - room.lastActive > this.idleMs) {
        // The code stops working too; the room itself can still be opened by id.
        this.codes.delete(room.code);
        room.saveNow();
        this.rooms.delete(id);
      }
    }
  }
}
