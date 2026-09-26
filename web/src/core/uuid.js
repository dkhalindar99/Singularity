// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// A random (version 4) UUID, in capitals as Swift writes them. Browsers only
// offer crypto.randomUUID on secure (https or localhost) pages; a phone
// opening a developer's server at http://192.168.x.x has only
// crypto.getRandomValues, so this builds the UUID from that when it must.

export function uuid() {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID().toUpperCase();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  const h = [...b].map((x) => x.toString(16).padStart(2, "0")).join("").toUpperCase();
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
