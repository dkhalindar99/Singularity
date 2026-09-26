// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// protocol/PROTOCOL.md, "Permissions". The server's answer is the one that
// counts; clients call the same function only to grey out their tools.

const HOST_ONLY = new Set(["room.policy", "host.page", "page.add"]);
const POLICIES = new Set(["everyone", "host", "pen"]);
const INKS_MAX_POINTS = 5000;

/** True if this member may change the notebook's content right now. */
export function canDraw(state, member) {
  if (member.role === "host") return true;
  if (state.drawPolicy === "everyone") return true;
  return state.drawPolicy === "pen" && state.penHolder === member.uid;
}

/**
 * @returns {null | "not-host" | "drawing-locked" | "invalid-op"} null means allowed.
 */
export function authorize(state, member, op) {
  if (!isValidOp(op)) return "invalid-op";
  if (HOST_ONLY.has(op.kind)) return member.role === "host" ? null : "not-host";
  return canDraw(state, member) ? null : "drawing-locked";
}

const isString = (v) => typeof v === "string" && v.length > 0;
const isNumber = (v) => typeof v === "number" && Number.isFinite(v);
const isStringArray = (v) => Array.isArray(v) && v.every(isString);
const isColor = (c) => c && isNumber(c.r) && isNumber(c.g) && isNumber(c.b) && isNumber(c.a);
const isFrame = (f) => f && isNumber(f.x) && isNumber(f.y) && isNumber(f.width) && isNumber(f.height);

export function isValidStroke(s) {
  if (!s || typeof s !== "object") return false;
  if (!isString(s.id) || !isString(s.ink) || !isColor(s.color) || !isNumber(s.width)) return false;
  if (!Array.isArray(s.points) || s.points.length === 0 || s.points.length > INKS_MAX_POINTS) return false;
  return s.points.every((p) => p && isNumber(p.x) && isNumber(p.y) && isNumber(p.pressure) && isNumber(p.timeOffset) && isNumber(p.width));
}

export function isValidText(t) {
  return !!t && isString(t.id) && typeof t.text === "string" && isFrame(t.frame) && isNumber(t.fontSize) && isColor(t.color);
}

export function isValidPage(p) {
  return !!p && isString(p.id) && isNumber(p.width) && isNumber(p.height) && p.width > 0 && p.height > 0
    && !!p.background && isString(p.background.kind);
}

export function isValidOp(op) {
  if (!op || typeof op !== "object" || !isString(op.kind)) return false;
  switch (op.kind) {
    case "stroke.add": return isString(op.pageId) && isValidStroke(op.stroke);
    case "stroke.erase":
    case "stroke.restore": return isString(op.pageId) && isStringArray(op.strokeIds);
    case "text.upsert": return isString(op.pageId) && isValidText(op.text);
    case "text.erase": return isString(op.pageId) && isStringArray(op.textIds);
    case "items.move":
      return isString(op.pageId) && isNumber(op.dx) && isNumber(op.dy)
        && (op.strokeIds === undefined || isStringArray(op.strokeIds))
        && (op.textIds === undefined || isStringArray(op.textIds));
    case "page.add": return isValidPage(op.page) && (op.afterPageId == null || isString(op.afterPageId));
    case "room.policy":
      return POLICIES.has(op.drawPolicy) && (op.penHolder == null || isString(op.penHolder));
    case "host.page": return isString(op.pageId);
    default: return false;
  }
}
