# Trying SpaceNotes Live yourself

Three levels, easiest first. Each one needs only the one before it to work.
Everything below runs on your Mac; nothing is put online until Level 3.

## Level 1 — two browser windows on your Mac (about 5 minutes)

What it shows: shared ink appearing while it is drawn, text, the laser,
following the host, locking, undo, and ending the room.

1. Open Terminal and go to the repository:
   `cd ~/Documents/Singularity` (or wherever you cloned it).
2. Start the room server: `cd server && npm run dev`.
   (It needs Node 22; it prints the addresses it is listening on.)
3. Open **http://localhost:8080** in Safari or Chrome. Type your name and
   press **Start room**. Note the six-letter code at the top.
4. Open a **private window** (so it counts as a second person), go to the same
   address, type another name, and join with the code.
5. Put the two windows side by side and try the checklist below.

Voice on Level 1 needs a local LiveKit server; see "Adding voice" below.

## Level 2 — real iPad and Android tablet on your home Wi-Fi

What it adds: real Apple Pencil and stylus feel, palm rejection, real
touch screens, and (with voice) real microphones and speakers.

1. Keep the server from Level 1 running. It prints a line such as
   `http://192.168.1.23:8080` — that is your Mac's address on the Wi-Fi.
2. **iPad:** build and install the demo app from Xcode. The steps are in
   `ios/README.md`, "How to try it on your iPad". In the app, type the
   address from step 1 and your name.
3. **Android:** install the demo app. The steps are in `android/README.md`,
   "How to try it on your Android tablet". Every CI run also keeps a ready
   APK: open the latest run under the repository's Actions tab and download
   `SpaceNotesLiveDemo-debug-apk`. Type the same address.
4. A browser on a phone also works for ink: open the same address. (Phone
   browsers only allow the microphone on secure https pages, so for voice on
   Level 2 use the demo apps or the Mac's own browser.)
5. Start a room on one device, join from the others, and go through the
   checklist.

All devices must be on the same Wi-Fi as the Mac. If a device cannot
connect, check that the Mac's firewall allows Node to accept connections
(System Settings › Network › Firewall).

### Adding voice (Level 1 or 2)

1. Download `livekit-server` for macOS from LiveKit's GitHub releases page
   (github.com/livekit/livekit/releases, the `darwin_arm64` file for an
   Apple-silicon Mac) and unpack it.
2. Run it with your Mac's Wi-Fi address (the one the room server prints):
   `./livekit-server --dev --bind 0.0.0.0 --node-ip 192.168.1.23`
   (developer mode: its keys are `devkey` and `secret`). Without
   `--node-ip`, tablets are told to reach voice at their own address and
   stay silent.
3. Stop the room server (Ctrl-C) and start it again with voice:
   ```sh
   LIVEKIT_URL=ws://192.168.1.23:7880 LIVEKIT_API_KEY=devkey \
   LIVEKIT_API_SECRET=secret npm run dev
   ```
   using your Mac's address from the server's printout.

## Level 3 — friends over the internet

This needs the room server online (Google Cloud Run in Mumbai, with
`server/scripts/deploy-gcp.sh`) and a LiveKit Cloud project in the India
region. Both create accounts and small bills, so it waits for your
go-ahead. When it is online, friends use the same demo apps (with the online
address) or simply open the web link in a browser, with real sign-in.

## The checklist

Write down anything that feels slow, wrong or confusing — that is the point
of testing. Note the device for each.

**Ink**
- [ ] A line appears on the other screens *while* it is being drawn.
- [ ] How long does it feel behind? (Unnoticeable / slight / annoying.)
- [ ] Lines look smooth, with no corners where there should be curves.
- [ ] Apple Pencil pressure changes the thickness; the palm does not draw.
- [ ] Highlighter, eraser, text box, move, laser all work across devices.
- [ ] Undo removes only your own writing, never a friend's.

**The room**
- [ ] Joining by code works; the invite link opens the join screen.
- [ ] "Follow host" moves you with the host's page; turning a page yourself
      stops following; the chip brings you back.
- [ ] The host's "Only me" and "One person at a time" really stop others.
- [ ] Removing someone and ending the room work.
- [ ] Turn Wi-Fi off on one device for 20 seconds, write something, turn it
      back on: the writing arrives once, and nothing is lost.

**Voice** (if set up)
- [ ] Everyone hears everyone; no echo with speakers (try with and without
      earphones).
- [ ] Mute shows on your tile for everyone; the green ring follows who speaks.
- [ ] Put the app in the background for over 2 minutes: voice leaves, and
      comes back when you return.

**Comfort**
- [ ] Text is readable, buttons are easy to hit, nothing is cut off on the
      smallest device.
- [ ] Battery and heat after 30 minutes on a tablet.

## After testing

Send the notes back (a photo of the ticked list is fine). Problems found on
real devices are expected at this stage; each one becomes a small fix.
