# Browser tests

Two real browsers in one room, driven by Playwright. They are run by hand,
not in `npm test`, because they need a running server (and, for voice, a
LiveKit server).

```sh
# Ink, text, pointers, follow the host, locking, undo, ending the room:
cd server && LIVE_DEV_AUTH=1 PORT=8787 node src/server.js &
node web/e2e/two-friends.mjs /tmp/shots

# Voice, against a local LiveKit dev server (keys devkey/secret):
livekit-server --dev --bind 127.0.0.1 &
cd server && LIVE_DEV_AUTH=1 PORT=8787 LIVEKIT_URL=ws://127.0.0.1:7880 \
  LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret node src/server.js &
node web/e2e/voice-call.mjs /tmp/shots
```

`playwright` must be installed where Node can find it (`npm i playwright` in a
scratch folder and run from there, or `NODE_PATH`). Set `CHROMIUM_PATH` if
Playwright's own Chromium is not installed. The voice test uses Chromium's
fake microphone.

The voice test also tries to turn a camera on from inside the page, by
calling LiveKit directly: the room server's ticket allows the microphone
only, so LiveKit must refuse it.

## How fast ink reaches a friend

```sh
node web/e2e/ink-latency.mjs     # against a running server
```

It draws a stroke in one browser and times each point until it is in the
other browser's live preview (both on one machine, so no network in between).
On 2026-09-26: with 30 ms batching, median 16 ms and 90th percentile 29 ms;
with the first point sent at once and then one message per 16 ms frame,
median about 2 ms and 90th percentile about 4 ms. The test moves the pen
about once a frame, so each point goes out at once; a real pencil at
120–240 Hz groups points for up to 16 ms, so expect about 8 ms on average.
Real networks add their own travel time on top (roughly 20–60 ms in India).
