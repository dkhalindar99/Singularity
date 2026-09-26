# Live video/audio (WebRTC SFU) for a 2–8 person study room — iPad, Android, web

Researched 2026-09-26. Pricing pages were fetched live today unless marked otherwise. Items marked "(from memory, unverified)" were not confirmed from a fetched source in this session and should be checked before relying on them.

## Per option: SDKs on iOS / Android (Compose) / web, licence, managed pricing, free tiers, India presence

### Takeaway
LiveKit is the only option that has first-party Swift, Kotlin (with Jetpack Compose components) and JS/React SDKs, an Apache-2.0 server you can self-host, *and* a managed cloud with an India region. It is also by far the cheapest managed option per participant-minute. Cloudflare's raw SFU is cheaper still per GB, but it gives you no room/participant model on mobile unless you use RealtimeKit (still in beta, priced per minute at GA). Daily, 100ms, Agora and Zoom all cost roughly $0.002–0.004 per video participant-minute, which is 4–8× LiveKit's overage.

### Cited Findings

**LiveKit Cloud (managed)**
- Plans: Build $0/mo, Ship $50/mo, Scale $500/mo, Enterprise custom — [LiveKit pricing](https://livekit.com/pricing)
- WebRTC participant minutes: Build includes 5,000; Ship includes 150,000, then $0.0005/min; Scale includes 1.5M, then $0.0004/min — [LiveKit pricing](https://livekit.com/pricing)
- Downstream data transfer: Build includes 50 GB; Ship includes 250 GB, then $0.12/GB; Scale includes 3 TB, then $0.10/GB — [LiveKit pricing](https://livekit.com/pricing)
- Concurrent connections: Build 100, Ship 1,000, Scale 5,000 — [LiveKit pricing](https://livekit.com/pricing)
- The page lists no separate audio-only participant-minute rate. One rate applies, and bandwidth is billed separately, so audio-only is cheaper only through lower GB — [LiveKit pricing](https://livekit.com/pricing)
- India region: region pinning lists the region group codes `us`, `eu` and `india` — [LiveKit region pinning](https://docs.livekit.io/deploy/admin/regions/region-pinning/). LiveKit Cloud agents deploy to us-east, eu-central and **ap-south (Mumbai)** — [LiveKit blog: voice agents in India](https://livekit.com/blog/building-performant-voice-agents-india)
- Users connect to the closest edge by default; LiveKit recommends leaving routing on default — [LiveKit regions](https://docs.livekit.io/deploy/admin/regions/)
- Android Jetpack Compose: `livekit/components-android` provides "Jetpack Compose Components for LiveKit Android SDK" (RoomScope, VideoTrackView, rememberTracks), Apache-2.0 — [GitHub components-android](https://github.com/livekit/components-android)

**LiveKit self-hosted (open source)**
- Server licence Apache-2.0 (from memory, unverified in this session; the LiveKit GitHub repo states it). The Compose components repo is Apache-2.0 — [GitHub components-android](https://github.com/livekit/components-android)

**mediasoup**
- An SFU delivered as a Node.js module (with a Rust crate). Client libraries are mediasoup-client (JS) and libmediasoupclient (C++). It is "signaling agnostic" with a "super low level API" — [mediasoup overview](https://mediasoup.org/documentation/overview/)
- There are no official Swift or Kotlin SDKs. Mobile apps would wrap libmediasoupclient themselves or use community wrappers — [mediasoup overview](https://mediasoup.org/documentation/overview/). Licence is ISC (from memory, unverified).

**Jitsi (JVB self-hosted / 8x8 JaaS)**
- JaaS Developer tier is free for up to 25 MAU with unlimited minutes. Paid tiers are $99 for 300 MAU, $499 for 1,500 and $999 for 3,000, with $0.99 per extra MAU — [8x8 JaaS pricing](https://cpaas.8x8.com/en/pricing/jitsi-as-a-service-pricing/) (the figures come via an aggregator summary; the official page did not render in the fetch)
- Jitsi Meet and JVB are Apache-2.0. The mobile SDKs embed the whole Jitsi Meet UI (React Native based) rather than giving low-level tracks (from memory, unverified).

**Daily**
- Video: $0.0015–$0.004 per participant-minute depending on volume. Audio-only: $0.00036–$0.00099. 10,000 free minutes every month. No platform fee listed — [Daily Video SDK pricing](https://www.daily.co/pricing/video-sdk/)
- Volume discounts run from 7% (100k–500k minutes a month) to 63% (50M+) — [Daily Video SDK pricing](https://www.daily.co/pricing/video-sdk/)

**Agora**
- Per 1,000 minutes: audio $0.99, Video HD $3.99, Full HD $8.99, 2K $15.99 — [Agora docs pricing](https://docs.agora.io/en/video-calling/overview/pricing)
- The tier is set by the **aggregate resolution a user subscribes to**: HD is ≤ 921,600 px, and Full HD is 921,600–2,073,600 px — [Agora docs pricing](https://docs.agora.io/en/video-calling/overview/pricing)
- 10,000 free minutes a month on the default package; paid packages fold the free minutes into their discounts — [Agora docs pricing](https://docs.agora.io/en/video-calling/overview/pricing); marketing page: "First 10,000 combined RTC minutes free every month" — [Agora pricing](https://www.agora.io/en/pricing/)
- The SDKs are proprietary and closed-source.

**Zoom Video SDK**
- 10,000 free minutes a month; about $0.0035 per session-minute ($3.50 per 1,000). Zoom is reported to sell access through "Zoom Build Platform" credit subscriptions ($100 for 100 credits, $450 for 500) — [TRTC blog on Zoom Video SDK pricing 2026](https://trtc.io/blog/details/zoom-video-sdk-pricing-2026) (a competitor's blog; the official page returned 404, so treat this as unverified)

**100ms**
- Conferencing video $0.004 per participant-minute, audio-only $0.001. 10,000 free conferencing minutes a month — [100ms pricing](https://www.100ms.live/pricing) (via search summary)
- An India- and US-based company; no acquisition found — [TechCrunch 2022](https://techcrunch.com/2022/03/10/100ms-secures-20m-to-power-next-generation-of-live-video-apps)

**Twilio Video**
- EOL was announced for 5 Dec 2024, extended to 5 Dec 2026, then **reversed on 21 Oct 2024**: "Twilio Video will remain a standalone product" — [Twilio changelog](https://www.twilio.com/en-us/changelog/-twilio-video-will-remain-a-standalone-product); [BlogGeek.me](https://bloggeek.me/twilio-programmable-video-back/)
- Current per-minute price not fetched (see Gaps).

**Cloudflare Realtime (formerly Calls) SFU and RealtimeKit**
- Raw SFU: $0.05 per GB egress after a 1,000 GB/month free tier shared with TURN — [Cloudflare SFU pricing](https://developers.cloudflare.com/realtime/sfu/pricing) (via search summary)
- RealtimeKit (the higher-level SDK, from the Dyte acquisition): SDKs for web (React, JS, Angular), React Native, Flutter, iOS and Android. It is free during beta; at GA it will cost $0.002/min for an audio/video participant and $0.0005/min audio-only — [Cloudflare RealtimeKit pricing](https://developers.cloudflare.com/realtime/realtimekit/pricing); [Cloudflare blog](https://blog.cloudflare.com/introducing-cloudflare-realtime-and-realtimekit/)
- It runs on Cloudflare's anycast network, which has many Indian PoPs (from memory, unverified).

### Inferences
- **Cost of one 60-minute session with 5 students at 180p tiles** (300 participant-minutes; about 1.7 GB of downstream in total, see the bandwidth section):
  - LiveKit Ship overage: 300 × $0.0005 = $0.15, plus about $0.20 of bandwidth once the 250 GB included is used up. Inside the included 150k minutes and 250 GB it costs $0 above the $50/mo base.
  - Cloudflare raw SFU: about $0.08 ($0 inside 1 TB/mo).
  - RealtimeKit at GA: $0.60.
  - Daily and 100ms at list price: $1.20.
  - Agora: $1.20. Four 320×180 subscriptions total 230,400 px, which is the HD tier; audio-only would be $0.30.
  - Zoom: about $1.05.
- On every free tier (Daily, Agora, 100ms and Zoom at 10k minutes; LiveKit Build at 5k minutes and 50 GB), 5 users × 1 hour a day uses up the allowance in about 2–4 weeks.
- JaaS's per-MAU pricing ($99 for 300 MAU is $0.33 per student a month) is predictable. But its mobile SDK is a full meeting UI, which clashes with a custom ink-plus-video study room.
- The Agora model penalises showing more or larger tiles, so small tiles keep you in the HD tier.

### Gaps
- Twilio Video's 2026 price per participant-minute and its regions: not fetched.
- The official Zoom Video SDK pricing page returned 404. The Build Platform credit model comes from a competitor blog.
- Official JaaS page did not render; figures via aggregator.
- Verified lists of Indian edge PoPs (Mumbai / Chennai / Delhi) were not found for Daily, Agora, 100ms, Zoom or Cloudflare in this session. LiveKit's is confirmed only as an `india` region group plus Mumbai for agents.
- Whether mediasoup and Jitsi Compose/Swift wrappers are maintained was not checked.

## LiveKit specifics: data packets, token auth from Cloud Run + Firebase, self-hosting, simulcast/adaptive stream

### Takeaway
Ink points fit well in LiveKit data packets. Use lossy packets (≤1,300 bytes, on a topic such as `ink`) for live stroke points, and reliable packets (≤15 KiB) or text/byte streams for committed strokes. Tokens are plain JWTs a Node backend can mint after verifying a Firebase ID token, so the existing Cloud Run proxy can do it. The media server itself cannot run on Cloud Run or on a private GKE cluster: it needs host networking and open UDP ports on a public-IP VM or node.

### Cited Findings
- **Reliable** packets arrive "in order, with automatic retransmission"; **lossy** packets are "sent once, with no ordering guarantee" — [LiveKit data packets](https://docs.livekit.io/home/client/data/packets/)
- Size limits: reliable up to 15 KiB (the protocol limit is 16 KiB with headers); lossy should stay at or under 1,300 bytes to fit a 1,400-byte MTU. If one fragment of a larger lossy packet is lost, the whole packet is lost — [LiveKit data packets](https://docs.livekit.io/home/client/data/packets/)
- `topic` strings tell packet purposes apart; `destinationIdentities` targets particular participants, and leaving it empty broadcasts to the room — [LiveKit data packets](https://docs.livekit.io/home/client/data/packets/)
- Higher-level alternatives: "Data tracks" for unreliable low-latency data, and "Text streams"/"byte streams" for reliable data (chunked, so larger payloads are fine) — [LiveKit data packets](https://docs.livekit.io/home/client/data/packets/)
- Tokens are JWTs: "Generating a token requires API keys so it must be created on a backend server, sent to the frontend" — [LiveKit authentication](https://docs.livekit.io/home/get-started/authentication/). Grants (roomJoin, canPublish, canPublishData, canSubscribe), identity and TTL are set with `AccessToken` in `livekit-server-sdk` for Node (from memory; the detail page was not fetched).
- Ports: 7880/TCP for the API/WebSocket, 7881/TCP for ICE/TCP, 50000–60000/UDP for ICE (or 7882/UDP mux), TURN/UDP 3478, TURN/TLS 5349 (or 443 when there is no load balancer) — [LiveKit ports & firewall](https://docs.livekit.io/home/self-hosting/ports-firewall/)
- Kubernetes: "LiveKit pods requires direct access to the network with host networking", one pod per node, Redis for a distributed deployment, and TLS certificates for the domain and TURN/TLS. "LiveKit does not support deployment to serverless and/or private clusters. Private clusters have additional layers of NAT that make it unsuitable for WebRTC traffic." The Helm chart configures TLS for GKE — [LiveKit Kubernetes](https://docs.livekit.io/home/self-hosting/kubernetes/)
- Simulcast "is enabled by default in all LiveKit SDKs"; Dynacast "automatically pauses video layer publications when they aren't being consumed" — [LiveKit advanced tracks](https://docs.livekit.io/home/client/tracks/advanced/)
- Presets in the JS SDK:
  - Video: h90 160×90 at 90 kbps, h180 320×180 at 160 kbps / 20 fps, h216 384×216 at 180 kbps, h360 640×360 at 450 kbps / 20 fps, h540 960×540 at 800 kbps, h720 1280×720 at 1.7 Mbps / 30 fps.
  - Audio: telephone 12 kbps, speech 24 kbps, music 48 kbps.
  - Default simulcast layers are h180 and h360 — [client-sdk-js options.ts](https://raw.githubusercontent.com/livekit/client-sdk-js/main/src/room/track/options.ts)
- GCP has two India regions, asia-south1 (Mumbai) and asia-south2 (Delhi) — [CloudZero GCP regions](https://www.cloudzero.com/blog/gcp-regions/)
- GCP internet egress: Premium tier starts at about $0.12/GiB and Standard tier at about $0.085/GiB (for US source regions). Some destinations are $0.19/GiB — [search summary citing GCP Network Tiers pricing](https://cloud.google.com/network-tiers/pricing). The asia-south1-specific table could not be extracted (see Gaps).

### Inferences
- Firebase-gated join flow:
  1. The app calls the existing Cloud Run proxy (`/room-token`) with its Firebase ID token.
  2. The proxy verifies the token as it already does, checks the user is a member of the study room, and mints a LiveKit JWT (identity = pseudonymous uid, room = study-room id, TTL of a few minutes to join).
  3. The API secret lives in Secret Manager like the other keys.
- This fits the proxy's existing pattern. Only signalling-free token minting runs on Cloud Run; media goes directly to LiveKit Cloud or a self-hosted VM.
- Ink over data:
  - A pen sample of x, y, pressure and t is about 8–16 bytes when packed, so batching every 16–33 ms keeps lossy packets far below 1,300 bytes.
  - Send a reliable "stroke committed" message with the full `PortableStroke` JSON (or a byte stream if it exceeds 15 KiB) so late or lossy receivers converge.
  - This matches the NotebookCore portable model, which already crosses platforms.
- Self-host on GCP:
  - Start with one Compute Engine VM in asia-south1 with a public IP and firewall rules for the ports above, running `livekit-server` with its embedded TURN. A small instance should handle a few 2–8 person rooms (sizing not verified).
  - GKE is possible only as a public cluster with host networking.
  - The dominant running cost is egress. 1.7 GB per session-hour at about $0.12/GiB is about $0.20, close to LiveKit Cloud's $0.12/GB overage, so self-hosting saves little until the $50 Ship base or scale matters.
  - Hetzner or OVH-style VMs with cheap bandwidth are the usual cost play, but none were checked for India latency.
- Adaptive stream (a client option, from memory): subscribers request only the layer that fits the rendered tile size and pause hidden tiles. Combined with Dynacast, a publisher whose viewers all show small tiles sends only its h180 layer.

### Gaps
- The exact per-GiB internet egress price from asia-south1 (Premium vs Standard) was not extractable; the page truncated. Check the table before costing a self-host.
- The LiveKit "Tokens & grants" detail page was not fetched. The grant names come from memory.
- The LiveKit self-hosting VM sizing and benchmark page (participants per core) was not fetched.
- There was no primary confirmation of LiveKit Cloud *media* edges in Chennai or Delhi, only an `india` region group and Mumbai.

## Bandwidth per participant (4–6 people, small tiles) and keeping mobile data low in India

### Takeaway
At 180p tiles, each student in a 5-person room downloads about 0.75 Mbps, roughly 330 MB an hour, and uploads about 0.2 Mbps once Dynacast drops the unused 360p layer. Audio-only is about 0.1 Mbps down, roughly 45–60 MB an hour. So audio-first with the camera off by default cuts mobile data about 6–7×.

### Cited Findings
- h180 = 160 kbps, h360 = 450 kbps, speech audio = 24 kbps, and the default simulcast layers are h180 + h360 — [client-sdk-js options.ts](https://raw.githubusercontent.com/livekit/client-sdk-js/main/src/room/track/options.ts)
- Dynacast pauses layers nobody is consuming — [LiveKit advanced tracks](https://docs.livekit.io/home/client/tracks/advanced/)
- Agora bills by the total subscribed resolution, so fewer or smaller tiles also lower cost there — [Agora docs pricing](https://docs.agora.io/en/video-calling/overview/pricing)

### Inferences
Arithmetic from the presets, excluding RTP/ICE overhead of roughly 10–20%.

| | Download | Upload | Per hour |
|---|---|---|---|
| 5 people, video | 4 × 160 + 4 × 24 ≈ 736 kbps | 160 + 24 ≈ 184 kbps with Dynacast (≈ 634 kbps if h360 is also sent) | ≈ 330 MB down |
| 6 people, video | ≈ 920 kbps | same as 5 people | ≈ 414 MB |
| 5 people, audio only | ≈ 96 kbps | ≈ 24 kbps | ≈ 43 MB down |

Recommended defaults:
- Camera off, mic on push-to-talk or muted.
- Publish a single h180 layer, or h180+h360 with Dynacast.
- Adaptive stream on.
- Subscribe to video only for tiles on screen, and to the speaker's tile at 360p at most.
- A "data saver" toggle that turns off video subscription.
- Ink over data packets costs almost nothing next to video (a few kbps).
- Screen-share of a notebook page is unnecessary, because ink goes as vector points.

## Recommended choice for a small team: closed-source commercial app, lowest cost, path to self-host

### Takeaway
LiveKit. Start on LiveKit Cloud (the free Build plan for development, Ship at $50/mo when live, with the India region pinned). Mint tokens from the existing Firebase-verified Cloud Run proxy. Send ink as LiveKit data packets. Self-host the Apache-2.0 server on a public Compute Engine VM in asia-south1 later, with no app changes beyond the URL. Apache-2.0 allows a closed-source commercial app. The CLAUDE.md rules out AGPL for the canvas; this avoids the same trap.

### Cited Findings
- It is the only option here with first-party iOS, Android (with Compose components) and web SDKs plus both managed and self-host paths — [GitHub components-android](https://github.com/livekit/components-android); [LiveKit Kubernetes](https://docs.livekit.io/home/self-hosting/kubernetes/)
- It has the lowest managed per-minute rate found ($0.0005/min on Ship, $0.0004 on Scale) against $0.002–0.004 for RealtimeKit, Daily, 100ms, Agora and Zoom — [LiveKit pricing](https://livekit.com/pricing); [Daily](https://www.daily.co/pricing/video-sdk/); [Agora](https://docs.agora.io/en/video-calling/overview/pricing); [RealtimeKit](https://developers.cloudflare.com/realtime/realtimekit/pricing)
- Its India region group exists — [LiveKit region pinning](https://docs.livekit.io/deploy/admin/regions/region-pinning/)

### Inferences
- Runner-up is **Cloudflare**:
  - The raw SFU is cheapest ($0.05/GB after 1 TB free).
  - But using it means building your own room and signalling layer on three platforms, or taking RealtimeKit. That is in beta and will be $0.002/min at GA, 4× LiveKit, with no self-host path.
- **Avoid for this use case:**
  - mediasoup: no official mobile SDKs, and a lot of engineering for a small team.
  - Jitsi JaaS: a whole-meeting UI, which clashes with custom ink tiles.
  - Agora and Zoom: proprietary, several times the price, and no self-host.
- Twilio Video is alive again but carries history risk.
- 100ms is India-based, but costs 8× LiveKit per minute.
- Pricing risk: all vendor prices are as fetched on 2026-09-26. LiveKit's lack of a separate audio-only rate means audio savings come only from bandwidth.

### Gaps
- There was no independent India latency benchmark comparing these vendors.
- There was no maintained public benchmark of LiveKit participants per vCPU for sizing a self-host VM.
