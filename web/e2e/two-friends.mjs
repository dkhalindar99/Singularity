// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Two friends in one room, in two real browsers: host starts, guest joins by
// code, both draw, guest follows host's page, host locks writing.
import { chromium } from "playwright";

const BASE = process.env.LIVE_BASE || "http://localhost:8787";
const shots = process.argv[2] || ".";
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const errors = [];
async function person(name) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 860 } });
  const page = await context.newPage();
  page.on("pageerror", (e) => errors.push(`${name}: ${e.message}`));
  page.on("console", (m) => { if (m.type() === "error") errors.push(`${name} console: ${m.text()}`); });
  return page;
}

async function draw(page, points) {
  const box = await page.locator(".page-overlay").boundingBox();
  await page.mouse.move(box.x + points[0][0] * box.width, box.y + points[0][1] * box.height);
  await page.mouse.down();
  for (const [x, y] of points.slice(1)) await page.mouse.move(box.x + x * box.width, box.y + y * box.height, { steps: 6 });
  await page.mouse.up();
}

const strokeCount = (page) => page.evaluate(() => window.__live?.client?.state.pages.flatMap((p) => p.strokes.filter((s) => !s.erased)).length);

const host = await person("host");
await host.goto(BASE);
await host.fill("#name", "Asha");
await host.fill("#create-title", "Cardiology — heart sounds");
await host.click("#create-form button[type=submit]");
await host.waitForSelector("#room:not([hidden])");
await host.waitForFunction(() => document.getElementById("room-code").textContent.length === 6);
const code = await host.textContent("#room-code");
console.log("room code", code);

const guest = await person("guest");
await guest.goto(`${BASE}/join/${code}`);
await guest.fill("#name", "Ravi");
await guest.click("#join-form button[type=submit]");
await guest.waitForSelector("#room:not([hidden])");
await host.waitForFunction(() => document.querySelectorAll("#tiles .tile").length === 2);

await draw(host, [[0.2, 0.2], [0.4, 0.25], [0.6, 0.2]]);
await draw(guest, [[0.2, 0.4], [0.5, 0.5], [0.7, 0.45]]);
await host.waitForFunction(() => window.__live.client.state.pages[0].strokes.length === 2);
await guest.waitForFunction(() => window.__live.client.state.pages[0].strokes.length === 2);
console.log("strokes host/guest", await strokeCount(host), await strokeCount(guest));

// Text box from the guest.
await guest.click('#tools button[data-tool="text"]');
const gbox = await guest.locator(".page-overlay").boundingBox();
await guest.mouse.click(gbox.x + gbox.width * 0.15, gbox.y + gbox.height * 0.65);
await guest.waitForSelector(".text-editor");
await guest.keyboard.type("S1 = mitral + tricuspid closing");
await guest.keyboard.press("Enter");
await host.waitForFunction(() => window.__live.client.state.pages[0].texts.length === 1);

// Live pointer: guest hovers; host sees it.
await guest.click('#tools button[data-tool="pen"]');
await guest.mouse.move(gbox.x + gbox.width * 0.5, gbox.y + gbox.height * 0.3);
await guest.mouse.move(gbox.x + gbox.width * 0.52, gbox.y + gbox.height * 0.31);
await host.waitForFunction(() => window.__live.client.activePointers().length === 1);

await host.screenshot({ path: `${shots}/host-drawing.png` });
await guest.screenshot({ path: `${shots}/guest-drawing.png` });

// Host goes to page 2; the guest follows.
await host.click('#pages button[aria-label="Page 2"]');
await guest.waitForFunction(() => document.querySelector('#pages button[aria-current="page"]')?.textContent.startsWith("2"));
console.log("guest followed host to page 2");

// Host locks writing; the guest's pen is refused.
await host.click("#people-button");
await host.selectOption("#policy-select", "host");
await guest.waitForFunction(() => window.__live.client.state.drawPolicy === "host");
await draw(guest, [[0.3, 0.3], [0.5, 0.3]]);
await guest.waitForTimeout(400);
const guestStrokesPage2 = await guest.evaluate(() => window.__live.client.state.pages[1].strokes.length);
console.log("guest strokes on page 2 while locked:", guestStrokesPage2);
await host.screenshot({ path: `${shots}/host-people.png` });

// Guest undoes their own stroke on page 1 (host's stays).
await guest.click('#pages button[aria-label="Page 1"]');
await host.selectOption("#policy-select", "everyone");
await guest.waitForFunction(() => window.__live.client.state.drawPolicy === "everyone");
await guest.click("#undo"); // undoes the text box
await guest.click("#undo"); // undoes the guest's stroke
await host.waitForFunction(() => window.__live.client.state.pages[0].strokes.filter((s) => !s.erased).length === 1 && window.__live.client.state.pages[0].texts.filter((t) => !t.erased).length === 0);
const remaining = await host.evaluate(() => window.__live.client.state.pages[0].strokes.filter((s) => !s.erased).map((s) => s.author));
console.log("after guest's undo, remaining stroke authors:", remaining);

// Narrow phone-sized guest.
await guest.setViewportSize({ width: 390, height: 780 });
await guest.waitForTimeout(300);
await guest.screenshot({ path: `${shots}/guest-phone.png` });

// Host ends the room.
host.on("dialog", (d) => d.accept());
await host.click("#end-room");
await guest.waitForSelector("#ended:not([hidden])");
console.log("guest sees:", await guest.textContent("#ended-title"));
await guest.screenshot({ path: `${shots}/guest-ended.png` });

console.log("errors:", errors.length ? errors : "none");
await browser.close();
