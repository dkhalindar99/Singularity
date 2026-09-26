// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// When to leave voice (PROTOCOL.md, "Voice and cost"). LiveKit bills every
// connected minute, talking or not, and voice is most of what a room costs,
// so a client leaves voice when nobody is using it. Pure and clock-driven, so
// it is tested without a browser; the Swift and Kotlin ports follow the same
// rules.

export const BACKGROUND_MS = 2 * 60_000;
export const QUIET_MS = 15 * 60_000;

export class VoiceIdlePolicy {
  constructor({ now = Date.now, backgroundMs = BACKGROUND_MS, quietMs = QUIET_MS } = {}) {
    this.now = now;
    this.backgroundMs = backgroundMs;
    this.quietMs = quietMs;
    this.lastActivity = now();
    this.hiddenSince = null;
  }

  /** Someone spoke, drew or wrote: the room is in use. */
  activity() {
    this.lastActivity = this.now();
  }

  /** The app or tab was hidden (true) or shown again (false). */
  setHidden(hidden) {
    if (hidden) this.hiddenSince ??= this.now();
    else this.hiddenSince = null;
  }

  /**
   * Why voice should be left now: "background", "quiet", or null to stay.
   * Background wins, because coming back to the app rejoins it by itself.
   */
  pauseReason() {
    const t = this.now();
    if (this.hiddenSince !== null && t - this.hiddenSince >= this.backgroundMs) return "background";
    if (t - this.lastActivity >= this.quietMs) return "quiet";
    return null;
  }

  /** After rejoining, the quiet clock starts again. */
  resumed() {
    this.lastActivity = this.now();
    this.hiddenSince = null;
  }
}
