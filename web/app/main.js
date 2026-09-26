// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// The SpaceNotes Live web app: the lobby, the room and the goodbye screen.
// The room is laid out like a video call — people along the top, the shared
// page in the middle, tools along the bottom.

import { RoomClient } from "/src/client/room-client.js";
import { LiveApi } from "/src/client/api.js";
import { CanvasView } from "/src/ui/canvas-view.js";
import { deviceId, makeAuth } from "/app/auth.js";

const $ = (id) => document.getElementById(id);
const serverUrl = location.origin;
const COLORS = [
  { r: 0.19, g: 0.22, b: 0.26, a: 1 },
  { r: 0.18, g: 0.33, b: 0.72, a: 1 },
  { r: 0.75, g: 0.2, b: 0.2, a: 1 },
  { r: 0.17, g: 0.52, b: 0.3, a: 1 },
  { r: 0.55, g: 0.24, b: 0.66, a: 1 },
  { r: 0.93, g: 0.55, b: 0.1, a: 1 },
];
const REJECT_TEXT = {
  "drawing-locked": "The host has paused writing for now.",
  "not-host": "Only the host can do that.",
  "invalid-op": "That change could not be saved.",
};
const ENDED_TEXT = {
  "left": ["You left the room", "The notes stay with the host."],
  "room-ended": ["The room has ended", "The host closed it. Thanks for studying together."],
  "removed-by-host": ["You were removed", "The host removed you from this room."],
  "no-such-room": ["That room is not open", "It may have ended, or the link is wrong."],
  "guests-not-allowed": ["Sign in to join", "The host asked for signed-in friends only."],
  "room-full": ["This room is full", "Ask the host to make space."],
};

let getToken;
let api;
let client = null;
let view = null;
let video = null;
let follow = true;
let lastSnapshot = null;
const images = new Map(); // assetId -> ImageBitmap | "loading"

// ---- start --------------------------------------------------------------

async function start() {
  const config = await fetch("/config.json").then((r) => r.json()).catch(() => ({ auth: "dev" }));
  const auth = await makeAuth(config);
  getToken = () => auth(nameValue());
  api = new LiveApi({ serverUrl, getToken });

  $("name").value = localGet("spacenotes-live-name") || "";
  const joinMatch = /^\/join\/([A-Za-z0-9]{6})$/.exec(location.pathname);
  if (joinMatch) $("join-code").value = joinMatch[1].toUpperCase();
  const roomInHash = new URLSearchParams(location.hash.slice(1)).get("room");
  if (roomInHash && nameValue()) return enterRoom(roomInHash);
  show("lobby");
  (joinMatch ? $("name").value ? $("join-code") : $("name") : $("name")).focus();
}

function nameValue() {
  return $("name").value.trim();
}

function localGet(key) {
  try { return localStorage.getItem(key); } catch { return null; }
}
function localSet(key, value) {
  try { localStorage.setItem(key, value); } catch {}
}

function show(screen) {
  for (const id of ["lobby", "room", "ended"]) $(id).hidden = id !== screen;
}

function toast(text) {
  const el = $("toast");
  el.textContent = text;
  el.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => el.classList.remove("show"), 2600);
}

function requireName() {
  if (nameValue()) {
    localSet("spacenotes-live-name", nameValue());
    return true;
  }
  $("lobby-error").textContent = "Please add your name first.";
  $("name").focus();
  return false;
}

$("join-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("lobby-error").textContent = "";
  if (!requireName()) return;
  const code = $("join-code").value.trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(code)) {
    $("lobby-error").textContent = "A room code has six letters and numbers.";
    return;
  }
  try {
    const found = await api.lookup(code);
    if (!found) {
      $("lobby-error").textContent = "No open room has that code.";
      return;
    }
    enterRoom(found.roomId);
  } catch (err) {
    $("lobby-error").textContent = err.message || "Could not reach the room server.";
  }
});

$("create-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("lobby-error").textContent = "";
  if (!requireName()) return;
  const paper = $("create-paper").value;
  const count = Math.max(1, Math.min(50, Number($("create-pages").value) || 1));
  const pages = Array.from({ length: count }, () => ({
    id: crypto.randomUUID().toUpperCase(),
    width: 595,
    height: 842,
    background: paper === "blank" ? { kind: "blank" } : { kind: "template", template: paper },
  }));
  try {
    const title = $("create-title").value.trim() || `${nameValue()}'s study room`;
    const created = await api.createRoom({ title, pages, allowGuests: $("create-guests").checked });
    enterRoom(created.roomId);
  } catch (err) {
    $("lobby-error").textContent = err.message || "Could not start the room.";
  }
});

// ---- the room -----------------------------------------------------------

function enterRoom(roomId) {
  history.replaceState(null, "", `/#room=${roomId}`);
  show("room");
  client = new RoomClient({ serverUrl, roomId, name: nameValue(), deviceId, getToken });
  view = new CanvasView($("stage"), client, pageImage);
  view.onTextRequest = editText;
  window.__live = { client, view }; // for the browser tests and for debugging
  wireRoom();
  client.connect();
}

function wireRoom() {
  let firstWelcome = true;
  client.addEventListener("status", () => {
    const status = $("status");
    const text = { connecting: "Connecting…", connected: "", reconnecting: "Reconnecting…" }[client.status] ?? "";
    status.textContent = text;
    status.classList.toggle("bad", client.status === "reconnecting");
    if (client.status === "connected" && firstWelcome) {
      firstWelcome = false;
      onFirstWelcome();
    }
    if (client.status === "ended") leaveRoom(client.endedReason);
  });
  client.addEventListener("state", () => {
    lastSnapshot = client.state;
    if (!view.pageId || !client.state.pages.some((p) => p.id === view.pageId)) goTo(client.state.hostPageId ?? client.state.pages[0]?.id, { fromUser: false });
    if (follow && !client.isHost && client.state.hostPageId && view.pageId !== client.state.hostPageId) goTo(client.state.hostPageId, { fromUser: false });
    loadImages();
    renderPages();
    renderToolbar();
    renderPolicy();
    renderFollowHint();
  });
  client.addEventListener("members", () => {
    renderTiles();
    renderPeople();
    renderPages();
  });
  client.addEventListener("presence", () => renderPages());
  client.addEventListener("history", renderToolbar);
  client.addEventListener("reject", (e) => {
    if (e.detail.reason !== "duplicate") toast(REJECT_TEXT[e.detail.reason] ?? "That change was not saved.");
  });
}

async function onFirstWelcome() {
  $("room-title").textContent = client.room.title;
  $("room-code").textContent = client.room.code;
  $("add-page").hidden = !client.isHost;
  $("end-room").hidden = !client.isHost;
  $("follow").hidden = client.isHost;
  $("policy").hidden = !client.isHost;
  goTo(client.state.hostPageId ?? client.state.pages[0]?.id, { fromUser: false });
  renderTiles();
  renderPeople();
  startVideo();
}

function goTo(pageId, { fromUser = true } = {}) {
  if (!pageId) return;
  if (fromUser && !client.isHost && pageId !== client.state.hostPageId) setFollow(false);
  view.showPage(pageId);
  client.sendView(pageId);
  if (client.isHost) client.setHostPage(pageId);
  renderPages();
  renderFollowHint();
}

function setFollow(on) {
  follow = on;
  $("follow").setAttribute("aria-pressed", String(on));
  if (on && client.state.hostPageId) goTo(client.state.hostPageId, { fromUser: false });
  renderFollowHint();
}

$("follow").addEventListener("click", () => setFollow(!follow));

function renderFollowHint() {
  const hint = $("follow-hint");
  const hostPage = client?.state.hostPageId;
  if (!client || client.isHost || follow || !hostPage || hostPage === view.pageId) {
    hint.hidden = true;
    return;
  }
  const number = client.state.pages.findIndex((p) => p.id === hostPage) + 1;
  hint.hidden = false;
  hint.replaceChildren(`The host is on page ${number}`, button("Follow", () => setFollow(true), "primary chip"));
}

function button(label, onClick, className = "") {
  const b = document.createElement("button");
  b.type = "button";
  b.textContent = label;
  if (className) b.className = className;
  b.addEventListener("click", onClick);
  return b;
}

// ---- pages ------------------------------------------------------------------

function renderPages() {
  const nav = $("pages");
  const whoIsWhere = new Map();
  for (const m of client.members) {
    const pageId = client.views.get(m.connectionId) ?? m.pageId;
    if (!whoIsWhere.has(pageId)) whoIsWhere.set(pageId, []);
    whoIsWhere.get(pageId).push(m);
  }
  nav.replaceChildren(...client.state.pages.map((page, i) => {
    const b = button(String(i + 1), () => goTo(page.id), "page-thumb" + (page.width > page.height ? " landscape" : ""));
    b.setAttribute("aria-label", `Page ${i + 1}`);
    if (page.id === view.pageId) b.setAttribute("aria-current", "page");
    const dots = document.createElement("span");
    dots.className = "dots";
    for (const m of whoIsWhere.get(page.id) ?? []) {
      const dot = document.createElement("span");
      dot.className = "dot";
      dot.style.background = m.color;
      dot.title = m.name;
      dots.append(dot);
    }
    b.append(dots);
    return b;
  }));
}

$("add-page").addEventListener("click", () => {
  const current = view.page;
  const page = { id: crypto.randomUUID().toUpperCase(), width: current?.width ?? 595, height: current?.height ?? 842, background: current?.background?.kind === "template" ? current.background : { kind: "blank" } };
  client.addPage(page, current?.id ?? null);
  goTo(page.id);
});

function pageImage(page) {
  if (page.background?.kind !== "image") return null;
  const image = images.get(page.background.assetId);
  return image && image !== "loading" ? image : null;
}

function loadImages() {
  for (const page of client.state.pages) {
    const assetId = page.background?.kind === "image" ? page.background.assetId : null;
    if (!assetId || images.has(assetId)) continue;
    images.set(assetId, "loading");
    api.asset(client.roomId, assetId)
      .then((blob) => createImageBitmap(blob))
      .then((bitmap) => {
        images.set(assetId, bitmap);
        view.invalidate();
      })
      .catch(() => images.delete(assetId));
  }
}

// ---- tools --------------------------------------------------------------------

let colorIndex = 0;
function renderToolbar() {
  $("undo").disabled = !client.canUndo;
  $("redo").disabled = !client.canRedo;
  document.querySelector(".toolbar").classList.toggle("locked", !client.canDraw);
  for (const b of document.querySelectorAll("#tools button")) b.setAttribute("aria-pressed", String(b.dataset.tool === view.tool));
}

document.querySelectorAll("#tools button").forEach((b) => b.addEventListener("click", () => {
  view.setTool(b.dataset.tool);
  renderToolbar();
}));
$("colors").replaceChildren(...COLORS.map((color, i) => {
  const b = button("", () => {
    colorIndex = i;
    view.color = color;
    if (view.tool !== "pen" && view.tool !== "highlighter") view.setTool("pen");
    renderColors();
    renderToolbar();
  }, "color");
  b.style.background = `rgb(${color.r * 255}, ${color.g * 255}, ${color.b * 255})`;
  b.setAttribute("aria-label", `Colour ${i + 1}`);
  return b;
}));
function renderColors() {
  [...$("colors").children].forEach((b, i) => b.setAttribute("aria-pressed", String(i === colorIndex)));
}
renderColors();
$("undo").addEventListener("click", () => client.undo());
$("redo").addEventListener("click", () => client.redo());
document.addEventListener("keydown", (e) => {
  if (!client || e.target.closest?.("input, textarea")) return;
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") {
    e.preventDefault();
    e.shiftKey ? client.redo() : client.undo();
  }
});

function editText(page, existing, at) {
  const f = existing?.frame ?? { x: at.x, y: at.y, width: 220, height: 48 };
  const box = document.createElement("textarea");
  box.className = "text-editor";
  box.value = existing?.text ?? "";
  const { left, top } = view.toScreen(f.x, f.y);
  Object.assign(box.style, { left: `${left}px`, top: `${top}px`, width: `${f.width * view.scale}px`, height: `${f.height * view.scale}px`, fontSize: `${(existing?.fontSize ?? 16) * view.scale}px` });
  document.body.append(box);
  view.editingTextId = existing?.id ?? null;
  view.invalidate();
  box.focus();
  let done = false;
  const finish = (save) => {
    if (done) return;
    done = true;
    view.editingTextId = null;
    const value = box.value.replace(/\s+$/, "");
    const rect = box.getBoundingClientRect(); // before it leaves the page
    box.remove();
    view.invalidate();
    if (!save) return;
    if (!value && existing) return client.eraseTexts(page.id, [existing.id]);
    if (!value || value === existing?.text) return;
    client.upsertText(page.id, {
      id: existing?.id ?? crypto.randomUUID().toUpperCase(),
      text: value,
      frame: { x: f.x, y: f.y, width: Math.max(80, Math.round(rect.width / view.scale)) || f.width, height: Math.max(24, Math.round(rect.height / view.scale)) || f.height },
      fontSize: existing?.fontSize ?? 16,
      color: existing?.color ?? view.color,
    });
  };
  box.addEventListener("blur", () => finish(true));
  box.addEventListener("keydown", (e) => {
    if (e.key === "Escape") finish(false);
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      finish(true);
    }
  });
}

// ---- people -------------------------------------------------------------------

function uniqueMembers() {
  const seen = new Map();
  for (const m of client.members) if (!seen.has(m.uid)) seen.set(m.uid, m);
  return [...seen.values()];
}

function initials(name) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join("") || "?";
}

const tileElements = new Map(); // uid -> { tile, video, avatar, label, badge, track }
function renderTiles() {
  const strip = $("tiles");
  const members = uniqueMembers();
  const wanted = new Set(members.map((m) => m.uid));
  for (const [uid, el] of tileElements) {
    if (!wanted.has(uid)) {
      el.track?.detach(el.video);
      el.tile.remove();
      tileElements.delete(uid);
    }
  }
  for (const m of members) {
    let el = tileElements.get(m.uid);
    if (!el) {
      const tile = document.createElement("div");
      tile.className = "tile";
      const videoEl = document.createElement("video");
      videoEl.autoplay = true;
      videoEl.playsInline = true;
      videoEl.muted = true;
      const avatar = document.createElement("div");
      avatar.className = "avatar";
      const label = document.createElement("div");
      label.className = "tile-name";
      const badge = document.createElement("div");
      badge.className = "tile-badge";
      tile.append(videoEl, avatar, label, badge);
      el = { tile, video: videoEl, avatar, label, badge, track: null };
      tileElements.set(m.uid, el);
    }
    strip.append(el.tile);
    const track = video?.cameraTrack(m.uid) ?? null;
    if (track !== el.track) {
      el.track?.detach(el.video);
      track?.attach(el.video);
      el.track = track;
    }
    el.video.hidden = !track;
    el.avatar.hidden = !!track;
    el.avatar.style.background = m.color;
    el.avatar.textContent = initials(m.name);
    const isMe = m.uid === client.me?.uid;
    const micOff = video ? !video.isMicOn(m.uid) : false;
    const nameTag = document.createElement("span");
    nameTag.textContent = `${m.name}${isMe ? " (you)" : ""}${m.role === "host" ? " · host" : ""}${micOff ? " · muted" : ""}`;
    el.label.replaceChildren(nameTag);
    el.badge.hidden = !m.handRaised;
    el.badge.textContent = "Hand raised";
    el.tile.classList.toggle("speaking", !!video?.isSpeaking(m.uid));
    el.tile.style.borderColor = video?.isSpeaking(m.uid) ? "" : "transparent";
  }
  $("people-count").textContent = String(members.length);
}

$("people-button").addEventListener("click", () => {
  $("people").hidden = !$("people").hidden;
  view.layout();
});

function renderPeople() {
  const list = $("people-list");
  const state = client.state;
  list.replaceChildren(...uniqueMembers().map((m) => {
    const li = document.createElement("li");
    const swatch = document.createElement("span");
    swatch.className = "swatch";
    swatch.style.background = m.color;
    const who = document.createElement("div");
    who.className = "who";
    const role = m.role === "host" ? "Host" : state.drawPolicy === "pen" && state.penHolder === m.uid ? "Has the pen" : "Friend";
    who.append(`${m.name}${m.uid === client.me?.uid ? " (you)" : ""}`);
    const small = document.createElement("small");
    small.textContent = role + (m.handRaised ? " · hand raised" : "");
    who.append(small);
    li.append(swatch, who);
    if (client.isHost && m.role !== "host") {
      li.append(button("Give pen", () => client.setPolicy("pen", m.uid)));
      li.append(button("Remove", () => {
        if (confirm(`Remove ${m.name} from the room?`)) client.removeMember(m.uid);
      }, "danger"));
    }
    return li;
  }));
}

function renderPolicy() {
  if (!client.isHost) return;
  $("policy-select").value = client.state.drawPolicy;
  renderPeople();
}

$("policy-select").addEventListener("change", (e) => {
  const policy = e.target.value;
  if (policy === "pen") {
    const first = uniqueMembers().find((m) => m.role !== "host");
    client.setPolicy("pen", first?.uid ?? null);
  } else {
    client.setPolicy(policy);
  }
});

$("hand").addEventListener("click", () => {
  const raised = $("hand").getAttribute("aria-pressed") !== "true";
  $("hand").setAttribute("aria-pressed", String(raised));
  $("hand").textContent = raised ? "Lower hand" : "Raise hand";
  client.setHandRaised(raised);
});

$("copy-link").addEventListener("click", async () => {
  const link = `${location.origin}/join/${client.room.code}`;
  try {
    await navigator.clipboard.writeText(link);
    toast("Invite link copied");
  } catch {
    prompt("Copy this invite link:", link);
  }
});

$("end-room").addEventListener("click", () => {
  if (confirm("End the room for everyone? The notes stay with you.")) client.endRoom();
});
$("leave").addEventListener("click", () => client.disconnect());

// ---- voice and video ----------------------------------------------------------

async function startVideo() {
  let ticket;
  try {
    ticket = await api.videoToken(client.roomId);
  } catch {
    ticket = null;
  }
  if (!ticket) {
    for (const id of ["mic", "camera", "saver"]) $(id).title = "Voice and video are not set up on this server";
    return;
  }
  try {
    const { LiveVideo } = await import("/src/video/livekit.js");
    video = await LiveVideo.connect({ url: ticket.url, token: ticket.token });
  } catch (err) {
    toast("Voice could not start. You can still write together.");
    console.warn(err);
    return;
  }
  video.attachAudio($("audio"));
  video.addEventListener("change", () => {
    renderMedia();
    renderTiles();
  });
  for (const id of ["mic", "camera", "saver"]) $(id).disabled = false;
  renderMedia();
}

function renderMedia() {
  if (!video) return;
  $("mic").setAttribute("aria-pressed", String(video.micEnabled));
  $("mic").textContent = video.micEnabled ? "Mic on" : "Mic off";
  $("camera").setAttribute("aria-pressed", String(video.cameraEnabled));
  $("camera").textContent = video.cameraEnabled ? "Camera on" : "Camera off";
  $("camera").disabled = video.dataSaver;
  $("saver").setAttribute("aria-pressed", String(video.dataSaver));
  if (!video.canPlayAudio) toast("Tap anywhere to hear the others");
}

$("mic").addEventListener("click", () => video?.setMic(!video.micEnabled).catch(() => toast("The microphone is blocked in this browser.")));
$("camera").addEventListener("click", () => video?.setCamera(!video.cameraEnabled).catch(() => toast("The camera is blocked in this browser.")));
$("saver").addEventListener("click", () => video?.setDataSaver(!video.dataSaver));
document.addEventListener("click", () => {
  if (video && !video.canPlayAudio) video.startAudio();
});

// ---- leaving -------------------------------------------------------------------

function leaveRoom(reason) {
  const wasHost = client?.isHost;
  video?.disconnect();
  video = null;
  view?.destroy();
  history.replaceState(null, "", "/");
  const [title, text] = ENDED_TEXT[reason] ?? ["Disconnected", "The connection to the room was lost."];
  $("ended-title").textContent = title;
  $("ended-text").textContent = text;
  $("download").hidden = !(wasHost && lastSnapshot);
  show("ended");
}

$("download").addEventListener("click", () => {
  const pages = lastSnapshot.pages.map((page) => ({
    ...page,
    strokes: page.strokes.filter((s) => !s.erased).map((s) => s.stroke),
    texts: page.texts.filter((t) => !t.erased).map((t) => t.text),
  }));
  const blob = new Blob([JSON.stringify({ title: client?.room?.title, pages }, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "spacenotes-live-notes.json";
  a.click();
});

start();
