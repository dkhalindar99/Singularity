// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Where the connection stands. */
public sealed interface RoomStatus {
    /** Before the first `welcome`. */
    public data object Connecting : RoomStatus

    public data object Connected : RoomStatus

    /** Had a `welcome`, lost the socket, and is getting it back. */
    public data object Reconnecting : RoomStatus

    /** Over for good: removed, the room ended, a refusal, or [RoomClient.disconnect]. */
    public data class Ended(val reason: String) : RoomStatus

    public companion object {
        /** The reason [RoomClient.disconnect] ends with. */
        public const val LEFT: String = "left"
    }
}

/** Things worth telling the person, once. */
public sealed interface RoomEvent {
    /** The server refused one of this client's ops; its local effect is gone. */
    public data class Rejected(val clientOpId: String, val reason: String) : RoomEvent

    /** An `error` frame. */
    public data class ServerError(val code: String, val message: String) : RoomEvent
}

/** Someone else's stroke while it is still being drawn. */
public data class RemoteInk(
    val liveId: String,
    val uid: String,
    val connectionId: String,
    val pageId: String,
    val ink: String,
    val color: LiveColor,
    val width: Double,
    val points: List<LivePoint>,
    /** The pen has lifted; the committed stroke is on its way. */
    val done: Boolean,
) {
    val inkKind: LiveInk get() = LiveInk.fromWireName(ink)
}

/** Where someone's pen or finger is. */
public data class RemotePointer(
    val uid: String,
    val connectionId: String,
    val pageId: String,
    val x: Double,
    val y: Double,
    val laser: Boolean,
    /** [RoomClient]'s clock when it arrived, so a laser dot can fade. */
    val receivedAt: Long,
)

/**
 * One room connection: the shared notebook, who is here, and everything this
 * person sends. The same API as the web and iPad clients.
 *
 * [confirmed] is exactly what the server has numbered. [state] is that plus
 * this client's own ops the server has not answered yet, applied on top so
 * drawing never waits for the network. An op leaves the pending list when it
 * comes back numbered, or when it is rejected (and then its effect is gone).
 *
 * Every public method is safe to call from any thread.
 */
public class RoomClient(
    serverUrl: String,
    public val roomId: String,
    private val name: String,
    private val deviceId: String,
    private val tokenProvider: suspend () -> String,
    private val transportFactory: LiveTransportFactory = OkHttpTransportFactory(),
    private val scope: CoroutineScope,
    /** Milliseconds. Tests pass the virtual clock so throttles are exact. */
    private val clock: () -> Long = System::currentTimeMillis,
    /**
     * Where this client's `clientOpId` counter starts. The server never
     * sequences the same id twice in a room, so a counter restarting at 1
     * after the app relaunches would have fresh ops thrown away as duplicates;
     * starting from the clock keeps it increasing across launches.
     */
    firstOpNumber: Long = System.currentTimeMillis(),
) {
    private val url: String = liveSocketUrl(serverUrl)
    private val lock = Any()

    private val _status = MutableStateFlow<RoomStatus>(RoomStatus.Connecting)
    private val _confirmed = MutableStateFlow(RoomState())
    private val _state = MutableStateFlow(RoomState())
    private val _members = MutableStateFlow<List<Member>>(emptyList())
    private val _me = MutableStateFlow<You?>(null)
    private val _room = MutableStateFlow<RoomInfo?>(null)
    private val _canDraw = MutableStateFlow(false)
    private val _canUndo = MutableStateFlow(false)
    private val _canRedo = MutableStateFlow(false)
    private val _liveInk = MutableStateFlow<Map<String, RemoteInk>>(emptyMap())
    private val _pointers = MutableStateFlow<Map<String, RemotePointer>>(emptyMap())
    private val _views = MutableStateFlow<Map<String, String>>(emptyMap())
    private val _events = MutableSharedFlow<RoomEvent>(extraBufferCapacity = 64)

    public val status: StateFlow<RoomStatus> = _status.asStateFlow()

    /** The notebook as the server has numbered it. */
    public val confirmed: StateFlow<RoomState> = _confirmed.asStateFlow()

    /** [confirmed] with this client's pending ops on top. Draw this. */
    public val state: StateFlow<RoomState> = _state.asStateFlow()
    public val members: StateFlow<List<Member>> = _members.asStateFlow()
    public val me: StateFlow<You?> = _me.asStateFlow()
    public val room: StateFlow<RoomInfo?> = _room.asStateFlow()

    /** Whether this person may change the notebook now (tools grey out otherwise). */
    public val canDraw: StateFlow<Boolean> = _canDraw.asStateFlow()
    public val canUndo: StateFlow<Boolean> = _canUndo.asStateFlow()
    public val canRedo: StateFlow<Boolean> = _canRedo.asStateFlow()

    /** Other people's strokes in progress, by `liveId`. */
    public val liveInk: StateFlow<Map<String, RemoteInk>> = _liveInk.asStateFlow()

    /** Other people's pointers, by connection id. */
    public val pointers: StateFlow<Map<String, RemotePointer>> = _pointers.asStateFlow()

    /** The page each other connection is looking at, by connection id. */
    public val views: StateFlow<Map<String, String>> = _views.asStateFlow()
    public val events: SharedFlow<RoomEvent> = _events.asSharedFlow()

    private class Pending(val clientOpId: String, val op: Op)

    /**
     * One undoable action of this person's: the ops that take it back and the
     * ops that do it again, both worked out when it was first sent. Redo is
     * never the original op, because a resent `stroke.add` for an id already
     * on the page (erased by the undo) is a no-op.
     */
    private class HistoryEntry(val undo: List<Op>, val redo: List<Op>)

    private var started = false
    private var ended = false
    private var transport: LiveTransport? = null
    private var generation = 0
    private var welcomed = false
    private var everWelcomed = false
    private var attempt = 0
    private var connectJob: Job? = null
    private var pingJob: Job? = null
    private var opCounter = firstOpNumber
    private val pending = ArrayList<Pending>()
    private val undoStack = ArrayList<HistoryEntry>()
    private val redoStack = ArrayList<HistoryEntry>()
    private val entryByOpId = HashMap<String, HistoryEntry>()
    private val inkExpiry = HashMap<String, Job>()
    private var myView: String? = null
    private var myHand = false
    private val pointerThrottle = Throttle<Presence>(PRESENCE_INTERVAL_MS) { presence -> sendPresenceLocked(presence) }

    // ---- Connection ----------------------------------------------------------

    /** Opens the connection. Calling it again does nothing. */
    public fun connect() {
        synchronized(lock) {
            if (started || ended) return
            started = true
            _status.value = RoomStatus.Connecting
            openLocked()
        }
    }

    /** Leaves the room. The last [state] stays readable. */
    public fun disconnect() {
        synchronized(lock) { endLocked(RoomStatus.LEFT) }
    }

    private fun openLocked() {
        val gen = ++generation
        connectJob = scope.launch {
            val token = try {
                tokenProvider()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                synchronized(lock) { if (gen == generation) connectionLostLocked() }
                return@launch
            }
            synchronized(lock) {
                if (gen != generation || ended) return@launch
                val socket = transportFactory.open(url, Listener(gen))
                if (gen != generation || ended) {
                    // The listener reported a failure while opening.
                    socket.close()
                    return@launch
                }
                transport = socket
                socket.send(ClientMessage.Hello(PROTOCOL_VERSION, token, roomId, name, deviceId).encode())
            }
        }
    }

    private inner class Listener(private val gen: Int) : LiveTransportListener {
        override fun onMessage(text: String) {
            synchronized(lock) {
                if (gen != generation || ended) return
                handleLocked(ServerMessage.decode(text))
            }
        }

        override fun onClosed(code: Int, reason: String) {
            synchronized(lock) {
                if (gen != generation || ended) return
                connectionLostLocked()
            }
        }
    }

    /** Forgets the current socket and tries again after the backoff. */
    private fun connectionLostLocked() {
        generation++ // anything the old socket still reports is ignored
        transport?.close(1000, "reconnecting")
        transport = null
        welcomed = false
        pingJob?.cancel()
        pointerThrottle.cancel()
        clearRemotePresenceLocked()
        if (ended) return
        _status.value = if (everWelcomed) RoomStatus.Reconnecting else RoomStatus.Connecting
        val wait = BACKOFF_MS[attempt.coerceAtMost(BACKOFF_MS.lastIndex)]
        attempt++
        connectJob?.cancel()
        connectJob = scope.launch {
            delay(wait)
            synchronized(lock) { if (!ended) openLocked() }
        }
    }

    private fun endLocked(reason: String) {
        if (ended) return
        ended = true
        generation++
        connectJob?.cancel()
        pingJob?.cancel()
        pointerThrottle.cancel()
        transport?.close(1000, reason)
        transport = null
        welcomed = false
        clearRemotePresenceLocked()
        _status.value = RoomStatus.Ended(reason)
    }

    // ---- Incoming ------------------------------------------------------------

    private fun handleLocked(message: ServerMessage) {
        when (message) {
            is ServerMessage.Welcome -> welcomeLocked(message)
            is ServerMessage.OpFrame -> if (welcomed) opLocked(message)
            is ServerMessage.Reject -> rejectLocked(message)
            is ServerMessage.Members -> membersLocked(message.members)
            is ServerMessage.PresenceFrame -> presenceLocked(message.from, message.presence)
            // After any `removed` there is nothing to come back to, including a
            // rejoin that the server answers with `removed` instead of `welcome`.
            is ServerMessage.Removed -> endLocked(message.reason)
            is ServerMessage.Error -> {
                _events.tryEmit(RoomEvent.ServerError(message.code, message.message))
                if (message.code in FATAL_ERRORS) endLocked(message.code)
                // Otherwise the server closes the socket and we come back.
            }
            is ServerMessage.Pong, is ServerMessage.Unknown -> Unit
        }
    }

    private fun welcomeLocked(welcome: ServerMessage.Welcome) {
        welcomed = true
        everWelcomed = true
        attempt = 0
        _confirmed.value = welcome.state
        _me.value = welcome.you
        _room.value = welcome.room
        _members.value = welcome.members
        clearRemotePresenceLocked()
        // Ops the server already numbered before this connection come back as
        // `duplicate` rejects; the rest are numbered now.
        for (item in pending) sendLocked(ClientMessage.OpRequest(item.clientOpId, item.op))
        myView?.let { sendPresenceLocked(Presence.View(it)) }
        if (myHand) sendPresenceLocked(Presence.Hand(true))
        _status.value = RoomStatus.Connected
        startPingLocked()
        recomputeLocked()
    }

    private fun opLocked(frame: ServerMessage.OpFrame) {
        val confirmed = _confirmed.value
        if (frame.seq != confirmed.seq + 1) {
            // Missed something. The next `welcome` brings the whole state.
            connectionLostLocked()
            return
        }
        _confirmed.value = Reducer.apply(confirmed, frame.sequenced)
        frame.clientOpId?.let { id ->
            pending.removeAll { it.clientOpId == id }
            entryByOpId.remove(id)
        }
        val op = frame.op
        if (op is Op.StrokeAdd) removeLiveInkLocked(op.stroke.id)
        recomputeLocked()
    }

    private fun rejectLocked(reject: ServerMessage.Reject) {
        val removed = pending.removeAll { it.clientOpId == reject.clientOpId }
        val entry = entryByOpId.remove(reject.clientOpId)
        if (reject.reason != RejectReason.DUPLICATE) {
            // A real refusal: the optimistic effect goes (by dropping it from
            // pending) and so does the history entry it belonged to.
            if (entry != null) {
                undoStack.remove(entry)
                redoStack.remove(entry)
            }
            if (removed) _events.tryEmit(RoomEvent.Rejected(reject.clientOpId, reject.reason))
        }
        updateHistoryFlagsLocked()
        recomputeLocked()
    }

    private fun membersLocked(members: List<Member>) {
        _members.value = members
        val here = members.mapTo(HashSet()) { it.connectionId }
        val gone = _liveInk.value.values.filter { it.connectionId !in here }.map { it.liveId }
        gone.forEach(::removeLiveInkLocked)
        _pointers.value = _pointers.value.filterKeys { it in here }
        _views.value = _views.value.filterKeys { it in here }
    }

    private fun presenceLocked(from: PresenceSender, presence: Presence) {
        when (presence) {
            is Presence.InkLive -> inkLiveLocked(from, presence)
            is Presence.Pointer -> _pointers.value = _pointers.value + (
                from.connectionId to RemotePointer(
                    from.uid, from.connectionId, presence.pageId, presence.x, presence.y, presence.laser, clock(),
                )
                )
            Presence.PointerHide -> _pointers.value = _pointers.value - from.connectionId
            is Presence.View -> {
                _views.value = _views.value + (from.connectionId to presence.pageId)
                _members.value = _members.value.map {
                    if (it.connectionId == from.connectionId) it.copy(pageId = presence.pageId) else it
                }
            }
            is Presence.Hand -> _members.value = _members.value.map {
                if (it.connectionId == from.connectionId) it.copy(handRaised = presence.raised) else it
            }
            is Presence.Unknown -> Unit
        }
    }

    private fun inkLiveLocked(from: PresenceSender, presence: Presence.InkLive) {
        val existing = _liveInk.value[presence.liveId]
        if (existing == null && _state.value.page(presence.pageId)?.strokes?.any { it.stroke.id == presence.liveId } == true) {
            return // the committed stroke got here first
        }
        val added = ArrayList<LivePoint>(presence.p.size / 3)
        var i = 0
        while (i + 2 < presence.p.size) {
            added += LivePoint(presence.p[i], presence.p[i + 1], 1.0, 0.0, presence.p[i + 2])
            i += 3
        }
        val ink = (existing ?: RemoteInk(
            presence.liveId, from.uid, from.connectionId, presence.pageId,
            presence.ink, presence.color, presence.width, emptyList(), false,
        )).let { it.copy(points = it.points + added, done = it.done || presence.done) }
        _liveInk.value = _liveInk.value + (presence.liveId to ink)
        if (presence.done) {
            // Kept until the committed stroke arrives (right behind this frame),
            // so the preview is swapped for the stroke without a gap. The timer
            // only clears a preview whose stroke never comes.
            inkExpiry.remove(presence.liveId)?.cancel()
            inkExpiry[presence.liveId] = scope.launch {
                delay(DONE_INK_GRACE_MS)
                synchronized(lock) { removeLiveInkLocked(presence.liveId) }
            }
        }
    }

    private fun removeLiveInkLocked(liveId: String) {
        inkExpiry.remove(liveId)?.cancel()
        if (liveId in _liveInk.value) _liveInk.value = _liveInk.value - liveId
    }

    private fun clearRemotePresenceLocked() {
        inkExpiry.values.forEach { it.cancel() }
        inkExpiry.clear()
        _liveInk.value = emptyMap()
        _pointers.value = emptyMap()
        _views.value = emptyMap()
    }

    private fun startPingLocked() {
        pingJob?.cancel()
        val gen = generation
        pingJob = scope.launch {
            while (isActive) {
                delay(PING_INTERVAL_MS)
                synchronized(lock) {
                    if (gen != generation || !welcomed) return@launch
                    sendLocked(ClientMessage.Ping(clock()))
                }
            }
        }
    }

    // ---- Outgoing ops ----------------------------------------------------------

    public fun addStroke(pageId: String, stroke: LiveStroke): String? = synchronized(lock) {
        val ids = listOf(stroke.id)
        submitWithHistoryLocked(
            Op.StrokeAdd(pageId, stroke),
            HistoryEntry(undo = listOf(Op.StrokeErase(pageId, ids)), redo = listOf(Op.StrokeRestore(pageId, ids))),
        )
    }

    public fun eraseStrokes(pageId: String, strokeIds: List<String>): String? = synchronized(lock) {
        val page = _state.value.page(pageId)
        // Only what this erase actually hides comes back on undo; a stroke
        // someone else had already erased stays erased.
        val hiding = strokeIds.filter { id -> page?.strokes?.any { it.stroke.id == id && !it.erased } == true }
        if (hiding.isEmpty()) return@synchronized null
        submitWithHistoryLocked(
            Op.StrokeErase(pageId, strokeIds),
            HistoryEntry(undo = listOf(Op.StrokeRestore(pageId, hiding)), redo = listOf(Op.StrokeErase(pageId, hiding))),
        )
    }

    public fun restoreStrokes(pageId: String, strokeIds: List<String>): String? = synchronized(lock) {
        val page = _state.value.page(pageId)
        val showing = strokeIds.filter { id -> page?.strokes?.any { it.stroke.id == id && it.erased } == true }
        if (showing.isEmpty()) return@synchronized null
        submitWithHistoryLocked(
            Op.StrokeRestore(pageId, strokeIds),
            HistoryEntry(undo = listOf(Op.StrokeErase(pageId, showing)), redo = listOf(Op.StrokeRestore(pageId, showing))),
        )
    }

    public fun moveItems(
        pageId: String,
        strokeIds: List<String>,
        textIds: List<String>,
        dx: Double,
        dy: Double,
    ): String? = synchronized(lock) {
        if (strokeIds.isEmpty() && textIds.isEmpty()) return@synchronized null
        val op = Op.ItemsMove(pageId, strokeIds, textIds, dx, dy)
        submitWithHistoryLocked(
            op,
            HistoryEntry(undo = listOf(Op.ItemsMove(pageId, strokeIds, textIds, -dx, -dy)), redo = listOf(op)),
        )
    }

    public fun upsertText(pageId: String, text: LiveText): String? = synchronized(lock) {
        val existing = _state.value.page(pageId)?.texts?.firstOrNull { it.text.id == text.id }
        val op = Op.TextUpsert(pageId, text)
        val undo: Op = if (existing == null || existing.erased) {
            Op.TextErase(pageId, listOf(text.id))
        } else {
            Op.TextUpsert(pageId, existing.text)
        }
        submitWithHistoryLocked(op, HistoryEntry(undo = listOf(undo), redo = listOf(op)))
    }

    public fun eraseTexts(pageId: String, textIds: List<String>): String? = synchronized(lock) {
        val ids = textIds.toSet()
        val hiding = _state.value.page(pageId)?.texts?.filter { it.text.id in ids && !it.erased }.orEmpty()
        if (hiding.isEmpty()) return@synchronized null
        val op = Op.TextErase(pageId, textIds)
        submitWithHistoryLocked(
            op,
            HistoryEntry(undo = hiding.map { Op.TextUpsert(pageId, it.text) }, redo = listOf(op)),
        )
    }

    /** Host only. Not undoable. */
    public fun addPage(page: LivePageSpec, afterPageId: String?): String? =
        synchronized(lock) { submitLocked(Op.PageAdd(page, afterPageId)) }

    /** Host only. Not undoable. */
    public fun setPolicy(drawPolicy: String, penHolder: String? = null): String? =
        synchronized(lock) { submitLocked(Op.RoomPolicy(drawPolicy, penHolder)) }

    /** Host only: where "Follow host" takes everyone. Not undoable. */
    public fun setHostPage(pageId: String): String? =
        synchronized(lock) { submitLocked(Op.HostPage(pageId)) }

    /** Takes back this person's last action (never anyone else's). */
    public fun undo(): Boolean = synchronized(lock) {
        val entry = undoStack.removeLastOrNull() ?: return@synchronized false
        redoStack += entry
        entry.undo.forEach { submitLocked(it)?.let { id -> entryByOpId[id] = entry } }
        updateHistoryFlagsLocked()
        true
    }

    public fun redo(): Boolean = synchronized(lock) {
        val entry = redoStack.removeLastOrNull() ?: return@synchronized false
        undoStack += entry
        entry.redo.forEach { submitLocked(it)?.let { id -> entryByOpId[id] = entry } }
        updateHistoryFlagsLocked()
        true
    }

    private fun submitWithHistoryLocked(op: Op, entry: HistoryEntry): String? {
        val id = submitLocked(op) ?: return null
        entryByOpId[id] = entry
        undoStack += entry
        if (undoStack.size > MAX_HISTORY) undoStack.removeAt(0)
        redoStack.clear() // a new action of one's own starts a new branch
        updateHistoryFlagsLocked()
        return id
    }

    /** Applies the op locally and sends it. Null if it is too big to send. */
    private fun submitLocked(op: Op): String? {
        if (ended) return null
        val clientOpId = "$deviceId:${opCounter++}"
        val frame = ClientMessage.OpRequest(clientOpId, op).encode()
        if (frame.toByteArray(Charsets.UTF_8).size > MAX_FRAME_BYTES) {
            // The server would refuse the frame and close; resending it after
            // every reconnect would never end. Refuse it here instead.
            _events.tryEmit(RoomEvent.Rejected(clientOpId, ErrorCode.TOO_LARGE))
            return null
        }
        pending += Pending(clientOpId, op)
        if (welcomed) transport?.send(frame)
        recomputeLocked()
        return clientOpId
    }

    private fun recomputeLocked() {
        val confirmed = _confirmed.value
        val author = _me.value?.uid ?: ""
        _state.value = pending.fold(confirmed) { state, item ->
            Reducer.apply(state, SequencedOp(confirmed.seq, author, item.clientOpId, item.op))
        }
        _canDraw.value = _state.value.canDraw(_me.value?.actor)
    }

    private fun updateHistoryFlagsLocked() {
        _canUndo.value = undoStack.isNotEmpty()
        _canRedo.value = redoStack.isNotEmpty()
    }

    // ---- Outgoing presence and control ----------------------------------------------

    /**
     * Starts streaming a stroke as it is drawn. Feed it points, then
     * [LiveInkStreamer.finish] on lift, which also commits the stroke.
     */
    public fun beginStroke(
        pageId: String,
        ink: String,
        color: LiveColor,
        width: Double,
        id: String = java.util.UUID.randomUUID().toString().uppercase(),
    ): LiveInkStreamer = LiveInkStreamer(this, pageId, id, ink, color, width)

    public fun sendPointer(pageId: String, x: Double, y: Double, laser: Boolean = false) {
        synchronized(lock) { pointerThrottle.offer(Presence.Pointer(pageId, round1(x), round1(y), laser)) }
    }

    public fun hidePointer() {
        synchronized(lock) {
            pointerThrottle.cancel()
            sendPresenceLocked(Presence.PointerHide)
        }
    }

    /** The page this person is looking at. Sent again after a reconnect. */
    public fun sendView(pageId: String) {
        synchronized(lock) {
            myView = pageId
            sendPresenceLocked(Presence.View(pageId))
        }
    }

    public fun setHandRaised(raised: Boolean) {
        synchronized(lock) {
            myHand = raised
            sendPresenceLocked(Presence.Hand(raised))
            _me.value?.let { me ->
                _members.value = _members.value.map {
                    if (it.connectionId == me.connectionId) it.copy(handRaised = raised) else it
                }
            }
        }
    }

    /** Host: removes a person from the room. */
    public fun remove(uid: String): Boolean = synchronized(lock) { sendLocked(ClientMessage.ControlRequest(Control.Remove(uid))) }

    /** Host: ends the room for everyone. */
    public fun endRoom(): Boolean = synchronized(lock) { sendLocked(ClientMessage.ControlRequest(Control.End)) }

    internal fun sendPresence(presence: Presence) {
        synchronized(lock) { sendPresenceLocked(presence) }
    }

    /** Presence is dropped, not queued, while disconnected: it is only ever "now". */
    private fun sendPresenceLocked(presence: Presence): Boolean = sendLocked(ClientMessage.PresenceUpdate(presence))

    private fun sendLocked(message: ClientMessage): Boolean {
        if (!welcomed) return false
        return transport?.send(message.encode()) ?: false
    }

    internal fun now(): Long = clock()

    internal fun launchDelayed(delayMs: Long, block: () -> Unit): Job = scope.launch {
        delay(delayMs)
        synchronized(lock) { block() }
    }

    internal fun <T> locked(block: () -> T): T = synchronized(lock, block)

    /** Latest-value throttle for pointer updates. Runs under [lock]. */
    private inner class Throttle<T : Any>(private val intervalMs: Long, private val send: (T) -> Unit) {
        private var lastSent: Long? = null
        private var waiting: T? = null
        private var job: Job? = null

        fun offer(value: T) {
            val now = clock()
            val last = lastSent
            if (job == null && (last == null || now - last >= intervalMs)) {
                lastSent = now
                send(value)
                return
            }
            waiting = value
            if (job == null) {
                job = launchDelayed((last ?: now) + intervalMs - now) {
                    job = null
                    waiting?.let { lastSent = clock(); send(it) }
                    waiting = null
                }
            }
        }

        fun cancel() {
            job?.cancel()
            job = null
            waiting = null
        }
    }

    public companion object {
        /** Reconnect waits: 0.5, 1, 2, 4, then every 8 seconds. */
        public val BACKOFF_MS: List<Long> = listOf(500, 1000, 2000, 4000, 8000)
        public const val PING_INTERVAL_MS: Long = 20_000

        /** Live ink and pointers go out at most this often. */
        public const val PRESENCE_INTERVAL_MS: Long = 30
        public const val MAX_FRAME_BYTES: Int = 256 * 1024
        internal const val DONE_INK_GRACE_MS: Long = 1500
        private const val MAX_HISTORY = 200

        /** Errors that no reconnect can fix. */
        public val FATAL_ERRORS: Set<String> = setOf(
            ErrorCode.BAD_HELLO,
            ErrorCode.NO_SUCH_ROOM,
            ErrorCode.ROOM_FULL,
            ErrorCode.GUESTS_NOT_ALLOWED,
            ErrorCode.PROTOCOL_MISMATCH,
        )

        /** `https://host` → `wss://host/live`; a URL already ending in /live is kept. */
        public fun liveSocketUrl(serverUrl: String): String {
            val trimmed = serverUrl.trimEnd('/')
            val ws = when {
                trimmed.startsWith("https://") -> "wss://" + trimmed.removePrefix("https://")
                trimmed.startsWith("http://") -> "ws://" + trimmed.removePrefix("http://")
                else -> trimmed
            }
            return if (ws.endsWith("/live")) ws else "$ws/live"
        }

        internal fun round1(value: Double): Double = Math.round(value * 10.0) / 10.0
    }
}
