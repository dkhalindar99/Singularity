// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import { test } from "node:test";
import assert from "node:assert/strict";
import { uuid } from "../src/core/uuid.js";

const SHAPE = /^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/;

test("uuid is a capital version-4 UUID", () => {
  assert.match(uuid(), SHAPE);
});

test("without crypto.randomUUID (a plain-http page), it still makes valid, different UUIDs", () => {
  const saved = crypto.randomUUID;
  Object.defineProperty(crypto, "randomUUID", { value: undefined, configurable: true, writable: true });
  try {
    const a = uuid();
    const b = uuid();
    assert.match(a, SHAPE);
    assert.match(b, SHAPE);
    assert.notEqual(a, b);
  } finally {
    Object.defineProperty(crypto, "randomUUID", { value: saved, configurable: true, writable: true });
  }
});
