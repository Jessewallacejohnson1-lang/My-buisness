//
//  HelloDrop.swift
//  Block Party — the day's first open: a flat ink pill drops from under the Dynamic Island
//  with only your hello, then stretches to the screen's width with one plain fact about your
//  town (BP app docs/plans/hello-drop, ticket 01; the board on Figma "BP · Hello drop").
//

import SwiftUI

/// What the pill says: the hello, and the one message under it.
enum HelloDrop {
    /// What a tap on the message opens.
    enum Target: Hashable {
        case event(FeedCardItem)
        case group(TownGroup)
        /// Town on that day: the Town tab.
        case town
        /// A town news post, in Instagram or Facebook (hello-drop 03).
        case news(TownNews)
        /// A contact who just joined: their page (hello-drop 04).
        case person(Neighbor)
    }

    struct Message: Hashable {
        let text: String
        let target: Target
        /// A team's final (hello-drop 03): its logo on the left, and on a win its colour behind and
        /// its colours in the confetti.
        var logo: URL? = nil
        /// The picture on the left is a photo, round and filled, not a logo on white.
        var photo = false
        var tint: UInt32? = nil
        var confetti: [UInt32]? = nil
    }

    /// A contact who joined, as the pill says it: their photo round at the left, when they have one.
    static func joined(_ person: Neighbor) -> Message {
        Message(text: "\(person.firstName) joined Block Party", target: .person(person),
                logo: person.avatarUrl.flatMap(URL.init(string:)), photo: true)
    }

    /// Your followed team's final as the pill says it; nil when it can't be worded.
    static func final(_ final: TeamFinal) -> Message? {
        guard let text = final.text, let team = final.team else { return nil }
        let colors = team.colors.isEmpty ? team.rgb.map { [$0] } ?? [] : team.colors
        return Message(text: text, target: .town, logo: team.logo,
                       tint: final.won ? colors.first : nil,
                       confetti: final.won ? colors : nil)
    }

    /// White words on a dark tint, ink on a light one (Cathedral's gold).
    nonisolated static func light(_ rgb: UInt32) -> Bool {
        let r = Double((rgb >> 16) & 0xFF), g = Double((rgb >> 8) & 0xFF), b = Double(rgb & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.62
    }

    /// The hello and the key kept for tomorrow's "never the same one two days running".
    struct Hello: Equatable {
        let text: String
        let key: String
    }

    private static let anyTime = ["Hi", "Hey", "Hello", "Hey there", "Good to see you", "There you are"]

    /// Always the first name. A special day beats the time of day, which beats the any-time
    /// ones; those stand in when the time of day's would repeat yesterday's.
    /// `lastSeen` is nil on the very first open; `yesterday` is the last hello's key.
    static func hello(name: String?, now: Date, lastSeen: Date?, yesterday: String?) -> Hello {
        let calendar = Town.calendar
        func said(_ words: String, _ key: String? = nil) -> Hello {
            Hello(text: name.map { "\(words), \($0)" } ?? words, key: key ?? words)
        }
        guard let lastSeen else { return said("Welcome to Block Party") }
        if now.timeIntervalSince(lastSeen) >= 3 * 86_400 { return said("Welcome back") }
        if let holiday = holiday(now, calendar: calendar) { return said(holiday) }
        let weekday = calendar.component(.weekday, from: now)
        if weekday == 6 || weekday == 7 || weekday == 1 {
            return said("Happy \(Town.format(now, "EEEE"))")
        }
        let hour = calendar.component(.hour, from: now)
        let timeOfDay = hour >= 22 || hour < 4 ? "Night owl"
            : hour < 11 ? "Morning"
            : hour < 17 ? "Afternoon"
            : "Evening"
        guard timeOfDay == yesterday else { return said(timeOfDay) }
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        return said(anyTime[day % anyTime.count])
    }

    /// The holidays a hello names, in the Town's calendar.
    private static func holiday(_ now: Date, calendar: Calendar) -> String? {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: now)
        switch (parts.month, parts.day) {
        case (1, 1): return "Happy New Year"
        case (7, 4): return "Happy Fourth"
        case (10, 31): return "Happy Halloween"
        case (12, 25): return "Merry Christmas"
        // Thanksgiving: November's fourth Thursday.
        case (11, let day?) where parts.weekday == 5 && (22...28).contains(day): return "Happy Thanksgiving"
        default: return nil
        }
    }

    /// The first true one, top down: your event today, your group meets today, friends going
    /// today, your event tomorrow, a contact who joined, new since your last open, then today's,
    /// the weekend's (Thu to Sun) and the week's count. nil when the Town has nothing coming this
    /// week. `going` is your Going, `town` the Town feed's cards as the screen shows them.
    static func message(now: Date, lastSeen: Date?, going: [DailyEvent], groups: [TownGroup],
                        town: [DailyEvent], news: [TownNews] = [], joined: Neighbor? = nil) -> Message? {
        let calendar = Town.gregorian
        let today = Town.day(now)
        let tomorrow = Town.day(calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let mine = going.filter { !$0.item.cancelled && $0.ends > now }
        func when(_ starts: Date) -> String { calendar.component(.hour, from: starts) >= 17 ? "tonight" : "today" }

        if let event = mine.filter({ Town.day($0.starts) == today }).min(by: { $0.starts < $1.starts }) {
            let at = event.timed && !event.isOn(now) ? " at \(clock(event.starts))" : ""
            return Message(text: "\(event.item.title) is today\(at)", target: .event(event.item))
        }
        let meetings = groups.filter(\.joined).compactMap { group in
            group.meetings.first { $0.day == today }.map { (group, $0) }
        }
        if let (group, meeting) = meetings.first {
            let minutes = EventWhen.minutes(meeting.time)
            let starts = minutes.flatMap { calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: now) }
            let text = starts.map { "\(group.name) meets \(when($0)) at \(clock($0))" } ?? "\(group.name) meets today"
            return Message(text: text, target: .group(group))
        }
        let todays = town.filter { Town.day($0.starts) == today && $0.ends > now && !$0.item.cancelled }
        if let event = todays.filter({ !$0.item.friendsGoing.isEmpty }).min(by: { $0.starts < $1.starts }) {
            let friends = event.item.friendsGoing
            let others = friends.count - 1
            let who = others == 0 ? "\(friends[0].name) is"
                : "\(friends[0].name) and \(others) friend\(others == 1 ? "" : "s") are"
            return Message(text: "\(who) going \(when(event.starts))", target: .event(event.item))
        }
        if let event = mine.filter({ Town.day($0.starts) == tomorrow }).min(by: { $0.starts < $1.starts }) {
            return Message(text: "\(event.item.title) is tomorrow", target: .event(event.item))
        }
        if let joined { return Self.joined(joined) }
        // The town's top news for you, new since your last open, in the feed's own order.
        if let lastSeen, let post = news.first(where: { ($0.published ?? .distantPast) > lastSeen }) {
            // The picture says who posted it, so the words stand alone beside it (Jesse, 2026-10-23).
            let text = post.picture == nil ? "\(post.place): \(post.words)" : post.words
            return Message(text: text, target: .news(post), logo: post.picture?.url,
                           photo: post.picture?.kind == .photo)
        }
        if let lastSeen {
            let new = town.filter { ($0.item.createdAt ?? .distantPast) > lastSeen }.count
            if new > 0 {
                let overnight = Town.day(lastSeen) == Town.day(calendar.date(byAdding: .day, value: -1, to: now) ?? now)
                return Message(text: "\(new) new event\(new == 1 ? "" : "s") \(overnight ? "overnight" : "since you were last here")",
                               target: .town)
            }
        }
        if !todays.isEmpty {
            return Message(text: "\(todays.count) thing\(todays.count == 1 ? "" : "s") happening today", target: .town)
        }
        // The days left of this week, today to Sunday, and its weekend, Friday to Sunday.
        let weekday = calendar.component(.weekday, from: now)
        // Sunday's week is today and the six days after it, so a quiet Sunday still names Monday on.
        let left = weekday == 1 ? 6 : 8 - weekday
        let days = (0...left).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
        let weekend = Set(days.prefix { calendar.component(.weekday, from: $0) != 2 }
            .filter { [6, 7, 1].contains(calendar.component(.weekday, from: $0)) }.map(Town.day))
        let week = Set(days.map(Town.day))
        let upcoming = town.filter { $0.ends > now && !$0.item.cancelled }
        if [5, 6, 7, 1].contains(weekday) {
            let count = upcoming.filter { weekend.contains(Town.day($0.starts)) }.count
            if count > 0 { return Message(text: "\(count) event\(count == 1 ? "" : "s") this weekend", target: .town) }
        }
        let count = upcoming.filter { week.contains(Town.day($0.starts)) }.count
        return count > 0 ? Message(text: "\(count) event\(count == 1 ? "" : "s") this week", target: .town) : nil
    }

    /// "4", "7:30": the hour alone, as the board words it ("Rocktoberfest is today at 4").
    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = Town.gregorian.component(.minute, from: date) == 0 ? "h" : "h:mm"
        return formatter.string(from: date)
    }

    /// Whether this launch shows it at all: on a phone, the day's first open; under DEBUG,
    /// `-hello-drop` shows it on every launch, and any other launch flag (screenshots, UI
    /// tests) never does, so other runs' frames stay as they were.
    static var allowed: Bool {
        #if DEBUG
        forced || later || debugMoment != nil || debugFinal != nil
            || !ProcessInfo.processInfo.arguments.dropFirst().contains { $0.hasPrefix("-") }
        #else
        return true
        #endif
    }

    static var forced: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-hello-drop") || arguments.contains("-hello-welcome")
        #else
        return false
        #endif
    }

    /// DEBUG `-hello-later`: a later open, the day's hello already said. 8 s after launch a
    /// sample final and a sample contact who joined are found at once: the final drops, and the
    /// contact waits behind the bell for the hour between pills (hello-drop 05).
    static var later: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-hello-later")
        #else
        return false
        #endif
    }

    /// DEBUG `-hello-welcome`: the very first open's welcome, whatever this phone has seen.
    static var forcedWelcome: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-hello-welcome")
        #else
        return false
        #endif
    }

    /// DEBUG `-hello-final win|loss`: Saint John's final against Gustavus drops 8 s after launch.
    static var debugFinal: Bool? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-hello-final"), flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1] == "win"
        #else
        return nil
        #endif
    }

    /// DEBUG `-hello-moment <name>` (`firstEvent`, `tenthEvent`, `firstFriend`...): that moment
    /// drops 8 s after launch, said or not, and the day's hello stays away.
    static var debugMoment: HelloMoment? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-hello-moment"), flag + 1 < arguments.count else { return nil }
        return HelloMoment(rawValue: arguments[flag + 1])
        #else
        return nil
        #endif
    }
}

/// The pill itself, over the whole shell. It drops on the day's first open, holds the hello
/// 1.2 s, stretches to the message, stays 4 s and goes back up. A swipe up sends it away
/// early and a tap opens what the message names. A later open drops it straight to something
/// new from its memory (`HelloInbox`): at most 3 pills a day, an hour apart (hello-drop 05).
struct HelloDropView: View {
    /// Reads anything the message needs that isn't in yet.
    let prepare: @MainActor () async -> Void
    /// Whether the Going and the Town feed are in.
    let ready: @MainActor () -> Bool
    let message: @MainActor (_ lastSeen: Date?, _ joined: Neighbor?) -> HelloDrop.Message?
    let open: @MainActor (HelloDrop.Target) -> Void
    /// Events attended (hello-drop 02), read on each open; nil when the read failed.
    let attended: @MainActor () async -> Int?
    /// Your followed teams' finals read since a time (hello-drop 03), newest first.
    /// nil when the read failed.
    let finals: @MainActor (_ since: Date) async -> [TeamFinal]?
    /// Contacts who joined since a time, newest first (hello-drop 04); nil when it can't check.
    let joined: @MainActor (_ since: Date) async -> [Neighbor]?

    private enum Step { case hidden, hello, message }

    @State private var step = Step.hidden
    @State private var hello = ""
    @State private var said: HelloDrop.Message?
    @State private var dragY: CGFloat = 0
    @State private var run: Task<Void, Never>?
    /// A first or milestone on the pill: it hugs its words and the tick (hello-drop 02).
    @State private var moment: HelloMoment?
    @State private var tick = 0
    @State private var confetti = 0
    @State private var attendedAt = Date.distantPast
    /// A final's confetti colours (empty: BP's).
    @State private var confettiColors: [UInt32] = []
    @AppStorage("helloDrop.finalsSince") private var finalsSince: Double = 0
    /// The day's first open's reads are back: attended, finals and contacts.
    @State private var readsIn = false
    /// Contacts joining after this are said: the first check's time, so nobody already here is.
    @AppStorage("helloDrop.joinedSince") private var joinedSince: Double = 0
    /// The item on the pill now, told once it's up.
    @State private var saying: String?
    private let moments = HelloMoments.shared
    private let inbox = HelloInbox.shared
    @AppStorage("helloDrop.day") private var shownDay = ""
    @AppStorage("helloDrop.lastHello") private var lastHello = ""
    /// When the app last left the screen; 0 before the very first open.
    @AppStorage("helloDrop.lastSeen") private var lastSeen: Double = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The pill's top sits 6 pt above the safe area's: 56 pt on a 16 Pro, just under its island.
    static let aboveSafeTop: CGFloat = 6
    static let height: CGFloat = 58
    /// More than any phone's safe area top: hidden, the pill waits this far above it.
    static let offscreen: CGFloat = 100
    static let side: CGFloat = 12
    static let holdHello: Duration = .seconds(1.2)
    /// 4 s; 10 s with VoiceOver on, so there's time to reach it and open it. DEBUG
    /// `-hello-drop-hold` keeps it 10 s too, so a recorded tap lands on the message.
    static var stay: Duration {
        if UIAccessibility.isVoiceOverRunning { return .seconds(10) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-hello-drop-hold") { return .seconds(10) }
        #endif
        return .seconds(4)
    }

    var body: some View {
        ZStack(alignment: .top) {
            HelloConfetti(burst: confetti, colors: confettiColors)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if step != .hidden {
                pill
                    .padding(.top, topGap)
                    .offset(y: dragY)
                    // Up past the screen's top and back the same way.
                    .transition(reduceMotion ? .opacity : .offset(y: -(Self.offscreen + Self.height)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .task {
            #if DEBUG
            if let won = HelloDrop.debugFinal {
                try? await Task.sleep(for: .seconds(8))
                if let final = HelloItem.Final(TeamFinal.sample(won: won)) {
                    run = Task { await say(HelloItem(what: .final(final), at: Date()), fromHello: false) }
                }
                return
            }
            if let shown = HelloDrop.debugMoment {
                try? await Task.sleep(for: .seconds(8))
                run = Task { await say(HelloItem(what: .moment(shown), at: Date()), fromHello: false) }
                return
            }
            if HelloDrop.later {
                shownDay = Town.day(Date())
                try? await Task.sleep(for: .seconds(8))
                for item in HelloInbox.samples(now: Date()) where item.rank > 0 { inbox.add(item.what) }
                return
            }
            #endif
            if !start() { await later() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, HelloDrop.debugMoment == nil, HelloDrop.debugFinal == nil, !start() {
                Task { await later() }
            }
            if phase == .background {
                lastSeen = Date().timeIntervalSince1970
                // Gone before it could be read: still new, for the bell's dot and the next pill.
                if let saying {
                    inbox.tell(saying, false)
                    dismiss()
                }
            }
        }
        // Something found while the app is open drops when it may: a first you made at once.
        .onChange(of: inbox.next?.id) { _, next in
            if next != nil { dropNext() }
        }
    }

    /// Under a Dynamic Island (a safe area top over 50 pt) it rides 6 pt into the safe area's
    /// top; on a phone with a notch or a home button, where that is the status bar, 8 pt under it.
    private var topGap: CGFloat {
        let top = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.top ?? 62
        return top > 50 ? -Self.aboveSafeTop : 8
    }

    private var pill: some View {
        ZStack {
            if step == .hello {
                Text(hello)
                    .font(.sansSemibold(17))
                    .padding(.horizontal, 24)
                    // Gone before the message comes in, so the two never show at once.
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            if step == .message, let moment {
                HStack(spacing: 10) {
                    Text(moment.text)
                        .font(.sansSemibold(15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HelloTick(stage: tick)
                }
                .padding(.leading, 22)
                .padding(.trailing, 10)
                .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.2).delay(0.12)),
                                        removal: .opacity))
            } else if step == .message, let said, let logo = said.logo {
                HStack(spacing: 10) {
                    Group {
                        if said.photo {
                            FeedAuthorAvatar(url: logo, name: "", side: 34)
                        } else {
                            LogoDisc(logo: logo, initial: "", logoSide: 26, letter: .sansSemibold(12))
                        }
                    }
                    .frame(width: 34, height: 34)
                    Text(said.text)
                        .font(.sansSemibold(15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // Hugs its picture and words, as a pill with the tick does (Jesse, 2026-10-26).
                .padding(.leading, 12)
                .padding(.trailing, 22)
                .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.2).delay(0.12)),
                                        removal: .opacity))
            } else if step == .message, let said {
                Text(said.text)
                    .font(.sansSemibold(15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.2).delay(0.12)),
                                            removal: .opacity))
            }
        }
        .foregroundStyle(said?.tint.map { HelloDrop.light($0) } == true ? Hue.ink.onLightCanvas : .white)
        .frame(height: Self.height)
        .background(said?.tint.map { Color(hex: $0) } ?? Hue.ink, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 9, y: 6)
        .padding(.horizontal, step == .message && moment == nil ? Self.side : 0)
        .contentShape(Capsule())
        .onTapGesture {
            if moment != nil { dismiss(); return }
            guard step == .message, let said else { return }
            open(said.target)
            dismiss()
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    // Up follows the finger; down only stretches a little, then stops.
                    let y = value.translation.height
                    dragY = y < 0 ? y : y / 6
                    // Held on the message, it stays; held on the hello, the message still comes.
                    if step == .message { run?.cancel() }
                }
                .onEnded { value in
                    // Let go still raised and heading up: away. Brought back down: it stays.
                    if value.translation.height < -12, value.predictedEndTranslation.height < -30 {
                        dismiss()
                    } else {
                        withAnimation(Motion.card) { dragY = 0 }
                        if step == .message { run = Task { await finish(after: Self.stay) } }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(step == .message && moment == nil ? .isButton : [])
    }

    /// The day's first open says the hello once, as the day's first pill; false when this open
    /// isn't it (a later open, or the last pill under an hour ago).
    @discardableResult
    private func start() -> Bool {
        let now = Date()
        let today = Town.day(now)
        guard HelloDrop.allowed, HelloDrop.debugMoment == nil, HelloDrop.debugFinal == nil, !HelloDrop.later,
              step == .hidden, run == nil,
              HelloDrop.forced || (shownDay != today && inbox.mayDrop(now: now)) else { return false }
        shownDay = today
        if !HelloDrop.forced { inbox.dropped(now: now) }
        var seen = lastSeen > 0 && !HelloDrop.forcedWelcome ? Date(timeIntervalSince1970: lastSeen) : nil
        #if DEBUG
        // `-hello-seen-days N`: as if the last open was N days ago, so recent news and finals show.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-hello-seen-days"), flag + 1 < arguments.count,
           let days = Double(arguments[flag + 1]) {
            seen = Date().addingTimeInterval(-days * 86_400)
        }
        #endif
        let greeting = HelloDrop.hello(name: YouPage.firstName(Interests.displayName), now: Date(),
                                       lastSeen: seen, yesterday: lastHello)
        lastHello = greeting.key
        hello = greeting.text
        readsIn = false
        run = Task {
            Task { await prepare() }
            // All three at once, so a final or a first found this morning makes this pill.
            Task {
                async let attended: Void = checkAttended()
                async let finals: Void = checkFinals()
                async let joined: Void = checkJoined()
                _ = await (attended, finals, joined)
                readsIn = true
            }
            // DEBUG `-hello-drop` waits 8 s, so a recording that starts after launch (eyes.py
            // settles 6 s) sees it drop.
            if HelloDrop.forced { try? await Task.sleep(for: .seconds(8)) }
            withAnimation(reduceMotion ? Motion.smooth : Motion.sheet) { step = .hello }
            AccessibilityNotification.Announcement(greeting.text).post()
            // The very first open: "Welcome to Block Party" with confetti (hello-drop 02).
            if seen == nil {
                if !reduceMotion { confetti += 1 }
                Haptics.success()
            }
            try? await Task.sleep(for: Self.holdHello)
            // The message waits up to 1 s more for its reads, then says what it can.
            var waited = 0
            while !(ready() && readsIn), waited < 10 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            guard !Task.isCancelled else { return }
            // A first, a milestone or a final waiting takes the day's line (hello-drop 02, 03); a
            // contact who joined comes after your own day (`HelloDrop.message`).
            let waiting = inbox.next
            var joined: Neighbor?
            if let waiting {
                if case .joined(let person) = waiting.what {
                    joined = person
                } else {
                    await say(waiting, fromHello: true)
                    return
                }
            }
            guard let message = message(seen, joined) else { dismiss(); return }
            if case .person = message.target, let waiting {
                saying = waiting.id
                inbox.tell(waiting.id)
            }
            said = message
            withAnimation(reduceMotion ? Motion.smooth : Motion.bentoExpand) { step = .message }
            AccessibilityNotification.Announcement(message.text).post()
            await finish(after: Self.stay)
        }
        return true
    }

    /// A later open: something new waiting drops, then the reads look for more.
    private func later() async {
        dropNext()
        await checkAttended()
        await checkFinals()
    }

    /// Something waiting, on a later open, once it's found, or once a pill goes back up: the pill
    /// drops straight to it while today's 3 aren't used and the last was an hour ago. A first you
    /// made with a tap doesn't wait.
    private func dropNext() {
        let now = Date()
        guard HelloDrop.allowed, HelloDrop.debugMoment == nil, HelloDrop.debugFinal == nil,
              scenePhase != .background, step == .hidden, run == nil, let item = inbox.next else { return }
        let yours = if case .moment(let moment) = item.what { moment.yours } else { false }
        guard yours || inbox.mayDrop(now: now) else { return }
        if !yours { inbox.dropped(now: now) }
        run = Task { await say(item, fromHello: false) }
    }

    /// One item on the pill, from the hello or straight down: a first or milestone with its
    /// tick, else its line, a win with its team's confetti. Told as it comes up.
    private func say(_ item: HelloItem, fromHello: Bool) async {
        saying = item.id
        inbox.tell(item.id)
        let comeIn = reduceMotion ? Motion.smooth : fromHello ? Motion.bentoExpand : Motion.sheet
        if case .moment(let next) = item.what {
            moment = next
            tick = 0
            withAnimation(comeIn) { step = .message }
            AccessibilityNotification.Announcement(next.text).post()
            try? await Task.sleep(for: .seconds(fromHello ? 0.3 : 0.38))
            await celebrate(next)
        } else if let message = item.message {
            said = message
            withAnimation(comeIn) { step = .message }
            AccessibilityNotification.Announcement(message.text).post()
            if let colors = message.confetti {
                try? await Task.sleep(for: .seconds(0.3))
                confettiColors = colors
                if !reduceMotion { confetti += 1 }
                Haptics.success()
            }
        }
        await finish(after: Self.stay)
    }

    /// New finals since the last read, into the pill's memory, newest first.
    private func checkFinals() async {
        guard HelloDrop.allowed else { return }
        // An hour back from the last read: the finals job stamps a final when its run starts and
        // saves it minutes later, so a read in between would step past it. The memory stops repeats.
        let since = finalsSince > 0 ? Date(timeIntervalSince1970: finalsSince - 3600) : Date().addingTimeInterval(-36 * 3600)
        let started = Date()
        guard let read = await finals(since) else { return }
        finalsSince = started.timeIntervalSince1970
        for final in read { if let said = HelloItem.Final(final) { inbox.add(.final(said)) } }
    }

    /// Today's check of who in your contacts joined this past week, into the pill's memory, newest
    /// first: once a day, since each check spends one of the Contacts page's 5.
    private func checkJoined() async {
        #if DEBUG
        // Each check spends one of the Contacts page's 5 a day; a forced pill checks only when asked.
        if HelloDrop.forced, !ProcessInfo.processInfo.arguments.contains("-hello-joined") { return }
        #endif
        // ponytail: the cut-off and the memory are the phone's, not the account's, as the
        // moments are; key them by account if two people share a phone.
        let started = Date()
        // A week back at most, as long as the memory keeps one, so nobody it let go is new again.
        let since = max(joinedSince > 0 ? Date(timeIntervalSince1970: joinedSince) : started,
                        started.addingTimeInterval(-Double(HelloInbox.days) * 86_400))
        guard let read = await joined(since) else { return }
        // Set on the first check that worked, so allowing Contacts later doesn't make old news new.
        if joinedSince == 0 { joinedSince = started.timeIntervalSince1970 }
        inbox.keepJoined(Set(read.map(\.userId)))
        for person in read {
            inbox.add(.joined(person), at: DateHelpers.timestamp(person.since) ?? started, now: started)
        }
    }

    /// The tick, its haptics, then confetti for the 10th and 100th.
    private func celebrate(_ moment: HelloMoment) async {
        await HelloTick.play(reduceMotion: reduceMotion, stage: $tick)
        if moment.confetti, !reduceMotion { confetti += 1 }
    }

    private func checkAttended() async {
        // Launch brings both the first task and an active phase: one read is enough.
        guard HelloDrop.allowed, Date().timeIntervalSince(attendedAt) > 30 else { return }
        attendedAt = Date()
        guard let count = await attended() else { return }
        moments.attended(count)
    }

    private func finish(after wait: Duration) async {
        try? await Task.sleep(for: wait)
        guard !Task.isCancelled else { return }
        dismiss()
    }

    /// Back up the way it came, from wherever the finger left it.
    private func dismiss() {
        run?.cancel()
        withAnimation(reduceMotion ? Motion.smooth : Motion.sheet) {
            step = .hidden
        } completion: {
            dragY = 0
            said = nil
            moment = nil
            tick = 0
            run = nil
            saying = nil
            confettiColors = []
            // One found while this pill was up comes next, when it may.
            dropNext()
        }
    }
}
