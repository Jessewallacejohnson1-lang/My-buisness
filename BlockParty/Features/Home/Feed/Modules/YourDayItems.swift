//
//  YourDayItems.swift
//  Block Party — building Your Day: today only, town time, two lanes, no repeats.
//
//  TOWN TIME, DELIBERATELY NOT `DateHelpers`. `DateHelpers.localDate()` pins
//  "today" to `TimeZone.current`, which is right for the device-local reads it was
//  written for. Your Day is a statement about the TOWN's day: a neighbour reading
//  the app from a conference in Denver should still see St. Joseph's Monday, and
//  should not watch the rail flip an hour early. So everything below runs on
//  `Town.calendar` / `Town.timeZone`. The two definitions of "today" coexisted in
//  this one feature before — this file is the side that wins for Your Day.
//

import Foundation

nonisolated extension YourDayLogic {

    /// How long an event runs when the row does not say. Matches the window
    /// `DateHelpers.isLiveNow` uses to keep a map pin pulsing.
    static var assumedEventDuration: TimeInterval { 2 * 60 * 60 }

    /// 11:59 PM — where an unparseable start time gets placed.
    static var lastMinuteOfDay: Int { 23 * 60 + 59 }

    // MARK: - The town's today

    /// `[startOfToday, endOfToday)` in America/Chicago. Half-open on purpose: an
    /// event at 11:59 PM is today, an event at 12:00 AM is tomorrow.
    static func todayInterval(now: Date) -> (start: Date, end: Date) {
        let start = Town.calendar.startOfDay(for: now)
        let end = Town.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    // MARK: - Building the rail

    /// The whole rail from one already-merged candidate list, split into its two
    /// lanes by the viewer's own RSVP state.
    static func dayItems(from candidates: [UpcomingEvent], now: Date) -> [DayItem] {
        dayItems(
            committed: candidates.filter(\.rsvpd),
            wholeTown: candidates.filter { !$0.rsvpd },
            now: now
        )
    }

    /// Merge the two lanes into the neighbour's day.
    ///
    /// - Both lanes are filtered to today by `overlapsToday`.
    /// - An id present in both lanes is **committed**, and appears exactly once.
    /// - All-day items sort first, then by start ascending.
    ///
    /// Returns a new array; nothing passed in is mutated.
    static func dayItems(
        committed: [UpcomingEvent],
        wholeTown: [UpcomingEvent],
        now: Date
    ) -> [DayItem] {
        let committedIDs = Set(committed.map(\.id))
        let lanes: [(event: UpcomingEvent, source: DayItemSource)] =
            committed.map { ($0, .committed) }
            + wholeTown.filter { !committedIDs.contains($0.id) }.map { ($0, .wholeTown) }

        var seen = Set<String>()
        let items = lanes.compactMap { lane -> DayItem? in
            guard seen.insert(lane.event.id).inserted else { return nil }
            return dayItem(for: lane.event, source: lane.source, now: now)
        }

        return sortedForRail(items)
    }

    /// One item, or nil when the row does not belong to today.
    static func dayItem(
        for event: UpcomingEvent,
        source: DayItemSource,
        now: Date
    ) -> DayItem? {
        guard let span = span(for: event) else { return nil }

        let today = todayInterval(now: now)
        // THE OVERLAP RULE: an item belongs to today iff its own local-day
        // interval overlaps today. `end ?? start` is the graceful degradation for
        // the nil `end_at` that every row has until the migration lands — an
        // event with no stated end occupies its start instant, nothing more.
        guard span.start < today.end, (span.end ?? span.start) >= today.start
        else { return nil }

        let dayOfStart = Town.calendar.startOfDay(for: span.start)
        let dayOfEnd = Town.calendar.startOfDay(for: span.end ?? span.start)
        let isMultiDay = dayOfStart != dayOfEnd

        return DayItem(
            id: event.id,
            title: event.title,
            source: source,
            start: span.start,
            end: span.end,
            isAllDay: event.isAllDay,
            isMultiDay: isMultiDay,
            isComplete: now >= completionInstant(for: event, span: span),
            eyebrow: eyebrow(for: event, isMultiDay: isMultiDay, span: span),
            location: placeText(for: event),
            goingCount: event.goingCount,
            event: event
        )
    }

    // MARK: - Derived state

    /// When an item counts as done.
    ///
    /// With a stated `end_at`, that instant — no interpretation needed.
    ///
    /// WITHOUT ONE (every row today), the least surprising rule is the one the app
    /// already lives by: `DateHelpers.isLiveNow` has always treated an event as
    /// happening for two hours from its start, which is what makes a map pin stop
    /// pulsing. Your Day reuses that same assumed duration rather than inventing a
    /// second, disagreeing guess. The alternative — "complete the moment it starts"
    /// — would grey out the card of the potluck the neighbour is standing in.
    ///
    /// An all-day item is done only when its day is.
    static func completionInstant(
        for event: UpcomingEvent,
        span: (start: Date, end: Date?)
    ) -> Date {
        if let end = span.end { return end }
        if event.isAllDay {
            let day = Town.calendar.startOfDay(for: span.start)
            return Town.calendar.date(byAdding: .day, value: 1, to: day) ?? span.start
        }
        return span.start.addingTimeInterval(assumedEventDuration)
    }

    /// The one separator the eyebrow ever uses. Named because `DayScheduleLogic`
    /// has to split the clock time back off the line to build the gutter.
    static var eyebrowSeparator: String { " · " }

    /// The line above the title. A multi-day item says it is still running instead
    /// of quoting a start time that was two days ago.
    ///
    /// A timed item whose row STATES an end carries how long it runs — `11:00 AM ·
    /// 2 hr`. That clause is reachable now that `club_events.end_at` exists and
    /// silent on every row that leaves it NULL, which today is all of them: the
    /// assumed two-hour duration behind `completionInstant` is a guess good enough
    /// to grey a card out and not good enough to print, so it is never borrowed
    /// here. `span` is optional so the two structural shapes above can still be
    /// asked for on their own.
    static func eyebrow(
        for event: UpcomingEvent,
        isMultiDay: Bool,
        span: (start: Date, end: Date?)? = nil
    ) -> String {
        if event.isAllDay { return "Today · all day" }
        if isMultiDay { return "Today · ongoing" }

        guard let time = startTimeText(for: event) else { return "Today" }
        guard let span,
              let length = durationText(start: span.start, end: span.end)
        else { return time }

        return time + eyebrowSeparator + length
    }

    /// `45 min` · `2 hr` · `1 hr 5 min` · `10 hr 36 min`, or nil when the row never
    /// stated an end.
    ///
    /// HOURS AND MINUTES, NOT A DECIMAL. This used to print `10.6 hr`, which is a
    /// number nobody says out loud — a neighbour reads a clock, not a fraction.
    /// Whole hours drop the minute clause entirely (`2 hr`, never `2 hr 0 min`) and
    /// anything under an hour is minutes alone.
    ///
    /// Rounded to the nearest whole MINUTE, once, before anything is worded — so
    /// 59m40s reads `1 hr` rather than `0 hr 60 min`, and the two call sites below
    /// can never disagree about a boundary.
    ///
    /// The ONE duration vocabulary in the feature — the day sheet's `DURATION`
    /// column reads it too, so an event cannot say "2 hr" in the eyebrow and
    /// "120 min" in its stats.
    ///
    /// Nil is the SUPPRESSION path, and it is still the common one: every live
    /// `club_events` row leaves `end_at` NULL, so most items have no duration to
    /// state and must render no clause and no column at all.
    static func durationText(start: Date, end: Date?) -> String? {
        guard let end else { return nil }
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        guard minutes > 0 else { return nil }

        let hours = minutes / 60
        let remainder = minutes % 60

        switch (hours, remainder) {
        case (0, let minutes):        return "\(minutes) min"
        case (let hours, 0):          return "\(hours) hr"
        case (let hours, let minutes): return "\(hours) hr \(minutes) min"
        }
    }

    // MARK: - Placing a row on the clock

    /// The row's own interval, in town time. Nil when `event_date` will not parse —
    /// an item we cannot place on a day cannot be claimed for today.
    ///
    /// The end is whatever `end_at` said and nothing more. Degrading a nil end to
    /// the start is the OVERLAP rule's job, not this function's, so that
    /// `completionInstant` can apply a different (duration-based) degradation
    /// without the two rules being confused for one.
    static func span(for event: UpcomingEvent) -> (start: Date, end: Date?)? {
        guard let day = eventDay(for: event) else { return nil }

        guard !event.isAllDay else { return (day, event.endAt) }

        // Reuses the one free-text parser. Unparseable prose ("after dark") is
        // placed at the end of its day, matching `DateHelpers.minutesOf`'s
        // long-standing "undated/unparseable → end of day" convention, so such a
        // card sorts after everything scheduled instead of jumping to dawn.
        let minutes = minutes(from: event.startTime) ?? lastMinuteOfDay
        guard let start = townInstant(day: day, minutesFromMidnight: minutes)
        else { return nil }

        return (start, event.endAt)
    }

    // MARK: - Realtime relevance

    /// Should a `club_events` change re-sync the rail? Mirrors `MapModel.handle`'s
    /// test, widened from `event_date == today` to the same
    /// `[today − lookback, today]` town-time window `getTownDayCandidates` reads —
    /// a multi-day row dated days ago can still overlap today.
    ///
    /// Status is deliberately NOT checked: the UPDATE that approves a pending
    /// event must count, and an irrelevant insert only costs one idempotent
    /// (debounced) refetch. A DELETE's `old_record` carries only the primary key,
    /// so deletes match by shown id.
    static func changeIsRelevant(
        _ change: RealtimeClient.Change,
        shownIDs: Set<String>,
        now: Date
    ) -> Bool {
        let today = Town.day(now)
        let earliest = Town.day(
            Town.calendar.date(byAdding: .day, value: -CommunityAPI.dayLookbackDays, to: now) ?? now
        )
        // "YYYY-MM-DD" compares correctly as a string.
        func inWindow(_ row: RealtimeClient.Change.Row?) -> Bool {
            guard let row else { return false }
            if let kind = row.kind, kind != "event" { return false }
            guard let date = row.eventDate else { return false }
            return date >= earliest && date <= today
        }
        func shown(_ id: String?) -> Bool {
            id.map(shownIDs.contains) ?? false
        }
        switch change.kind {
        case .insert: return inWindow(change.new)
        case .update: return inWindow(change.new) || shown(change.new?.id ?? change.old?.id)
        case .delete: return shown(change.old?.id)
        }
    }

    // MARK: - Ordering

    /// All-day first, then start ascending, then by id so the order is stable for
    /// two events that begin at the same minute.
    static func sortedForRail(_ items: [DayItem]) -> [DayItem] {
        items.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.id < rhs.id
        }
    }
}
