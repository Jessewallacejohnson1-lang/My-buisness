//
//  PlaceEvents.swift
//  Block Party — a place's Events on its business page (BP app place-pages 05): a row under its hours, "8 Events
//  coming up", that opens in place as the hours row does to show the place's month, Search's Event calendar made
//  small (40 pt discs, past days faded, the next Event's day picked, only months with Events), and the picked day's
//  Events. No row when nothing is coming up.
//
//  Reference: the hours row's fold (`HoursPill`) and Search's Event calendar (`EventCalendarView`), in the mock
//  Jesse approved (https://claude.ai/artifact/D8ovBahnQ9FAbTScTb4xTh, 2026-11-16: "yes"). The Events are the
//  Event calendar's own (`get_town_calendar`), so who sees what stays the calendar's rule; the place's are those
//  found at it (`club_events.place_entry_id`).
//

import SwiftUI

/// The row's rules, pure so the tests drive them with fixed dates.
enum PlaceEvents {
    static var calendar: Calendar { EventCalendar.calendar }

    /// The calendar's Events found at the place, in the calendar's order.
    static func events(_ all: [DailyEvent], ids: Set<String>) -> [DailyEvent] {
        EventCalendar.ordered(all.filter { ids.contains($0.id) })
    }

    /// How many are on today or later: the row's number.
    static func coming(_ events: [DailyEvent], today: Date) -> Int {
        events.count(where: { $0.starts >= today })
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

    /// "8 Events coming up"; "1 Event coming up". The approved mock's words.
    static func words(_ count: Int) -> (count: String, rest: String) {
        (count == 1 ? "1 Event" : "\(count) Events", " coming up")
    }
}

/// Sizes from the approved mock, 1 pt to the CSS pixel: the month made to fit inside the row, 40 pt in from the
/// screen's sides.
enum PlaceEventsMetric {
    static let day: CGFloat = 40
    static let dayNumber: CGFloat = 16
    static let monthTop: CGFloat = 2
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
}

/// The row itself. Its Events come from Search's calendar read; it asks for the place's ids once.
struct PlaceEventsPill: View {
    let entryId: String

    @Environment(SearchModel.self) private var model: SearchModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var shown: Date?
    @State private var picked: Date?
    @Namespace private var ring

    private typealias Metric = EventPage.Metric
    private typealias Size = PlaceEventsMetric

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = PlaceEvents.calendar.startOfDay(for: context.date)
            let events = model.flatMap { model in
                model.placeEventIDs[entryId].map { PlaceEvents.events(model.calendar ?? [], ids: $0) }
            } ?? []
            let count = PlaceEvents.coming(events, today: today)
            if count > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    // Only the row takes the fold's tap: the days, arrows and Events under it are buttons of their own.
                    Button {
                        withAnimation(reduceMotion ? nil : Motion.bentoExpand) { expanded.toggle() }
                    } label: {
                        row(count).contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.squish))
                    .accessibilityLabel(PlaceEvents.words(count).count + PlaceEvents.words(count).rest)
                    .accessibilityHint(expanded ? "Hides the calendar" : "Shows the calendar")
                    if expanded {
                        // Fades in place as the row grows, as the hours' week does.
                        month(events, today: today, now: context.date)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Hue.fill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .padding(.top, SearchMetric.bizLinkGap)
                // Its read lands after the page opens: it fades in and the rows under it ease down, never a jump.
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.bentoExpand, value: model?.placeEventIDs[entryId] != nil)
        .task(id: entryId) { await model?.loadPlaceEvents(entryId) }
    }

    private func row(_ count: Int) -> some View {
        let words = PlaceEvents.words(count)
        return HStack(spacing: Metric.pinGap) {
            Image(systemName: "calendar")
                .font(.sans(14))
                .foregroundStyle(Hue.ink)
                .frame(width: SearchMetric.bizGlyphBox)
            Text("\(Text(words.count).font(.sansSemibold(15)))\(words.rest)")
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.sans(12))
                .foregroundStyle(Hue.inkSecondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .padding(.horizontal, Metric.pillInset)
        .frame(height: Metric.pillHeight)
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
