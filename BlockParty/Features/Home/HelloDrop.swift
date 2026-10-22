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
    }

    struct Message: Hashable {
        let text: String
        let target: Target
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
        guard let lastSeen else { return said("Welcome") }
        if now.timeIntervalSince(lastSeen) >= 3 * 86_400 { return said("Welcome back") }
        if let holiday = holiday(now, calendar: calendar) { return said(holiday) }
        let weekday = calendar.component(.weekday, from: now)
        if weekday == 6 || weekday == 7 || weekday == 1 {
            return said("Happy \(DailyEvent.townTime("EEEE", now))")
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
    /// today, your event tomorrow, new since your last open, then today's, the weekend's
    /// (Thu to Sun) and the week's count. nil when the Town has nothing coming this week.
    /// `going` is your Going, `town` the Town feed's cards as the screen shows them.
    static func message(now: Date, lastSeen: Date?, going: [DailyEvent], groups: [TownGroup],
                        town: [DailyEvent]) -> Message? {
        let calendar = Town.calendar
        let today = Town.day(now)
        let tomorrow = Town.day(calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let mine = going.filter { !$0.item.cancelled && $0.ends > now }
        func when(_ starts: Date) -> String { Town.calendar.component(.hour, from: starts) >= 17 ? "tonight" : "today" }

        if let event = mine.filter({ Town.day($0.starts) == today }).min(by: { $0.starts < $1.starts }) {
            let at = event.timed && !event.isOn(now) ? " at \(clock(event.starts))" : ""
            return Message(text: "\(event.item.title) is today\(at)", target: .event(event.item))
        }
        let meetings = groups.filter(\.joined).compactMap { group in
            group.meetings.first { $0.day == today }.map { (group, $0) }
        }
        if let (group, meeting) = meetings.first {
            let minutes = YourDayLogic.minutes(from: meeting.time)
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
        let left = weekday == 1 ? 0 : 8 - weekday
        let days = (0...left).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
        let weekend = Set(days.filter { [6, 7, 1].contains(calendar.component(.weekday, from: $0)) }.map(Town.day))
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
        formatter.dateFormat = Town.calendar.component(.minute, from: date) == 0 ? "h" : "h:mm"
        return formatter.string(from: date)
    }

    /// Whether this launch shows it at all: on a phone, the day's first open; under DEBUG,
    /// `-hello-drop` shows it on every launch, and any other launch flag (screenshots, UI
    /// tests) never does, so other runs' frames stay as they were.
    static var allowed: Bool {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments.dropFirst().filter { $0.hasPrefix("-") }
        if flags.contains("-hello-drop") { return true }
        return flags.isEmpty
        #else
        return true
        #endif
    }

    static var forced: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-hello-drop")
        #else
        return false
        #endif
    }
}

/// The pill itself, over the whole shell. It drops on the day's first open, holds the hello
/// 1.2 s, stretches to the message, stays 4 s and goes back up. A swipe up sends it away
/// early and a tap opens what the message names.
struct HelloDropView: View {
    /// Reads anything the message needs that isn't in yet.
    let prepare: @MainActor () async -> Void
    /// Whether the Going and the Town feed are in.
    let ready: @MainActor () -> Bool
    let message: @MainActor (_ lastSeen: Date?) -> HelloDrop.Message?
    let open: @MainActor (HelloDrop.Target) -> Void

    private enum Step { case hidden, hello, message }

    @State private var step = Step.hidden
    @State private var hello = ""
    @State private var said: HelloDrop.Message?
    @State private var dragY: CGFloat = 0
    @State private var run: Task<Void, Never>?
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
    /// 4 s; DEBUG `-hello-drop-hold` keeps it 10 s, so a recorded tap lands on the message.
    static var stay: Duration {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-hello-drop-hold") { return .seconds(10) }
        #endif
        return .seconds(4)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if step != .hidden {
                pill
                    .padding(.top, -Self.aboveSafeTop)
                    .offset(y: dragY)
                    // Up past the screen's top and back the same way.
                    .transition(reduceMotion ? .opacity : .offset(y: -(Self.offscreen + Self.height)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .task { start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { start() }
            if phase == .background { lastSeen = Date().timeIntervalSince1970 }
        }
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
            if step == .message, let said {
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
        .foregroundStyle(.white)
        .frame(height: Self.height)
        .background(Hue.ink, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 9, y: 6)
        .padding(.horizontal, step == .message ? Self.side : 0)
        .contentShape(Capsule())
        .onTapGesture {
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
                    run?.cancel()
                }
                .onEnded { value in
                    // Let go still raised and heading up: away. Brought back down: it stays.
                    if value.translation.height < -12, value.predictedEndTranslation.height < -30 {
                        dismiss()
                    } else {
                        withAnimation(Motion.card) { dragY = 0 }
                        run = Task { await finish(after: Self.stay) }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(step == .message ? .isButton : [])
    }

    /// The day's first open shows it once; a second open that day shows nothing.
    private func start() {
        let today = Town.day(Date())
        guard HelloDrop.allowed, step == .hidden, run == nil,
              HelloDrop.forced || shownDay != today else { return }
        shownDay = today
        let seen = lastSeen > 0 ? Date(timeIntervalSince1970: lastSeen) : nil
        let greeting = HelloDrop.hello(name: YouPage.firstName(Interests.displayName), now: Date(),
                                       lastSeen: seen, yesterday: lastHello)
        lastHello = greeting.key
        hello = greeting.text
        run = Task {
            Task { await prepare() }
            // DEBUG `-hello-drop` waits 4 s, so a recording that starts after launch sees it drop.
            if HelloDrop.forced { try? await Task.sleep(for: .seconds(4)) }
            withAnimation(reduceMotion ? Motion.smooth : Motion.sheet) { step = .hello }
            AccessibilityNotification.Announcement(greeting.text).post()
            try? await Task.sleep(for: Self.holdHello)
            // The message waits up to 4 s more for its reads, then says what it can.
            for _ in 0..<40 where !ready() {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            guard let message = message(seen) else { dismiss(); return }
            said = message
            withAnimation(reduceMotion ? Motion.smooth : Motion.bentoExpand) { step = .message }
            AccessibilityNotification.Announcement(message.text).post()
            await finish(after: Self.stay)
        }
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
            run = nil
        }
    }
}
