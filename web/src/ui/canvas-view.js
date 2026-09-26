// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// The shared page on screen: two stacked canvases. The lower one holds the
// paper and everything committed, and is redrawn only when the notebook
// changes; the upper one holds what moves — ink still being drawn (yours and
// other people's), pointers, the laser and a stroke being dragged — and is
// redrawn every frame while anything is moving.

import { LiveInkStreamer, round1 } from "../client/room-client.js";
import { drawBackground, drawPoints, drawPointer, drawStroke, drawText, distanceToStroke, strokePoints, textAt } from "./page-renderer.js";

// PROTOCOL.md, `pointer`: hover at most 10 times a second, the laser 30.
const POINTER_EVERY_MS = 100;
const LASER_EVERY_MS = 33;
const LASER_FADE_MS = 700;
const ERASER_RADIUS = 8;
const MAX_POINTS = 5000;

export const TOOLS = {
  pen: { ink: "pen", width: 2.4 },
  highlighter: { ink: "marker", width: 14, alpha: 0.35 },
  eraser: {},
  text: {},
  move: {},
  laser: {},
};

export class CanvasView {
  /**
   * @param {HTMLElement} host  the element the page fills
   * @param {import("../client/room-client.js").RoomClient} client
   * @param {(page) => (CanvasImageSource|null)} pageImage  picture for image backgrounds, if loaded
   */
  constructor(host, client, pageImage = () => null) {
    this.host = host;
    this.client = client;
    this.pageImage = pageImage;
    this.pageId = null;
    this.tool = "pen";
    this.color = { r: 0.19, g: 0.22, b: 0.26, a: 1 };
    this.stylusOnly = false;
    this.scale = 1;
    this.local = null; // the stroke you are drawing
    this.erasing = null; // Set of stroke ids hidden while the eraser is down
    this.dragging = null; // { strokeId | textId, startX, startY, dx, dy }
    this.lasers = new Map(); // connectionId -> [{ x, y, t }]
    this.lastPointerSent = 0;
    this.streamer = new LiveInkStreamer(client);
    this.baseDirty = true;

    this.wrapper = document.createElement("div");
    this.wrapper.className = "page-surface";
    this.base = document.createElement("canvas");
    this.overlay = document.createElement("canvas");
    this.overlay.className = "page-overlay";
    this.overlay.setAttribute("aria-label", "Shared page");
    this.overlay.setAttribute("role", "img");
    this.wrapper.append(this.base, this.overlay);
    host.append(this.wrapper);

    this.#bindInput();
    this.resizeObserver = new ResizeObserver(() => this.layout());
    this.resizeObserver.observe(host);
    client.addEventListener("state", () => { this.baseDirty = true; });
    client.addEventListener("presence", () => this.#collectLasers());
    this.frame = requestAnimationFrame(() => this.#tick());
  }

  destroy() {
    cancelAnimationFrame(this.frame);
    this.resizeObserver.disconnect();
    this.wrapper.remove();
  }

  get page() {
    return this.client.state.pages.find((p) => p.id === this.pageId) ?? null;
  }

  showPage(pageId) {
    if (this.pageId === pageId) return;
    this.pageId = pageId;
    this.baseDirty = true;
    this.layout();
  }

  setTool(tool) {
    this.tool = tool;
    this.overlay.dataset.tool = tool;
  }

  invalidate() {
    this.baseDirty = true;
  }

  layout() {
    const page = this.page;
    if (!page) return;
    const box = this.host.getBoundingClientRect();
    const margin = 24;
    this.scale = Math.max(0.1, Math.min((box.width - margin) / page.width, (box.height - margin) / page.height));
    const cssW = Math.floor(page.width * this.scale);
    const cssH = Math.floor(page.height * this.scale);
    const dpr = window.devicePixelRatio || 1;
    for (const canvas of [this.base, this.overlay]) {
      canvas.style.width = `${cssW}px`;
      canvas.style.height = `${cssH}px`;
      canvas.width = Math.round(cssW * dpr);
      canvas.height = Math.round(cssH * dpr);
    }
    this.wrapper.style.width = `${cssW}px`;
    this.wrapper.style.height = `${cssH}px`;
    this.baseDirty = true;
  }

  #context(canvas) {
    const ctx = canvas.getContext("2d");
    const k = canvas.width / (this.page?.width || 1);
    ctx.setTransform(k, 0, 0, k, 0, 0);
    return ctx;
  }

  #tick() {
    this.frame = requestAnimationFrame(() => this.#tick());
    const page = this.page;
    if (!page) return;
    if (this.baseDirty) {
      this.baseDirty = false;
      this.#drawBase(page);
    }
    this.#drawOverlay(page);
  }

  #drawBase(page) {
    const ctx = this.#context(this.base);
    ctx.clearRect(0, 0, page.width, page.height);
    drawBackground(ctx, page, this.pageImage(page));
    for (const item of page.strokes) {
      if (item.erased || this.erasing?.has(item.stroke.id)) continue;
      if (this.dragging?.strokeId === item.stroke.id) continue;
      drawStroke(ctx, item.stroke);
    }
    for (const item of page.texts) {
      if (item.erased || this.dragging?.textId === item.text.id || this.editingTextId === item.text.id) continue;
      drawText(ctx, item.text);
    }
  }

  #drawOverlay(page) {
    const ctx = this.#context(this.overlay);
    ctx.clearRect(0, 0, page.width, page.height);
    const byConnection = new Map(this.client.members.map((m) => [m.connectionId, m]));

    for (const preview of this.client.live.values()) {
      if (preview.pageId !== page.id) continue;
      drawPoints(ctx, preview.points, preview);
    }
    if (this.local) drawPoints(ctx, this.local.points.map((p) => [p.x, p.y, p.width]), this.local);
    if (this.dragging) {
      ctx.save();
      ctx.translate(this.dragging.dx, this.dragging.dy);
      if (this.dragging.strokeId) {
        const item = page.strokes.find((s) => s.stroke.id === this.dragging.strokeId);
        if (item) drawPoints(ctx, strokePoints(item.stroke), item.stroke);
      } else {
        const item = page.texts.find((t) => t.text.id === this.dragging.textId);
        if (item) drawText(ctx, item.text, { selected: true });
      }
      ctx.restore();
    }

    const now = Date.now();
    for (const [connectionId, pointer] of this.client.activePointers(now)) {
      if (pointer.pageId !== page.id || pointer.laser) continue;
      const member = byConnection.get(connectionId);
      if (member) drawPointer(ctx, pointer, member, this.scale);
    }
    for (const [connectionId, trail] of this.lasers) {
      const fresh = trail.filter((p) => now - p.t < LASER_FADE_MS && p.pageId === page.id);
      this.lasers.set(connectionId, fresh);
      fresh.forEach((p, i) => {
        ctx.globalAlpha = (1 - (now - p.t) / LASER_FADE_MS) * 0.6;
        drawPointer(ctx, { x: p.x, y: p.y, laser: true }, { name: "", color: "#E74C3C" }, this.scale * (1.6 - 0.6 * (i / Math.max(1, fresh.length))));
      });
      ctx.globalAlpha = 1;
      const last = fresh[fresh.length - 1];
      if (last) {
        const member = byConnection.get(connectionId);
        drawPointer(ctx, { x: last.x, y: last.y, laser: true }, { name: member?.name ?? "", color: "#E74C3C" }, this.scale);
      }
    }
  }

  /** Other people's laser positions become fading trails. */
  #collectLasers() {
    for (const [connectionId, pointer] of this.client.pointers) {
      if (!pointer.laser) continue;
      const trail = this.lasers.get(connectionId) ?? [];
      const last = trail[trail.length - 1];
      if (!last || last.x !== pointer.x || last.y !== pointer.y) trail.push({ x: pointer.x, y: pointer.y, pageId: pointer.pageId, t: Date.now() });
      this.lasers.set(connectionId, trail.slice(-24));
    }
  }

  // ---- input ----------------------------------------------------------------

  #toPage(event) {
    const rect = this.overlay.getBoundingClientRect();
    return { x: (event.clientX - rect.left) / this.scale, y: (event.clientY - rect.top) / this.scale };
  }

  #bindInput() {
    const el = this.overlay;
    el.style.touchAction = "none";
    el.addEventListener("pointerdown", (e) => this.#down(e));
    el.addEventListener("pointermove", (e) => this.#move(e));
    el.addEventListener("pointerup", (e) => this.#up(e));
    el.addEventListener("pointercancel", (e) => this.#up(e, true));
    el.addEventListener("pointerleave", () => {
      if (!this.local && !this.dragging) this.client.hidePointer();
    });
  }

  #accepts(event) {
    return !this.stylusOnly || event.pointerType === "pen" || event.pointerType === "mouse";
  }

  #down(event) {
    const page = this.page;
    if (!page || !this.#accepts(event) || event.button > 0) return;
    const { x, y } = this.#toPage(event);
    if (this.tool === "laser") {
      this.overlay.setPointerCapture(event.pointerId);
      this.laserDown = true;
      this.#sendPointer(page.id, x, y, true, Date.now());
      this.#addLocalLaser(x, y);
      return;
    }
    if (!this.client.canDraw) return;
    this.overlay.setPointerCapture(event.pointerId);

    if (this.tool === "pen" || this.tool === "highlighter") {
      const spec = TOOLS[this.tool];
      const color = this.tool === "highlighter" ? { ...this.color, a: spec.alpha } : this.color;
      this.local = {
        id: crypto.randomUUID().toUpperCase(),
        ink: spec.ink,
        color,
        width: spec.width,
        startedAt: performance.now(),
        points: [],
      };
      this.streamer.begin({ pageId: page.id, liveId: this.local.id, ink: spec.ink, color, width: spec.width });
      this.#addPoint(event);
    } else if (this.tool === "eraser") {
      this.erasing = new Set();
      this.#eraseAt(x, y);
    } else if (this.tool === "move") {
      const text = textAt(page, x, y);
      const hit = text ? null : this.#strokeAt(x, y, 10);
      if (text) this.dragging = { textId: text.id, startX: x, startY: y, dx: 0, dy: 0 };
      else if (hit) this.dragging = { strokeId: hit.id, startX: x, startY: y, dx: 0, dy: 0 };
      this.baseDirty = true;
    } else if (this.tool === "text") {
      // Open the editor after this press ends, or the press takes focus back from it.
      event.preventDefault();
      const existing = textAt(page, x, y);
      setTimeout(() => this.onTextRequest?.(page, existing, { x, y }), 0);
    }
  }

  #move(event) {
    const page = this.page;
    if (!page) return;
    const { x, y } = this.#toPage(event);
    const now = Date.now();
    if (this.tool === "laser" && this.laserDown) {
      this.#addLocalLaser(x, y);
      if (now - this.lastPointerSent >= LASER_EVERY_MS) this.#sendPointer(page.id, x, y, true, now);
      return;
    }
    if (this.local) {
      for (const e of event.getCoalescedEvents?.() ?? [event]) this.#addPoint(e);
    } else if (this.erasing) {
      this.#eraseAt(x, y);
    } else if (this.dragging) {
      this.dragging.dx = x - this.dragging.startX;
      this.dragging.dy = y - this.dragging.startY;
    }
    // While drawing, the live ink already shows where the pen is.
    if (this.local || this.tool === "laser") return;
    const last = this.lastPointer;
    const moved = !last || Math.abs(last.x - x) >= 1 || Math.abs(last.y - y) >= 1;
    if (moved && now - this.lastPointerSent >= POINTER_EVERY_MS) this.#sendPointer(page.id, x, y, false, now);
  }

  #sendPointer(pageId, x, y, laser, now) {
    this.lastPointerSent = now;
    this.lastPointer = { x, y };
    this.client.sendPointer(pageId, x, y, laser);
  }

  #up(event, cancelled = false) {
    const page = this.page;
    if (this.laserDown) {
      this.laserDown = false;
      this.client.hidePointer();
      return;
    }
    if (this.local && page) {
      if (!cancelled) this.#addPoint(event);
      this.streamer.end();
      const stroke = this.#finishStroke(this.local);
      this.local = null;
      if (!cancelled && stroke.points.length) this.client.addStroke(page.id, stroke);
    } else if (this.erasing && page) {
      const ids = [...this.erasing];
      this.erasing = null;
      if (ids.length) this.client.eraseStrokes(page.id, ids);
      this.baseDirty = true;
    } else if (this.dragging && page) {
      const { strokeId, textId, dx, dy } = this.dragging;
      this.dragging = null;
      if (!cancelled && (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5)) {
        this.client.moveItems(page.id, strokeId ? { strokeIds: [strokeId] } : { textIds: [textId] }, round1(dx), round1(dy));
      }
      this.baseDirty = true;
    }
  }

  #addPoint(event) {
    const { x, y } = this.#toPage(event);
    const local = this.local;
    const last = local.points[local.points.length - 1];
    if (last && Math.hypot(last.x - x, last.y - y) < 0.4) return; // closer than a pixel adds nothing
    const isPen = event.pointerType === "pen";
    // PortablePoint.pressure is a raw force where about 1.0 is an average
    // press (PencilKit's scale). Browsers report 0…1 with 0.5 as average.
    const pressure = isPen && event.pressure > 0 ? event.pressure * 2 : 1;
    const width = local.ink === "marker" ? local.width : local.width * (isPen ? 0.55 + 0.45 * pressure : 1);
    const point = {
      x: round2(x),
      y: round2(y),
      pressure: round2(pressure),
      timeOffset: Math.round(performance.now() - local.startedAt) / 1000,
      width: round2(width),
    };
    if (isPen && typeof event.altitudeAngle === "number") point.altitude = round2(event.altitudeAngle);
    if (isPen && typeof event.azimuthAngle === "number") point.azimuth = round2(event.azimuthAngle);
    local.points.push(point);
    this.streamer.add(point.x, point.y, point.width);
    if (local.points.length >= MAX_POINTS) this.#continueStroke();
  }

  /** A stroke may hold 5,000 points (PROTOCOL.md); a longer one carries on as a new stroke. */
  #continueStroke() {
    const page = this.page;
    const done = this.local;
    this.streamer.end();
    this.client.addStroke(page.id, this.#finishStroke(done));
    const last = done.points[done.points.length - 1];
    this.local = { ...done, id: crypto.randomUUID().toUpperCase(), startedAt: performance.now(), points: [{ ...last, timeOffset: 0 }] };
    this.streamer.begin({ pageId: page.id, liveId: this.local.id, ink: done.ink, color: done.color, width: done.width });
    this.streamer.add(last.x, last.y, last.width);
  }

  #finishStroke(local) {
    const widths = local.points.map((p) => p.width);
    return {
      id: local.id,
      ink: local.ink,
      color: local.color,
      width: round2(widths.reduce((a, b) => a + b, 0) / Math.max(1, widths.length)),
      // Whole seconds, like the notebook's own dates (NotebookStorage uses .iso8601).
      createdAt: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
      points: local.points,
    };
  }

  #strokeAt(x, y, radius) {
    const page = this.page;
    for (let i = page.strokes.length - 1; i >= 0; i--) {
      const item = page.strokes[i];
      if (!item.erased && distanceToStroke(item.stroke, x, y) <= radius / Math.max(this.scale, 0.5)) return item.stroke;
    }
    return null;
  }

  #eraseAt(x, y) {
    const page = this.page;
    for (const item of page.strokes) {
      if (item.erased || this.erasing.has(item.stroke.id)) continue;
      if (distanceToStroke(item.stroke, x, y) <= ERASER_RADIUS / Math.max(this.scale, 0.5)) {
        this.erasing.add(item.stroke.id);
        this.baseDirty = true;
      }
    }
  }

  #addLocalLaser(x, y) {
    const trail = this.lasers.get("me") ?? [];
    trail.push({ x, y, pageId: this.pageId, t: Date.now() });
    this.lasers.set("me", trail.slice(-24));
  }

  /** Where a page point is on screen, for placing the text editor. */
  toScreen(x, y) {
    const rect = this.overlay.getBoundingClientRect();
    return { left: rect.left + x * this.scale, top: rect.top + y * this.scale };
  }
}

const round2 = (n) => Math.round(n * 100) / 100;
