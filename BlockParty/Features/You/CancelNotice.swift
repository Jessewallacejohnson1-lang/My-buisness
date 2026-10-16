//
//  CancelNotice.swift
//  Block Party — tells the people Going when an Event is called off (BP app
//  docs/plans/watch-every-place, ticket 12). The free Apple team can't send a push, so the
//  app says it in Apple's alert when it next opens (Jesse, 2026-10-15: "take it out of
//  agenda and notify its cancelation"). Once per Event, ever: a school's schedule that drops
//  a game and brings it back can't tell anyone twice. Only Going: `get_my_going` is the
//  caller's own, and the Event leaves their You tab (`YouCalendar.going`).
//

import Foundation

@Observable
final class CancelNotice {
    /// The called-off Events the alert names; empty when there's nothing to tell.
    private(set) var showing: [UpcomingEvent] = []

    private let read: () async throws -> [UpcomingEvent]
    private let keep: UserDefaults
    /// The Events already told, by id, on this phone.
    static let toldKey = "bp.cancelled.told"

    init(read: @escaping () async throws -> [UpcomingEvent], keep: UserDefaults = .standard) {
        self.read = read
        self.keep = keep
    }

    /// Your Going from today on, a year ahead (the iPhone Calendar's reach), or under DEBUG
    /// `-town-samples` the You tab's samples (`-town-cancelled` calls one off).
    convenience init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-town-samples") {
            self.init(read: { YouCalendar.samples(now: Date()) })
            return
        }
        #endif
        self.init(read: {
            let today = YouCalendar.calendar.startOfDay(for: Date())
            let last = YouCalendar.calendar.date(byAdding: .year, value: 1, to: today) ?? today
            return try await CommunityAPI(auth: AuthStore.shared).getMyGoing(from: Town.day(today), to: Town.day(last))
        })
    }

    /// Reads your Going and puts up what's newly called off. A failed read waits for the
    /// next open; an alert already up is left as it is.
    func check() async {
        guard let going = try? await read(), showing.isEmpty else { return }
        showing = Self.toTell(going, told: told)
    }

    /// OK: told, for good.
    func ok() {
        keep.set(Array(told.union(showing.map(\.id))).sorted(), forKey: Self.toldKey)
        showing = []
    }

    private var told: Set<String> { Set(keep.stringArray(forKey: Self.toldKey) ?? []) }

    /// The called-off Events in `going` not told yet, each once, in the read's order.
    static func toTell(_ going: [UpcomingEvent], told: Set<String>) -> [UpcomingEvent] {
        var seen = told
        return going.filter { $0.cancelled && seen.insert($0.id).inserted }
    }

    /// "Event canceled", or "2 events canceled".
    static func title(_ events: [UpcomingEvent]) -> String {
        events.count == 1 ? "Event canceled" : "\(events.count) events canceled"
    }

    /// Each Event's name and when, as its card says it: "Music in Millstream Park, Tonight · 7 PM".
    /// The when never breaks across lines: a long name wraps after its comma instead of
    /// leaving "8 AM" alone on the next line (the first build's alert did).
    static func message(_ events: [UpcomingEvent]) -> String {
        events.map { event in
            let item = FeedCardItem(event)
            let when = item.whenLine?.text.replacingOccurrences(of: " ", with: "\u{00A0}")
            return [item.title, when].compactMap { $0 }.joined(separator: ", ")
        }.joined(separator: "\n")
    }
}
