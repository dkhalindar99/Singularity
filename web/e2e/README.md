# Browser tests

Two real browsers in one room, driven by Playwright. They are run by hand,
not in `npm test`, because they need a running server (and, for video, a
LiveKit server).

```sh
# Ink, text, pointers, follow the host, locking, undo, ending the room:
cd server && LIVE_DEV_AUTH=1 PORT=8787 node src/server.js &
node web/e2e/two-friends.mjs /tmp/shots

# Voice and video, against a local LiveKit dev server (keys devkey/secret):
livekit-server --dev --bind 127.0.0.1 &
cd server && LIVE_DEV_AUTH=1 PORT=8787 LIVEKIT_URL=ws://127.0.0.1:7880 \
  LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret node src/server.js &
node web/e2e/video-call.mjs /tmp/shots
```

`playwright` must be installed where Node can find it (`npm i playwright` in a
scratch folder and run from there, or `NODE_PATH`). Set `CHROMIUM_PATH` if
Playwright's own Chromium is not installed. The video test uses Chromium's
fake camera and microphone.

Last run (2026-09-26): both pass. The guest received the host's camera at
640×360 and their audio, data saver hid the video, and mute showed on the
host's tile.
