// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// LiveKit access tokens. Voice goes through LiveKit, not this server; all
// this server does is hand each member a short-lived signed ticket for the
// matching LiveKit room.
//
// SpaceNotes Live is ink and voice only: no cameras, no screen sharing. The
// ticket itself says so (canPublishSources), so LiveKit refuses any other
// track even from a modified app. Faces are never carried, which keeps both
// the bill and the personal data small (docs/research).
//
// A LiveKit token is an HS256 JWT signed with the project's API secret
// (docs.livekit.io, "Authentication"), so node:crypto is all it needs.

import crypto from "node:crypto";

const b64 = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");

/**
 * @param {object} o
 * @param {string} o.apiKey
 * @param {string} o.apiSecret
 * @param {string} o.room      LiveKit room name (the Live room id).
 * @param {string} o.identity  The member's uid.
 * @param {string} o.name      Shown under their tile.
 * @param {number} [o.ttlSec]  Lifetime; the SDK reconnects with a fresh one.
 * @param {number} [o.nowSec]
 */
export function liveKitToken({ apiKey, apiSecret, room, identity, name, ttlSec = 2 * 3600, nowSec = Math.floor(Date.now() / 1000) }) {
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    iss: apiKey,
    sub: identity,
    name,
    nbf: nowSec - 10,
    exp: nowSec + ttlSec,
    video: {
      room,
      roomJoin: true,
      canPublish: true,
      canPublishSources: ["microphone"],
      canSubscribe: true,
      // Ink goes through the room server, which orders and checks it; nothing
      // should be able to bypass that through LiveKit's data channel.
      canPublishData: false,
    },
  };
  const input = `${b64(header)}.${b64(payload)}`;
  const signature = crypto.createHmac("sha256", apiSecret).update(input).digest("base64url");
  return `${input}.${signature}`;
}
