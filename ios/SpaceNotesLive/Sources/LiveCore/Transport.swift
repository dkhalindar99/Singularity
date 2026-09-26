// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What a socket reports back to the room client. Delivered on the main actor.
public enum TransportEvent: Sendable {
    case open
    case message(String)
    /// `code` is the WebSocket close code when the server sent one. The room
    /// server closes with 4000 (room-ended), 4001 (removed-by-host) and 4002
    /// (an error, reason = its code), and `reason` then carries that word.
    case closed(code: Int?, reason: String?)
}

/// One WebSocket connection. The room client makes a fresh transport for every
/// connection attempt and never reuses a closed one.
@MainActor
public protocol WebSocketTransport: AnyObject {
    func connect(url: URL, onEvent: @escaping @MainActor (TransportEvent) -> Void)
    func send(_ text: String)
    func close()
}

// MARK: - URLSession

/// The real socket, on URLSessionWebSocketTask. Text frames only.
@MainActor
public final class URLSessionWebSocketTransport: WebSocketTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var onEvent: (@MainActor (TransportEvent) -> Void)?
    private var closed = false

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(url: URL, onEvent: @escaping @MainActor (TransportEvent) -> Void) {
        self.onEvent = onEvent
        let task = session.webSocketTask(with: url)
        // A welcome carries the whole notebook, which can pass the 1 MiB
        // default receive limit.
        task.maximumMessageSize = 64 * 1024 * 1024
        self.task = task
        task.resume()
        // Sends made before the handshake finishes are queued by the task, so
        // the client may say hello straight away.
        onEvent(.open)
        receive()
    }

    public func send(_ text: String) {
        guard let task, !closed else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.finish(error) }
        }
    }

    public func close() {
        guard !closed else { return }
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        onEvent = nil
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                switch result {
                case .success(.string(let text)):
                    self.onEvent?(.message(text))
                    self.receive()
                case .success(.data(let data)):
                    self.onEvent?(.message(String(decoding: data, as: UTF8.self)))
                    self.receive()
                case .success:
                    self.receive()
                case .failure(let error):
                    self.finish(error)
                }
            }
        }
    }

    private func finish(_ error: Error) {
        guard !closed, let task else { return }
        let code = task.closeCode == .invalid ? nil : task.closeCode.rawValue
        let reason = task.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? error.localizedDescription
        let onEvent = self.onEvent
        close()
        onEvent?(.closed(code: code, reason: reason))
    }
}

// MARK: - In memory

/// A transport for tests and previews: records what the client sent and lets
/// the test play the server.
@MainActor
public final class InMemoryTransport: WebSocketTransport {
    public private(set) var url: URL?
    public private(set) var sent: [String] = []
    public private(set) var isClosed = false
    private var onEvent: (@MainActor (TransportEvent) -> Void)?

    public init() {}

    public func connect(url: URL, onEvent: @escaping @MainActor (TransportEvent) -> Void) {
        self.url = url
        self.onEvent = onEvent
        onEvent(.open)
    }

    public func send(_ text: String) {
        guard !isClosed else { return }
        sent.append(text)
    }

    public func close() {
        isClosed = true
        onEvent = nil
    }

    /// Every frame the client sent, decoded.
    public var sentMessages: [ClientMessage] {
        sent.compactMap { try? LiveJSON.decode(ClientMessage.self, from: $0) }
    }

    public func clearSent() { sent.removeAll() }

    /// Delivers a server frame to the client.
    public func receive(_ message: ServerMessage) {
        guard let text = try? LiveJSON.encodeString(message) else { return }
        onEvent?(.message(text))
    }

    public func receive(text: String) {
        onEvent?(.message(text))
    }

    /// The server (or the network) closed the socket.
    public func drop(code: Int? = nil, reason: String? = nil) {
        let onEvent = self.onEvent
        isClosed = true
        self.onEvent = nil
        onEvent?(.closed(code: code, reason: reason))
    }
}

// MARK: - Time

public protocol LiveCancellable: AnyObject {
    func cancel()
}

/// Timers for the room client: reconnect backoff, pings and the live-ink
/// throttle. Injected so tests can move time by hand.
@MainActor
public protocol LiveScheduler: AnyObject {
    /// Seconds on a monotonic clock.
    var now: Double { get }
    @discardableResult
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> LiveCancellable
}

@MainActor
public final class TaskScheduler: LiveScheduler {
    private final class Handle: LiveCancellable {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    public init() {}

    public var now: Double { ProcessInfo.processInfo.systemUptime }

    @discardableResult
    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> LiveCancellable {
        let handle = Handle()
        handle.task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        return handle
    }
}

/// A scheduler whose clock only moves when told to. For tests.
@MainActor
public final class ManualScheduler: LiveScheduler {
    private final class Entry: LiveCancellable {
        let due: Double
        let order: Int
        let action: @MainActor () -> Void
        var cancelled = false
        init(due: Double, order: Int, action: @escaping @MainActor () -> Void) {
            self.due = due
            self.order = order
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    public private(set) var now: Double = 0
    private var entries: [Entry] = []
    private var counter = 0

    public init() {}

    @discardableResult
    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> LiveCancellable {
        counter += 1
        let entry = Entry(due: now + max(0, seconds), order: counter, action: action)
        entries.append(entry)
        return entry
    }

    /// Timers still waiting, as delays from now.
    public var pendingDelays: [Double] {
        entries.filter { !$0.cancelled }.map { $0.due - now }.sorted()
    }

    /// Moves the clock forward, running every timer that falls due, in order.
    public func advance(by seconds: Double) {
        let target = now + seconds
        while true {
            entries.removeAll { $0.cancelled }
            guard let next = entries.filter({ $0.due <= target }).min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) else { break }
            entries.removeAll { $0 === next }
            now = max(now, next.due)
            next.action()
        }
        now = target
    }
}
