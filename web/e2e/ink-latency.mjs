// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Measures how long a point of a stroke being drawn takes to appear on a
// friend's screen: from the pen moving on one page to the point being in the
// other page's live preview. Both browsers share this machine's clock.
import { chromium } from "playwright";
const BASE = process.env.LIVE_BASE || "http://localhost:8787";
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
async function person(name) {
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 860 } })).newPage();
  await page.goto(BASE);
  await page.fill("#name", name);
  return page;
}
const host = await person("Asha");
await host.click("#create-form button[type=submit]");
await host.waitForFunction(() => window.__live?.client?.status === "connected");
const code = await host.textContent("#room-code");
const guest = await person("Ravi");
await guest.fill("#join-code", code);
await guest.click("#join-form button[type=submit]");
await guest.waitForFunction(() => window.__live?.client?.status === "connected");
await host.waitForFunction(() => window.__live.client.members.length === 2);

// Guest: note when each preview point arrives. Host: note when each move happens.
await guest.evaluate(() => {
  window.__arrivals = [];
  window.__live.client.addEventListener("presence", () => {
    const now = performance.timeOrigin + performance.now();
    for (const p of window.__live.client.live.values()) {
      while (window.__arrivals.length < p.points.length) window.__arrivals.push(now);
    }
  });
});
await host.evaluate(() => {
  window.__moves = [];
  document.querySelector(".page-overlay").addEventListener("pointermove", (e) => {
    if (e.buttons) window.__moves.push(performance.timeOrigin + performance.now());
  });
});
const box = await host.locator(".page-overlay").boundingBox();
await host.mouse.move(box.x + 50, box.y + 100);
await host.mouse.down();
const N = 120;
for (let i = 1; i <= N; i++) {
  await host.mouse.move(box.x + 50 + i * 2.5, box.y + 100 + Math.sin(i / 6) * 40);
  await host.waitForTimeout(8); // a hand at ~120 Hz
}
await guest.waitForTimeout(400);
const moves = await host.evaluate(() => window.__moves);
const arrivals = await guest.evaluate(() => window.__arrivals);
await host.mouse.up();
// The first recorded point is the pointerdown; moves line up from index 1.
const lat = [];
for (let i = 0; i < Math.min(moves.length, arrivals.length - 1); i++) lat.push(arrivals[i + 1] - moves[i]);
lat.sort((a, b) => a - b);
const q = (f) => lat[Math.min(lat.length - 1, Math.floor(f * lat.length))].toFixed(1);
console.log(JSON.stringify({ points: lat.length, medianMs: q(0.5), p90Ms: q(0.9), maxMs: lat[lat.length - 1].toFixed(1) }));
await browser.close();
