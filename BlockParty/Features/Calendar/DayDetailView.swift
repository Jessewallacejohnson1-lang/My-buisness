//
//  DayDetailView.swift
//  Block Party — full-screen single-day timeline agenda, ported frame-by-frame from a
//  reference recording (see docs/superpowers/specs/2026-07-14-calendar-day-detail-
//  animation-design.md). An hourly ruler: each hour is either an event block
//  (colored bar + title + big tinted icon + RSVP checkbox) or an open "No plans"
//  slot (three dots + "1 hour → No plans" + an add button). Rows reveal top-down
//  with a staggered spring cascade on appear (replayed on day-change).
//
//  Title-only rows (no location) — tap a row to see its full description.
//  Each event row's accent bar + icon come from its EventCategory — a colored circle
//  with a white SF Symbol glyph; a null / legacy row falls back to `.other`. The
//  multi-color palette is a reference-fidelity carve-out (like the map's
//  BasemapPalette / SpotCategory.tint): a calendar reads deliberately multi-color.
//

import SwiftUI

struct DayDetailView: View {
    let date: String                 // YYYY-MM-DD
    let events: [TimelineEvent]
    let loading: Bool
    let failed: Bool
    var onToggleRsvp: ((TimelineEvent) -> Void)? = nil
    var onChangeDay: ((Int) -> Void)? = nil   // -1 / +1 → conductor changes the day
    var onClose: (() -> Void)? = nil

    @State private var revealed = false
    @State private var animateReveal = true
    @State private var composing = false          // day-scoped event composer
    @State private var describing: TimelineEvent? = nil   // tap-a-row → description
    #if DEBUG
    @State private var replayTask: Task<Void, Never>?
    #endif

    /// Reveal feel, tuned frame-by-frame against the reference: a deliberate
    /// top-down wipe over the hour slots. Smaller stagger than the 3-row version
    /// because the ruler now has ~5 reveal units (events + open slots) that must
    /// finish in the reference's ~0.6 s.
    private let rowStagger: Double = 0.10
    private let rowDuration: Double = 0.60
    private let rowBounce: Double = 0.16

    private var slots: [DaySlot] { DaySlot.build(from: displayEvents) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 14)

            timeline
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Hue.paper)
        .onAppear {
            revealed = true
            #if DEBUG
            startReplayIfNeeded()
            // `-calendar-compose` auto-presents the event composer so its category
            // picker can be screenshotted headlessly (no tap driving needed).
            if ProcessInfo.processInfo.arguments.contains("-calendar-compose") { composing = true }
            #endif
        }
        .onChange(of: date) { _, _ in replay() }
        .sheet(isPresented: $composing) {
            AddFormView(kind: .event, initialDate: dayDate)
        }
        .sheet(item: $describing) { ev in
            EventDescriptionSheet(event: ev, date: date,
                                  onToggleRsvp: onToggleRsvp.map { cb in { cb(ev) } })
        }
        #if DEBUG
        .onDisappear {
            replayTask?.cancel()
            replayTask = nil
        }
        #endif
    }

    /// Instant-hide, then animate the cascade in. `animated:false` snaps the reset
    /// so the outgoing spring never lingers — a clean replay on day-change/DEBUG loop.
    private func replay() {
        animateReveal = false
        revealed = false
        DispatchQueue.main.async {
            animateReveal = true
            revealed = true
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                dayChevron(system: "chevron.left") { onChangeDay?(-1) }
                VStack(spacing: 2) {
                    Text(Self.weekdayFormatter.string(from: dayDate))
                        .font(.displaySemi(26))
                        .foregroundStyle(Hue.ink)
                    Text(Self.prettyFormatter.string(from: dayDate))
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                }
                dayChevron(system: "chevron.right") { onChangeDay?(1) }
            }

            HStack {
                Spacer()
                closeButton
            }
        }
    }

    private func dayChevron(system: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Hue.inkSecondary)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
    }

    private var closeButton: some View {
        Button {
            Haptics.selection()
            onClose?()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: 36, height: 36)
                .background(Hue.surface, in: Circle())
                .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
                .mapFloatShadow()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel("Close")
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timeline: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                let s = slots
                if !showSample && loading {
                    ProgressView().tint(Hue.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 64)
                } else if !showSample && failed {
                    VStack(spacing: 6) {
                        Text("Couldn't load this day")
                            .font(.sansSemibold(15)).foregroundStyle(Hue.ink)
                        Text("Check your connection and try again.")
                            .font(.sans(13)).foregroundStyle(Hue.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 64)
                } else if s.isEmpty {
                    VStack(spacing: 12) {
                        VStack(spacing: 6) {
                            Text("A clear day")
                                .font(.sansSemibold(15)).foregroundStyle(Hue.ink)
                            Text("Nothing on the calendar for this day yet.")
                                .font(.sans(13)).foregroundStyle(Hue.inkSecondary)
                        }
                        Button {
                            Haptics.light()
                            composing = true
                        } label: {
                            Text("Add the first thing")
                                .font(.sansSemibold(14)).foregroundStyle(.white)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(Hue.ink,
                                            in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                        }
                        .buttonStyle(PressableStyle(scale: 0.96))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    ForEach(Array(s.enumerated()), id: \.element.id) { i, slot in
                        TimelineSlotView(
                            slot: slot,
                            index: i,
                            revealed: revealed,
                            animated: animateReveal,
                            stagger: rowStagger,
                            duration: rowDuration,
                            bounce: rowBounce,
                            onTapEvent: { ev in describing = ev },
                            onToggleRsvp: onToggleRsvp,
                            onAdd: { Haptics.light(); composing = true }
                        )
                    }

                    // Export the whole day to Apple Calendar — rides the cascade tail.
                    InlineAction(
                        icon: "calendar.badge.plus",
                        label: "Add to your calendar",
                        doneLabel: "Added to your calendar",
                        actionText: "Add",
                        perform: { try await CalendarExport.addDay(date: date, events: events) }
                    )
                    .springReveal(s.count, revealed: revealed, animated: animateReveal,
                                  stagger: rowStagger, duration: rowDuration, bounce: rowBounce)
                    .padding(.top, 6)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
        }
    }

    // MARK: - Date parsing / formatting

    private var dayDate: Date {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents()
        if p.count == 3 { c.year = p[0]; c.month = p[1]; c.day = p[2] }
        return CalendarModel.gregorian.date(from: c) ?? Date()
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = CalendarModel.gregorian
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE"
        return f
    }()

    private static let prettyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = CalendarModel.gregorian
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // MARK: - DEBUG sample day (deterministic cascade for headless frame-matching)

    /// `-calendar-sample` forces the reference's exact 3-event day (→ a 5-slot
    /// ruler once open slots are filled in) so the cascade renders regardless of
    /// network/auth. No effect in release, never touches real data.
    private var showSample: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-calendar-sample")
        #else
        return false
        #endif
    }

    private var displayEvents: [TimelineEvent] {
        #if DEBUG
        if showSample { return Self.sampleEvents }
        #endif
        return events
    }

    #if DEBUG
    static let sampleEvents: [TimelineEvent] = [
        TimelineEvent(id: "s1", title: "Focus time", startTime: "11:00", location: nil,
                      goingCount: 0, rsvpd: false, clubName: nil, fromJoinedClub: false,
                      details: "A protected hour to get real work done — no meetings, phone on Do Not Disturb.",
                      category: .books),
        TimelineEvent(id: "s2", title: "Lunch", startTime: "13:00", location: "Local Blend",
                      goingCount: 4, rsvpd: false, clubName: nil, fromJoinedClub: false,
                      details: "Midday break at Local Blend. Grab a table on the patio if it's sunny.",
                      category: .food),
        TimelineEvent(id: "s3", title: "Check emails", startTime: "15:00", location: nil,
                      goingCount: 0, rsvpd: false, clubName: "Newsletter Club", fromJoinedClub: true,
                      details: "Clear the inbox and reply to anything from the newsletter crew.",
                      category: .other),
    ]
    #endif

    // MARK: - DEBUG replay hook

    #if DEBUG
    /// `-calendar-replay` loops the reveal on the reference's 2.115s cadence so a
    /// headless recording can be montaged frame-for-frame against the reference.
    private func startReplayIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-calendar-replay") else { return }
        guard replayTask == nil else { return }
        replayTask = Task { @MainActor in
            while !Task.isCancelled {
                animateReveal = false
                revealed = false
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled else { return }
                animateReveal = true
                revealed = true
                try? await Task.sleep(nanoseconds: 2_115_000_000)
            }
        }
    }
    #endif
}

// MARK: - Timeline model

/// One hour of the day: an event block or an open "No plans" slot.
struct DaySlot: Identifiable {
    let id: String
    let hourLabel: String
    let kind: Kind

    enum Kind {
        case event(TimelineEvent)   // tint + glyph derive from ev.category at render
        case open
    }

    /// Build the hourly ruler: for the span from the first event hour to the last,
    /// each hour is its event(s) or an open slot. Events with no parseable time are
    /// appended after. Each event's color + icon come from its `category`.
    static func build(from events: [TimelineEvent]) -> [DaySlot] {
        var timed: [(Int, TimelineEvent)] = []
        var untimed: [TimelineEvent] = []
        for ev in events {
            if let h = hour(of: ev.startTime) { timed.append((h, ev)) } else { untimed.append(ev) }
        }

        var slots: [DaySlot] = []
        if let minH = timed.map(\.0).min(), let maxH = timed.map(\.0).max() {
            var byHour: [Int: [TimelineEvent]] = [:]
            for (h, ev) in timed { byHour[h, default: []].append(ev) }
            for h in minH...maxH {
                if let evs = byHour[h] {
                    for ev in evs {
                        slots.append(DaySlot(id: "e-\(ev.id)", hourLabel: rulerLabel(hour: h), kind: .event(ev)))
                    }
                } else {
                    slots.append(DaySlot(id: "o-\(h)", hourLabel: rulerLabel(hour: h), kind: .open))
                }
            }
        }
        for ev in untimed {
            slots.append(DaySlot(id: "e-\(ev.id)", hourLabel: "", kind: .event(ev)))
        }
        return slots
    }

    /// Hour-of-day (0–23) from a raw start-time string ("14:00", "2:00 PM", …).
    static func hour(of raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let cal = CalendarModel.gregorian
        for fmt in ["HH:mm", "HH:mm:ss", "h:mm a", "h:mma", "ha", "h a"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            if let d = f.date(from: raw.trimmingCharacters(in: .whitespaces)) {
                return cal.component(.hour, from: d)
            }
        }
        return nil
    }

    /// "11.00 AM" / "12.00 PM" / "01.00 PM" — period separator, leading zero (reference).
    static func rulerLabel(hour: Int) -> String {
        let ampm = hour < 12 ? "AM" : "PM"
        var h12 = hour % 12
        if h12 == 0 { h12 = 12 }
        return String(format: "%02d.00 %@", h12, ampm)
    }
}

// MARK: - One hour slot (event or open)

private struct TimelineSlotView: View {
    let slot: DaySlot
    let index: Int
    let revealed: Bool
    var animated: Bool = true
    var stagger: Double = 0.085
    var duration: Double = 0.60
    var bounce: Double = 0.16
    var onTapEvent: ((TimelineEvent) -> Void)? = nil
    var onToggleRsvp: ((TimelineEvent) -> Void)? = nil
    var onAdd: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !slot.hourLabel.isEmpty {
                Text(slot.hourLabel)
                    .font(.monoMedium(11))
                    .monospacedDigit()
                    .foregroundStyle(Hue.inkSecondary)
            }
            switch slot.kind {
            case let .event(ev):
                eventRow(ev)
            case .open:
                openRow
            }
        }
        .springReveal(index, revealed: revealed, animated: animated,
                      stagger: stagger, duration: duration, bounce: bounce)
    }

    // Filled hour — category-colored bar + title (tap → description) + category icon + RSVP.
    private func eventRow(_ ev: TimelineEvent) -> some View {
        let cat = ev.category
        return HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cat.tint)
                .frame(width: 5, height: 48)

            Button {
                Haptics.light()
                onTapEvent?(ev)
            } label: {
                HStack(spacing: 14) {
                    Text(ev.title)
                        .font(.sansBold(19))
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    iconCircle(category: cat)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))

            rsvpCheckbox(ev)
        }
    }

    private func iconCircle(category cat: EventCategory) -> some View {
        Circle()
            .fill(cat.tint)
            .frame(width: 54, height: 54)
            .overlay(
                Image(systemName: cat.glyph)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(cat.label) event")
            )
            .scaleEffect(revealed || reduceMotion ? 1 : 0.5, anchor: .center)
            .animation(
                (animated && !reduceMotion)
                    ? .spring(response: 0.42, dampingFraction: 0.62)
                        .delay(Double(index) * stagger + 0.05)
                    : nil,
                value: revealed
            )
    }

    private func rsvpCheckbox(_ ev: TimelineEvent) -> some View {
        Group {
            if let onToggleRsvp {
                Button {
                    Haptics.light()
                    onToggleRsvp(ev)
                } label: {
                    ZStack {
                        if ev.rsvpd {
                            Circle().fill(Hue.ink)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle().stroke(Hue.inkSecondary.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 26, height: 26)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: ev.rsvpd)
            }
        }
    }

    // Open hour — three dots (in the bar column) + "1 hour → No plans" + add button.
    private var openRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ThreeDots(reduceMotion: reduceMotion)
                .frame(width: 5)

            Text("1 hour  →  No plans")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)

            Spacer(minLength: 8)

            Button {
                onAdd?()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(width: 30, height: 30)
                    .background(Hue.fill, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Add something at this time")
        }
        .frame(minHeight: 48)
    }
}

/// The three stacked dots that mark an open slot — a perpetual staggered flicker
/// (typing-indicator style), running the whole time the day is open, not just on
/// reveal. Reduce Motion → static dots (no looping motion).
private struct ThreeDots: View {
    let reduceMotion: Bool
    @State private var flicker = false

    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Hue.inkSecondary.opacity(0.65))
                    .frame(width: 4, height: 4)
                    .opacity(reduceMotion ? 1 : (flicker ? 1.0 : 0.3))
                    // small pulse — swells a touch past rest at the peak.
                    .scaleEffect(reduceMotion ? 1 : (flicker ? 1.12 : 0.68))
                    .animation(
                        reduceMotion ? nil
                            : .easeInOut(duration: 0.72)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                        value: flicker
                    )
            }
        }
        .onAppear { flicker = true }
    }
}

// MARK: - Description sheet (tap a row)

private struct EventDescriptionSheet: View {
    let event: TimelineEvent
    let date: String
    var onToggleRsvp: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text(event.title)
                    .font(.displaySemi(24))
                    .foregroundStyle(Hue.ink)
                    .padding(.top, 8)

                metaRow(icon: "clock", text: whenText, tint: Hue.inkSecondary)
                if let club = event.clubName, !club.isEmpty {
                    metaRow(icon: "person.2.fill", text: club, tint: Hue.ink)
                }
                if let loc = event.location, !loc.isEmpty {
                    metaRow(icon: "mappin.and.ellipse", text: loc, tint: Hue.inkSecondary)
                }

                Divider().overlay(Hue.hairline).padding(.vertical, 4)

                if let d = event.details, !d.isEmpty {
                    Text(d)
                        .font(.sans(15))
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No description yet.")
                        .font(.sans(14))
                        .foregroundStyle(Hue.inkSecondary)
                }

                if let onToggleRsvp {
                    Button {
                        Haptics.light()
                        onToggleRsvp()
                    } label: {
                        Text(event.rsvpd ? "Going" : "RSVP")
                            .font(.sansSemibold(15))
                            .foregroundStyle(event.rsvpd ? .white : Hue.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(event.rsvpd ? Hue.ink : Hue.surface,
                                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                .stroke(event.rsvpd ? Color.clear : Hue.ink.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .padding(.top, 4)
                }

                if event.goingCount > 0 {
                    Text("\(event.goingCount) going")
                        .font(.mono(12)).monospacedDigit()
                        .foregroundStyle(Hue.inkSecondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
        .background(Hue.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func metaRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text).font(.sans(14))
        }
        .foregroundStyle(tint)
    }

    private var whenText: String {
        let day = DateHelpers.prettyDate(date)
        if let t = event.startTime, !t.isEmpty, let h = DaySlot.hour(of: t) {
            return "\(day) · \(DaySlot.rulerLabel(hour: h).replacingOccurrences(of: ".00", with: ":00"))"
        }
        return day
    }
}
