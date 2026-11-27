//
//  PlaceEvents.swift
//  Block Party — a place's Events on its business page, under its About (BP app profile-left 05): each day's title
//  ("Today / Wednesday") and its Events with picture, title, time and price tag, the next ten and then See all. The
//  calendar button beside "Events" puts the place's month in the list's place (place-pages 05's month, Search's
//  Event calendar made small: 40 pt discs, past days faded, the next Event's day picked, only months with Events),
//  and the picked day's Events. No section when nothing is coming up. A repeat shows once at its next date with
//  "+24 more dates", whose tap opens those dates under it (profile-left 06).
//
//  Reference: the approved mock (https://www.figma.com/design/a0MSz1SJyLe704coW2x8lc?node-id=3-2, Jesse,
//  2026-11-25) and, for the month, place-pages 05's (2026-11-16: "yes"). The Events are the
//  Event calendar's own (`get_town_calendar`), so who sees what stays the calendar's rule; the place's are those
//  found at it (`club_events.place_entry_id`).
//

import SwiftUI

/// The list's and the month's rules, pure so the tests drive them with fixed dates.
enum PlaceEvents {
    static var calendar: Calendar { EventCalendar.calendar }

    /// The calendar's Events found at the place, in the calendar's order.
    static func events(_ all: [DailyEvent], ids: Set<String>) -> [DailyEvent] {
        EventCalendar.ordered(all.filter { ids.contains($0.id) })
    }

    /// The months with an Event, from this month on: the arrows go only to these (the mock's).
    static func months(_ events: [DailyEvent], today: Date) -> [Date] {
        let first = EventCalendar.month(of: today)
        return Set(events.map { EventCalendar.month(of: $0.starts) }).filter { $0 >= first }.sorted()
    }

    /// The day picked first: the next day with an Event, today included.
    static func next(_ events: [DailyEvent], today: Date) -> Date? {
        events.first { $0.starts >= today }.map { calendar.startOfDay(for: $0.starts) }
    }

    /// The day an arrow lands on in `month`: its first day with an Event from today on.
    static func landing(_ month: Date, events: [DailyEvent], today: Date) -> Date? {
        events.lazy.map { calendar.startOfDay(for: $0.starts) }
            .first { $0 >= today && EventCalendar.month(of: $0) == month }
    }

    // MARK: The list (profile-left 05)

    /// The rows before "See all".
    static let shown = 10

    /// The list's rows: the place's Events not over by `now`, in the calendar's order. A repeat, the same title
    /// (letter case aside) at the same start time, shows once at its next date; its dates on later days are its
    /// `more`, one a day (profile-left 06). A second one on a day the repeat already has is a row of its own.
    static func rows(_ events: [DailyEvent], now: Date) -> [PlaceEventRow] {
        var rows: [PlaceEventRow] = []
        var index: [String: Int] = [:]
        for event in events where event.ends > now {
            let key = repeatKey(event)
            let day = calendar.startOfDay(for: event.starts)
            if let at = index[key], calendar.startOfDay(for: (rows[at].more.last ?? rows[at].event).starts) < day {
                rows[at].more.append(event)
            } else {
                rows.append(PlaceEventRow(event: event, id: index[key] == nil ? key : key + "|" + event.id))
                if index[key] == nil { index[key] = rows.count - 1 }
            }
        }
        return rows
    }

    /// What makes Events one repeat: the title, letter case aside, and the start time the row shows.
    private static func repeatKey(_ event: DailyEvent) -> String {
        let time = event.timed ? Town.clock(event.starts) : event.item.startTime ?? ""
        return event.item.title.lowercased() + "|" + time
    }

    /// "+24 more dates" under a repeat's time, "+1 more date"; nil when it has none.
    static func moreDates(_ count: Int) -> String? {
        count > 0 ? "+\(count) more date\(count == 1 ? "" : "s")" : nil
    }

    /// The rows under their days, the first `limit` of them: a day cut short keeps the ones that fit. An Event that
    /// started on an earlier day and is still on sits under today.
    static func days(_ rows: [PlaceEventRow], now: Date, limit: Int = .max) -> [PlaceEventDay] {
        let today = calendar.startOfDay(for: now)
        var days: [PlaceEventDay] = []
        for row in rows.prefix(limit) {
            let day = max(calendar.startOfDay(for: row.event.starts), today)
            if days.last?.day == day {
                days[days.count - 1].rows.append(row)
            } else {
                days.append(PlaceEventDay(day: day, rows: [row]))
            }
        }
        return days
    }

    /// More rows than `shown`: the list ends on "See all".
    static func seeAll(_ rows: [PlaceEventRow]) -> Bool { rows.count > shown }

    /// A day's title, "Today", "Tomorrow", then "Nov 28", and its weekday, which follows a slash in grey.
    static func title(_ day: Date, now: Date) -> (day: String, weekday: String) {
        let title = switch Town.days(from: now, to: day) {
        case 0: "Today"
        case 1: "Tomorrow"
        default: Town.format(day, "MMMd")
        }
        return (title, Town.format(day, "EEEE"))
    }

    /// The row's price tag: "Free", "No cover", or one dollar amount ten letters at most ("$50", "$5 cover");
    /// nil for anything else, so a long or unclear price never crowds the row.
    static func priceTag(_ price: String?) -> String? {
        guard let price = price?.trimmingCharacters(in: .whitespacesAndNewlines), !price.isEmpty else { return nil }
        switch price.lowercased() {
        case "free": return "Free"
        case "no cover": return "No cover"
        default: return price.count <= 10 && price.wholeMatch(of: /\$\d+(\.\d\d)?( [A-Za-z]+)*/) != nil ? price : nil
        }
    }
}

/// Where "+24 more dates" sits in its row, so its own button can be laid over that spot.
private struct MoreSpot: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// One row of a place's list: an Event at its date and, for a repeat, its later dates.
struct PlaceEventRow: Identifiable {
    let event: DailyEvent
    /// The repeat's title and time, so the row keeps its place (and stays open) when its next date moves on.
    let id: String
    var more: [DailyEvent] = []
}

/// A day of the list, under its title.
struct PlaceEventDay: Identifiable {
    let day: Date
    var rows: [PlaceEventRow]
    var id: Date { day }
}

/// Sizes from the approved mocks, 1 pt to the CSS pixel: the month made to fit inside a grey card 20 pt in from the
/// screen's sides, and the list.
enum PlaceEventsMetric {
    static let day: CGFloat = 40
    static let dayNumber: CGFloat = 16
    /// The month's name under its grey card's top edge.
    static let monthTop: CGFloat = 14
    static let monthLead: CGFloat = 15
    static let monthTrail: CGFloat = 10
    static let tool: CGFloat = 32
    static let toolGap: CGFloat = 6
    static let weekdaysTop: CGFloat = 12
    static let gridSide: CGFloat = 10
    static let gridTop: CGFloat = 8
    static let gridBottom: CGFloat = 4
    /// 4 between 44 pt tap rows keeps the mock's 48 pt pitch of 40 pt discs 8 apart.
    static let rowGap: CGFloat = 4
    static let dayTitleTop: CGFloat = 10
    static let dayTitleBottom: CGFloat = 2
    static let rowPhoto: CGFloat = 48
    static let rowPhotoGap: CGFloat = 12
    static let rowVertical: CGFloat = 7
    static let rowTrail: CGFloat = 0
    static let bottom: CGFloat = 8
    /// The heart's circle on the grey row: ink at 6%, the mock's.
    static let heartWash: Double = 0.06

    // The list (profile-left 05), the approved mock's CSS (`.eh`, `.dh`, `.er`, `.et`, `.t1`, `.ln`, `.see`).
    /// Above the section's hairline, and from it to "Events".
    static let sectionTop: CGFloat = 26
    static let headerTop: CGFloat = 20
    static let headerHeight: CGFloat = 25
    static let hairline: CGFloat = 1
    /// The calendar button's glyph, and the grey disc behind it while the month is open (agent's pick).
    static let calendarGlyph: CGFloat = 20
    static let calendarDisc: CGFloat = 36
    /// A day's title under the one before it.
    static let dayTop: CGFloat = 18
    /// A row under its day's title or the row before, and the month under "Events".
    static let listRowTop: CGFloat = 12
    static let listPhoto: CGFloat = 80
    static let listPhotoGap: CGFloat = 12
    static let listTextTop: CGFloat = 4
    static let tagGap: CGFloat = 10
    static let tagInset: CGFloat = 7
    static let tagHeight: CGFloat = 20
    static let lineTop: CGFloat = 6
    static let lineGap: CGFloat = 6
    static let seeAll: CGFloat = 44
    /// "+24 more dates" under the time (`.mo`).
    static let moreTop: CGFloat = 3
    static let seeAllTop: CGFloat = 20
}

/// A place's Events on its page, under its About (profile-left 05): "Events" with a calendar button, then each day's
/// title and its Events, the next ten and then "See all". The button puts the place's month in the list's place and
/// takes it away. No section at all with nothing coming up or no read.
struct PlaceEventsSection: View {
    /// The place: its Events are the ones found at it (`club_events.place_entry_id`), so a row never names a place.
    let entryId: String

    @Environment(SearchModel.self) private var model: SearchModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set where the page sits outside a navigation stack (opened over the whole app): a row's tap goes here.
    @Environment(\.openEvent) private var openEvent
    @State private var all = false
    /// The repeats whose more dates are open, by row id.
    @State private var opened: Set<String> = []
    @State private var monthOpen = false
    @State private var shown: Date?
    @State private var picked: Date?
    @Namespace private var ring

    private typealias Metric = EventPage.Metric
    private typealias Size = PlaceEventsMetric

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let events = model.flatMap { model in
                model.placeEventIDs[entryId].map { PlaceEvents.events(model.calendar ?? [], ids: $0) }
            } ?? []
            let rows = PlaceEvents.rows(events, now: now)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if monthOpen {
                        month(events, today: PlaceEvents.calendar.startOfDay(for: now), now: now)
                            .background(Hue.fill)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                            .padding(.top, Size.listRowTop)
                            .transition(.opacity)
                    } else {
                        list(rows, now: now)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Its read lands after the page opens, at the page's foot: it fades in, and nothing above it moves.
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: model?.placeEventIDs[entryId] != nil)
        .task(id: entryId) { await model?.loadPlaceEvents(entryId) }
    }

    /// "Events" and the calendar button, 20 pt under a hairline.
    private var header: some View {
        VStack(spacing: 0) {
            Hue.hairline.frame(height: Size.hairline)
            HStack(spacing: 0) {
                Text("Events")
                    .font(.display(20))
                    .foregroundStyle(Hue.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : Motion.smooth) { monthOpen.toggle() }
                } label: {
                    Image(systemName: "calendar")
                        .font(.glyph(Size.calendarGlyph, weight: .regular))
                        .foregroundStyle(Hue.ink)
                        .frame(width: Size.calendarDisc, height: Size.calendarDisc)
                        .background(Circle().fill(Hue.fill).opacity(monthOpen ? 1 : 0))
                        .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))
                // The glyph's right edge on the page's, its 44 pt tap box past it.
                .padding(.trailing, -(PageMetric.tapMin - Size.calendarGlyph) / 2)
                .accessibilityLabel("Calendar")
                .accessibilityAddTraits(monthOpen ? .isSelected : [])
                .accessibilityHint(monthOpen ? "Shows the list" : "Shows the month")
            }
            .frame(height: Size.headerHeight)
            .padding(.top, Size.headerTop)
        }
        .padding(.top, Size.sectionTop)
    }

    // MARK: The list

    private func list(_ rows: [PlaceEventRow], now: Date) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(PlaceEvents.days(rows, now: now, limit: all ? .max : PlaceEvents.shown)) { day in
                dayTitle(day.day, now: now)
                    .padding(.top, Size.dayTop)
                ForEach(day.rows) { row($0, now: now).padding(.top, Size.listRowTop) }
            }
            if PlaceEvents.seeAll(rows) {
                Button {
                    withAnimation(reduceMotion ? nil : Motion.smooth) { all.toggle() }
                } label: {
                    Text(all ? "Show less" : "See all")
                        .font(.displaySemi(15))
                        .foregroundStyle(Hue.ink)
                        .frame(maxWidth: .infinity, minHeight: Size.seeAll)
                        .background(Capsule().fill(Hue.fill))
                        .contentShape(Capsule())
                }
                .buttonStyle(.press(.squish))
                .padding(.top, Size.seeAllTop)
            }
        }
    }

    /// "Today / Wednesday": the day in ink, the slash and weekday in grey.
    private func dayTitle(_ day: Date, now: Date) -> some View {
        let title = PlaceEvents.title(day, now: now)
        return Text("\(Text(title.day).font(.sansSemibold(17)).foregroundStyle(Hue.ink))\(Text(" / " + title.weekday).foregroundStyle(Hue.weekday))")
            .font(.sans(17))
            .lineLimit(1)
            .accessibilityLabel("\(title.day), \(title.weekday)")
            .accessibilityAddTraits(.isHeader)
    }

    /// The Event's picture, its title and price tag and its time; a repeat adds "+24 more dates", whose tap opens
    /// those dates under the row and folds them again (profile-left 06). A tap elsewhere opens its Event page as the
    /// month's rows do. "+24 more dates" is its own button laid over its spot in the row, never inside the row's.
    private func row(_ row: PlaceEventRow, now: Date) -> some View {
        let event = row.event
        let isOpen = opened.contains(row.id)
        let more = PlaceEvents.moreDates(row.more.count)
        let tag = PlaceEvents.priceTag(event.item.price)
        let toggle = {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : Motion.bentoExpand) { opened.formSymmetricDifference([row.id]) }
        }
        let label = HStack(alignment: .top, spacing: Size.listPhotoGap) {
            Hue.fill
                .frame(width: Size.listPhoto, height: Size.listPhoto)
                .overlay { if let url = event.photo { FeedCardURLPhoto(url: url, loadingFill: Hue.fill) } }
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: Size.tagGap) {
                    Text(event.item.title)
                        .font(.sansSemibold(17))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let tag {
                        Text(tag)
                            .font(.sansSemibold(13))
                            .foregroundStyle(Hue.priceTag)
                            .padding(.horizontal, Size.tagInset)
                            .frame(height: Size.tagHeight)
                            .background(RoundedRectangle(cornerRadius: Radius.priceTag, style: .continuous)
                                .fill(Hue.priceTagWash))
                            .fixedSize()
                    }
                }
                line("clock", event.startTime(now: now))
                if let more {
                    // Holds the button's room; the button itself is laid over it, outside the row's.
                    moreText(more)
                        .hidden()
                        .anchorPreference(key: MoreSpot.self, value: .bounds) { $0 }
                }
            }
            .padding(.top, Size.listTextTop)
        }
        .contentShape(Rectangle())

        return VStack(alignment: .leading, spacing: 0) {
            opener(event.item) { label }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([event.item.title, event.startSpoken(now: now), tag, more]
                    .compactMap { $0 }.joined(separator: ", "))
                .accessibilityActions {
                    if more != nil { Button(isOpen ? "Hide more dates" : "Show more dates", action: toggle) }
                }
                .overlayPreferenceValue(MoreSpot.self) { spot in
                    if let spot, let more {
                        GeometryReader { proxy in
                            let frame = proxy[spot]
                            Button(action: toggle) {
                                moreText(more)
                                    // Its tap reaches past the line to the 44 pt minimum.
                                    .contentShape(TapArea())
                            }
                            .buttonStyle(.press(.squish))
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            // VoiceOver has it as the row's action.
                            .accessibilityHidden(true)
                        }
                    }
                }
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(row.more) { date(of: $0, now: now) }
                }
                .padding(.leading, Size.listPhoto + Size.listPhotoGap)
                // Fades in place as the list grows under it, as the hours' week does.
                .transition(.opacity)
            }
        }
    }

    private func moreText(_ more: String) -> some View {
        Text(more)
            .font(.sansSemibold(15))
            .foregroundStyle(Hue.ink)
            .padding(.top, Size.moreTop)
    }

    /// One of a repeat's more dates, "Nov 28 / Saturday" with a chevron, opening that date's Event page.
    private func date(of event: DailyEvent, now: Date) -> some View {
        let title = PlaceEvents.title(PlaceEvents.calendar.startOfDay(for: event.starts), now: now)
        return opener(event.item) {
            HStack(spacing: Size.lineGap) {
                Text("\(Text(title.day).foregroundStyle(Hue.ink))\(Text(" / " + title.weekday).foregroundStyle(Hue.weekday))")
                    .font(.sans(15))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.sansSemibold(12))
                    .foregroundStyle(Hue.weekday)
            }
            .frame(minHeight: PageMetric.tapMin)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.item.title), \(title.day), \(title.weekday), \(event.startSpoken(now: now))")
    }

    /// Opens the Event page as the month's rows do: pushed in the page's stack, or by the opener over the whole app.
    private func opener(_ item: FeedCardItem, @ViewBuilder label: () -> some View) -> some View {
        let label = label()
        return Group {
            if let openEvent {
                Button { openEvent.open(item) } label: { label }
            } else {
                NavigationLink(value: item) { label }
            }
        }
        .buttonStyle(.press(.row))
    }

    private func line(_ glyph: String, _ text: String) -> some View {
        HStack(spacing: Size.lineGap) {
            Image(systemName: glyph)
                .font(.sans(13))
                .foregroundStyle(Hue.weekday)
            Text(text)
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
        }
        .padding(.top, Size.lineTop)
    }

    // MARK: The month

    private func month(_ events: [DailyEvent], today: Date, now: Date) -> some View {
        let months = PlaceEvents.months(events, today: today)
        // It opens on the next Event's month, which may not be this one when this month's are all past.
        let month = shown.flatMap { months.contains($0) ? $0 : nil }
            ?? PlaceEvents.next(events, today: today).map { EventCalendar.month(of: $0) } ?? EventCalendar.month(of: today)
        let byDay = YouCalendar.byDay(events)
        let day = picked.flatMap { EventCalendar.month(of: $0) == month ? $0 : nil }
            ?? PlaceEvents.landing(month, events: events, today: today) ?? today
        let index = months.firstIndex(of: month) ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Size.toolGap) {
                Text(Town.format(month, "MMMM"))
                    .font(.display(20))
                    .foregroundStyle(Hue.ink)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                arrow("chevron.left", label: "Previous month", to: index > 0 ? months[index - 1] : nil,
                      events: events, today: today)
                arrow("chevron.right", label: "Next month", to: index + 1 < months.count ? months[index + 1] : nil,
                      events: events, today: today)
            }
            .padding(.leading, Size.monthLead)
            .padding(.trailing, Size.monthTrail)
            .padding(.top, Size.monthTop)
            weekdays
                .padding(.top, Size.weekdaysTop)
            grid(month, byDay: byDay, today: today, day: day)
                .padding(.horizontal, Size.gridSide)
                .padding(.top, Size.gridTop)
                .padding(.bottom, Size.gridBottom)
            dayTitle(day)
                .padding(.horizontal, Metric.pillInset)
                .padding(.top, Size.dayTitleTop)
                .padding(.bottom, Size.dayTitleBottom)
            VStack(spacing: 0) {
                ForEach(byDay[day] ?? []) {
                    CalendarRow(event: $0, now: now, photo: Size.rowPhoto, photoGap: Size.rowPhotoGap,
                                lead: Metric.pillInset, vertical: Size.rowVertical, trail: Size.rowTrail,
                                heartFill: Hue.ink.opacity(Size.heartWash))
                }
            }
        }
        .padding(.bottom, Size.bottom)
    }

    private func arrow(_ symbol: String, label: String, to month: Date?, events: [DailyEvent],
                       today: Date) -> some View {
        Button {
            guard let month else { return }
            Haptics.selection()
            withAnimation(reduceMotion ? nil : Motion.smooth) {
                shown = month
                picked = PlaceEvents.landing(month, events: events, today: today)
            }
        } label: {
            Image(systemName: symbol)
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.ink)
                .frame(width: Size.tool, height: Size.tool)
                .background(Circle().fill(Hue.surface).strokeBorder(Hue.searchChipEdge, lineWidth: 1))
                .contentShape(Rectangle().inset(by: (Size.tool - PageMetric.tapMin) / 2))
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
                    .font(.sansMedium(12))
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Size.gridSide)
        .accessibilityHidden(true)
    }

    private func grid(_ month: Date, byDay: [Date: [DailyEvent]], today: Date, day: Date) -> some View {
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
                               isPicked: date == day, ring: ring, disc: true, gapColor: Hue.fill,
                               side: Size.day, number: Size.dayNumber)
                            // The whole column, 44 pt tall, takes the tap: the 40 pt disc alone is under the minimum.
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

    /// "Tuesday November 17", the mock's line over the day's Events.
    private func dayTitle(_ day: Date) -> some View {
        let weekday = Text(Town.format(day, "EEEE")).font(.sansSemibold(15)).foregroundStyle(Hue.ink)
        let date = Text(" " + Town.format(day, "MMMM d")).font(.sans(15)).foregroundStyle(Hue.inkSecondary)
        return Text("\(weekday)\(date)")
            .lineLimit(1)
            .contentTransition(.opacity)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Opens an Event page from a place's page when that page sits outside a navigation stack (the shell's own, opened
/// over the whole app): it closes the place and pushes the Event (place-pages 05). A value, so the environment can
/// hold it without a bare closure.
struct EventPageOpener {
    let open: (FeedCardItem) -> Void
}

extension EnvironmentValues {
    @Entry var openEvent: EventPageOpener? = nil
}
