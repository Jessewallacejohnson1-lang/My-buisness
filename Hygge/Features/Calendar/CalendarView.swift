//
//  CalendarView.swift
//  Hygge — the town calendar, BeReal-style: a fixed header (Upcoming ⇄ Calendar
//  pill + info), then a scrolling year of month grids. Coral numbers are days
//  with happenings, the filled circle is today, the outlined cell is the day
//  you're looking at, and a pulse above today means live right now.
//

import SwiftUI

/// Which face of the tab is showing: the agenda list or the month grids.
private enum CalendarFace: String, CaseIterable {
    case upcoming = "Upcoming"
    case grid = "Calendar"
}

struct CalendarView: View {
    /// The global composer, injected by MainTabsView. CalendarView's own empty
    /// state invites "anyone can add something" — this makes that reachable here.
    var onCompose: (() -> Void)? = nil

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = CalendarModel()
    @State private var face: CalendarFace = CalendarView.initialFace()
    @State private var selectedDate: String?   // outlined cell — survives sheet dismissal
    @State private var sheetDate: DayKey?      // drives the day sheet
    @State private var showLegend = false
    @Namespace private var selectionNS
    @Namespace private var segmentNS

    private let months = CalendarView.buildMonths()
    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var todayKey: String { DateHelpers.localDate() }

    /// DEBUG-only: `-calendar-face upcoming|grid` starts the tab on a given face
    /// so both states can be screenshotted headlessly. No effect in release.
    private static func initialFace() -> CalendarFace {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-calendar-face"), i + 1 < args.count {
            switch args[i + 1] {
            case "upcoming": return .upcoming
            case "grid":     return .grid
            default:         break
            }
        }
        #endif
        return .grid
    }

    /// DEBUG-only: `-calendar-open 2026-07-10` preselects a day (outline + sheet)
    /// and `-calendar-legend` opens the info sheet — both for headless screenshots.
    private func applyDebugLaunchState() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-calendar-open"), i + 1 < args.count {
            pick(args[i + 1])
        }
        if args.contains("-calendar-legend") {
            showLegend = true
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ZStack {
                if face == .grid {
                    monthScroll
                        .transition(reduceMotion ? .opacity
                            : .offset(x: 28).combined(with: .opacity))
                } else {
                    agenda
                        .transition(reduceMotion ? .opacity
                            : .offset(x: -28).combined(with: .opacity))
                }
            }
        }
        .background(Hue.canvas)
        .overlay(alignment: .bottomTrailing) { ComposeFAB(action: onCompose) }
        .task { await model.load(api) }
        .onAppear { applyDebugLaunchState() }
        .sheet(item: $sheetDate) { key in
            DaySheet(date: key.date, events: model.dayEvents,
                     loading: model.loadingDay, failed: model.dayFailed,
                     onToggleRsvp: { ev in Task { await model.toggleRsvp(api, ev) } })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLegend) {
            CalendarLegendSheet()
        }
    }

    // MARK: - Header (segmented pill · info)

    private var header: some View {
        HStack {
            segmentPill
            Spacer()
            Button {
                Haptics.light()
                showLegend = true
            } label: {
                Image(systemName: "info")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 36, height: 36)
                    .background(Hue.surface, in: Circle())
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
                    .mapFloatShadow()
                    .frame(width: 44, height: 44)   // HIG hit target around the 36pt circle
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel("How the calendar works")
        }
    }

    private var segmentPill: some View {
        HStack(spacing: 2) {
            ForEach(CalendarFace.allCases, id: \.self) { f in
                let on = face == f
                Button {
                    guard face != f else { return }
                    Haptics.selection()
                    if reduceMotion {
                        face = f
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { face = f }
                    }
                } label: {
                    Text(f.rawValue)
                        .font(.sansSemibold(14))
                        .foregroundStyle(on ? .white : Hue.ink2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background {
                            if on {
                                Capsule().fill(Hue.ink)
                                    .matchedGeometryEffect(id: "seg", in: segmentNS)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Hue.surface, in: Capsule())
        .overlay(Capsule().stroke(Hue.hairline, lineWidth: 1))
        .mapFloatShadow()
    }

    // MARK: - Month grids

    private var monthScroll: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 36) {
                if model.failed {
                    offlineNote
                }
                ForEach(months) { m in
                    MonthSection(
                        spec: m,
                        counts: model.counts,
                        todayKey: todayKey,
                        liveNow: model.liveNow,
                        selected: selectedDate,
                        selectionNS: selectionNS,
                        onPick: pick
                    )
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
        }
        .refreshable { await model.load(api) }
    }

    // MARK: - Agenda

    private var agenda: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                if model.failed {
                    offlineNote
                        .padding(.top, 64)
                } else if !model.loaded {
                    ProgressView().tint(Hue.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 64)
                } else if model.upcoming.isEmpty {
                    VStack(spacing: 6) {
                        Text("Nothing on the calendar yet")
                            .font(.sansSemibold(15)).foregroundStyle(Hue.ink)
                        Text("Anyone can add something — it's the whole town's calendar.")
                            .font(.sans(13)).foregroundStyle(Hue.ink2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 64)
                } else {
                    ForEach(agendaDays, id: \.date) { group in
                        agendaHeader(group.date)
                            .padding(.top, 10)
                        ForEach(group.events) { e in
                            AgendaRowCard(event: e) { pick(e.eventDate) }
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .animation(.easeOut(duration: 0.25), value: model.loaded)
        }
        .refreshable { await model.load(api) }
    }

    /// Quiet failure copy — shown only when a load failed with nothing to show.
    private var offlineNote: some View {
        VStack(spacing: 6) {
            Text("Couldn't reach the calendar")
                .font(.sansSemibold(15)).foregroundStyle(Hue.ink)
            Text("Pull down to try again.")
                .font(.sans(13)).foregroundStyle(Hue.ink2)
        }
        .frame(maxWidth: .infinity)
    }

    private func agendaHeader(_ date: String) -> some View {
        HStack(spacing: 6) {
            if date == todayKey {
                Text("Today").font(.sansSemibold(13)).foregroundStyle(Hue.accent)
                Text("·").font(.sans(13)).foregroundStyle(Hue.ink3)
            }
            Text(DateHelpers.prettyDate(date))
                .font(.sansSemibold(13)).foregroundStyle(Hue.ink2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Upcoming events grouped by day, keeping the date+time order they arrived in.
    private var agendaDays: [(date: String, events: [AgendaEvent])] {
        var order: [String] = []
        var map: [String: [AgendaEvent]] = [:]
        for e in model.upcoming {
            if map[e.eventDate] == nil { order.append(e.eventDate) }
            map[e.eventDate, default: []].append(e)
        }
        return order.map { (date: $0, events: map[$0] ?? []) }
    }

    // MARK: - Selection

    private func pick(_ ymd: String) {
        Haptics.selection()
        if reduceMotion {
            selectedDate = ymd
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { selectedDate = ymd }
        }
        sheetDate = DayKey(date: ymd)
        Task { await model.loadDay(api, date: ymd) }
    }

    // MARK: - Month math

    fileprivate struct MonthSpec: Identifiable {
        let year: Int
        let month: Int
        let title: String       // "July 2026"
        let monthName: String   // "July" — for VoiceOver day labels
        let dayCount: Int
        let leadingBlanks: Int
        var id: String { "\(year)-\(month)" }
    }

    /// Current month + the next 11 — the calendar looks forward, like the tab.
    /// Gregorian-pinned so day keys match the DB even on Buddhist/Japanese devices.
    private static func buildMonths() -> [MonthSpec] {
        let cal = CalendarModel.gregorian
        guard let base = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return [] }
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = Locale(identifier: "en_US")
        fmt.dateFormat = "MMMM yyyy"
        let monthName = DateFormatter()
        monthName.calendar = cal
        monthName.locale = Locale(identifier: "en_US")
        monthName.dateFormat = "MMMM"
        return (0..<12).compactMap { offset in
            guard let d = cal.date(byAdding: .month, value: offset, to: base) else { return nil }
            let c = cal.dateComponents([.year, .month], from: d)
            guard let y = c.year, let m = c.month else { return nil }
            return MonthSpec(
                year: y, month: m,
                title: fmt.string(from: d),
                monthName: monthName.string(from: d),
                dayCount: cal.range(of: .day, in: .month, for: d)?.count ?? 30,
                leadingBlanks: cal.component(.weekday, from: d) - 1
            )
        }
    }
}

// MARK: - One month: title, weekday row, day grid

private struct MonthSection: View {
    let spec: CalendarView.MonthSpec
    let counts: [String: Int]
    let todayKey: String
    let liveNow: Bool
    let selected: String?
    let selectionNS: Namespace.ID
    let onPick: (String) -> Void

    private static let symbols = [
        ("SUN", "Sunday"), ("MON", "Monday"), ("TUE", "Tuesday"), ("WED", "Wednesday"),
        ("THU", "Thursday"), ("FRI", "Friday"), ("SAT", "Saturday"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(spec.title)
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                ForEach(Self.symbols, id: \.0) { s in
                    Text(s.0)
                        .font(.sansMedium(11))
                        .kerning(0.4)
                        .foregroundStyle(Hue.ink3)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(s.1)
                }
            }

            // One ForEach over grid slots — separate blank/day ForEach loops
            // would collide on integer IDs and LazyVGrid drops the dupes.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                      spacing: 18) {
                ForEach(0..<(spec.leadingBlanks + spec.dayCount), id: \.self) { slot in
                    if slot < spec.leadingBlanks {
                        Color.clear.frame(height: 48)
                    } else {
                        let day = slot - spec.leadingBlanks + 1
                        let key = String(format: "%04d-%02d-%02d", spec.year, spec.month, day)
                        DayCell(
                            day: day,
                            monthName: spec.monthName,
                            count: counts[key] ?? 0,
                            isToday: key == todayKey,
                            isPast: key < todayKey,
                            isSelected: key == selected,
                            showLivePulse: liveNow && key == todayKey,
                            selectionNS: selectionNS
                        ) { onPick(key) }
                    }
                }
            }
        }
    }
}

// MARK: - One day cell

private struct DayCell: View {
    let day: Int
    let monthName: String
    let count: Int
    let isToday: Bool
    let isPast: Bool
    let isSelected: Bool
    let showLivePulse: Bool
    let selectionNS: Namespace.ID
    let onPick: () -> Void

    private var hasEvents: Bool { count > 0 }

    // Deep coral (accentPressed) for the numerals — same family as the live
    // circle but clears 3:1 on the near-white canvas, which FF6B57 doesn't.
    private var numberColor: Color {
        if isToday { return .white }
        if hasEvents { return Hue.accentPressed }
        return isPast ? Hue.ink3 : Hue.ink
    }

    var body: some View {
        Button(action: onPick) {
            Text("\(day)")
                // One weight for every number — hierarchy is color's job, and a
                // uniform weight means nothing snaps when the data loads in.
                .font(.system(size: 18, weight: isToday ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .frame(width: 38, height: 38)
                .background {
                    if isToday { Circle().fill(Hue.accent) }
                }
                .animation(.easeOut(duration: 0.25), value: hasEvents)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(alignment: .top) {
                    if showLivePulse {
                        LivePulseDot().offset(y: -4)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Hue.ink, lineWidth: 1.5)
                            .frame(width: 42, height: 48)
                            .matchedGeometryEffect(id: "daySelection", in: selectionNS)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var accessibilityText: String {
        var s = "\(monthName) \(day)"
        if isToday { s += ", today" }
        if hasEvents { s += ", \(count) \(count == 1 ? "happening" : "happenings")" }
        if showLivePulse { s += ", live right now" }
        return s
    }
}

/// The live-now marker above today: a coral dot with a soft expanding pulse.
/// Reduce Motion gets the dot alone, no pulse.
private struct LivePulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Hue.accent)
            .frame(width: 6, height: 6)
            .background {
                if !reduceMotion {
                    Circle()
                        .fill(Hue.accent.opacity(0.35))
                        .scaleEffect(pulsing ? 2.8 : 1)
                        .opacity(pulsing ? 0 : 0.7)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Agenda row

private struct AgendaRowCard: View {
    let event: AgendaEvent
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.sansBold(15))
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if let loc = event.location, !loc.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11))
                            Text(loc).font(.sans(13))
                        }
                        .foregroundStyle(Hue.ink2)
                    }
                }
                Spacer(minLength: 8)
                if let time = event.startTime, !time.isEmpty {
                    Text(time)
                        .font(.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hyggeCard(padding: 14)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Legend ("i")

private struct CalendarLegendSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Reading the calendar")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
                .padding(.top, 8)

            legendRow(detailTitle: "Today", detail: "The filled circle is always today.") {
                Text("6")
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Hue.accent))
            }

            legendRow(detailTitle: "A day with happenings",
                      detail: "Coral days have something planned — tap one to see it.") {
                Text("14")
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Hue.accent)
                    .frame(width: 32, height: 32)
            }

            legendRow(detailTitle: "Live right now",
                      detail: "A pulse above today means something's happening this minute.") {
                LivePulseDot().frame(width: 32, height: 32)
            }

            Text("This is the whole town's calendar — anyone can add to it.")
                .font(.sans(13))
                .foregroundStyle(Hue.ink3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .background(Hue.canvas)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
    }

    private func legendRow(detailTitle: String, detail: String,
                           @ViewBuilder sample: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 14) {
            sample()
                .frame(width: 44, height: 44)
                .background(Hue.paper, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Hue.hairline, lineWidth: 1)
                )
                .accessibilityHidden(true)   // decorative — the text row says it all
            VStack(alignment: .leading, spacing: 2) {
                Text(detailTitle).font(.sansSemibold(14)).foregroundStyle(Hue.ink)
                Text(detail).font(.sans(13)).foregroundStyle(Hue.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Identifiable wrapper so a YYYY-MM-DD string drives a .sheet(item:).
private struct DayKey: Identifiable {
    let date: String
    var id: String { date }
}

// MARK: - Day sheet (unchanged behavior: events for one day + calendar export)

struct DaySheet: View {
    let date: String
    let events: [TimelineEvent]
    let loading: Bool
    var failed = false
    var onToggleRsvp: ((TimelineEvent) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var composing = false

    /// The tapped day as a Date, for prefilling the composer.
    private var dayDate: Date {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents(); if p.count == 3 { c.year = p[0]; c.month = p[1]; c.day = p[2] }
        return Calendar.current.date(from: c) ?? Date()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text(DateHelpers.prettyDate(date))
                    .font(.displaySemi(22))
                    .foregroundStyle(Hue.ink)
                    .padding(.top, 8)

                if loading {
                    ProgressView().tint(Hue.ink3).frame(maxWidth: .infinity).padding(.top, 30)
                } else if failed {
                    // Never claim "a clear day" when the fetch failed — the grid
                    // may be showing a coral count for this very day.
                    VStack(spacing: 6) {
                        Text("Couldn't load this day")
                            .font(.sansSemibold(15)).foregroundStyle(Hue.ink)
                        Text("Check your connection and try again.")
                            .font(.sans(13)).foregroundStyle(Hue.ink2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
                } else if events.isEmpty {
                    VStack(spacing: 12) {
                        VStack(spacing: 6) {
                            Text("A clear day")
                                .font(.sansSemibold(15)).foregroundStyle(Hue.ink)
                            Text("Nothing on the calendar for this day yet.")
                                .font(.sans(13)).foregroundStyle(Hue.ink2)
                        }
                        // Capture the intent right here — the composer opens already
                        // scoped to this day (Apple Calendar / Partiful pattern).
                        Button {
                            Haptics.light()
                            composing = true
                        } label: {
                            Text("Add the first thing")
                                .font(.sansSemibold(14)).foregroundStyle(.white)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(Hue.accent, in: Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.96))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
                } else {
                    ForEach(events) { ev in
                        EventRow(event: ev, date: date,
                                 onToggleRsvp: onToggleRsvp.map { cb in { cb(ev) } })
                    }

                    InlineAction(
                        icon: "calendar.badge.plus",
                        label: "Add to your calendar",
                        doneLabel: "Added to your calendar",
                        actionText: "Add",
                        perform: { try await CalendarExport.addDay(date: date, events: events) }
                    )
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 18)
        }
        .background(Hue.canvas)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $composing) {
            AddFormView(kind: .event, initialDate: dayDate)
        }
    }
}
