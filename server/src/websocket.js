// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// A minimal, dependency-free WebSocket (RFC 6455), copied from the notebook
// proxy (notebook/backend/src/websocket.js): accepting a connection on the
// server's `upgrade` event, and opening one (used by the tests). Text and
// binary messages, fragmentation, ping/pong and the close handshake; no
// extensions (permessage-deflate is never offered, so peers send uncompressed
// frames).

import crypto from "node:crypto";
import http from "node:http";
import https from "node:https";
import { EventEmitter } from "node:events";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const DEFAULT_MAX_MESSAGE = 1024 * 1024;

export function acceptKey(key) {
  return crypto.createHash("sha1").update(key + GUID).digest("base64");
}

/**
 * One open WebSocket. Emits `message` (string for text, Buffer for binary),
 * `close` (code, reason) once, and `error`.
 */
export class WebSocketConnection extends EventEmitter {
  constructor(socket, { isClient = false, maxMessage = DEFAULT_MAX_MESSAGE, head } = {}) {
    super();
    this.socket = socket;
    this.isClient = isClient; // clients mask what they send
    this.maxMessage = maxMessage;
    this.buffer = Buffer.alloc(0);
    this.fragments = [];
    this.fragmentOpcode = 0;
    this.fragmentSize = 0;
    this.closed = false;
    this.closeSent = false;

    socket.setNoDelay?.(true);
    socket.on("data", (chunk) => this.#receive(chunk));
    socket.on("error", (err) => this.emit("error", err));
    socket.on("close", () => this.#finish(1006, "connection lost"));
    if (head && head.length) this.#receive(head);
  }

  get isOpen() {
    return !this.closed && !this.closeSent;
  }

  send(data) {
    if (!this.isOpen) return;
    const isText = typeof data === "string";
    this.#writeFrame(isText ? 0x1 : 0x2, isText ? Buffer.from(data, "utf8") : data);
  }

  sendJSON(value) {
    this.send(JSON.stringify(value));
  }

  close(code = 1000, reason = "") {
    if (this.closed) return;
    if (!this.closeSent) {
      const why = Buffer.from(String(reason).slice(0, 120), "utf8");
      const payload = Buffer.alloc(2 + why.length);
      payload.writeUInt16BE(code, 0);
      why.copy(payload, 2);
      this.#writeFrame(0x8, payload);
      this.closeSent = true;
    }
    // Don't wait forever for the peer's close frame.
    setTimeout(() => this.#finish(code, reason), 1000).unref?.();
  }

  #finish(code, reason) {
    if (this.closed) return;
    this.closed = true;
    this.socket.end();
    this.socket.destroy();
    this.emit("close", code, reason);
  }

  #writeFrame(opcode, payload) {
    const length = payload.length;
    let header;
    if (length < 126) {
      header = Buffer.alloc(2);
      header[1] = length;
    } else if (length < 65536) {
      header = Buffer.alloc(4);
      header[1] = 126;
      header.writeUInt16BE(length, 2);
    } else {
      header = Buffer.alloc(10);
      header[1] = 127;
      header.writeBigUInt64BE(BigInt(length), 2);
    }
    header[0] = 0x80 | opcode; // FIN + opcode
    if (this.isClient) {
      header[1] |= 0x80;
      const mask = crypto.randomBytes(4);
      const masked = Buffer.alloc(length);
      for (let i = 0; i < length; i++) masked[i] = payload[i] ^ mask[i & 3];
      this.socket.write(Buffer.concat([header, mask, masked]));
    } else {
      this.socket.write(Buffer.concat([header, payload]));
    }
  }

  #receive(chunk) {
    this.buffer = this.buffer.length ? Buffer.concat([this.buffer, chunk]) : chunk;
    while (!this.closed) {
      const frame = this.#readFrame();
      if (!frame) return;
      this.#handleFrame(frame);
    }
  }

  #readFrame() {
    const b = this.buffer;
    if (b.length < 2) return null;
    const fin = (b[0] & 0x80) !== 0;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let length = b[1] & 0x7f;
    let offset = 2;
    if (length === 126) {
      if (b.length < 4) return null;
      length = b.readUInt16BE(2);
      offset = 4;
    } else if (length === 127) {
      if (b.length < 10) return null;
      const big = b.readBigUInt64BE(2);
      if (big > BigInt(this.maxMessage)) {
        this.#protocolClose(1009, "message too big");
        return null;
      }
      length = Number(big);
      offset = 10;
    }
    if (length > this.maxMessage) {
      this.#protocolClose(1009, "message too big");
      return null;
    }
    const maskLength = masked ? 4 : 0;
    if (b.length < offset + maskLength + length) return null;
    let payload = b.subarray(offset + maskLength, offset + maskLength + length);
    if (masked) {
      const mask = b.subarray(offset, offset + 4);
      const unmasked = Buffer.alloc(length);
      for (let i = 0; i < length; i++) unmasked[i] = payload[i] ^ mask[i & 3];
      payload = unmasked;
    } else {
      payload = Buffer.from(payload);
    }
    this.buffer = b.subarray(offset + maskLength + length);
    return { fin, opcode, payload };
  }

  #handleFrame({ fin, opcode, payload }) {
    switch (opcode) {
      case 0x8: { // close: echo it, then finish
        const code = payload.length >= 2 ? payload.readUInt16BE(0) : 1005;
        const reason = payload.length > 2 ? payload.subarray(2).toString("utf8") : "";
        if (!this.closeSent) {
          this.#writeFrame(0x8, payload.subarray(0, Math.min(payload.length, 125)));
          this.closeSent = true;
        }
        this.#finish(code, reason);
        return;
      }
      case 0x9: // ping
        if (this.isOpen) this.#writeFrame(0xa, payload);
        return;
      case 0xa: // pong
        return;
      case 0x0: // continuation
      case 0x1: // text
      case 0x2: { // binary
        if (opcode !== 0x0) {
          this.fragments = [];
          this.fragmentSize = 0;
          this.fragmentOpcode = opcode;
        }
        this.fragments.push(payload);
        this.fragmentSize += payload.length;
        if (this.fragmentSize > this.maxMessage) {
          this.#protocolClose(1009, "message too big");
          return;
        }
        if (!fin) return;
        const whole = Buffer.concat(this.fragments);
        this.fragments = [];
        this.fragmentSize = 0;
        this.emit("message", this.fragmentOpcode === 0x1 ? whole.toString("utf8") : whole);
        return;
      }
      default:
        this.#protocolClose(1002, "unknown opcode");
    }
  }

  #protocolClose(code, reason) {
    this.close(code, reason);
    this.buffer = Buffer.alloc(0);
  }
}

/**
 * Completes the server side of an upgrade. Returns the connection, or `null`
 * after answering 400 when the request isn't a valid WebSocket upgrade.
 */
export function acceptUpgrade(req, socket, head, { maxMessage } = {}) {
  const key = req.headers["sec-websocket-key"];
  const isUpgrade = (req.headers.upgrade || "").toLowerCase() === "websocket";
  if (!isUpgrade || !key || req.headers["sec-websocket-version"] !== "13") {
    rejectUpgrade(socket, 400, "Bad Request");
    return null;
  }
  socket.write(
    "HTTP/1.1 101 Switching Protocols\r\n" +
      "Upgrade: websocket\r\n" +
      "Connection: Upgrade\r\n" +
      `Sec-WebSocket-Accept: ${acceptKey(key)}\r\n\r\n`
  );
  return new WebSocketConnection(socket, { maxMessage, head });
}

export function rejectUpgrade(socket, status, message) {
  const body = JSON.stringify({ error: message });
  socket.write(
    `HTTP/1.1 ${status} ${http.STATUS_CODES[status] || "Error"}\r\n` +
      "Content-Type: application/json\r\n" +
      `Content-Length: ${Buffer.byteLength(body)}\r\n` +
      "Connection: close\r\n\r\n" +
      body
  );
  socket.destroy();
}

/**
 * Opens a client connection to `url` (ws:// or wss://) with extra request
 * `headers` (e.g. Authorization). Resolves once the handshake is verified.
 */
export function connect(url, { headers = {}, maxMessage, timeoutMs = 10_000 } = {}) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const secure = target.protocol === "wss:";
    const key = crypto.randomBytes(16).toString("base64");
    const request = (secure ? https : http).request({
      host: target.hostname,
      port: target.port || (secure ? 443 : 80),
      path: target.pathname + target.search,
      headers: {
        ...headers,
        Connection: "Upgrade",
        Upgrade: "websocket",
        "Sec-WebSocket-Version": "13",
        "Sec-WebSocket-Key": key,
      },
      timeout: timeoutMs,
    });
    request.on("upgrade", (res, socket, head) => {
      if (res.headers["sec-websocket-accept"] !== acceptKey(key)) {
        socket.destroy();
        reject(new Error("upstream handshake failed"));
        return;
      }
      resolve(new WebSocketConnection(socket, { isClient: true, maxMessage, head }));
    });
    request.on("response", (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => reject(new Error(`upstream refused the connection (${res.statusCode}) ${body.slice(0, 200)}`)));
    });
    request.on("timeout", () => request.destroy(new Error("upstream connection timed out")));
    request.on("error", reject);
    request.end();
  });
}
