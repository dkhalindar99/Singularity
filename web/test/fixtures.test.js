// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// The format contract: the JavaScript reducer and permission check against
// every file in fixtures/protocol/. The Swift and Kotlin ports run the same files.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { apply, authorize } from "../src/core/index.js";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "fixtures", "protocol");
const load = (path) => JSON.parse(readFileSync(join(fixtures, path), "utf8"));

/** Value equality where a missing field equals null (protocol/PROTOCOL.md, Numbers). */
export function normalized(value) {
  if (Array.isArray(value)) return value.map(normalized);
  if (value && typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      if (value[key] !== null && value[key] !== undefined) out[key] = normalized(value[key]);
    }
    return out;
  }
  return value;
}

for (const file of readdirSync(join(fixtures, "scenarios")).sort()) {
  const scenario = load(join("scenarios", file));
  test(`scenario ${scenario.name}`, () => {
    const before = structuredClone(scenario.initial);
    let state = scenario.initial;
    for (const sequenced of scenario.ops) state = apply(state, sequenced);
    assert.deepEqual(normalized(state), normalized(scenario.expected));
    assert.deepEqual(scenario.initial, before, "apply must not modify its input");
  });
}

for (const c of load("permissions/cases.json").cases) {
  test(`permission: ${c.name}`, () => {
    assert.equal(authorize(c.state, c.member, c.op), c.expected);
  });
}

test("every message fixture is a JSON object with a type", () => {
  for (const file of ["messages/server-to-client.json", "messages/client-to-server.json"]) {
    for (const [name, message] of Object.entries(load(file).messages)) {
      assert.equal(typeof message.type, "string", `${file} ${name}`);
    }
  }
});
