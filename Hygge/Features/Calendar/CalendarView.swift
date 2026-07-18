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
    @State private var dayDetailDate: String?  // the day shown full-screen (nil = closed)
    @State private var showLegend = false
    @Namespace private var selectionNS
    @Namespace private var segmentNS

    private let months = CalendarView.buildMonths()
    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var todayKey: String { DateHelpers.localDate() }

    /// Real, PERSONAL town-calendar data for the Upcoming Insights face, derived
    /// from the same CalendarModel load the grid uses plus two small personal reads
    /// (myRsvps, rsvpCounts) and the on-device onboarding interests. DEBUG
    /// `-insights-sample[-nointerests|-sparse|-empty]` injects each state so every
    /// card variant can be screenshotted headlessly on a signed-out sim.
    private var insightsData: InsightsData {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-insights-sample-nointerests") { return .sampleNoInterests }
        if args.contains("-insights-sample-sparse") { return .sampleSparse }
        if args.contains("-insights-sample-empty") { return .empty }
        if args.contains("-insights-sample") { return .sample }
        #endif
        return InsightsData.from(counts: model.counts, upcoming: model.upcoming,
                                 myRsvps: model.myRsvps, rsvpCounts: model.rsvpCounts,
                                 interests: Interests.get(), today: todayKey)
    }

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
                // Keep the info button LEFT of the pinned compose "+" (top-right).
                .padding(.trailing, ComposeSpeedDial.topDiscHeaderClearance)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ZStack {
                if face == .grid {
                    monthScroll
                        .transition(reduceMotion ? .opacity
                            : .offset(x: 28).combined(with: .opacity))
                } else {
                    UpcomingInsightsView(data: insightsData, onOpenDay: pick)
                        .transition(reduceMotion ? .opacity
                            : .offset(x: -28).combined(with: .opacity))
                }
            }
        }
        .background(Hue.canvas)
        // The compose "+" is now the ComposeSpeedDial, hosted by MainTabsView.
        .task { await model.load(api) }
        .onAppear { applyDebugLaunchState() }
        // isPresented (not item:) so chevron day-nav mutates `dayDetailDate` in
        // place — the cover stays up and DayDetailView replays its cascade via
        // .onChange(of: date), instead of an item-identity change tearing the
        // cover down and re-presenting it.
        .fullScreenCover(isPresented: Binding(
            get: { dayDetailDate != nil },
            set: { if !$0 { dayDetailDate = nil } }
        )) {
            DayDetailView(date: dayDetailDate ?? todayKey, events: model.dayEvents,
                           loading: model.loadingDay, failed: model.dayFailed,
                           onToggleRsvp: { ev in Task { await model.toggleRsvp(api, ev) } },
                           onChangeDay: { delta in changeDay(delta) },
                           onClose: { dayDetailDate = nil })
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
        dayDetailDate = ymd
        Task { await model.loadDay(api, date: ymd) }
    }

    /// Chevron navigation from DayDetailView — steps `dayDetailDate` by `delta`
    /// days without dismissing the full-screen cover, and keeps the grid's
    /// outlined cell (`selectedDate`) in sync so returning to the grid shows it.
    private func changeDay(_ delta: Int) {
        guard let current = dayDetailDate else { return }
        let cal = CalendarModel.gregorian
        let parts = current.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard let currentDate = cal.date(from: c),
              let nextDate = cal.date(byAdding: .day, value: delta, to: currentDate) else { return }
        let nc = cal.dateComponents([.year, .month, .day], from: nextDate)
        guard let y = nc.year, let m = nc.month, let d = nc.day else { return }
        let newYmd = String(format: "%04d-%02d-%02d", y, m, d)

        Haptics.selection()
        selectedDate = newYmd
        dayDetailDate = newYmd
        Task { await model.loadDay(api, date: newYmd) }
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
