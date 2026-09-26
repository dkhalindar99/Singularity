// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Voice and video through a local LiveKit dev server, with Chromium's fake
// camera and microphone: host turns the camera on; the guest sees the video.
import { chromium } from "playwright";

const BASE = process.env.LIVE_BASE || "http://localhost:8787";
const shots = process.argv[2] || ".";
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
  args: ["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream", "--autoplay-policy=no-user-gesture-required"],
});
const errors = [];
async function person(name) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 860 }, permissions: ["camera", "microphone"] });
  const page = await context.newPage();
  page.on("pageerror", (e) => errors.push(`${name}: ${e.message}`));
  page.on("console", (m) => { if (m.type() === "error" || m.type() === "warning") errors.push(`${name} ${m.type()}: ${m.text().slice(0, 200)}`); });
  return page;
}

const host = await person("host");
await host.goto(BASE);
await host.fill("#name", "Asha");
await host.fill("#create-title", "Renal physiology");
await host.click("#create-form button[type=submit]");
await host.waitForFunction(() => document.getElementById("room-code").textContent.length === 6);
const code = await host.textContent("#room-code");
await host.waitForFunction(() => !document.getElementById("mic").disabled, null, { timeout: 30000 });
console.log("host mic button:", await host.textContent("#mic"));

const guest = await person("guest");
await guest.goto(`${BASE}/join/${code}`);
await guest.fill("#name", "Ravi");
await guest.click("#join-form button[type=submit]");
await guest.waitForFunction(() => !document.getElementById("mic").disabled, null, { timeout: 30000 });

await host.click("#camera");
await guest.waitForFunction(() => [...document.querySelectorAll("#tiles video")].some((v) => !v.hidden && v.videoWidth > 0), null, { timeout: 20000 });
const size = await guest.evaluate(() => { const v = [...document.querySelectorAll("#tiles video")].find((x) => !x.hidden); return [v.videoWidth, v.videoHeight]; });
console.log("guest receives host video at", size.join("x"));
await guest.waitForFunction(() => document.getElementById("audio").querySelectorAll("audio").length >= 1, null, { timeout: 10000 });
console.log("guest has remote audio elements:", await guest.evaluate(() => document.getElementById("audio").querySelectorAll("audio").length));
await guest.waitForTimeout(1500);
await guest.screenshot({ path: `${shots}/guest-video.png` });

await guest.click("#saver");
await guest.waitForFunction(() => [...document.querySelectorAll("#tiles video")].every((v) => v.hidden), null, { timeout: 10000 });
console.log("data saver hides video: yes");
await host.click("#mic");
await host.waitForFunction(() => document.getElementById("mic").textContent === "Mic off");
await guest.waitForFunction(() => [...document.querySelectorAll(".tile-name span")].some((s) => s.textContent.includes("Asha") && s.textContent.includes("muted")), null, { timeout: 10000 });
console.log("guest sees host muted: yes");
console.log("errors:", errors.filter((e) => !/favicon/.test(e)));
await browser.close();
