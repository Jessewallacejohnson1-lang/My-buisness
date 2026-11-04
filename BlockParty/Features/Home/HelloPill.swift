//
//  HelloPill.swift
//  Block Party — what the hello pill says next, and the reads behind it (BP app
//  codebase-health-2 14). The view (`HelloDropView`) draws the answer and follows the finger;
//  the pure rules stay in `HelloDrop`, `HelloSchedule` and `HelloInbox`.
//

import Foundation

/// The hello pill's decisions: the day's first open, a later open, and what it remembers. The
/// session holds one. Nothing of its own is drawn, so it isn't observed: the view's one watch,
/// `waiting`, reads the inbox, which is.
@MainActor
final class HelloPill {
    /// What it reads from outside, so a test hands it fakes (`live` for the app).
    struct Reads {
        /// Reads anything the day's line needs that isn't in yet.
        var prepare: @MainActor () async -> Void
        /// Whether the Going and the Town feed are in.
        var ready: @MainActor () -> Bool
        var day: @MainActor () -> Day
        /// Your first name; nil before you've given one.
        var name: @MainActor () -> String?
        /// Events attended (hello-drop 02), read on each open; nil when the read failed.
        var attended: @MainActor () async -> Int?
        /// Your followed teams' finals read since a time (hello-drop 03), newest first.
        /// nil when the read failed.
        var finals: @MainActor (_ since: Date) async -> [TeamFinal]?
        /// Contacts who joined since a time, newest first (hello-drop 04); nil when it can't check.
        var joined: @MainActor (_ since: Date) async -> [Neighbor]?
        /// Friend requests you sent that were accepted since your last Friends page visit
        /// (hello-drop 06); nil when it can't read.
        var accepted: @MainActor () async -> [Neighbor]?
    }

    /// What the day's line is worked out from: your Going, your groups, and the Town feed's cards
    /// and news as the screen shows them.
    struct Day {
        var going: [DailyEvent] = []
        var groups: [TownGroup] = []
        var town: [DailyEvent] = []
        var news: [TownNews] = []
    }

    /// The day's first open.
    struct Morning {
        let hello: String
        /// The very first open: the welcome, with confetti (hello-drop 02).
        let first: Bool
        /// The morning's reads, for tests.
        let reads: Task<Void, Never>
    }

    /// What goes on the pill.
    enum Say: Equatable {
        /// A first or a milestone, with its tick.
        case moment(HelloMoment)
        case line(HelloDrop.Message)
    }

    static let joinedSinceKey = "helloDrop.joinedSince"
    static let lastHelloKey = "helloDrop.lastHello"
    /// The day's line the last first open said, so a count isn't said two days running (hello-drop 08).
    static let lastLineKey = "helloDrop.lastLine"

    let inbox: HelloInbox
    private let reads: Reads
    private let phone: UserDefaults
    private let clock: @MainActor () -> Date
    private let pause: @MainActor (Duration) async -> Void
    private let moments: HelloMoments
    private let schedule: HelloSchedule

    /// The last open, as this morning's line reads it.
    private var seen: Date?
    /// The day's first open's reads are back: attended, finals, acceptances and contacts.
    private var readsIn = false
    private var attendedAt = Date.distantPast
    private var acceptedAt = Date.distantPast
    /// The item on the pill now, told once it's up.
    private var saying: String?

    init(reads: Reads, inbox: HelloInbox, phone: UserDefaults, now: @escaping @MainActor () -> Date = { Date() },
         pause: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.reads = reads
        self.inbox = inbox
        self.phone = phone
        clock = now
        self.pause = pause
        moments = HelloMoments(said: phone, inbox: inbox)
        schedule = HelloSchedule(store: phone, inbox: inbox)
    }

    /// The next item in the pill's memory; the view watches it, so one found while the app is open
    /// drops when it may.
    var waiting: HelloItem? { inbox.next }

    /// The day's first open says the hello once, as the day's first pill; nil when this open isn't
    /// it (a later open, or the last pill under an hour ago). A yes marks the day said, so the view
    /// checks its own guards first. The reads all start here, so a final, a first or an acceptance
    /// found this morning makes this pill.
    func morning() -> Morning? {
        let now = clock()
        guard schedule.shouldShow(now: now, forced: HelloDrop.forced) else { return nil }
        let lastSeen = phone.double(forKey: HelloDrop.lastSeenKey)
        // DEBUG `-hello-seen-days N`: as if the last open was N days ago, so recent news and finals show.
        let seen = HelloDrop.debugSeen(now: now)
            ?? (lastSeen > 0 && !HelloDrop.forcedWelcome ? Date(timeIntervalSince1970: lastSeen) : nil)
        self.seen = seen
        let greeting = HelloDrop.hello(name: reads.name(), now: now, lastSeen: seen,
                                       yesterday: phone.string(forKey: Self.lastHelloKey) ?? "")
        phone.set(greeting.key, forKey: Self.lastHelloKey)
        readsIn = false
        Task { await reads.prepare() }
        let reading = Task {
            async let attended: Void = readAttended()
            async let finals: Void = readFinals()
            async let accepted: Void = readAccepted()
            async let joined: Void = readJoined()
            _ = await (attended, finals, accepted, joined)
            readsIn = true
        }
        return Morning(hello: greeting.text, first: seen == nil, reads: reading)
    }

    /// What goes on after the hello. It waits up to 1 s more for its reads, then says what it can:
    /// a first, a milestone, a final or an acceptance waiting takes the day's line (hello-drop 02,
    /// 03, 06); a contact who joined or what you follow added comes after your own day. nil when
    /// there's nothing to say, or when cancelled (a swipe during the hello), which writes nothing.
    func afterHello() async -> Say? {
        var waited = 0
        while !(reads.ready() && readsIn), waited < 10 {
            await pause(.milliseconds(100))
            waited += 1
        }
        guard !Task.isCancelled else { return nil }
        let waiting = inbox.next
        if let waiting, !waiting.waitsForYourDay {
            phone.set(waiting.message?.text ?? "", forKey: Self.lastLineKey)
            return say(waiting)
        }
        let day = reads.day()
        guard let line = HelloDrop.message(now: clock(), lastSeen: seen, going: day.going, groups: day.groups,
                                           town: day.town, news: day.news, waiting: waiting?.message,
                                           yesterday: phone.string(forKey: Self.lastLineKey) ?? "") else {
            phone.set("", forKey: Self.lastLineKey)
            return nil
        }
        phone.set(line.text, forKey: Self.lastLineKey)
        if let waiting, line == waiting.message { return say(waiting) }
        return .line(line)
    }

    /// Something waiting, on a later open, once it's found, or once a pill goes back up: it drops
    /// straight to it while today's 3 aren't used and the last was an hour ago. A first you made
    /// with a tap doesn't wait.
    func drop() -> Say? {
        guard let item = inbox.next else { return nil }
        let now = clock()
        guard item.yours || inbox.mayDrop(now: now) else { return nil }
        if !item.yours { inbox.dropped(now: now) }
        return say(item)
    }

    /// One item on the pill, told as it comes up.
    func say(_ item: HelloItem) -> Say? {
        saying = item.id
        inbox.tell(item.id)
        if case .moment(let moment) = item.what { return .moment(moment) }
        return item.message.map(Say.line)
    }

    /// A later open's reads, one after the other; what they find drops when it may.
    func readLater() async {
        await readAttended()
        await readFinals()
        await readAccepted()
    }

    /// The app left the screen: when, for the next hello. An item on the pill is gone before it
    /// could be read: still new, for the bell's dot and the next pill. True when there was one, so
    /// the view sends it away; the hello and a plain day's line stay up.
    func wentAway() -> Bool {
        phone.set(clock().timeIntervalSince1970, forKey: HelloDrop.lastSeenKey)
        guard let saying else { return false }
        inbox.tell(saying, false)
        return true
    }

    /// The pill is back up, so leaving the app now un-tells nothing.
    func gone() {
        saying = nil
    }

    // MARK: The reads

    /// Launch brings both the first task and an active phase: one read is enough.
    private func readAttended() async {
        guard clock().timeIntervalSince(attendedAt) > 30 else { return }
        attendedAt = clock()
        guard let count = await reads.attended() else { return }
        moments.attended(count)
    }

    /// New finals since the last read, into the pill's memory, newest first.
    private func readFinals() async {
        let started = clock()
        guard let read = await reads.finals(schedule.finalsSince(now: started)) else { return }
        schedule.finalsRead(at: started)
        for final in read { if let said = HelloItem.Final(final) { inbox.add(.final(said), at: clock()) } }
    }

    /// Friend requests you sent that were accepted, into the pill's memory at when they were, at
    /// most every 30 s: the read is the whole Friends page.
    private func readAccepted() async {
        guard clock().timeIntervalSince(acceptedAt) > 30 else { return }
        // Stamped only once a read came back, so one before the saved login is in tries again.
        guard let read = await reads.accepted() else { return }
        let now = clock()
        acceptedAt = now
        for person in read {
            inbox.add(.accepted(person), at: DateHelpers.timestamp(person.friendsSince) ?? now, now: now)
        }
    }

    /// Today's check of who in your contacts joined this past week, into the pill's memory, newest
    /// first: once a day, since each check spends one of the Contacts page's 5.
    private func readJoined() async {
        #if DEBUG
        // Each check spends one of the Contacts page's 5 a day; a forced pill checks only when asked.
        if HelloDrop.forced, !LaunchFlags.has(.helloJoined) { return }
        #endif
        // ponytail: the cut-off and the memory are the phone's, not the account's, as the
        // moments are; key them by account if two people share a phone.
        let started = clock()
        let joinedSince = phone.double(forKey: Self.joinedSinceKey)
        // A week back at most, as long as the memory keeps one, so nobody it let go is new again.
        let since = max(joinedSince > 0 ? Date(timeIntervalSince1970: joinedSince) : started,
                        started.addingTimeInterval(-Double(HelloInbox.days) * 86_400))
        guard let read = await reads.joined(since) else { return }
        // Set on the first check that worked, so allowing Contacts later doesn't make old news new.
        if phone.double(forKey: Self.joinedSinceKey) == 0 { phone.set(started.timeIntervalSince1970, forKey: Self.joinedSinceKey) }
        inbox.keepJoined(Set(read.map(\.userId)))
        for person in read {
            inbox.add(.joined(person), at: DateHelpers.timestamp(person.since) ?? started, now: started)
        }
    }
}

extension HelloPill.Reads {
    /// The session's models and its one client. Contacts read through `ContactsMatch`, as the
    /// Contacts page does.
    static func live(you: YouModel, townFeed: TownFeed, friendsBook: FriendsBook, actions: RealLifeActions,
                     supabase: Supabase) -> Self {
        Self(
            prepare: {
                if you.going == nil { await you.refresh() }
                if you.groups == nil, let groups = await you.refreshGroups() { actions.read(groups) }
            },
            ready: { townFeed.entries != nil && you.going != nil },
            day: {
                HelloPill.Day(going: you.going ?? [], groups: you.groups ?? [],
                              town: townFeed.cards.compactMap(YouCalendar.event(from:)),
                              news: townFeed.shown.compactMap { entry -> TownNews? in
                                  if case .news(let post) = entry.item { post } else { nil }
                              })
            },
            name: { YouPage.firstName(Interests.displayName()) },
            // Every Going this account has had, counted once over (hello-drop 02).
            attended: {
                guard let rows = try? await CommunityAPI(supabase)
                    .getMyGoing(from: "2000-01-01", to: Town.day(Date())) else { return nil }
                return HelloMoment.attendedCount(rows.compactMap(YouCalendar.event(from:)), now: Date())
            },
            finals: { try? await CommunityAPI(supabase).myTeamFinals(since: $0) },
            joined: { await ContactsMatch.joined(since: $0) },
            // The Friends page's own read, so someone you blocked is never said (hello-drop 06).
            accepted: {
                await friendsBook.refresh()
                return friendsBook.loaded && !friendsBook.failed ? friendsBook.accepted : nil
            })
    }
}
