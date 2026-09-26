// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// The room server's HTTP routes (protocol/PROTOCOL.md, "HTTP API").

export class LiveApiError extends Error {
  constructor(status, code, message) {
    super(message || code);
    this.status = status;
    this.code = code;
  }
}

export class LiveApi {
  /** @param {{ serverUrl: string, getToken: () => Promise<string>, fetchImpl?: typeof fetch }} o */
  constructor({ serverUrl, getToken, fetchImpl = globalThis.fetch.bind(globalThis) }) {
    this.serverUrl = serverUrl.replace(/\/$/, "");
    this.getToken = getToken;
    this.fetch = fetchImpl;
  }

  async #request(method, path, { json, body, contentType } = {}) {
    const headers = { Authorization: `Bearer ${await this.getToken()}` };
    if (json !== undefined) headers["Content-Type"] = "application/json";
    if (contentType) headers["Content-Type"] = contentType;
    const response = await this.fetch(this.serverUrl + path, { method, headers, body: json !== undefined ? JSON.stringify(json) : body });
    if (!response.ok) {
      let detail = {};
      try { detail = await response.json(); } catch {}
      throw new LiveApiError(response.status, detail.error || "http-error", detail.message);
    }
    return response;
  }

  /** Pages may carry starting `strokes` and `texts`. Returns { roomId, code, joinUrl }. */
  async createRoom({ title, pages, allowGuests = true }) {
    return (await this.#request("POST", "/rooms", { json: { title, pages, allowGuests } })).json();
  }

  /** Returns { roomId, title, hostName, allowGuests }, or null when no room has that code. */
  async lookup(code) {
    try {
      return await (await this.#request("GET", `/rooms/code/${encodeURIComponent(code.trim().toUpperCase())}`)).json();
    } catch (err) {
      if (err instanceof LiveApiError && err.status === 404) return null;
      throw err;
    }
  }

  /** Returns { url, token } for LiveKit, or null when the server has no video. */
  async videoToken(roomId) {
    try {
      return await (await this.#request("POST", `/rooms/${roomId}/video-token`)).json();
    } catch (err) {
      if (err instanceof LiveApiError && err.status === 503) return null;
      throw err;
    }
  }

  async uploadAsset(roomId, assetId, blob, contentType) {
    await this.#request("PUT", `/rooms/${roomId}/assets/${assetId}`, { body: blob, contentType });
  }

  /** The page picture as a Blob. */
  async asset(roomId, assetId) {
    return (await this.#request("GET", `/rooms/${roomId}/assets/${assetId}`)).blob();
  }

  async snapshot(roomId) {
    return (await this.#request("GET", `/rooms/${roomId}/snapshot`)).json();
  }
}
