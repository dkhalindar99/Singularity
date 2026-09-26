// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Who is calling. Production verifies Firebase ID tokens, the same way the
// notebook proxy does (notebook/backend/src/firebaseAuth.js): an RS256 JWT
// checked against Google's published certs, dependency-free. Development can
// switch on "dev" tokens instead, so the demo and tests run without Firebase.

import crypto from "node:crypto";

export class HttpError extends Error {
  constructor(status, message, code = undefined) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const CERT_URL =
  "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com";

/** An identity: `{ uid, name, isAnonymous }`. */

export function firebaseAuthenticator({ projectId, fetchImpl = fetch, now = Date.now, clockSkewSec = 300 }) {
  if (!projectId) throw new Error("FIREBASE_PROJECT_ID is required for Firebase authentication");
  const cache = { certs: null, expiresAt: 0 };

  async function certs() {
    if (cache.certs && now() < cache.expiresAt) return cache.certs;
    let response;
    try {
      response = await fetchImpl(CERT_URL);
    } catch (err) {
      throw new HttpError(503, `could not fetch token-signing certs: ${err.message}`);
    }
    if (!response.ok) throw new HttpError(503, "could not fetch token-signing certs");
    const body = await response.json();
    const maxAge = /max-age=(\d+)/.exec(response.headers.get("cache-control") || "");
    cache.certs = body;
    cache.expiresAt = now() + (maxAge ? Number(maxAge[1]) * 1000 : 3600_000);
    return body;
  }

  return async function authenticate(token) {
    if (!token) throw new HttpError(401, "missing token", "unauthenticated");
    const parts = token.split(".");
    if (parts.length !== 3) throw new HttpError(401, "malformed token", "unauthenticated");
    let header, payload;
    try {
      header = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
      payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    } catch {
      throw new HttpError(401, "malformed token", "unauthenticated");
    }
    if (header.alg !== "RS256" || !header.kid) throw new HttpError(401, "unexpected token header", "unauthenticated");
    const cert = (await certs())[header.kid];
    if (!cert) throw new HttpError(401, "unknown token key id", "unauthenticated");
    const ok = crypto.createVerify("RSA-SHA256").update(`${parts[0]}.${parts[1]}`)
      .verify(cert, Buffer.from(parts[2], "base64url"));
    if (!ok) throw new HttpError(401, "bad token signature", "unauthenticated");

    const nowSec = Math.floor(now() / 1000);
    if (payload.aud !== projectId || payload.iss !== `https://securetoken.google.com/${projectId}`) {
      throw new HttpError(401, "token is for another project", "unauthenticated");
    }
    if (typeof payload.exp !== "number" || payload.exp <= nowSec - clockSkewSec) {
      throw new HttpError(401, "token expired", "unauthenticated");
    }
    if (typeof payload.iat !== "number" || payload.iat > nowSec + clockSkewSec) {
      throw new HttpError(401, "token issued in the future", "unauthenticated");
    }
    if (typeof payload.sub !== "string" || !payload.sub) throw new HttpError(401, "token missing subject", "unauthenticated");
    return {
      uid: payload.sub,
      name: typeof payload.name === "string" ? payload.name : "",
      isAnonymous: payload.firebase?.sign_in_provider === "anonymous",
    };
  };
}

/**
 * Development only: a token is `dev:<uid>:<name>` or `dev:<uid>:<name>:guest`
 * (an anonymous user). Never enable this on a deployed server — anyone could
 * claim to be anyone.
 */
export function devAuthenticator() {
  return async function authenticate(token) {
    const match = /^dev:([A-Za-z0-9_-]{1,64}):([^:]{0,60})(:guest)?$/.exec(token || "");
    if (!match) throw new HttpError(401, "expected a dev token: dev:<uid>:<name>", "unauthenticated");
    return { uid: match[1], name: match[2], isAnonymous: Boolean(match[3]) };
  };
}
