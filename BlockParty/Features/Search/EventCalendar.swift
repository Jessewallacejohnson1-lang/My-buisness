//
//  EventCalendar.swift
//  Block Party — Search's Event calendar (BP app five-tabs 10): a year of the Town's public Events, one month
//  at a time (`get_town_calendar`). The Sports screen's layout in Search's light colours, with Partiful's
//  calendar: the month big with Today and round arrows, every day a disc (You's `YouDay`: a photo when it has
//  Events, a count at 2 or more), and under the month a card for the picked day, arrows either side of its
//  date, its Events as rows of photo, title, time and a heart.
//
//  Reference: Partiful's Discover calendar (BP app `references/event-calendar/partiful-month.jpg`) and the
//  Sports screen's mock, in the mock Jesse approved (https://claude.ai/artifact/1FKG4UjBecKUe1bxJk32Zt,
//  round 4). Jesse: "the whole year but one month at a time", "only show public events no news no groups",
//  "make the ui match the sports screen bubbly", "make it a lighter theme", "give it a grey fade for depth".
//

import SwiftUI

/// Sizes from the approved mock, drawn at 1 pt to the CSS pixel.
enum CalendarMetric {
    static let monthTop: CGFloat = 22
    static let monthLead: CGFloat = 18
    static let monthTrail: CGFloat = 12
    static let toolGap: CGFloat = 6
    /// The Today pill and the round arrows, Partiful's glass buttons in Search's grey.
    static let tool: CGFloat = 36
    static let todaySide: CGFloat = 14
    static let weekdaysTop: CGFloat = 16
    static let gridTop: CGFloat = 12
    /// The grid sits 18.5 pt in, as You's Calendar; the pager already keeps 16.
    static let gridInset: CGFloat = YouMetric.calendarSide - YouMetric.side
    static let cardTop: CGFloat = 12
    static let cardHead: CGFloat = 52
    static let cardHeadSide: CGFloat = 4
    static let cardBottom: CGFloat = 10
    static let rowPhoto: CGFloat = 56
    static let rowGap: CGFloat = 14
    static let rowLead: CGFloat = 16
    static let rowTrail: CGFloat = 6
    static let rowVertical: CGFloat = 8
    static let rowLines: CGFloat = 3
    static let heartCircle: CGFloat = 30
    static let heart: CGFloat = 15
    static let skeletonRows = 2
    /// The rows the picked day's card draws with the pill's tap: two show above the tab bar on an iPhone 16 Pro, a
    /// third under its glass, a fourth on the tallest iPhones (picked). The rest follow with the next step.
    static let firstRows = 4
}

/// The calendar's rules: which months, how a month lays out, which day a move lands on. Pure, so the tests
/// drive it with fixed dates.
enum EventCalendar {
    /// A year, one month at a time (Jesse, 2026-11-13): this month and the 11 after it.
    static let monthsShown = 12

    static var calendar: Calendar { YouCalendar.calendar }

    /// Town midnight on the 1st of the month `date` falls in.
    static func month(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    /// The 1st of `now`'s month and of each of the 11 after it.
    static func months(now: Date) -> [Date] {
        let first = month(of: now)
        return (0..<monthsShown).compactMap { calendar.date(byAdding: .month, value: $0, to: first) }
    }

    /// The month as the grid lays it out, weeks from Sunday: a blank (nil) for each weekday before the 1st,
    /// then every day.
    static func grid(_ month: Date) -> [Date?] {
        let first = self.month(of: month)
        let lead = calendar.component(.weekday, from: first) - calendar.firstWeekday
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        let days: [Date?] = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
        return Array(repeating: nil, count: (lead + 7) % 7) + days
    }

    /// A week of days, Sunday first: the weekday names over a grid ("Sun" … "Sat").
    static var week: [Date] {
        grid(month(of: Date())).compactMap { $0 }.prefix(7)
            .sorted { calendar.component(.weekday, from: $0) < calendar.component(.weekday, from: $1) }
    }

    /// Every day of the months, in order.
    static func days(_ months: [Date]) -> [Date] {
        months.flatMap { grid($0).compactMap { $0 } }
    }

    /// The read's Events in the calendar's order: by day, a day's timed Events soonest first and then its
    /// untimed ones, then by title.
    static func ordered(_ events: [DailyEvent]) -> [DailyEvent] {
        events.sorted {
            (calendar.startOfDay(for: $0.starts), $0.timed ? 0 : 1, $0.starts, $0.item.title)
                < (calendar.startOfDay(for: $1.starts), $1.timed ? 0 : 1, $1.starts, $1.item.title)
        }
    }

    /// The day before (`direction` -1) or after (+1) `day` that has Events, among `planned`; nil when none.
    static func step(_ day: Date, by direction: Int, planned: [Date]) -> Date? {
        direction < 0 ? planned.last { $0 < day } : planned.first { $0 > day }
    }

    /// The day picked once `month` comes to rest: the picked day when it's in that month, else today when it
    /// is, else the month's first day with Events, else its 1st. So the card always shows a day of the month
    /// on screen (the plan's review).
    static func settle(_ month: Date, picked: Date, today: Date, planned: [Date]) -> Date {
        let first = self.month(of: month)
        let inMonth = { (day: Date) in self.month(of: day) == first }
        if inMonth(picked) { return picked }
        if inMonth(today) { return today }
        return planned.first(where: inMonth) ?? first
    }

    /// Whether `page` is `current` or within `reach` pages of it in `pages`: the pages a swipe, or two swipes in a
    /// row, can bring in, the only ones worth drawing in full.
    static func near(_ page: Date, _ current: Date, in pages: [Date], reach: Int = 2) -> Bool {
        guard let a = pages.firstIndex(of: page), let b = pages.firstIndex(of: current) else { return page == current }
        return abs(a - b) <= reach
    }

    /// Whether the month pager draws `page`: the month shown, and with a `reach` every month up to that many past
    /// the furthest one shown (`furthest`, an index into `months`, or `shown` when that is further), so every month
    /// a slide can pass is there (tab-lag 02).
    static func drawn(_ page: Date, shown: Date, furthest: Int, reach: Int = 2, in months: [Date]) -> Bool {
        let index = months.firstIndex(of: page) ?? 0, at = months.firstIndex(of: shown) ?? 0
        return index == at || reach > 0 && index <= max(furthest, at) + reach
    }

    /// How far the calendar draws past the month and day on screen as `step` goes from 0 (the tap) to 4 (all), one
    /// part a frame apart, so no frame builds more than a month's grid or two day cards (tab-lag 02).
    static func reach(_ step: Int) -> (months: Int, days: Int) {
        (months: step >= 3 ? 2 : step >= 1 ? 1 : 0, days: step >= 4 ? 2 : step >= 2 ? 1 : 0)
    }

    /// How tall `month`'s grid stands: its weeks of day circles and the gaps between them, so a month drawn as
    /// nothing until it comes near takes the room its grid will (tab-lag 02).
    static func gridHeight(_ month: Date) -> CGFloat {
        let weeks = CGFloat((grid(month).count + 6) / 7)
        return weeks * YouMetric.day + (weeks - 1) * YouMetric.rowGap
    }

    /// The day pager's pages: every one up to `reach` past the last on or before `day`, so a few quick flicks on
    /// never meet a false end. A page for each of the year's ~90 days with Events held the pill's first frame, even
    /// drawn as nothing (BP app tab-lag 02). Only the far end is cut: a page added or taken before the one on
    /// screen shifted the pager under it, and it walked on by itself a day at a time.
    static func window(_ pages: [Date], through day: Date, reach: Int = 6) -> [Date] {
        guard !pages.isEmpty else { return pages }
        let at = pages.lastIndex { $0 <= day } ?? 0
        return Array(pages[...min(at + reach, pages.count - 1)])
    }

    /// "Friday, November 13, 3 Events"; "Today, …" for today. No count before the read is in (nil).
    static func spoken(_ date: Date, events: Int?, today: Bool) -> String {
        let name = (today ? "Today, " : "") + Town.format(date, "EEEEMMMMd")
        guard let events else { return name }
        return name + ", " + (events == 0 ? "nothing on" : events == 1 ? "1 Event" : "\(events) Events")
    }
}

/// The Event calendar's page, under Search's header.
struct EventCalendarView: View {
    @Environment(SearchModel.self) private var model
    @Environment(RealLifeActions.self) private var actions
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The month on screen and the day picked; nil is this month and today.
    @State private var shown: Date?
    @State private var picked: Date?
    /// The furthest month shown so far, as an index into the months: they stay drawn.
    @State private var furthest = 0
    /// The furthest day picked so far: the day pager runs on past it, and never shrinks under a move, which left
    /// it between two cards when Today came back from five months on.
    @State private var furthestDay: Date?
    /// The tap draws this month and the picked day's card; once the page has come in, the months and days one and
    /// two swipes away follow a part at a time (`EventCalendar.reach`), so the pill's first frame waits on less
    /// (tab-lag 02). Any move draws them all at once.
    @State private var step = 0
    @Namespace private var ring

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let today = EventCalendar.calendar.startOfDay(for: now)
            let months = EventCalendar.months(now: now)
            let month = shown.flatMap { months.contains($0) ? $0 : nil } ?? months[0]
            let events = model.calendar
            let byDay = YouCalendar.byDay(events ?? [])
            let planned = byDay.keys.sorted()
            let day = picked.flatMap { EventCalendar.days(months).contains($0) ? $0 : nil } ?? today
            let reach = EventCalendar.reach(step)
            VStack(spacing: 0) {
                monthRow(month, months: months, today: today, day: day, planned: planned)
                weekdays
                    .padding(.top, CalendarMetric.weekdaysTop)
                AgendaPager(pages: months, day: month, pick: { go(to: $0, today: today, day: day, planned: planned) },
                            jump: reduceMotion ? nil : Motion.smooth) { page in
                    // Drawn up to two months past the furthest one shown, so every month one or two slides can
                    // pass is there: the year at once held the pill's first frame for half a second (BP app
                    // tab-lag 02). A month past that stands in as its own height. Only the months within reach ask
                    // for their photos: a year of them at once kept the month on screen waiting behind the rest.
                    if EventCalendar.drawn(page, shown: month, furthest: furthest, reach: reach.months, in: months) {
                        let near = EventCalendar.near(page, month, in: months, reach: reach.months)
                        grid(page, byDay: near ? byDay : [:], today: today, day: day, loaded: events != nil)
                            .padding(.horizontal, CalendarMetric.gridInset)
                    } else {
                        Color.clear.frame(height: EventCalendar.gridHeight(page))
                    }
                }
                .padding(.top, CalendarMetric.gridTop)
                dayCards(events, byDay: byDay, months: months, today: today, day: day, now: now, planned: planned,
                         reach: reach.days)
                    .padding(.top, CalendarMetric.cardTop)
            }
        }
        .onChange(of: shown) { _, month in
            if let month, let index = EventCalendar.months(now: .now).firstIndex(of: month) { furthest = max(furthest, index) }
            step = 4
        }
        .onChange(of: picked) { _, day in
            if let day { furthestDay = max(furthestDay ?? day, day) }
            step = 4
        }
        // On every visit and a new account; the list on screen stays meanwhile.
        .task(id: auth.accountKey) { await model.loadCalendar() }
        .task {
            for next in 1...4 {
                guard (try? await Task.sleep(for: .milliseconds(next == 1 ? 350 : 100))) != nil else { return }
                step = max(step, next)
            }
        }
    }

    // MARK: The month

    private func monthRow(_ month: Date, months: [Date], today: Date, day: Date, planned: [Date]) -> some View {
        let index = months.firstIndex(of: month) ?? 0
        let home = index == 0 && day == today
        return HStack(spacing: CalendarMetric.toolGap) {
            monthName(month, thisYear: months[0])
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(reduceMotion ? nil : Motion.select) { shown = months[0]; picked = today }
            } label: {
                Text("Today")
                    .font(.displaySemi(14))
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, CalendarMetric.todaySide)
                    .frame(height: CalendarMetric.tool)
                    .background(Capsule().fill(Hue.surface).strokeBorder(Hue.searchChipEdge, lineWidth: 1))
                    .contentShape(Rectangle().inset(by: (CalendarMetric.tool - PageMetric.tapMin) / 2))
            }
            .buttonStyle(.press(.squish))
            .opacity(home ? 0 : 1)
            .allowsHitTesting(!home)
            .accessibilityHidden(home)
            .animation(reduceMotion ? nil : Motion.smooth, value: home)
            arrow("chevron.left", label: "Previous month", to: index > 0 ? months[index - 1] : nil,
                  today: today, day: day, planned: planned)
            arrow("chevron.right", label: "Next month", to: index + 1 < months.count ? months[index + 1] : nil,
                  today: today, day: day, planned: planned)
        }
        .padding(.leading, CalendarMetric.monthLead)
        .padding(.trailing, CalendarMetric.monthTrail)
        .padding(.top, CalendarMetric.monthTop)
    }

    /// "November", with its year after it in grey when it isn't this year's ("January 2027").
    private func monthName(_ month: Date, thisYear: Date) -> some View {
        let year = EventCalendar.calendar.component(.year, from: month)
        let other = year != EventCalendar.calendar.component(.year, from: thisYear)
        let name = Text(Town.format(month, "MMMM")).foregroundStyle(Hue.ink)
        let yearText = Text(other ? " \(String(year))" : "").foregroundStyle(Hue.inkSecondary)
        return Text("\(name)\(yearText)")
            .font(.display(26))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
            .contentTransition(.opacity)
    }

    private func arrow(_ symbol: String, label: String, to month: Date?, today: Date, day: Date,
                       planned: [Date]) -> some View {
        Button {
            if let month { go(to: month, today: today, day: day, planned: planned) }
        } label: {
            Image(systemName: symbol)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .frame(width: CalendarMetric.tool, height: CalendarMetric.tool)
                .background(Circle().fill(Hue.surface).strokeBorder(Hue.searchChipEdge, lineWidth: 1))
                .contentShape(Rectangle().inset(by: (CalendarMetric.tool - PageMetric.tapMin) / 2))
        }
        .buttonStyle(.press(.squish))
        .disabled(month == nil)
        .opacity(month == nil ? 0.3 : 1)
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
        .padding(.horizontal, YouMetric.calendarSide)
        .accessibilityHidden(true)
    }

    private func grid(_ month: Date, byDay: [Date: [DailyEvent]], today: Date, day: Date, loaded: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: YouMetric.rowGap) {
            ForEach(Array(EventCalendar.grid(month).enumerated()), id: \.offset) { _, date in
                if let date {
                    let events = byDay[date] ?? []
                    Button { pick(date, from: day) } label: {
                        YouDay(date: date, month: nil, events: events, isToday: date == today, isPast: date < today,
                               isPicked: date == day, ring: ring, disc: true)
                    }
                    .buttonStyle(.press(.squish))
                    .accessibilityLabel(EventCalendar.spoken(date, events: loaded ? events.count : nil, today: date == today))
                    .accessibilityAddTraits(date == day ? .isSelected : [])
                } else {
                    Color.clear.frame(height: YouMetric.day).accessibilityHidden(true)
                }
            }
        }
        // The ring travels to the picked day; nothing else in the grid moves.
        .animation(reduceMotion ? nil : Motion.select, value: day)
    }

    // MARK: The day

    /// The picked day's card, swiped day to day once the read is in (You's pager): every day with Events,
    /// today and the day picked. Before that, the card with its skeleton or the retry.
    @ViewBuilder
    private func dayCards(_ events: [DailyEvent]?, byDay: [Date: [DailyEvent]], months: [Date], today: Date,
                          day: Date, now: Date, planned: [Date], reach: Int) -> some View {
        if let events {
            let pages = EventCalendar.window(YouCalendar.pages(events, days: EventCalendar.days(months), today: today,
                                                               day: day), through: max(day, furthestDay ?? day))
            AgendaPager(pages: pages, day: day, pick: { pick($0, from: day) }) { page in
                // The picked day with the tap, the two each side a part at a time after (`reach`), as the months.
                if EventCalendar.near(page, day, in: pages, reach: reach) {
                    dayCard(page, events: byDay[page] ?? [], today: today, now: now, planned: planned, first: step == 0)
                } else {
                    Color.clear.frame(height: 0)
                }
            }
        } else {
            dayCard(day, events: nil, today: today, now: now, planned: planned)
                .padding(.horizontal, YouMetric.side)
        }
    }

    /// `first`: only its first rows (`CalendarMetric.firstRows`), as the pill's tap draws it: a day of 25 Events
    /// built them all with the first frame (BP app tab-lag 02).
    private func dayCard(_ day: Date, events: [DailyEvent]?, today: Date, now: Date, planned: [Date],
                         first: Bool = false) -> some View {
        let card = RoundedRectangle(cornerRadius: Radius.dayCard, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                step("chevron.left", label: "Day before with Events",
                     to: EventCalendar.step(day, by: -1, planned: planned.filter { $0 >= today }), from: day)
                let weekday = Text(day == today ? "Today" : Town.format(day, "EEEE")).font(.display(17))
                    .foregroundStyle(Hue.ink)
                let date = Text(" " + Town.format(day, day == today ? "MMM d" : "MMMM d")).font(.displaySemi(17))
                    .foregroundStyle(Hue.inkSecondary)
                Text("\(weekday)\(date)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                step("chevron.right", label: "Next day with Events",
                     to: EventCalendar.step(day, by: 1, planned: planned), from: day)
            }
            .padding(.horizontal, CalendarMetric.cardHeadSide)
            .frame(height: CalendarMetric.cardHead)
            rows(events, now: now, first: first)
        }
        .padding(.bottom, CalendarMetric.cardBottom)
        .background {
            card.fill(Hue.surface)
                .modifier(CardShadow())
                .overlay { card.strokeBorder(Hue.hairline, lineWidth: 0.5) }
        }
    }

    private func step(_ symbol: String, label: String, to target: Date?, from day: Date) -> some View {
        Button {
            if let target { pick(target, from: day) }
        } label: {
            Image(systemName: symbol)
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .disabled(target == nil)
        .opacity(target == nil ? 0.25 : 1)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func rows(_ events: [DailyEvent]?, now: Date, first: Bool) -> some View {
        if let events {
            if events.isEmpty {
                // A working line; Jesse writes the final words.
                Text("Nothing on this day")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, YouMetric.emptyLine)
            } else {
                VStack(spacing: 0) {
                    ForEach(first ? Array(events.prefix(CalendarMetric.firstRows)) : events) {
                        CalendarRow(event: $0, now: now)
                    }
                }
            }
        } else if model.calendarFailed {
            FeedRetryButton { Task { await model.loadCalendar() } }
                .padding(.vertical, YouMetric.emptyLine)
        } else {
            VStack(spacing: 0) {
                ForEach(0..<CalendarMetric.skeletonRows, id: \.self) { _ in
                    HStack(spacing: CalendarMetric.rowGap) {
                        SkeletonBlock(cornerRadius: Radius.tile)
                            .frame(width: CalendarMetric.rowPhoto, height: CalendarMetric.rowPhoto)
                        VStack(alignment: .leading, spacing: CalendarMetric.rowLines) {
                            SkeletonLine(widthFraction: 0.7)
                            SkeletonLine(widthFraction: 0.25)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CalendarMetric.rowLead)
                    .padding(.vertical, CalendarMetric.rowVertical)
                }
            }
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading the calendar")
        }
    }

    // MARK: Moving

    private func pick(_ date: Date, from current: Date) {
        guard date != current else { return }
        Haptics.selection()
        picked = date
        shown = EventCalendar.month(of: date)
    }

    /// A month the swipe or an arrow brought: the card follows to a day of it.
    private func go(to month: Date, today: Date, day: Date, planned: [Date]) {
        let next = EventCalendar.settle(month, picked: day, today: today, planned: planned)
        if month != shown { Haptics.selection() }
        shown = month
        picked = next
    }
}

/// One Event on the day's card, Partiful's row in BP's words: its photo, title and time, and the heart that
/// keeps it in You's Liked. A tap opens its Event page.
struct CalendarRow: View {
    let event: DailyEvent
    let now: Date
    /// Its photo, the gap after it and its insets: Search's by default; a place's page draws them smaller to fit
    /// inside its row (place-pages 05).
    var photo: CGFloat = CalendarMetric.rowPhoto
    var photoGap: CGFloat = CalendarMetric.rowGap
    var lead: CGFloat = CalendarMetric.rowLead
    var vertical: CGFloat = CalendarMetric.rowVertical
    var trail: CGFloat = CalendarMetric.rowTrail
    /// The heart's circle: Search's grey on its white card; a darker wash where the row sits on that grey (place-pages 05).
    var heartFill: Color = Hue.fill
    /// Set where the row sits outside a navigation stack (a place's page opened over the whole app): the tap
    /// goes here instead of pushing.
    @Environment(\.openEvent) private var openEvent
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heartTappedAt = 0

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let openEvent {
                    Button { openEvent.open(event.item) } label: { label }
                } else {
                    NavigationLink(value: event.item) { label }
                }
            }
            .buttonStyle(.press(.row))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(event.item.title), \(event.startSpoken(now: now))")
            heart
                .padding(.trailing, trail)
        }
    }

    private var label: some View {
                HStack(spacing: photoGap) {
                    Hue.fill
                        .frame(width: photo, height: photo)
                        .overlay { if let url = event.photo { FeedCardURLPhoto(url: url, loadingFill: Hue.fill) } }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    VStack(alignment: .leading, spacing: CalendarMetric.rowLines) {
                        Text(event.item.title)
                            .font(.sansSemibold(15))
                            .foregroundStyle(Hue.ink)
                            .lineLimit(1)
                        Text(event.startTime(now: now))
                            .font(.sans(13))
                            .foregroundStyle(Hue.inkSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, lead)
                .padding(.vertical, vertical)
                .contentShape(Rectangle())
    }

    private var heart: some View {
        let hearted = actions.heart(event.item).isHearted
        let failures = actions.heartFailureCount(event.item.id)
        return Button {
            heartTappedAt = failures
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.5)) {
                actions.toggleHeart(event.item)
            }
        } label: {
            FeedActionGlyphView(glyph: .heart, size: CalendarMetric.heart, filled: hearted)
                .foregroundStyle(hearted ? Hue.heart : Hue.ink)
                // The Town card's pop, out to 1.3 and back.
                .phaseAnimator([1, 1.3], trigger: hearted) { glyph, scale in
                    glyph.scaleEffect(reduceMotion ? 1 : scale)
                } animation: { _ in .spring(response: 0.3, dampingFraction: 0.5) }
                .frame(width: CalendarMetric.heartCircle, height: CalendarMetric.heartCircle)
                .background(Circle().fill(heartFill))
                .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .turnBackShake(failures: failures, shakes: !reduceMotion && heartTappedAt != failures)
        .accessibilityLabel("Like")
        .accessibilityValue(hearted ? "Liked" : "Not liked")
        .accessibilityAddTraits(hearted ? .isSelected : [])
    }
}
