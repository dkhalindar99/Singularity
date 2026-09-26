// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Drawing a shared page on a 2D canvas: the paper, committed strokes, text
// boxes, other people's strokes still being drawn, and pointers. Everything
// here is in page coordinates (points); the caller sets the transform.

const TEMPLATE_GAP = 24;

export function cssColor({ r, g, b, a }, alphaScale = 1) {
  return `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${a * alphaScale})`;
}

/** Paper and background. `image` is a loaded HTMLImageElement/ImageBitmap for image backgrounds. */
export function drawBackground(ctx, page, image) {
  ctx.fillStyle = "#FFFFFF";
  ctx.fillRect(0, 0, page.width, page.height);
  const bg = page.background ?? { kind: "blank" };
  if (bg.kind === "image" && image) {
    ctx.drawImage(image, 0, 0, page.width, page.height);
    return;
  }
  if (bg.kind !== "template") return;
  ctx.save();
  ctx.strokeStyle = "#E4EBF1";
  ctx.fillStyle = "#CFD8E3";
  ctx.lineWidth = 1;
  if (bg.template === "lined") {
    for (let y = TEMPLATE_GAP * 3; y < page.height; y += TEMPLATE_GAP) line(ctx, 0, y, page.width, y);
  } else if (bg.template === "grid") {
    for (let y = TEMPLATE_GAP; y < page.height; y += TEMPLATE_GAP) line(ctx, 0, y, page.width, y);
    for (let x = TEMPLATE_GAP; x < page.width; x += TEMPLATE_GAP) line(ctx, x, 0, x, page.height);
  } else if (bg.template === "dotted") {
    for (let y = TEMPLATE_GAP; y < page.height; y += TEMPLATE_GAP) {
      for (let x = TEMPLATE_GAP; x < page.width; x += TEMPLATE_GAP) ctx.fillRect(x - 0.75, y - 0.75, 1.5, 1.5);
    }
  }
  ctx.restore();
}

function line(ctx, x1, y1, x2, y2) {
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.stroke();
}

/**
 * One stroke from points `[[x, y, width], …]`. Pens vary their width point
 * by point; the marker (highlighter) is one even, see-through band, drawn as
 * a single path so its overlaps do not darken.
 */
export function drawPoints(ctx, points, { ink, color, width }) {
  if (!points.length) return;
  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  if (ink === "marker" || color.a < 1) {
    ctx.strokeStyle = cssColor({ ...color, a: 1 });
    ctx.globalAlpha = Math.min(1, color.a);
    ctx.lineWidth = width;
    ctx.beginPath();
    ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1]);
    if (points.length === 1) ctx.lineTo(points[0][0] + 0.01, points[0][1]);
    ctx.stroke();
  } else {
    ctx.strokeStyle = cssColor(color);
    ctx.fillStyle = cssColor(color);
    if (points.length === 1) {
      ctx.beginPath();
      ctx.arc(points[0][0], points[0][1], Math.max(0.5, points[0][2] / 2), 0, Math.PI * 2);
      ctx.fill();
    }
    for (let i = 1; i < points.length; i++) {
      const [x0, y0, w0] = points[i - 1];
      const [x1, y1, w1] = points[i];
      ctx.lineWidth = Math.max(0.5, (w0 + w1) / 2);
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.stroke();
    }
  }
  ctx.restore();
}

export function strokePoints(stroke) {
  return stroke.points.map((p) => [p.x, p.y, p.width]);
}

export function drawStroke(ctx, stroke) {
  drawPoints(ctx, strokePoints(stroke), stroke);
}

export function drawText(ctx, text, { selected = false } = {}) {
  const { frame } = text;
  ctx.save();
  ctx.fillStyle = cssColor(text.color);
  ctx.font = `${text.fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
  ctx.textBaseline = "top";
  const lineHeight = text.fontSize * 1.3;
  let y = frame.y + 4;
  for (const paragraph of text.text.split("\n")) {
    for (const row of wrap(ctx, paragraph, frame.width - 8)) {
      ctx.fillText(row, frame.x + 4, y);
      y += lineHeight;
    }
  }
  if (selected) {
    ctx.strokeStyle = "#62789A";
    ctx.setLineDash([4, 3]);
    ctx.lineWidth = 1;
    ctx.strokeRect(frame.x, frame.y, frame.width, frame.height);
  }
  ctx.restore();
}

function wrap(ctx, paragraph, maxWidth) {
  const words = paragraph.split(" ");
  const rows = [];
  let row = "";
  for (const word of words) {
    const candidate = row ? `${row} ${word}` : word;
    if (row && ctx.measureText(candidate).width > maxWidth) {
      rows.push(row);
      row = word;
    } else {
      row = candidate;
    }
  }
  rows.push(row);
  return rows;
}

/** A pointer: a small coloured dot with the person's name, or a glowing laser dot. */
export function drawPointer(ctx, { x, y, laser }, { name, color }, scale) {
  ctx.save();
  if (laser) {
    const glow = ctx.createRadialGradient(x, y, 0, x, y, 14 / scale);
    glow.addColorStop(0, "rgba(231, 76, 60, 0.95)");
    glow.addColorStop(0.35, "rgba(231, 76, 60, 0.55)");
    glow.addColorStop(1, "rgba(231, 76, 60, 0)");
    ctx.fillStyle = glow;
    ctx.beginPath();
    ctx.arc(x, y, 14 / scale, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.fillStyle = color;
    ctx.strokeStyle = "#FFFFFF";
    ctx.lineWidth = 1.5 / scale;
    ctx.beginPath();
    ctx.arc(x, y, 4.5 / scale, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
  }
  if (name) {
    const size = 11 / scale;
    ctx.font = `600 ${size}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
    const w = ctx.measureText(name).width + 8 / scale;
    const bx = x + 8 / scale;
    const by = y + 6 / scale;
    ctx.fillStyle = laser ? "#E74C3C" : color;
    roundRect(ctx, bx, by, w, size + 6 / scale, 4 / scale);
    ctx.fill();
    ctx.fillStyle = "#FFFFFF";
    ctx.textBaseline = "top";
    ctx.fillText(name, bx + 4 / scale, by + 3 / scale);
  }
  ctx.restore();
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** Distance from a point to a stroke (for the eraser), in page points. */
export function distanceToStroke(stroke, x, y) {
  const pts = stroke.points;
  let best = Infinity;
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i];
    const b = pts[i + 1] ?? a;
    best = Math.min(best, segmentDistance(x, y, a.x, a.y, b.x, b.y) - (a.width ?? stroke.width) / 2);
  }
  return best;
}

function segmentDistance(px, py, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const lengthSquared = dx * dx + dy * dy;
  let t = lengthSquared ? ((px - ax) * dx + (py - ay) * dy) / lengthSquared : 0;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

export function textAt(page, x, y) {
  for (let i = page.texts.length - 1; i >= 0; i--) {
    const item = page.texts[i];
    if (item.erased) continue;
    const f = item.text.frame;
    if (x >= f.x && x <= f.x + f.width && y >= f.y && y <= f.y + f.height) return item.text;
  }
  return null;
}
