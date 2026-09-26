// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// The room reducer: protocol/PROTOCOL.md, "The reducer". Pure and
// deterministic, shared by the server (which keeps the authoritative state)
// and the web client. The Swift and Kotlin ports must agree with it on every
// file in fixtures/protocol/scenarios.

export const PROTOCOL_VERSION = 1;

/** An empty room state. */
export function emptyState() {
  return {
    protocol: PROTOCOL_VERSION,
    seq: 0,
    drawPolicy: "everyone",
    penHolder: null,
    hostPageId: null,
    pages: [],
  };
}

/** A deep copy, so callers can keep the old state (undo, rollback). */
export function cloneState(state) {
  return structuredClone(state);
}

/**
 * Applies one sequenced op and returns the new state. Never throws on an op
 * that does not fit; the input state is not modified.
 * @param {object} state
 * @param {{seq:number, author:string, op:object}} sequenced
 */
export function apply(state, sequenced) {
  const next = cloneState(state);
  applyInPlace(next, sequenced);
  return next;
}

/** Same as `apply`, but mutates `state`. The server uses this on its own copy. */
export function applyInPlace(state, { seq, author, op }) {
  state.seq = seq;
  if (!op || typeof op !== "object") return state;
  const page = typeof op.pageId === "string" ? state.pages.find((p) => p.id === op.pageId) : undefined;

  switch (op.kind) {
    case "stroke.add": {
      const stroke = op.stroke;
      if (!page || !stroke || typeof stroke.id !== "string") break;
      if (page.strokes.some((item) => item.stroke.id === stroke.id)) break;
      page.strokes.push({ author, seq, erased: false, stroke: structuredClone(stroke) });
      break;
    }
    case "stroke.erase":
    case "stroke.restore": {
      if (!page || !Array.isArray(op.strokeIds)) break;
      const erased = op.kind === "stroke.erase";
      const ids = new Set(op.strokeIds);
      for (const item of page.strokes) if (ids.has(item.stroke.id)) item.erased = erased;
      break;
    }
    case "text.upsert": {
      const text = op.text;
      if (!page || !text || typeof text.id !== "string") break;
      const existing = page.texts.find((item) => item.text.id === text.id);
      if (existing) {
        existing.text = structuredClone(text);
        existing.erased = false;
      } else {
        page.texts.push({ author, seq, erased: false, text: structuredClone(text) });
      }
      break;
    }
    case "text.erase": {
      if (!page || !Array.isArray(op.textIds)) break;
      const ids = new Set(op.textIds);
      for (const item of page.texts) if (ids.has(item.text.id)) item.erased = true;
      break;
    }
    case "items.move": {
      if (!page || typeof op.dx !== "number" || typeof op.dy !== "number") break;
      const strokeIds = new Set(Array.isArray(op.strokeIds) ? op.strokeIds : []);
      const textIds = new Set(Array.isArray(op.textIds) ? op.textIds : []);
      for (const item of page.strokes) {
        if (item.erased || !strokeIds.has(item.stroke.id)) continue;
        for (const point of item.stroke.points) {
          point.x += op.dx;
          point.y += op.dy;
        }
      }
      for (const item of page.texts) {
        if (item.erased || !textIds.has(item.text.id)) continue;
        item.text.frame.x += op.dx;
        item.text.frame.y += op.dy;
      }
      break;
    }
    case "page.add": {
      const newPage = op.page;
      if (!newPage || typeof newPage.id !== "string") break;
      if (state.pages.some((p) => p.id === newPage.id)) break;
      const entry = { ...structuredClone(newPage), strokes: [], texts: [] };
      const index = op.afterPageId == null ? -1 : state.pages.findIndex((p) => p.id === op.afterPageId);
      if (index === -1) state.pages.push(entry);
      else state.pages.splice(index + 1, 0, entry);
      break;
    }
    case "room.policy": {
      if (typeof op.drawPolicy !== "string") break;
      state.drawPolicy = op.drawPolicy;
      state.penHolder = typeof op.penHolder === "string" ? op.penHolder : null;
      break;
    }
    case "host.page": {
      if (page) state.hostPageId = page.id;
      break;
    }
    default:
      break;
  }
  return state;
}

/** Strokes and texts that are drawn: everything not erased. */
export function visibleItems(page) {
  return {
    strokes: page.strokes.filter((item) => !item.erased),
    texts: page.texts.filter((item) => !item.erased),
  };
}
