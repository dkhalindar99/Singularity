// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// A token bucket per key. Room codes are only six characters, so guessing
// has to be slow; a socket that floods the room has to be cut off.

export class RateLimiter {
  constructor({ capacity, refillPerSecond, now = Date.now, maxKeys = 50_000 }) {
    this.capacity = capacity;
    this.refillPerSecond = refillPerSecond;
    this.now = now;
    this.maxKeys = maxKeys;
    this.buckets = new Map();
  }

  /** Takes one token for `key`; false when the bucket is empty. */
  take(key) {
    const t = this.now();
    let bucket = this.buckets.get(key);
    if (!bucket) {
      if (this.buckets.size >= this.maxKeys) this.buckets.delete(this.buckets.keys().next().value);
      bucket = { tokens: this.capacity, at: t };
      this.buckets.set(key, bucket);
    }
    bucket.tokens = Math.min(this.capacity, bucket.tokens + ((t - bucket.at) / 1000) * this.refillPerSecond);
    bucket.at = t;
    if (bucket.tokens < 1) return false;
    bucket.tokens -= 1;
    return true;
  }
}
