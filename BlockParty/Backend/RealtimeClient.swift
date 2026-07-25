//
//  RealtimeClient.swift
//  Block Party — a minimal Supabase Realtime (Phoenix channel) client over
//  URLSessionWebSocketTask. Subscribes to Postgres changes on one table and
//  reports INSERT / UPDATE / DELETE via `onChange`.
//
//  No Supabase SDK: this speaks the Phoenix wire protocol (vsn 1.0.0, object
//  frames) by hand, matching the hand-rolled REST layer in SupabaseHTTP. RLS
//  still governs which rows arrive — the channel joins with the user's JWT.
//
//  Main-actor isolated: the receive loop `await`s between frames, so it never
//  blocks the main thread, and callbacks can touch @Published state directly.
//

import Foundation

@MainActor
final class RealtimeClient {

    // MARK: Public change model (Sendable — no [String: Any] crosses a boundary)

    struct Change: Sendable {
        enum Kind: String, Sendable { case insert = "INSERT", update = "UPDATE", delete = "DELETE" }

        /// The subset of a club_events row the map cares about. INSERT/UPDATE
        /// carry a full `record`; a DELETE's `old_record` carries only the
        /// primary key (id) — Supabase Realtime sends just the replica-identity
        /// key on delete (verified empirically, even with REPLICA IDENTITY FULL)
        /// — so delete relevance is matched by id (see MapModel.currentlyShown).
        struct Row: Sendable {
            let id: String?
            let eventDate: String?
            let startTime: String?
            let status: String?
            let kind: String?
            let title: String?
            let location: String?
        }

        let kind: Kind
        let new: Row?   // record     (INSERT / UPDATE)
        let old: Row?   // old_record (UPDATE / DELETE)
    }

    enum Status: Equatable { case connecting, subscribed, disconnected }

    var onChange: ((Change) -> Void)?
    var onStatus: ((Status) -> Void)?
    /// Table-agnostic "something changed" ping — fires on ANY postgres_changes
    /// frame, before the club_events-shaped `Change` is built. A subscriber to a
    /// different table (e.g. town_status) that only needs to re-fetch listens here
    /// and ignores the typed `Change`. (See RoadsTileProvider.)
    var onAnyChange: (() -> Void)?

    // MARK: Config

    private let schema: String
    private let table: String
    private let topic: String
    private let tokenProvider: () async -> String?

    // MARK: State

    private let session = URLSession(configuration: .default)
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var ref = 0
    private var stopped = true
    private var reconnectAttempts = 0
    /// Bumped on every teardown/new socket. A join()/receiveLoop() spawned for an
    /// older socket captures its epoch and bails if it no longer matches — so a
    /// background→foreground flap that opens a fresh socket while a prior join() is
    /// still suspended on the token fetch can't join/receive on the new socket or
    /// double-count the reconnect backoff. (Same pattern as MapModel.loadGeneration.)
    private var epoch = 0

    init(schema: String = "public", table: String, tokenProvider: @escaping () async -> String?) {
        self.schema = schema
        self.table = table
        self.topic = "realtime:hygge-\(table)"
        self.tokenProvider = tokenProvider
    }

    // MARK: Lifecycle

    /// Idempotent: a second call while already running is a no-op, so re-entry
    /// from foreground / onAppear can't stack duplicate sockets.
    func start() {
        guard stopped else { return }
        stopped = false
        reconnectAttempts = 0
        openSocket()
    }

    func stop() {
        stopped = true
        teardown()
        onStatus?(.disconnected)
    }

    private func teardown() {
        epoch &+= 1                             // invalidate any in-flight join/receive from the prior socket
        heartbeatTask?.cancel(); heartbeatTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        receiveTask?.cancel(); receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: Connect

    private func openSocket() {
        teardown()                              // single-socket invariant (also bumps epoch)
        stopped = false
        let myEpoch = epoch
        onStatus?(.connecting)
        let task = session.webSocketTask(with: SupabaseConfig.realtimeURL)
        socket = task
        task.resume()
        receiveTask = Task { @MainActor [weak self] in
            await self?.join(epoch: myEpoch)
            await self?.receiveLoop(epoch: myEpoch)
        }
        startHeartbeat()
    }

    private func nextRef() -> String { ref += 1; return String(ref) }

    private func join(epoch: Int) async {
        let token = await tokenProvider()
        // A newer socket may have opened while the token fetch was suspended; if so
        // this attempt is stale — don't phx_join on someone else's socket.
        guard epoch == self.epoch, !stopped else { return }
        var payload: [String: Any] = [
            "config": [
                "postgres_changes": [
                    ["event": "*", "schema": schema, "table": table],
                ],
                "private": false,
            ],
        ]
        if let token { payload["access_token"] = token }
        send(event: "phx_join", payload: payload)
    }

    private func send(event: String, payload: [String: Any], topicOverride: String? = nil) {
        guard let socket else { return }
        let msg: [String: Any] = [
            "topic": topicOverride ?? topic,
            "event": event,
            "payload": payload,
            "ref": nextRef(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }     // fire-and-forget; drops surface as receive errors
    }

    // MARK: Heartbeat + token keepalive

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)
                guard !Task.isCancelled, let self, self.socket != nil else { break }
                self.send(event: "heartbeat", payload: [:], topicOverride: "phoenix")
                tick += 1
                // ~every 4 min push a fresh JWT so a long foreground session
                // doesn't drop the subscription when the token expires (~1 h).
                if tick % 10 == 0, let token = await self.tokenProvider() {
                    self.send(event: "access_token", payload: ["access_token": token])
                }
            }
        }
    }

    // MARK: Receive

    private func receiveLoop(epoch: Int) async {
        while true {
            guard !stopped, epoch == self.epoch, let socket else { return }
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text): handle(text)
                case .data(let d): if let s = String(data: d, encoding: .utf8) { handle(s) }
                @unknown default: break
                }
            } catch {
                if !stopped { scheduleReconnect() }
                return
            }
        }
    }

    private func handle(_ text: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let event = obj["event"] as? String else { return }
        switch event {
        case "postgres_changes":
            guard let payload = obj["payload"] as? [String: Any],
                  let data = payload["data"] as? [String: Any],
                  let typeStr = data["type"] as? String,
                  let kind = Change.Kind(rawValue: typeStr) else { return }
            onAnyChange?()   // table-agnostic ping (town_status re-fetch); before the typed Change
            let new = row(from: data["record"] as? [String: Any])
            let old = row(from: data["old_record"] as? [String: Any])
            onChange?(Change(kind: kind, new: new, old: old))
        case "system":
            // "Subscribed to PostgreSQL" with status ok = the subscription is
            // live. Reset the reconnect backoff ONLY here — resetting on any
            // frame (e.g. a join ack that arrives right before the server drops
            // a flapping socket) would defeat the exponential backoff and hammer
            // the endpoint every ~2s during an outage.
            if let payload = obj["payload"] as? [String: Any],
               (payload["status"] as? String) == "ok" {
                reconnectAttempts = 0
                onStatus?(.subscribed)
            }
        case "phx_reply":
            break   // join ack; the real confirmation is the "system" ok above
        case "phx_error", "phx_close":
            if !stopped { scheduleReconnect() }
        default:
            break
        }
    }

    private func row(from dict: [String: Any]?) -> Change.Row? {
        guard let d = dict, !d.isEmpty else { return nil }
        func str(_ k: String) -> String? { d[k] as? String }
        return Change.Row(id: str("id"), eventDate: str("event_date"),
                          startTime: str("start_time"), status: str("status"),
                          kind: str("kind"), title: str("title"), location: str("location"))
    }

    // MARK: Reconnect (capped exponential backoff)

    private func scheduleReconnect() {
        teardown()                               // drop the dead socket + heartbeat
        guard !stopped else { return }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(min(reconnectAttempts, 4))), 10)  // 2,4,8,10,10…
        onStatus?(.connecting)
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.stopped else { return }
            self.openSocket()
        }
    }
}
