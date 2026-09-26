# Competitors: real-time shared ink and live group sessions (as of Sept 2026)

Method note: the GoodNotes and Notability help-centre pages returned HTTP 403 when fetched directly, so their details come from search-result excerpts of those pages (linked). The Figma, Excalidraw, TechCrunch, Notability blog, GoodNotes feature page and Microsoft Q&A pages were read in full. Direct Reddit threads did not come up in search. Student-sentiment findings are therefore thin and marked as such.

## 1. Do strokes appear while they are drawn, or only when the pen lifts? What latency do users notice?

### Takeaway
The ink-first notebook apps (GoodNotes, older OneNote) have historically synced a stroke **when it is finished** (pen lift) or on a periodic sync. Real-time "live cursor" sessions were added later, and some are paywalled. The whiteboard tools (Microsoft Whiteboard, tldraw, Figma/FigJam, Zoom Whiteboard) stream changes continuously at high frequency. Users compare the two directly, e.g. OneNote "10+ s" against Whiteboard "instant".

### Cited Findings
- **GoodNotes (older shared-docs model):** "changes you make can be seen by others as soon as you finish an edit, for example by lifting your stylus from the screen." This is per-stroke, on pen-up, not point streaming. — [GoodNotes Support: Share a document for collaboration](https://support.goodnotes.com/hc/en-us/articles/7353695997839-Share-a-document-for-collaboration) (search excerpt)
- **GoodNotes (current real-time layer):** "Real-time collaboration lets multiple people work in the same shared document and see changes as they happen. With Live Cursor, participants can see where collaborators are writing." Shared documents "now sync changes noticeably faster than before … near real-time updates." — [GoodNotes Support: Live Cursor](https://support.goodnotes.com/hc/en-us/articles/13922131401615-Real-time-Collaboration-with-Live-Cursor-in-shared-documents); [GoodNotes Support: Improved Collaboration](https://support.goodnotes.com/hc/en-us/articles/13682950187279-Improved-Collaboration) (search excerpts). I could not confirm whether a stroke's points stream while it is being drawn.
- **GoodNotes limits:** up to **50** people get real-time updates at once. Anyone beyond 50 "can still work and receive regular sync updates, but they do not see Live Cursor or instant updates." — [GoodNotes Support: Live Cursor](https://support.goodnotes.com/hc/en-us/articles/13922131401615-Real-time-Collaboration-with-Live-Cursor-in-shared-documents)
- **GoodNotes web gap:** "some inserted Elements won't be shown on the web." — [GoodNotes Support: Share a document](https://support.goodnotes.com/hc/en-us/articles/7353695997839-Share-a-document-for-collaboration)
- **GoodNotes, Sept 2025:** it launched a collaborative whiteboard, collaborative docs and an AI assistant (meeting summaries, transcription) for professional users, and reports 25M+ monthly active users. The collaboration feature page lists live cursors and instant updates on iPad, Android, Windows and Web. — [TechCrunch, 2025-09-23](https://techcrunch.com/2025/09/23/goodnotes-collaborative-docs-and-ai-assitant-to-cater-to-professional-users/); [GoodNotes collaboration page](https://www.goodnotes.com/features/collaboration)
- **Notability:** notes shared by link or invite can be "edited collaboratively in real time" across iOS, Mac and Web. — [Notability Support: Live Collaboration](https://support.gingerlabs.com/hc/en-us/articles/10463526132122-Live-Collaboration) (search excerpt). In a January 2026 post, Notability listed "Shared Notes with Real-Time Sync" and "Live Cursor Presence" as **coming soon**, requiring Notability Cloud. — [Notability blog, 2026-01-21](https://blog.notability.com/post/whats-coming-to-notability-this-semester). Wikipedia says that in **August 2025** Notability began beta-testing a new file format "intended to support real-time collaboration and enhanced server-based syncing." — [Wikipedia: Notability](https://en.wikipedia.org/wiki/Notability_(application)). TechRadar's review headline: "a satisfying note-taking app, but its collaboration skills are weak" (body and date not retrievable). — [TechRadar](https://www.techradar.com/pro/software-services/notability-review)
- **OneNote (desktop Office version):** a user reported (28 Feb 2023) "When I write something it takes at least 10 seconds for my friend to see anything on his screen … Microsoft Whiteboard … synced instantly." The answer: Office OneNote "still has an older sync method which works periodically, not instantly." — [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/5197275/onenote-sync-is-very-slow-when-collaborating-with). Other reports put the delay at 20+ seconds. In Class Notebooks, pages with images or PDFs wait to sync until they are visited. — [Microsoft Support: slow sync in Class Notebook](https://support.microsoft.com/en-us/education/onenote/fix-slow-sync-times-and-delays-when-distributing-pages-in-class-notebook)
- **Microsoft Whiteboard in Teams:** participants' contributions "appear in real time." — [Univ. of Lincoln guide](https://digital.lincoln.ac.uk/resources/whiteboard-in-microsoft-teams/)
- **tldraw sync (reference architecture only; its code is off-limits for licensing reasons):** changes are sent at **30 FPS while collaborating, 1 FPS when solo**. Each room is one Durable Object, with up to 50 collaborators. Cursors, selections and viewports are animated. — [tldraw docs: collaboration](https://tldraw.dev/sdk-features/collaboration); [tldraw multiplayer feature page](https://tldraw.dev/features/composable-primitives/multiplayer-collaboration)
- **Zoom Whiteboard:** "all updates happen in real time"; about **30** simultaneous editors, "may vary depending on network conditions." — [Zoom Whiteboard explainer](https://library.zoom.com/zoom-workplace/zoom-whiteboard/zoom-whiteboard-explainer); [Tactiq guide](https://tactiq.io/learn/zoom-whiteboard)
- **Samsung Notes:** live collaboration arrived in One UI 5.1. Edits are "instantly viewed by each member", up to 10 people in total. — [Samsung Newsroom (Z Fold5)](https://news.samsung.com/my/all-together-now-collaborate-on-samsung-notes-on-the-galaxy-z-fold5); [Samsung US support](https://www.samsung.com/us/support/answer/ANS10003702/)
- **Explain Everything:** collaboration is "synchronous — participants … can hear one another and see what everyone else is doing." It supports up to 25 people but "works best with 8" for stability. — [Explain Everything help](https://help.explaineverything.com/hc/en-us/articles/360013242540-Working-together-using-an-online-whiteboard-canvas); [search summary of EE docs](https://explaineverything.zendesk.com/hc/en-us/articles/360015154794-Working-collaboratively)

### Inferences
- Syncing on pen-up ("finish an edit") makes handwriting show up a whole word or line at a time. Watching someone write only feels live with point streaming (about 30 Hz, as in tldraw). The medical-student use case, "watch my friend draw the brachial plexus", needs streaming, not pen-up sync.
- Pen-up sync is still the right unit to **persist**. Streaming the in-progress points as throwaway presence data, and committing the finished stroke on pen-up, maps cleanly onto SpaceNotes' PortableStroke model.

### Gaps
- No published millisecond latency figures for GoodNotes or Notability live sessions.
- Unconfirmed whether GoodNotes Live Cursor streams partial strokes or only shows the cursor position while writing.

## 2. Presence: live cursors and names, a colour per person, follow the host, page sync vs free navigation

### Takeaway
The whiteboards have mature presence features: named cursors in avatar colours, follow a person, and a host "spotlight" or "bring everyone to me". The notebook apps have only just added live cursors, and I found **no follow-the-host or page-sync mode** documented for GoodNotes, Notability or Samsung Notes.

### Cited Findings
- **FigJam:** Spotlight "lets you gather collaborators … to follow your view." You follow a person by tapping their avatar, and a border in their avatar colour appears. Also cursor chat (temporary typed messages) and high fives. Audio plus spotlight lets people "facilitate … without relying on an external meeting tool." — [Figma: Facilitate meetings with spotlight](https://help.figma.com/hc/en-us/articles/5025214483351-Facilitate-meetings-with-spotlight); [Figma: Spotlight presenters](https://help.figma.com/hc/en-us/articles/24260248467735-Spotlight-yourself-or-other-presenters); [Figma: FigJam for iPad](https://help.figma.com/hc/en-us/articles/4502073572247-FigJam-for-iPad)
- **Miro:** "Bring everyone to me" turns on auto-follow for everyone "until they move their cursors, zoom, or click on the board." You follow one person by clicking their avatar, and they are told they are being followed. Laser pointer: a long-standing community request, not available at the time of those threads (undated). Users also asked to enforce follow ("How to enforce 'follow me'"). — [Miro Help: Attention management](https://help.miro.com/hc/en-us/articles/360013358479-Attention-management); [Miro community: Laser pointer idea](https://community.miro.com/ideas/laser-pointer-11720); [Miro community: enforce follow me](https://community.miro.com/ask-the-community-45/how-to-enforce-follow-me-2401)
- **Microsoft Whiteboard:** "Follow" lets participants follow the presenter's view. People who don't respond within 20 seconds start following automatically. Collaborative cursors show every attendee's name and are on by default. — [Microsoft Support: Follow](https://support.microsoft.com/en-us/whiteboard/guide-participants-through-a-whiteboard-with-follow); [Microsoft Support: Whiteboard in Teams](https://support.microsoft.com/en-us/whiteboard/use-whiteboard-in-a-teams-meeting)
- **tldraw:** live cursors, selections, chat bubbles and "follow each other's viewports." — [tldraw collaboration docs](https://tldraw.dev/sdk-features/collaboration)
- **GoodNotes / Notability:** live cursors marking "exactly where others are editing." No follow or page-lock is described. — [GoodNotes Live Cursor](https://support.goodnotes.com/hc/en-us/articles/13922131401615-Real-time-Collaboration-with-Live-Cursor-in-shared-documents); [Notability blog 2026-01-21](https://blog.notability.com/post/whats-coming-to-notability-this-semester)

### Inferences
- A paged notebook needs a paged version of "follow": follow the host's **page** (and zoom), with a quiet "Jump back to host" chip when you wander. None of the notebook apps appears to offer this, so it is a clear gap.
- Miro's rule that follow ends when you move is a proven pattern: follow gently, never lock the view by force.

### Gaps
- Whether GoodNotes gives each participant a stroke colour or shows the author of a stroke (attribution) is undocumented in what I could read.

## 3. Permissions: host locks drawing, view-only guests, raising a hand, laser pointer

### Takeaway
Meeting whiteboards give the host a single switch between "everyone edits" and "view only" (Teams, Zoom). Notebook apps offer only document-level can-view/can-edit. Raising a hand lives in the video app, not the canvas. Laser pointers appear in presentation tools, and Miro users have asked for one.

### Cited Findings
- **Teams Whiteboard:** attendees can draw "unless editing is locked"; the organizer can make the board view-only while presenting. Only the organizer/owner can change the lock. — [Univ. of Lincoln](https://digital.lincoln.ac.uk/resources/whiteboard-in-microsoft-teams/); [usecarly guide 2026](https://www.usecarly.com/blog/how-to-use-whiteboard-in-teams/)
- **Zoom Whiteboard:** when sharing in a meeting, choose "Collaborating – everyone can edit" or "Viewing". Whiteboards made in a meeting are shared with participants "with temporary permissions." Hosts can enable or disable in-meeting collaboration. — [Zoom: Sharing a whiteboard](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0058153); [Zoom: enable in-meeting collaboration](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0075898)
- **GoodNotes:** link sharing with view/edit controls; invite and remove people. Real-time sessions cannot start until "at least one participant with an active Goodnotes Pro subscription opens the shared document." Pro is $35.99/yr and Essentials $11.99/yr (Sept 2025). — [GoodNotes collaboration page](https://www.goodnotes.com/features/collaboration); [GoodNotes Live Cursor](https://support.goodnotes.com/hc/en-us/articles/13922131401615-Real-time-Collaboration-with-Live-Cursor-in-shared-documents); [TechCrunch 2025-09-23](https://techcrunch.com/2025/09/23/goodnotes-collaborative-docs-and-ai-assitant-to-cater-to-professional-users/)
- **Notability:** "can edit" or "can view"; access restricted or public. — [Notability: Link Sharing](https://support.gingerlabs.com/hc/en-us/articles/360052943751-Link-Sharing) (search excerpt)
- **Samsung Notes:** the creator is the "group leader" and can remove users and hand leadership on. "Anyone with access … will be able to edit it at any time," so there is no view-only role. — [Samsung US support](https://www.samsung.com/us/support/answer/ANS10003702/)

### Inferences
- For a study group, the useful modes are: **Host only** (lecture or teach-back), **Everyone draws**, and a per-person "pass the pen". A hand-raise that becomes "give pen" would link the video call and the canvas, and no competitor documents that link.

### Gaps
- No notebook app documents a hand-raise or laser pointer inside a shared session. Search did not confirm GoodNotes' single-user laser pointer being shared live.

## 4. Undo in multi-user sessions and conflict handling

### Takeaway
The industry norm is **undo only your own changes**, last-writer-wins per property, tombstones for deletions, and optimistic local application. Multi-user undo is admitted to be hard; Excalidraw said so openly.

### Cited Findings
- **Figma:** the server is authoritative, with last-writer-wins per property per object. Client-generated unique IDs (the client ID is embedded). Local edits apply at once, and incoming server values that conflict with unacknowledged local edits are discarded. Undo principle: "if you undo a lot, copy something, and redo back to the present, the document should not change." OT was rejected as "unnecessarily complex." Offline: fetch a fresh copy on reconnect and reapply local edits. — [Figma blog: How Figma's multiplayer technology works](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/); [Figma blog: Making multiplayer more reliable](https://www.figma.com/blog/making-multiplayer-more-reliable/)
- **Excalidraw:** each element carries `version` plus a random `versionNonce` tie-break (the lower one wins, deterministically), and deletions are tombstoned with `isDeleted` so a resync cannot bring them back. The merge is a union by element id. "One problem we haven't solved yet is implementing multiplayer undo/redo," and the undo stack was cleared on peer updates at the time. The relay server passes on end-to-end encrypted messages. The AES key sits in the URL fragment (#), which browsers never send to the server. — [Excalidraw blog: P2P collaboration](https://plus.excalidraw.com/blog/building-excalidraw-p2p-collaboration-feature); [Excalidraw blog: E2E encryption](https://plus.excalidraw.com/blog/end-to-end-encryption)
- **tldraw:** "separate layers for confirmed server data and pending edits," resolving conflicts automatically. — [tldraw collaboration docs](https://tldraw.dev/sdk-features/collaboration)
- **OneNote:** sync problems happen when several students "edit the same page location at the same time." — [Microsoft Support: Class Notebook sync](https://support.microsoft.com/en-us/education/onenote/fix-slow-sync-times-and-delays-when-distributing-pages-in-class-notebook)

### Inferences
- Ink conflicts are few: strokes are append-only objects with unique IDs, so two people drawing at once never collide. Conflicts arise only with erase, lasso-move and tape. An Excalidraw-style version plus tombstone per stroke, with undo scoped to the author's own strokes, fits PortableStroke well.

### Gaps
- GoodNotes' and Notability's undo semantics in shared documents are undocumented in the sources I could reach.

## 5. Join flow: links, short codes, QR, guests without accounts

### Takeaway
Links are universal. Short codes are an education pattern (Explain Everything). Notebook apps generally require the app and often an account or subscription. Excalidraw's link-with-key-in-fragment shows joining with no account at all.

### Cited Findings
- GoodNotes: Share › "Enable Share Link to Collaborate" › Send Link; iCloud-synced owners need iCloud space for shared docs. — [GoodNotes Support](https://support.goodnotes.com/hc/en-us/articles/7353695997839-Share-a-document-for-collaboration); [Share Link across platforms](https://support.goodnotes.com/hc/en-us/articles/7445581406095-Share-notebooks-between-iOS-and-other-platforms-Using-Share-Link)
- Samsung Notes: invite from contacts or a URL; the invitee taps Join. Galaxy only. — [Samsung US support](https://www.samsung.com/us/support/answer/ANS10003702/); [SamMobile](https://www.sammobile.com/news/shared-notebook-brilliant-samsung-notes-collaborative-feature/)
- Explain Everything: invite by link, code or email, with a join-code field in the corner. — [Explain Everything help](https://explaineverything.zendesk.com/hc/en-us/articles/360015154794-Working-collaboratively)
- Excalidraw: a room link whose encryption key sits in the fragment. No login. — [Excalidraw E2E blog](https://plus.excalidraw.com/blog/end-to-end-encryption)
- Zoom: in-meeting whiteboards are shared automatically with meeting participants. — [Zoom Whiteboard explainer](https://library.zoom.com/zoom-workplace/zoom-whiteboard/zoom-whiteboard-explainer)
- Ziteboard: students join video calls on free accounts; Scribble Together lets a paying teacher invite any number of guests. — [Ziteboard](https://ziteboard.com/); [Scribble Together](https://scribbletogether.com/)

### Gaps
- No competitor was found using QR codes for joining a notebook session.

## 6. Student complaints and requests; video call plus shared notebook; the gap

### Takeaway
I found no direct Reddit threads through search, so the student voice here is indirect. The documented pain points are: OneNote's slow shared-ink sync (10–20+ s); GoodNotes real-time locked behind Pro; Notability collaboration late (still "coming soon" in Jan 2026) and called weak by reviewers; and the loss of Jamboard (Dec 2024) as Google Meet's whiteboard. The workaround students use is screen-sharing an iPad into Zoom, which is one-way. No mainstream notebook combines a call with a shared, streaming, page-synced notebook.

### Cited Findings
- Jamboard went view-only on 1 Oct 2024 and was retired on **31 Dec 2024**. Google points users to FigJam, Lucidspark and Miro, all infinite whiteboards, not paged notebooks. — [Google Workspace Updates, Sept 2023](https://workspaceupdates.googleblog.com/2023/09/the-next-phase-of-digital-whiteboarding-for-google-workspace.html); [Edutopia](https://www.edutopia.org/article/replacements-for-google-jamboard/)
- The Zoom workaround: GoodNotes shared into Zoom as "iPad via AirPlay" enters presentation mode. Only one person writes. — [Northeastern AAC blog](https://asianamericancenter.northeastern.edu/blog/good-notes/)
- Samsung community users filed a "Feature Request: Real-Time Collaborative Editing within Samsung Notes" (undated in excerpt). — [Samsung Community](https://us.community.samsung.com/t5/Samsung-Apps-and-Services/Feature-Request-Real-Time-Collaborative-Editing-within-Samsung/td-p/3138344)
- Study-together apps (StudyStream: 270K+ users in live study rooms) centre on accountability video rooms, not shared ink. — [StudyStream on Google Play](https://play.google.com/store/apps/details?id=live.studystream.app&hl=en_US); [Saima: study-together apps](https://saima.ai/blog/top-10-study-together-apps-for-students)
- Whiteboards with built-in calls exist (Ziteboard video chat, FigJam audio, Explain Everything voice), but they are blank canvases, not the student's own annotated lecture PDFs. — [Ziteboard](https://ziteboard.com/); [Figma spotlight](https://help.figma.com/hc/en-us/articles/5025214483351-Facilitate-meetings-with-spotlight); [Explain Everything](https://help.explaineverything.com/hc/en-us/articles/360013242540-Working-together-using-an-online-whiteboard-canvas)

### Inferences (the gap for SpaceNotes)
- **The gap:** one tap on a notebook the student already owns (lecture PDF plus handwriting) starts a call with voice or video, and everyone sees the same page with ink streaming as it is drawn. The session has follow-the-host page sync, host/everyone/pass-the-pen modes, per-person colours with named pen pointers, undo that touches only your own strokes, a link or short code to join, and guests who can join on Android or web. When the call ends, the session's ink stays in each person's notebook through the portable model. No competitor documented here does all of this. GoodNotes comes closest but has no call, no follow or page sync, requires Pro, and syncs on pen-up.
- **Medical-specific hooks** (inferred, not sourced): teach-back rounds (one student draws the pathway while the others watch it appear live), group viva on a slide, and AI features (Ask with cited sources, flashcards) run on the group's shared page afterwards.
- **Indian-market inference:** GoodNotes' live-session paywall ($35.99/yr) and Samsung's Galaxy-only limit leave an opening for a free session, or one where only the host pays, especially on mixed iPad and Android groups.

### Gaps
- Reddit (r/GoodNotes, r/notabilityapp, r/medicalschool, r/Indianmedschool) threads were not surfaced by the search tool. The claims about student demand for studying together on a call are therefore inferred, not quoted. A follow-up with direct Reddit browsing is needed.
- No 2025–2026 app was found that pairs a video call with a paged, handwritten notebook, but the absence is not proven.
- Nothing was found on Microsoft Whiteboard, Miro or Zoom stroke-streaming implementation or latency beyond "real time"/"instantly."
