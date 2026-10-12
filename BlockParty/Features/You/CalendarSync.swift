//
//  CalendarSync.swift
//  Block Party — your Going in your iPhone Calendar (BP app docs/plans/you-tab, ticket 05).
//  A switch in Profile, off until you turn it on. On, every upcoming Event you're Going to
//  has an entry in the phone's default calendar; leaving takes it out and a time change
//  moves it. Your calendar wins: an entry you delete stays deleted, one you move stays
//  moved unless the Event's own time changes. Nothing about it leaves the phone.
//
//  Removing and updating need iOS's full calendar access: write-only access can't see
//  any entry, its own included (Apple, "Accessing the event store"; Jesse picked full
//  access, 2026-10-12).
//

import EventKit
import SwiftUI

/// What Block Party writes into a calendar entry.
struct CalendarEntry: Codable, Equatable {
    var title: String
    var starts: Date
    var ends: Date
    var allDay: Bool
    var place: String?
}

/// The phone's calendar, as the sync uses it. EventKit's in the app, a stand-in in tests.
@MainActor
protocol PhoneCalendar: AnyObject {
    var hasAccess: Bool { get }
    /// Asks iOS once; true when the person allowed it, now or before.
    func requestAccess() async -> Bool
    /// Whether the entry under `ref` is still there.
    func exists(_ ref: String) -> Bool
    /// An entry already there with this title starting then: its ref.
    func find(_ entry: CalendarEntry) -> String?
    func add(_ entry: CalendarEntry) throws -> String
    func update(_ ref: String, to entry: CalendarEntry) throws
    func remove(_ ref: String) throws
}

@MainActor @Observable
final class CalendarSync {
    /// The switch.
    private(set) var isOn: Bool
    /// True while iOS is being asked, so the switch shows on until the answer.
    private(set) var asking = false
    /// Counts refusals; each one shakes the switch (`turnBackShake`).
    private(set) var refusals = 0
    /// iOS said no: Profile shows the line about Settings.
    private(set) var refused = false

    /// What was written, kept on the phone: by Block Party Event id, the entry's ref and
    /// what it was given, so a person's own move is never undone.
    struct Written: Codable, Equatable {
        var ref: String
        var entry: CalendarEntry
    }
    struct State: Codable, Equatable {
        var account: String?
        var written: [String: Written] = [:]
    }

    /// How far ahead "upcoming" reaches.
    static let horizonDays = 365

    @ObservationIgnored private let calendar: PhoneCalendar
    @ObservationIgnored private let read: (_ from: String, _ to: String) async throws -> [UpcomingEvent]
    @ObservationIgnored private let account: () -> String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var syncing = false

    private static let onKey = "calendarSync.on"
    private static let stateKey = "calendarSync.state"

    init(calendar: PhoneCalendar, defaults: UserDefaults = .standard, account: @escaping () -> String?,
         read: @escaping (_ from: String, _ to: String) async throws -> [UpcomingEvent]) {
        self.calendar = calendar
        self.defaults = defaults
        self.account = account
        self.read = read
        isOn = defaults.bool(forKey: Self.onKey)
    }

    /// EventKit and `get_my_going`, or under DEBUG the You tab's sample Going
    /// (`-town-samples`) and failing reads (`-town-offline`), as `YouModel` has them.
    convenience init() {
        var read: (String, String) async throws -> [UpcomingEvent] = { from, to in
            try await CommunityAPI(auth: AuthStore.shared).getMyGoing(from: from, to: to)
        }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-town-offline") { read = { _, _ in throw URLError(.notConnectedToInternet) } }
        if arguments.contains("-town-samples") { read = { _, _ in YouCalendar.samples(now: Date()) } }
        #endif
        self.init(calendar: EventKitCalendar(), account: { AuthStore.shared.userId }, read: read)
    }

    // MARK: The switch

    /// Asks iOS when it hasn't been asked; allowed, the switch goes on and the shell adds
    /// the upcoming Going (`MainTabsView`). Refused, the switch flips back, then shakes
    /// with the error buzz (taste.md 2026-09-27).
    func turnOn() async {
        asking = true
        let allowed = await calendar.requestAccess()
        guard allowed else {
            withAnimation(.easeInOut(duration: 0.25)) { asking = false }
            try? await Task.sleep(for: .milliseconds(300))
            refused = true
            refusals += 1
            Haptics.error()
            // The shake and the buzz are silent to VoiceOver; this says it.
            AccessibilityNotification.Announcement("Calendar access is off").post()
            return
        }
        asking = false
        refused = false
        setOn(true)
        Haptics.selection()
    }

    /// Stops keeping the calendar; what's there stays (the agent's default; Jesse can ask
    /// for removal).
    func turnOff() {
        setOn(false)
        Haptics.selection()
    }

    private func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: Self.onKey)
    }

    // MARK: Keeping the calendar

    /// Brings the calendar in line with the Going: the read's from today for a year, with
    /// this session's taps laid over it. A failed read changes nothing.
    func sync(tapped: [FeedCardItem], isGoing: (FeedCardItem) -> Bool, now: Date = Date()) async {
        guard isOn, !syncing else { return }
        guard calendar.hasAccess else {
            // Access taken away in Settings: the switch says so.
            setOn(false)
            refused = true
            return
        }
        syncing = true
        defer { syncing = false }
        let today = YouCalendar.calendar.startOfDay(for: now)
        let last = YouCalendar.calendar.date(byAdding: .day, value: Self.horizonDays, to: today) ?? today
        guard let rows = try? await read(Town.day(today), Town.day(last)), isOn else { return }
        let going = YouCalendar.going(read: rows.compactMap(YouCalendar.event(from:)), tapped: tapped,
                                      isGoing: isGoing, first: today, days: Self.horizonDays + 1)
        var wanted: [String: CalendarEntry] = [:]
        for event in going { wanted[event.id] = Self.entry(for: event) }
        var state = loadState()
        Self.apply(wanted, to: &state, in: calendar, account: account(), now: now)
        saveState(state)
    }

    /// The rules, apart from the read and the phone, so the tests drive them.
    /// - A new account starts over and leaves the calendar alone.
    /// - Going and not yet written: added, or adopted when the same entry is already
    ///   there (the app was deleted and put back), so nothing is added twice.
    /// - Written before: found by its ref, else by what was written (a full calendar sync
    ///   can lose the ref). Not found: the person deleted it, and it stays deleted.
    ///   Updated only when the Event changed since it was written.
    /// - Written and no longer Going: removed, unless it's already over.
    static func apply(_ wanted: [String: CalendarEntry], to state: inout State, in calendar: PhoneCalendar,
                      account: String?, now: Date) {
        if state.account != account { state = State(account: account) }
        func locate(_ written: Written) -> String? {
            calendar.exists(written.ref) ? written.ref : calendar.find(written.entry)
        }
        do {
            for (id, entry) in wanted.sorted(by: { $0.key < $1.key }) {
                if var written = state.written[id] {
                    guard let ref = locate(written) else { continue }
                    if entry != written.entry {
                        try calendar.update(ref, to: entry)
                        written.entry = entry
                    }
                    written.ref = ref
                    state.written[id] = written
                } else {
                    let ref = try calendar.find(entry) ?? calendar.add(entry)
                    state.written[id] = Written(ref: ref, entry: entry)
                }
            }
            for (id, written) in state.written where wanted[id] == nil {
                if written.entry.ends > now, let ref = locate(written) { try calendar.remove(ref) }
                state.written[id] = nil
            }
        } catch {
            // EventKit refused a write: keep what was done, try again next time.
        }
    }

    /// An Event as its calendar entry: an untimed one ("after dark", all day) on its day.
    static func entry(for event: DailyEvent) -> CalendarEntry {
        CalendarEntry(title: event.item.title, starts: event.starts, ends: event.ends,
                      allDay: !event.timed, place: YouCalendar.place(of: event))
    }

    private func loadState() -> State {
        defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    private func saveState(_ state: State) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.stateKey)
    }
}

/// The phone's calendar through EventKit, entries in the default calendar for new events.
@MainActor
final class EventKitCalendar: PhoneCalendar {
    private let store = EKEventStore()

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    func exists(_ ref: String) -> Bool {
        store.calendarItem(withIdentifier: ref) != nil
    }

    func find(_ entry: CalendarEntry) -> String? {
        let day = YouCalendar.calendar.startOfDay(for: entry.starts)
        let next = YouCalendar.calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let found = store.events(matching: store.predicateForEvents(withStart: day, end: next, calendars: nil))
        return found.first { $0.title == entry.title && $0.isAllDay == entry.allDay
                             && (entry.allDay || $0.startDate == entry.starts) }?.calendarItemIdentifier
    }

    func add(_ entry: CalendarEntry) throws -> String {
        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        Self.write(entry, into: event)
        try store.save(event, span: .thisEvent)
        return event.calendarItemIdentifier
    }

    func update(_ ref: String, to entry: CalendarEntry) throws {
        guard let event = store.calendarItem(withIdentifier: ref) as? EKEvent else { return }
        Self.write(entry, into: event)
        try store.save(event, span: .thisEvent)
    }

    func remove(_ ref: String) throws {
        guard let event = store.calendarItem(withIdentifier: ref) as? EKEvent else { return }
        try store.remove(event, span: .thisEvent)
    }

    private static func write(_ entry: CalendarEntry, into event: EKEvent) {
        event.title = entry.title
        event.location = entry.place
        event.isAllDay = entry.allDay
        // The Town's clock, so a plan reads right wherever the phone is.
        event.timeZone = entry.allDay ? nil : Town.timeZone
        event.startDate = entry.starts
        event.endDate = entry.allDay ? entry.starts : entry.ends
    }
}
