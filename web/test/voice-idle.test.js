// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import { test } from "node:test";
import assert from "node:assert/strict";
import { VoiceIdlePolicy, BACKGROUND_MS, QUIET_MS } from "../src/core/voice-idle.js";

function clock(start = 1_000_000) {
  let t = start;
  return { now: () => t, advance: (ms) => { t += ms; } };
}

test("the rule's numbers are the spec's: 2 minutes hidden, 15 minutes quiet", () => {
  assert.equal(BACKGROUND_MS, 120_000);
  assert.equal(QUIET_MS, 900_000);
});

test("a hidden app leaves voice after 2 minutes, and not before", () => {
  const c = clock();
  const policy = new VoiceIdlePolicy({ now: c.now });
  policy.setHidden(true);
  c.advance(BACKGROUND_MS - 1);
  assert.equal(policy.pauseReason(), null);
  c.advance(1);
  assert.equal(policy.pauseReason(), "background");
});

test("coming back before 2 minutes keeps voice; hiding again starts over", () => {
  const c = clock();
  const policy = new VoiceIdlePolicy({ now: c.now });
  policy.setHidden(true);
  c.advance(90_000);
  policy.setHidden(false);
  policy.setHidden(true);
  c.advance(90_000);
  assert.equal(policy.pauseReason(), null);
});

test("hiding twice does not restart the clock", () => {
  const c = clock();
  const policy = new VoiceIdlePolicy({ now: c.now });
  policy.setHidden(true);
  c.advance(100_000);
  policy.setHidden(true);
  c.advance(20_000);
  assert.equal(policy.pauseReason(), "background");
});

test("a quiet room leaves voice after 15 minutes; any ink or speech keeps it", () => {
  const c = clock();
  const policy = new VoiceIdlePolicy({ now: c.now });
  c.advance(QUIET_MS - 60_000);
  policy.activity(); // someone drew
  c.advance(QUIET_MS - 1);
  assert.equal(policy.pauseReason(), null);
  c.advance(1);
  assert.equal(policy.pauseReason(), "quiet");
});

test("background wins over quiet, and resuming starts both clocks again", () => {
  const c = clock();
  const policy = new VoiceIdlePolicy({ now: c.now });
  policy.setHidden(true);
  c.advance(QUIET_MS);
  assert.equal(policy.pauseReason(), "background");
  policy.resumed();
  assert.equal(policy.pauseReason(), null);
  c.advance(QUIET_MS);
  assert.equal(policy.pauseReason(), "quiet");
});
