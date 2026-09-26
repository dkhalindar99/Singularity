// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Voice through a local LiveKit dev server, with Chromium's fake microphone:
// the guest hears the host, sees the host's mute, and nobody can turn a
// camera on — not even by calling LiveKit directly from the page, because
// the room server's ticket allows the microphone only.
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
  page.on("console", (m) => { if (m.type() === "error") errors.push(`${name} ${m.type()}: ${m.text().slice(0, 200)}`); });
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
console.log("camera button present:", await host.locator("#camera").count() > 0);

const guest = await person("guest");
await guest.goto(`${BASE}/join/${code}`);
await guest.fill("#name", "Ravi");
await guest.click("#join-form button[type=submit]");
await guest.waitForFunction(() => !document.getElementById("mic").disabled, null, { timeout: 30000 });
await guest.waitForFunction(() => document.getElementById("audio").querySelectorAll("audio").length >= 1, null, { timeout: 10000 });
console.log("guest hears the host: yes");

// Try to force a camera on from inside the page. The ticket forbids it.
const forced = await host.evaluate(async () => {
  try {
    await window.__live.voice.room.localParticipant.setCameraEnabled(true);
    await new Promise((r) => setTimeout(r, 1500));
    const pub = [...window.__live.voice.room.localParticipant.trackPublications.values()].find((p) => p.source === "camera");
    return pub ? "camera published" : "camera not published";
  } catch (err) {
    return `refused: ${err.message.slice(0, 80)}`;
  }
});
console.log("forcing a camera:", forced);
await guest.waitForTimeout(1500);
const guestVideoTracks = await guest.evaluate(() => [...window.__live.voice.room.remoteParticipants.values()].flatMap((p) => [...p.trackPublications.values()]).filter((t) => t.kind === "video").length);
console.log("video tracks the guest can see:", guestVideoTracks);

await host.click("#mic");
await host.waitForFunction(() => document.getElementById("mic").textContent === "Mic off");
await guest.waitForFunction(() => [...document.querySelectorAll(".tile-name span")].some((s) => s.textContent.includes("Asha") && s.textContent.includes("muted")), null, { timeout: 10000 });
console.log("guest sees host muted: yes");
await guest.screenshot({ path: `${shots}/guest-voice.png` });
console.log("errors:", errors);
await browser.close();
