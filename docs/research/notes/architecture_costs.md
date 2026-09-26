# Study Room: backend architecture and running costs (as of 26 Sep 2026)

Exchange rate used throughout: **US$1 = ₹96**. A search snippet reported ₹95.99 on 26 Sep 2026, with a week's range of ₹95.54–96.07 ([search result citing Fed H.10 / Wise pages](https://www.federalreserve.gov/releases/h10/hist/dat00_in.htm)). I could not confirm this against a primary table because the Fed page returned only historical rows, so treat it as approximate.

Traffic assumptions used in the maths. These are my assumptions, not sourced facts.
- **Ink:** a drawer sends point batches at 20 Hz, about 400 bytes of JSON each, so about 8 KB/s per active drawer. Each batch goes out to the other 5 people.
- **Video:** the 360p simulcast layer runs at about 450 kbps.
- **Audio:** Opus runs at about 32 kbps.
- **Room:** 6 people. Each subscribes to 5 remote video tracks and 5 audio tracks.

## Q1. Transport for ink ops: Cloud Run WebSockets vs LiveKit data vs Firestore/RTDB vs Durable Objects

### Takeaway
The cheapest good option is **one small Cloud Run WebSocket service with rooms pinned to an instance**. It can hold about 160 six-person rooms per instance and costs well under ₹0.1 per room-hour. You need either `max-instances=1` or Redis pub/sub to fan messages out once rooms spread across instances. Cloudflare Durable Objects fits the "one object per room" model better and costs about the same, but it moves the service off GCP. Streaming ink through Firestore works out 500–1000× more expensive and runs into Firestore's write limits (see Q2).

### Cited Findings
**Cloud Run WebSockets**
- A WebSocket stream is an HTTP request, so it is subject to the request timeout. The default is 5 minutes and the maximum is **60 minutes**, so clients must reconnect at least hourly — [Cloud Run WebSockets docs](https://docs.cloud.google.com/run/docs/triggering/websockets)
- Session affinity is "best effort": "new WebSockets requests could still potentially connect to different instances". Google therefore says clients must be synchronised across instances and recommends **Redis Pub/Sub on Memorystore** or **Firestore real-time updates** — [Cloud Run WebSockets docs](https://docs.cloud.google.com/run/docs/triggering/websockets)
- The concurrency limit is **up to 1,000 concurrent connections per container**, and Google advises raising max concurrency for WebSocket services — [Cloud Run WebSockets docs](https://docs.cloud.google.com/run/docs/triggering/websockets)
- "A Cloud Run instance that has any open WebSocket connection is considered active… billed as instance-based billing", so an idle socket still costs money — [Cloud Run WebSockets docs](https://docs.cloud.google.com/run/docs/triggering/websockets)
- Do not enable end-to-end HTTP/2, because it is incompatible with WebSocket streaming — [Cloud Run WebSockets docs](https://docs.cloud.google.com/run/docs/triggering/websockets)
- Rates as of June 2026 (Tier-1 regions such as us-central1):
  - Instance-based billing: **$0.018 per 1k vCPU-s** and **$0.002 per 1k GiB-s**.
  - Request-based billing: $0.024 per 1k vCPU-s and $0.0025 per 1k GiB-s.
  - Instance-based free tier: 240k vCPU-s and 450k GiB-s a month.
  - Worker pools: $0.0112 per 1k vCPU-s.
  - Source: [preprice.app Cloud Run rates, verified 14 Jun 2026](https://preprice.app/ai-costs/gcp_cloud_run). The official page ([cloud.google.com/run/pricing](https://cloud.google.com/run/pricing)) would not render in full.
- Tier-2 regions, which include Asian regions, cost more than Tier 1 — [cloudchipr](https://cloudchipr.com/blog/cloud-run-pricing). I found no exact asia-south1 multiplier.

**LiveKit (as the ink carrier)**
- Scaling is "bound by CPU and bandwidth".
- Redis is recommended for multi-node production.
- Required ports: 7880 (signalling), 7881/TCP, UDP 50000–60000, and TURN on 443/5349.
- Source: [LiveKit deployment docs](https://docs.livekit.io/home/self-hosting/deployment/)

**Firestore and Realtime Database (RTDB)**
- Firestore's sustained write rate is **1 write/s per document**. Short bursts are queued, but a sustained excess causes contention errors. The fix is to spread writes across documents in a collection — [Firebase best practices](https://firebase.google.com/docs/firestore/best-practices); [Understand reads/writes at scale](https://firebase.google.com/docs/firestore/understand-reads-writes-scale)
- Firestore Standard charges **$0.18 per 100k writes** — [search summary of cloud.google.com/firestore/pricing](https://cloud.google.com/firestore/pricing). **$0.06 per 100k reads** was reported by a page fetch that I could not confirm verbatim. There is a daily free tier of 50k reads and 20k writes — [Firebase pricing](https://firebase.google.com/pricing)
- RTDB on Blaze:
  - **200k simultaneous connections per database.**
  - Storage costs **$5/GB-month**, and downloads cost **$1/GB** after a free 10 GB/month — [Firebase RTDB billing](https://firebase.google.com/docs/database/usage/billing); [back4app summary](https://blog.back4app.com/firebase-pricing/)
  - Download billing includes protocol, WebSocket and HTTP overhead, plus about **3.5 KB of TLS handshake per connection** and "tens of bytes" per outgoing message — [RTDB billing docs](https://firebase.google.com/docs/database/usage/billing)

**Cloudflare Durable Objects**
- Requests cost **$0.15 per million** after 1M/month. WebSocket messages count as requests, but **incoming messages are billed at 20:1**.
- Duration costs **$12.50 per million GB-s** after 400k GB-s. Every object is billed as 128 MB of wall-clock time unless it is hibernating.
- SQLite storage: row writes cost $1 per million after 50M, and storage costs $0.20/GB-month. Storage billing started in January 2026.
- Source: [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/)

### Inferences
- **A single instance for hundreds of rooms:**
  - Connection limit: 1,000 connections ÷ 6 people = **~166 rooms per instance**.
  - Bandwidth: 100 rooms with one drawer each is about 100 × 8 KB/s in plus 40 KB/s out, roughly 4.8 MB/s out. That fits on 1 vCPU with binary encoding, but plain JSON will be CPU-bound. This is an estimate; benchmark it.
  - So "hundreds of rooms" needs 2–3 instances, which brings in the cross-instance problem.
- **Cloud Run cost:** 1 vCPU and 0.5 GiB on instance billing is 3600 × (0.000018 + 0.5 × 0.000002) = **$0.068/hour, about ₹6.6/hour**. Running always on (min-instances=1) costs about $50/month (₹4,800) in us-central1, and more in asia-south1.
  - With 100 rooms live: **~$0.0007 (₹0.07) per room-hour** for compute.
  - Ink egress, if one person draws the whole hour: 8 KB/s × 5 × 3600 ≈ 144 MB, which is about $0.017 per room-hour at $0.12/GB. At a realistic 25% drawing time it is about $0.004. Binary or delta encoding cuts it by a further 3–5×.
- **Fanning out across instances, three options:**
  1. `max-instances=1` with room state in memory. This is simplest, but there is no redundancy and it is capped at about 160 rooms.
  2. Any instance, with Memorystore Redis pub/sub per room channel. This is Google's recommended pattern, but adds a fixed Memorystore bill (price not verified).
  3. Durable-Object-style routing: a lightweight lookup maps roomId to an owning instance, and clients connect there.
     - Cloud Run cannot address a specific instance, and affinity is only best effort.
     - This option therefore needs GKE, or a Compute Engine (GCE) VM, or Cloudflare Durable Objects itself.
- **The 60-minute cap:** the protocol must support resuming. On reconnect the client sends `lastSeq`, and the server replays the ops after it from memory or GCS. Build this in from day one.
- **Durable Objects per room-hour:**
  - Requests: 6 people × 20 Hz × 3600 s × 25% duty ≈ 108k incoming messages, which bills as 5.4k requests, about $0.0008.
  - Duration: 0.125 GB × 3600 s = 450 GB-s, about $0.0056.
  - Total **≈ $0.006 (₹0.6) per room-hour**, plus the Workers paid-plan base fee (not verified here).
  - Firebase ID tokens can be checked in the Worker against Google's JWKS.
  - Downside: a second cloud vendor and a separate place to keep secrets.
- **LiveKit data channels only:**
  - Upside: no ink server at all, and ink shares the transport already paid for with the video.
  - Downsides:
    - no authoritative sequence numbers or op log;
    - no persistence for people who join late;
    - host "lock drawing" cannot be enforced on the server unless a server-side participant (an agent or bot) relays the ink.
  - This suits cursors and laser pointers, which are fine to lose. It does not suit the source-of-truth ink log.

### Gaps
- The official Cloud Run price for asia-south1 (Tier 2) was not retrieved, and neither was the idle min-instance rate.
- Memorystore for Redis prices for the smallest Basic instance were not retrieved.
- Whether LiveKit Cloud charges separately for data packets was not listed on the pricing page.
- I found no published benchmark for ink fan-out throughput on Cloud Run.

## Q2. Firestore/RTDB if every stroke-point batch were a write (the maths), plus op-log persistence and late joiners

### Takeaway
Writing every point batch to Firestore costs about **₹12–50 per room-hour**, depending on how often batches are sent, against about ₹0.1 for a WebSocket relay. It also breaks the 1 write/s-per-document limit unless every batch becomes a new document. **Disproved** as the ink transport. RTDB is cheaper, because it bills bandwidth rather than operations (about ₹1.4–14 per room-hour), but it is still 10–100× the relay. Keep Firestore for room metadata only. Keep the op log in server memory, flushed to GCS as segments plus snapshots.

### Cited Findings
- Firestore charges $0.18 per 100k writes and $0.06 per 100k reads, with a sustained limit of 1 write/s per document — [Firestore pricing](https://cloud.google.com/firestore/pricing); [best practices](https://firebase.google.com/docs/firestore/best-practices)
- RTDB charges $1/GB downloaded (including protocol and TLS overhead) and $5/GB-month stored — [RTDB billing](https://firebase.google.com/docs/database/usage/billing)
- Google itself names Firestore real-time updates as one way to sync WebSocket instances — [Cloud Run WebSockets docs](https://docs.cloud.google.com/run/docs/triggering/websockets)

### Inferences (the maths)
**Firestore, one active drawer at 20 Hz**
- Writes: 72,000 per hour × $0.18/100k = **$0.130**.
- Reads: each of the 5 listeners reads each document, 360,000 per hour × $0.06/100k = **$0.216**.
- Total **$0.35 per drawer-hour (₹33)**.
- Six people each drawing 25% of the time is 1.5 drawer-hours per room-hour, which comes to **$0.52 per room-hour (₹50)**.

**Batching at 5 Hz instead**
- This costs **$0.13 per room-hour (₹12.5)**.
- Latency rises to 200 ms or more before Firestore's own delay.

**Firestore at scale**
- At 10,000 students × 5 hours in rooms of 6, there are about 8,300 room-hours a month.
- The cost is **$1,080–4,300 a month (₹1.0–4.1 lakh) for ink alone**.

**RTDB**
- 144 MB per drawer-hour of fan-out at $1/GB is $0.144 per drawer-hour.
- At 1.5 drawer-hours per room-hour that is about **$0.22 (₹21) per room-hour** in JSON.
- With binary or delta encoding, or 25% duty, it drops to about $0.015–0.05 (₹1.4–5).
- Storing the whole op log in RTDB costs $5/GB-month, 250× GCS Standard storage.

**Recommended persistence**
- **Hot:** the room's op log lives in memory on the room's owning instance (or Durable Object), with monotonic `seq` numbers.
- **Warm:** every N ops (for example 500) or every 30 s, append a compressed segment to GCS at `rooms/{id}/ops/{seqStart}.ndjson.gz`.
- **Snapshot:** every M ops, write a full page state to `snap/{seq}.json`, in the same portable JSON format NotebookCore already uses (`PortablePage`). Commit to the host's notebook when the room closes.
- **Late joiner:**
  1. The client asks to join.
  2. The server sends the latest snapshot `seq`, plus the ops after it from memory.
  3. If the snapshot is large, the server returns a short-lived GCS signed URL. The proxy already issues V4 signed URLs for backups.
- **Firestore** holds the room document only: host, code, state, participant list and lock flags. That is a few writes per room, so negligible.

### Gaps
- The Firestore read price and the asia-south1 regional multiplier were not verified verbatim, because the fetch of the official pricing page was unreliable.
- RTDB regional availability in India (asia-south1) was not checked.
- GCS operation prices (Class A/B) were not retrieved. At one segment every 30 s they are expected to be negligible.

## Q3. Video/audio: LiveKit Cloud vs self-hosted LiveKit on a GCE VM in asia-south1

### Takeaway
LiveKit Cloud's per-minute charge (**$0.0004–0.0005 per participant-minute, ₹2.3–2.9 per participant-hour**) is small. For video rooms, **downstream bandwidth dominates** the cost on both LiveKit Cloud Scale ($0.10/GB beyond 3 TB) and GCP egress (Asia premium $0.12 → $0.085/GB). A 6-person 360p room pulls about 1 GB per participant-hour, which is about ₹8–11 per participant-hour. Audio-only is about ₹0.8 in bandwidth. Self-hosting saves only around 15–20% on video at 10k MAU, and adds an operations burden.

### Cited Findings
- **LiveKit Cloud plans:**
  - Build: $0, 1,000 WebRTC minutes, 5 concurrent connections.
  - **Ship: $50/month**, 150,000 minutes, 1,000 concurrent connections, then **$0.0005/min**.
  - **Scale: $500/month**, 1.5M minutes, 5,000 concurrent, then **$0.0004/min**, with **3 TB of downstream data included, then $0.10/GB**.
  - Source: [LiveKit pricing](https://livekit.com/pricing)
- LiveKit benchmark on a GCP **c2-standard-16**:
  - A 720p meeting with **150 publishers and 150 subscribers** ran at 85% CPU, using 50 MB/s in and 93 MB/s out.
  - Audio only, with 10 publishers and 3,000 subscribers, ran at 80% CPU.
  - Source: [LiveKit benchmark docs](https://docs.livekit.io/transport/self-hosting/benchmark/)
- An SFU forwards rather than mixes, so load scales with subscribed tracks: about N × (N−1) video plus N × (N−1) audio — [search summary of LiveKit self-hosting guide](https://fazliev.com/blog/livekit-production-guide)
- **GCP premium-tier internet egress to Asia** (excluding Indonesia and Korea): **$0.12/GiB for 0–1 TiB, $0.11 for 1–10 TiB, $0.085 above 10 TiB** — [search summary of network-tiers pricing](https://cloud.google.com/network-tiers/pricing)
  - The North America figures are the same except for $0.08 above 10 TB. Standard tier is $0.085/GB for the first 10 TB (North America) — [egresscost.com](https://egresscost.com/gcp/)
  - Peering rates rose on 1 May 2026; standard internet egress did not change — [egresscost.com](https://egresscost.com/gcp/)
- LiveKit recommends compute-optimised instances and host networking — [LiveKit deployment](https://docs.livekit.io/home/self-hosting/deployment/)

### Inferences
**Bandwidth per participant-hour in a 6-person room**
- Video: 5 × 450 kbps = 2.25 Mbps, which is **~1.0 GB per hour**.
  - With adaptive stream on small tiles (the 180p layer, about 150 kbps) it is about 0.34 GB.
- Audio-only: 5 × 32 kbps is **~0.07 GB per hour**.

**Server size**
- The benchmark handled 22,500 video subscriptions on 16 cores, about 1,400 per core.
- A 6-person room has 30 video subscriptions, so one 4-vCPU VM should carry around 150 rooms (900 people).
- Compute is therefore minor when the VM is well used. It becomes the main cost when the VM is idle: an always-on VM of about $150/month (not verified) serves few hours at 1k MAU.

**LiveKit Cloud per participant-hour**
- Minutes: 60 × $0.0005 = $0.03 (₹2.9) on Ship, or $0.024 (₹2.3) on Scale.
- Bandwidth on Scale: video about 1 GB × $0.10 = $0.10 (₹9.6); audio about $0.007 (₹0.7).

**Self-hosted per participant-hour**
- Egress for video: 1 GB × $0.085–0.12 = **₹8–11.5**.
- Egress for audio: ₹0.7–0.8.
- Plus the VM and a TURN server.
- Plus Cloud NAT or a static IP, which is small.

### Gaps
- Whether the **Ship plan** bills bandwidth, and at what rate, is not shown on the pricing page. I assumed $0.10/GB like Scale; confirm with LiveKit.
- Whether audio-only minutes are priced lower is not shown either. The page lists only "WebRTC minutes", so I assumed the same rate.
- GCE c2 and c2d VM prices in asia-south1 were not retrieved.
- LiveKit's exact 360p simulcast bitrate was not verified; 450 kbps is an assumption.

## Q4. Cost per student-hour in INR, and totals for 1,000 and 10,000 MAU (5 hours each per month)

### Takeaway
- **Audio-only plus shared ink: about ₹2.5–3.5 per student-hour.**
  - 1k MAU: about ₹18k a month.
  - 10k MAU: about ₹1.2 lakh a month.
- **360p video plus ink: about ₹11–14 per student-hour.**
  - 1k MAU: about ₹66–75k a month.
  - 10k MAU: about ₹4.8–5.7 lakh a month.
- Ink sync is a rounding error, under ₹0.5 per student-hour at scale. Video bandwidth is the whole story.
- Against a ₹499 subscription, 5 hours of video costs ₹55–70 per student a month; audio-only costs about ₹15.

### Cited Findings
- All unit prices are cited in Q1–Q3: LiveKit plans ([pricing](https://livekit.com/pricing)), GCP egress ([network tiers](https://cloud.google.com/network-tiers/pricing)) and Cloud Run rates ([preprice.app](https://preprice.app/ai-costs/gcp_cloud_run)).

### Inferences (worked estimates, ₹96/$)
The two scales:
- 1,000 MAU = 5,000 student-hours = 300k participant-minutes.
- 10,000 MAU = 50,000 student-hours = 3M participant-minutes.

| Scenario | Media | Ink (Cloud Run, min-inst=1) | Total $/month | ₹/month | ₹/student-hour |
|---|---|---|---|---|---|
| 1k MAU, audio, LiveKit Ship | $50 + 150k × $0.0005 = $125; bandwidth 0.35 TB ≈ $35 (if billed) | ~$55 | ~$215 | ~₹20,600 | ~₹4.1 |
| 1k MAU, video 360p, LiveKit Ship | $125 + 5 TB × $0.10 ≈ $625 | ~$55 | ~$805 | ~₹77,000 | ~₹15 |
| 1k MAU, video, self-hosted asia-south1 | Egress: 1 TB × 0.12 + 4 TB × 0.11 = $560; VM + TURN ~$150–200 | ~$55 | ~$790 | ~₹76,000 | ~₹15 |
| 10k MAU, audio, LiveKit Scale | $500 + 1.5M × $0.0004 = $1,100; 3.5 TB, of which 0.5 TB is over the 3 TB included = $50 | ~$80 | ~$1,230 | ~₹1.18 lakh | ~₹2.4 |
| 10k MAU, video 360p, LiveKit Scale | $1,100 + 47 TB × $0.10 = $5,800 | ~$80 | ~$5,880 | ~₹5.6 lakh | ~₹11.3 |
| 10k MAU, video, self-hosted | Egress: $120 + $990 + 40 TB × $0.085 = $4,510; 2–3 VMs ~$400 | ~$80 | ~$5,000 | ~₹4.8 lakh | ~₹9.6 |
| 10k MAU, video, adaptive 180p tiles | 50,000 × 0.34 GB = 17 TB; on Scale, $1,100 + $1,400 | ~$80 | ~$2,580 | ~₹2.5 lakh | ~₹5 |

- **Per room-hour of ink** is ₹0.07–0.6 (Cloud Run or Durable Objects). **Per room-hour of Firestore ink** would be ₹12–50, more than the video.
- **Levers, in order of size:**
  1. Audio-first, with video opt-in.
  2. Adaptive stream and dynacast, sending small tiles at 180p.
  3. A cap on video subscriptions, such as showing only the active speaker plus 2 others.
  4. Self-hosting once past about 10 TB a month.
  5. Standard-tier egress, whose Asia price I did not verify.
- **Ink server at 1k MAU:** keep it on Cloud Run, where min-instances=1 costs about ₹5k a month. Alternatively, fold ink into the existing `gemini-proxy` service if its concurrency and timeout can be raised. That is not recommended, because long-lived sockets would pin that service's instances.

### Gaps
- The totals depend on four unverified inputs:
  - Ship-plan bandwidth pricing;
  - the asia-south1 Cloud Run and VM rates;
  - real 360p bitrates on Indian mobile networks;
  - actual camera-on and drawing duty cycles.
- Validate with a `lk load-test` run and a week of beta telemetry.

## Q5. Joining, permissions, security, privacy (DPDP) and packaging

### Takeaway
- **Security and joining:** use server-issued short codes and HTTPS join links that open the app through Universal Links and App Links. Every socket carries a Firebase ID token. The host's powers (lock drawing, remove a participant) are enforced by the room server, not the client.
- **DPDP:** the DPDP Rules were notified on 13 Nov 2025. Their consent and children's-data duties apply from **13 May 2027**. Anyone under 18 is a "child" and needs verifiable parental consent, which matters for NEET aspirants aged 17. Recording needs explicit, per-session consent from every participant.
- **Packaging:** ship one protocol spec plus JSON fixtures, tested by a Swift Package, an Android library (AAR) and an npm package. This mirrors `fixtures/notebook-format/`.

### Cited Findings
- The DPDP Rules 2025 were notified on **13 November 2025**. Rules 3 and 5–16 (including Rule 10, verifiable parental consent) come into force 18 months later, on **13 May 2027** — [dpdprules.org Rule 10](https://dpdprules.org/rules/10); [Xident](https://xident.io/blog/india-dpdp-age-verification-verifiable-parental-consent-childrens-data-2026/)
- The Act defines a child as **under 18**. Rule 10 requires verifiable consent from a parent, with due diligence on the parent's identity and age. This uses details the fiduciary already holds, or virtual tokens from government-authorised providers such as **DigiLocker** — [dpdpa.com Rule 10](https://www.dpdpa.com/dpdparules/rule10.html); [Seclore](https://www.seclore.com/fundamentals/dpdp-rules-2025-compliance-guide/)
- EdTech is named as a sector with heavy exposure to the parental-consent rules — [Consently](https://www.consently.in/blog/verifiable-parental-consent-dpdp-rules-2025-edtech-gaming)

### Inferences (design recommendations; not individually sourced)
**Join links and short codes**
- `POST /rooms` (Firebase-gated) creates a room document and returns:
  - a 6-character code from an unambiguous alphabet (no 0/O/1/I), with a 12–24 hour lifetime;
  - an HTTPS link, for example `https://<domain>/r/<code>`.
- The same domain serves three things:
  - `apple-app-site-association`, for iOS Universal Links;
  - `assetlinks.json`, for Android App Links;
  - a web fallback that runs the npm client in the browser.
- Codes are about 30 bits. Rate-limit code lookups per IP and per account to stop enumeration. The proxy already has per-account and per-IP rate limits to reuse.

**Guests**
- Use Firebase anonymous auth, which is already enabled on the project, so every socket still carries an ID token.
- The host sets whether guests are allowed.
- Guests get a display name only. Their notebook data is never saved to their account.

**Host permissions**
- The server holds the room's access list, and every op is checked against role and lock state before it is fanned out.
  - Messages: `lock(pages|all)`, `grant(uid)`, `remove(uid)`, `end`.
- "Remove" closes the socket and adds the uid to a deny list for the room.
- LiveKit tokens are minted server-side with matching grants (`canPublish`, `canPublishData`). Removing someone means calling LiveKit's RemoveParticipant and revoking the token.

**Rate limits**
- Per socket, cap ops per second (for example 60 batches/s), bytes per second and page count.
- Drop and disconnect anyone who goes over.
- Log usage per room in the existing `usageLog` style.

**Encryption**
- WebRTC media is always encrypted in transit (DTLS-SRTP), but the SFU can read it. LiveKit supports end-to-end encryption (E2EE) with insertable streams on its SDKs. Browser and SDK coverage was not verified in this session.
- True E2EE of ink would stop the server from enforcing locks and building snapshots. Recommendation: TLS plus encryption at rest in GCS, and no E2EE on ink.

**Recording**
- Off by default.
- Only the host can start it, and every participant sees a banner and must accept or leave.
- Consent is stored per participant, and recordings are kept for a limited time.
- Under DPDP, treat anyone under 18 as needing parental consent from May 2027, and avoid tracking or behavioural monitoring of children.
- Most MBBS students are adults, but the NEET PG and B.Sc courses offered in the app, and school-age TeachDraw audiences, may include minors. Collect age at signup.

**Data residency**
- Run the room server, the GCS bucket (asia-south1, like the backup bucket) and the LiveKit service in India, which also minimises latency.

**Packaging as a plugin**
- `spec/study-room-protocol.md` plus `fixtures/study-room/*.json` (versioned envelopes: `join`, `op`, `ack`, `snapshot`, `lock`, `presence`), with a `protocolVersion` field.
- Swift Package `StudyRoomKit`: Foundation plus URLSessionWebSocketTask, and LiveKit's Swift SDK as a dependency, as a separate product so the host can drop video.
- Android library module `:studyroom`, published as an AAR via Gradle or Maven, using OkHttp WebSocket plus the LiveKit Android SDK.
- npm `@spacenotes/study-room`, in TypeScript, using the browser WebSocket plus livekit-client.
- The server is a Node 20 package in the same repo.
- Each client's CI decodes and re-encodes every fixture byte for byte, as the NotebookCore/Android format contract already does.
- The host app supplies:
  - a token provider;
  - a canvas adapter that converts its strokes to and from `PortableStroke`;
  - UI slots.
- This keeps the module independent of the host app.

### Gaps
- Not verified in this session:
  - the platform coverage of LiveKit E2EE;
  - Apple and Google deep-link file requirements for 2026;
  - DPDP Section 9(3)'s exact wording on tracking and behavioural monitoring of children.
- No legal review.
- I found no source on whether a study-group video call counts as "processing" that needs separate notice beyond the account consent. Take legal advice before launch.
