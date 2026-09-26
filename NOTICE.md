# Notices

SpaceNotes Live — Copyright (c) 2026 Pillikandla Dada Khalindar. All rights
reserved. See [LICENSE](LICENSE).

## Third-party code

The room server and the web package's own code use only Node.js's built-in
modules and the browser's own APIs. Shipped third-party code:

| Code | Version | Licence | Where | Why |
|---|---|---|---|---|
| LiveKit JavaScript client (`livekit-client`), Copyright LiveKit, Inc. | 2.22.3 | Apache License 2.0 — full text in `web/vendor/livekit-client/LICENSE` | `web/vendor/livekit-client/` (the published ESM build, unmodified) | Voice in the web app |

The iPad and Android packages depend on LiveKit's official SDKs (Apache-2.0)
through their package managers; see `ios/README.md` and `android/README.md`
for the exact dependencies, each of which must be recorded here with its
licence before a release.

No code from tldraw (proprietary licence) or PenEcho (AGPL-3.0) is used, and
none may be: see docs/research.

## Third-party services (not included; each licensee needs its own account)

| Service | Used for | Where configured |
|---|---|---|
| LiveKit Cloud, or a self-hosted LiveKit server | Voice (microphone only) | Server: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` |
| Firebase Authentication | Who is who | Server: `FIREBASE_PROJECT_ID`; web: `FIREBASE_WEB_API_KEY` |
| Google Cloud Storage | Keeping rooms across restarts | Server: `LIVE_BUCKET` |

Names such as LiveKit, Firebase and Google Cloud are trademarks of their
owners. SpaceNotes Live is not affiliated with or endorsed by them.
