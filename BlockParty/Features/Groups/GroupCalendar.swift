//
//  GroupCalendar.swift
//  Block Party — the Group page's Calendar (BP app docs/plans/start-a-group, ticket 05; SPEC decisions 10 and 11,
//  Figma frame 6 beside Weverse's calendar). In Coming up's place: the month with ‹ ›, as far ahead as the Group has
//  Events, its repeating get-togethers 4 months ahead (`get_group_calendar`), each day You's Calendar day (`YouDay`:
//  a day with an Event shows its photo). A tap on a day lists its Events and get-togethers under the month in the
//  Agenda's cards. The + (for whoever Edit group's Who can add events lets in) opens New post's New event with the
//  Group as host; "Add when you meet", the Admin's, sets the repeats (`set_group_meets`). Your own Calendar doesn't
//  change: a Group's Event shows there only after Going.
//

import SwiftUI

/// The Calendar's rules, pure so the tests drive them with fixed dates.
enum GroupCalendar {
    /// The Group's Events and get-togethers as the Calendar's plans, in its order. An Event on a get-together's day
    /// takes its place, as Coming up did: it is that get-together with a page of its own (rsvp-and-groups 10). A
    /// get-together wears the Group's own photo, so its day shows it as the mock's Tuesday does.
    static func plans(_ group: TownGroup, meetings: [TownGroup.Meeting], events: [FeedCardItem]) -> [DailyEvent] {
        let found = events.compactMap { YouCalendar.event(from: $0) }
        let taken = Set(found.map { YouCalendar.calendar.startOfDay(for: $0.starts) })
        let photo = group.photos.first?.url ?? group.imageUrl
        let together = meetings.compactMap { YouCalendar.event(group, $0, photo: photo) }
            .filter { !taken.contains(YouCalendar.calendar.startOfDay(for: $0.starts)) }
        return EventCalendar.ordered(found + together)
    }

    /// The months ‹ › step through: this month, then each later one with a plan.
    static func months(_ plans: [DailyEvent], today: Date) -> [Date] {
        Array(Set(PlaceEvents.months(plans, today: today) + [EventCalendar.month(of: today)])).sorted()
    }

    /// The day picked first: the next with a plan, today included; nil with nothing ahead.
    static func first(_ plans: [DailyEvent], today: Date) -> Date? { PlaceEvents.next(plans, today: today) }

    #if DEBUG
    /// INVENTED, for `-group-admin`'s sample Group: Tuesday get-togethers at 6:30 for 4 months, and two made-up Events.
    static func sample(now: Date) -> (meetings: [TownGroup.Meeting], events: [FeedCardItem]) {
        let calendar = YouCalendar.calendar
        let today = calendar.startOfDay(for: now)
        let days = (0..<120).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let meetings = days.filter { calendar.component(.weekday, from: $0) == 3 }
            .map { TownGroup.Meeting(what: "Get-together", day: Town.day($0), time: "18:30") }
        let saturday = days.first { calendar.component(.weekday, from: $0) == 7 } ?? today
        let rows: [(Date, String, String, String)] = [
            (saturday, "Holiday quilt swap", "10:00 AM", "interest-shopping"),
            (calendar.date(byAdding: .day, value: 14, to: saturday) ?? saturday, "Mending clinic", "1:00 PM", "downtown"),
        ]
        let events = rows.enumerated().map { index, row in
            FeedCardItem(UpcomingEvent(id: "group-sample-\(index)", title: row.1, eventDate: Town.day(row.0),
                                       startTime: row.2, location: "Resurrection Lutheran", goingCount: 0, createdAt: "",
                                       imageUrl: Bundle.main.url(forResource: row.3, withExtension: "jpg")?.absoluteString))
        }
        return (meetings, events)
    }
    #endif
}

/// Sizes from Figma frame 6, 1 pt to the mock's pixel.
enum GroupCalendarMetric {
    static let top: CGFloat = 26
    /// The + : a 36 pt ink circle.
    static let plus: CGFloat = 36
    static let navGap: CGFloat = 4
    static let weekdaysTop: CGFloat = 12
    static let day: CGFloat = 44
    static let dayNumber: CGFloat = 19
    static let gridTop: CGFloat = 10
    static let rowGap: CGFloat = 8
    static let dayHeadTop: CGFloat = 20
    static let dayHeadBottom: CGFloat = 8
    static let dayHeadTracking: CGFloat = 0.8
    static let meetsTop: CGFloat = 14
    static let meetsGap: CGFloat = 8
}

/// The Calendar on the Group page: the month, the picked day's list, Add when you meet.
struct GroupCalendarView: View {
    let plans: [DailyEvent]
    /// Shows the +: the caller may add an Event.
    let adds: Bool
    /// Shows Add when you meet: the Admin's.
    let admin: Bool
    /// The Group already says when it meets: the row reads Edit.
    let meets: Bool
    let add: () -> Void
    let setMeets: () -> Void
    let open: (FeedCardItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Date?
    @State private var picked: Date?
    @Namespace private var ring

    private typealias Size = GroupCalendarMetric

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = EventCalendar.calendar.startOfDay(for: context.date)
            let months = GroupCalendar.months(plans, today: today)
            let first = GroupCalendar.first(plans, today: today)
            let month = shown.flatMap { months.contains($0) ? $0 : nil }
                ?? first.map { EventCalendar.month(of: $0) } ?? months[0]
            let byDay = YouCalendar.byDay(plans)
            // The picked day while its month shows, else the month's next day with a plan.
            let day = picked.flatMap { EventCalendar.month(of: $0) == month ? $0 : nil }
                ?? PlaceEvents.landing(month, events: plans, today: today)
            VStack(alignment: .leading, spacing: 0) {
                head(month, months: months, today: today)
                weekdays.padding(.top, Size.weekdaysTop)
                grid(month, byDay: byDay, today: today, day: day)
                    .padding(.top, Size.gridTop)
                if let day, let list = byDay[day], !list.isEmpty {
                    dayHead(day)
                    AgendaCards(events: list, now: context.date, open: open)
                        .id(day)
                        .transition(.opacity)
                }
                if admin { meetsRow }
            }
            .animation(reduceMotion ? nil : Motion.smooth, value: day)
        }
    }

    // MARK: The month

    /// "Calendar", ‹ November ›, and the +.
    private func head(_ month: Date, months: [Date], today: Date) -> some View {
        let index = months.firstIndex(of: month) ?? 0
        let thisYear = EventCalendar.calendar.component(.year, from: today)
        let year = EventCalendar.calendar.component(.year, from: month)
        return HStack(spacing: 0) {
            Text("Calendar")
                .font(.displaySemi(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            arrow("chevron.left", label: "Previous month", to: index > 0 ? months[index - 1] : nil, today: today)
            Text(Town.format(month, year == thisYear ? "MMMM" : "MMMM yyyy"))
                .font(.sansSemibold(16))
                .foregroundStyle(Hue.ink)
                .contentTransition(.opacity)
                .frame(minWidth: 84)
            arrow("chevron.right", label: "Next month", to: index + 1 < months.count ? months[index + 1] : nil,
                  today: today)
            Spacer(minLength: 0)
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.glyph(17, weight: .semibold))
                    .foregroundStyle(Hue.paper)
                    .frame(width: Size.plus, height: Size.plus)
                    .background(Circle().fill(Hue.ink))
                    .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .opacity(adds ? 1 : 0)
            .allowsHitTesting(adds)
            .accessibilityHidden(!adds)
            .accessibilityLabel("New event")
            .padding(.trailing, (Size.plus - PageMetric.tapMin) / 2)
        }
        .padding(.top, Size.top)
    }

    private func arrow(_ symbol: String, label: String, to month: Date?, today: Date) -> some View {
        Button {
            guard let month else { return }
            Haptics.selection()
            withAnimation(reduceMotion ? nil : Motion.smooth) {
                shown = month
                picked = PlaceEvents.landing(month, events: plans, today: today)
            }
        } label: {
            Image(systemName: symbol)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .disabled(month == nil)
        .opacity(month == nil ? 0.25 : 1)
        .accessibilityLabel(label)
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(EventCalendar.week, id: \.self) { weekday in
                Text(Town.format(weekday, "EEE"))
                    .font(.sansMedium(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func grid(_ month: Date, byDay: [Date: [DailyEvent]], today: Date, day: Date?) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: Size.rowGap) {
            ForEach(Array(EventCalendar.grid(month).enumerated()), id: \.offset) { _, date in
                if let date {
                    let events = byDay[date] ?? []
                    Button {
                        guard !events.isEmpty, date != day else { return }
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : Motion.select) { picked = date }
                    } label: {
                        YouDay(date: date, month: nil, events: events, isToday: date == today, isPast: date < today,
                               isPicked: date == day, ring: ring, side: Size.day, number: Size.dayNumber)
                            .frame(maxWidth: .infinity, minHeight: PageMetric.tapMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.squish))
                    .disabled(events.isEmpty)
                    .accessibilityLabel(EventCalendar.spoken(date, events: events.count, today: date == today))
                    .accessibilityAddTraits(date == day ? .isSelected : [])
                } else {
                    Color.clear.frame(height: PageMetric.tapMin).accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: The day

    /// "TUESDAY, NOV 24", the mock's line over the day's cards.
    private func dayHead(_ day: Date) -> some View {
        Text(Town.format(day, "EEEEMMMd").uppercased())
            .font(.sansSemibold(13))
            .tracking(Size.dayHeadTracking)
            .foregroundStyle(Hue.inkSecondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Size.dayHeadTop)
            .padding(.bottom, Size.dayHeadBottom)
            .contentTransition(.opacity)
    }

    private var meetsRow: some View {
        Button(action: setMeets) {
            Label(meets ? "Edit when you meet" : "Add when you meet", systemImage: "repeat")
                .labelStyle(MeetsLabelStyle())
                .font(.sansMedium(17))
                .foregroundStyle(Hue.ink)
                .frame(minHeight: PageMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
        .padding(.top, Size.meetsTop - (PageMetric.tapMin - 22) / 2)
    }
}

/// The glyph 8 pt before its words, as the mock's.
private struct MeetsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: GroupCalendarMetric.meetsGap) {
            configuration.icon.font(.glyph(16, weight: .semibold))
            configuration.title
        }
    }
}

// MARK: - Add when you meet

/// The sheet's picks as `set_group_meets` takes them. Pure, so a test reads what goes out.
nonisolated struct GroupMeetsDraft: Equatable {
    /// How often, the SPEC's three (decision 10).
    enum Often: CaseIterable {
        case weekly, firstAndThird, monthly

        var title: String {
            switch self {
            case .weekly: "Every week"
            case .firstAndThird: "1st and 3rd"
            case .monthly: "Once a month"
            }
        }
    }

    /// Postgres's day names, the week from Sunday (`clubs.meets`).
    static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    var days: Set<String> = []
    var often = Often.weekly
    /// Once a month: which week of the month, 1st to 4th.
    var week = 1
    /// 6 PM, a picked start: most groups here meet in the evening.
    var time: Date = Town.gregorian.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    var place = ""

    var ready: Bool { !days.isEmpty }
    var sentDays: [String] { Self.weekdays.filter(days.contains) }
    var weeks: [Int]? {
        switch often {
        case .weekly: nil
        case .firstAndThird: [1, 3]
        case .monthly: [week]
        }
    }
    var clock: String { NewEventDraft.clock(time) }
    var sentPlace: String? {
        let place = String(place.trimmingCharacters(in: .whitespacesAndNewlines).prefix(NewEventDraft.placeLimit))
        return place.isEmpty ? nil : place
    }
}

/// Add when you meet: Apple's sheet with Cancel and Save over a grouped form, the Clock app's Repeat rows for the
/// days, then how often, the time and the Place (New event's list).
struct GroupMeetsSheet: View {
    let group: TownGroup
    let places: [SearchItem]
    /// Saved: the when line the server wrote, and the Place.
    let saved: (String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = GroupMeetsDraft()
    @State private var saving = false
    @State private var failures = 0
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Days") {
                    ForEach(GroupMeetsDraft.weekdays.indices, id: \.self) { index in
                        let day = GroupMeetsDraft.weekdays[index]
                        Button {
                            Haptics.selection()
                            if draft.days.contains(day) { draft.days.remove(day) } else { draft.days.insert(day) }
                        } label: {
                            HStack {
                                Text(Town.gregorian.weekdaySymbols[index]).foregroundStyle(Hue.ink)
                                Spacer()
                                if draft.days.contains(day) {
                                    Image(systemName: "checkmark").font(.glyph(15, weight: .semibold)).foregroundStyle(Hue.ink)
                                }
                            }
                        }
                        .accessibilityAddTraits(draft.days.contains(day) ? .isSelected : [])
                    }
                }
                Section {
                    Picker("How often", selection: $draft.often) {
                        ForEach(GroupMeetsDraft.Often.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if draft.often == .monthly {
                        Picker("Week", selection: $draft.week) {
                            ForEach(1...4, id: \.self) { Text(["1st", "2nd", "3rd", "4th"][$0 - 1]).tag($0) }
                        }
                    }
                    DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)
                    NavigationLink {
                        NewEventPlace(places: places, place: $draft.place)
                    } label: {
                        LabeledContent(NewEventCopy.place, value: draft.sentPlace ?? NewEventCopy.addPlace)
                    }
                } footer: {
                    if let problem { Text(problem) }
                }
            }
            .navigationTitle("When you meet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!draft.ready)
                            .turnBackShake(failures: failures, shakes: true)
                    }
                }
            }
        }
        .tint(Hue.ink)
        .interactiveDismissDisabled(saving)
        .animation(Motion.smooth, value: draft.often)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let schedule = try await CommunityAPI(auth: AuthStore.shared).setGroupMeets(group.id, draft)
            saved(schedule, draft.sentPlace)
            dismiss()
        } catch {
            problem = NewEventCopy.offline
            failures += 1
            Haptics.error()
        }
    }
}
