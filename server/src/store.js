// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Where rooms outlive the process. A live room is held in memory; the store
// keeps its latest snapshot (room details + room state) and its page
// pictures, so a restart — or Cloud Run moving the service — loses at most
// the last few seconds of ink. Three backends share one small interface:
//
//   saveRoom(record)            record = { id, code, title, hostUid, hostName,
//                                          allowGuests, ended, removed, colors, state }
//   loadRoom(id) -> record | null
//   putAsset(roomId, assetId, { contentType, body })
//   getAsset(roomId, assetId) -> { contentType, body } | null

import { mkdir, readFile, writeFile, rename } from "node:fs/promises";
import { join } from "node:path";

const SAFE_ID = /^[A-Za-z0-9_-]{1,80}$/;
const assertId = (id) => {
  if (!SAFE_ID.test(id)) throw new Error(`unsafe id: ${id}`);
  return id;
};

export class MemoryStore {
  constructor() {
    this.rooms = new Map();
    this.assets = new Map();
  }
  async saveRoom(record) { this.rooms.set(record.id, structuredClone(record)); }
  async loadRoom(id) { return this.rooms.has(id) ? structuredClone(this.rooms.get(id)) : null; }
  async putAsset(roomId, assetId, asset) { this.assets.set(`${roomId}/${assetId}`, asset); }
  async getAsset(roomId, assetId) { return this.assets.get(`${roomId}/${assetId}`) ?? null; }
}

/** A directory on disk. Good for one machine and for development. */
export class FileStore {
  constructor(dir) { this.dir = dir; }

  async saveRoom(record) {
    const folder = join(this.dir, assertId(record.id));
    await mkdir(folder, { recursive: true });
    const temp = join(folder, "room.json.tmp");
    await writeFile(temp, JSON.stringify(record));
    await rename(temp, join(folder, "room.json")); // never leave half a file
  }

  async loadRoom(id) {
    try {
      return JSON.parse(await readFile(join(this.dir, assertId(id), "room.json"), "utf8"));
    } catch (err) {
      if (err.code === "ENOENT") return null;
      throw err;
    }
  }

  async putAsset(roomId, assetId, { contentType, body }) {
    const folder = join(this.dir, assertId(roomId), "assets");
    await mkdir(folder, { recursive: true });
    await writeFile(join(folder, assertId(assetId)), body);
    await writeFile(join(folder, `${assetId}.type`), contentType);
  }

  async getAsset(roomId, assetId) {
    const folder = join(this.dir, assertId(roomId), "assets");
    try {
      const [body, contentType] = await Promise.all([
        readFile(join(folder, assertId(assetId))),
        readFile(join(folder, `${assetId}.type`), "utf8"),
      ]);
      return { contentType, body };
    } catch (err) {
      if (err.code === "ENOENT") return null;
      throw err;
    }
  }
}

/**
 * A Cloud Storage bucket, through the JSON API with the service account's
 * token from the metadata server — dependency-free, as in sage-state's
 * library store. Only used on Cloud Run (LIVE_BUCKET).
 */
export class GcsStore {
  constructor(bucket, { fetchImpl = fetch } = {}) {
    this.bucket = bucket;
    this.fetch = fetchImpl;
    this.token = null;
    this.tokenExpiresAt = 0;
  }

  async #accessToken() {
    if (this.token && Date.now() < this.tokenExpiresAt) return this.token;
    const response = await this.fetch(
      "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
      { headers: { "Metadata-Flavor": "Google" } },
    );
    if (!response.ok) throw new Error(`metadata token: ${response.status}`);
    const body = await response.json();
    this.token = body.access_token;
    this.tokenExpiresAt = Date.now() + (body.expires_in - 60) * 1000;
    return this.token;
  }

  async #put(name, contentType, body) {
    const url = `https://storage.googleapis.com/upload/storage/v1/b/${this.bucket}/o?uploadType=media&name=${encodeURIComponent(name)}`;
    const response = await this.fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${await this.#accessToken()}`, "Content-Type": contentType },
      body,
    });
    if (!response.ok) throw new Error(`GCS upload ${name}: ${response.status}`);
  }

  async #get(name) {
    const url = `https://storage.googleapis.com/storage/v1/b/${this.bucket}/o/${encodeURIComponent(name)}?alt=media`;
    const response = await this.fetch(url, { headers: { Authorization: `Bearer ${await this.#accessToken()}` } });
    if (response.status === 404) return null;
    if (!response.ok) throw new Error(`GCS download ${name}: ${response.status}`);
    return { contentType: response.headers.get("content-type") || "application/octet-stream", body: Buffer.from(await response.arrayBuffer()) };
  }

  async saveRoom(record) {
    await this.#put(`rooms/${assertId(record.id)}/room.json`, "application/json", JSON.stringify(record));
  }

  async loadRoom(id) {
    const object = await this.#get(`rooms/${assertId(id)}/room.json`);
    return object ? JSON.parse(object.body.toString("utf8")) : null;
  }

  async putAsset(roomId, assetId, { contentType, body }) {
    await this.#put(`rooms/${assertId(roomId)}/assets/${assertId(assetId)}`, contentType, body);
  }

  async getAsset(roomId, assetId) {
    return this.#get(`rooms/${assertId(roomId)}/assets/${assertId(assetId)}`);
  }
}
