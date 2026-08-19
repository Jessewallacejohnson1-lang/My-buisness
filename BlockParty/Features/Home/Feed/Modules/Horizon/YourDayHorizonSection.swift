//
//  YourDayHorizonSection.swift
//  BlockParty
//
//  The "Your day" section body: the untouched section heading over the
//  horizon card. Owns the two routes — card body → the day schedule sheet,
//  See all → today's postings in Activities — and the once-a-minute clock
//  that keeps the sky honest.
//

import SwiftUI

struct YourDayHorizonSection: View {
    let items: [DayItem]
    let sunrise: Date?
    let sunset: Date?
    var isLoading = false
    let dates: any DateProviding
    /// See all → today's postings (Activities filtered to today).
    let onSeeAll: () -> Void

    @Environment(\.daySchedule) private var host
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var M: YourDayRailMetrics.Type { YourDayRailMetrics.self }

    var body: some View {
        // Recompute every 60 s and on scene activation. The sky moves at
        // the speed of the actual sky — no ambient animation. Solar times
        // are re-dated onto now's town day so a session that stays mounted
        // across midnight keeps a truthful sky. The HEADER lives inside
        // the same tick as the card so both count the same today with the
        // same now — a raw items.count up here once read "See all 3 ›"
        // over "1 plan today" (review finding: the picture contradicting
        // the words is the exact defect this card was rebuilt to kill).
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let now = resolvedNow(context.date)
            let sun = resolvedSun()
            let day = HorizonDay(items: items, axis: TimeAxis(now: now, width: 1), now: now)
            VStack(alignment: .leading, spacing: M.headerToRail) {
                header(todayCount: day.yoursCount + day.openCount)
                HorizonCard(
                    now: now,
                    sunrise: SolarSky.rebase(sun.rise, ontoDayOf: now),
                    sunset: SolarSky.rebase(sun.set, ontoDayOf: now),
                    items: items,
                    isLoading: isLoading,
                    onOpenDay: openDay
                )
            }
        }
        .padding(.horizontal, M.pageMargin)
        .modifier(DayScheduleDemoOpener(items: items, open: open))
        .modifier(HorizonDebugTapDriver(openDay: openDay, seeAll: onSeeAll))
    }

    /// Heading plus the section's one See-all route: a plain "See all 16 ›"
    /// text link (App Store section-header pattern — no fill, no border),
    /// which replaced both the old "16 things" count and the card's pill.
    /// The heading keeps its tokens and firstTextBaseline alignment.
    private func header(todayCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(YourDayRailCopy.header)
                .font(.dayDisplaySemi(M.headerSize))
                .foregroundStyle(Hue.ink)
                // The heading is its own element: the card announces the
                // counts itself (double-speak history), and the link below
                // must stay independently tappable for VoiceOver.
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let link = HorizonCopy.seeAllLink(todayCount) {
                Button(action: onSeeAll) {
                    // ≥44 pt hit target the way the deleted pill proved it:
                    // padding grows the label (and so the button's real hit
                    // region), then the outer negative padding hands the
                    // space back so the firstTextBaseline alignment holds.
                    Text(link)
                        .font(.sansMedium(M.bodySize))
                        .foregroundStyle(Hue.inkSecondary)
                        .monospacedDigit()
                        .padding(15)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FeedCardPressStyle())
                .padding(-15)
                .accessibilityLabel(
                    HorizonCopy.seeAllLinkAccessibilityLabel(todayCount))
            }
        }
    }

    // MARK: Routes

    private func openDay() {
        open(.top)
    }

    /// Card body → the full day schedule, through the shared host lane so
    /// the sheet lands above the tab bar. Galleries and previews mount no
    /// host; there the card tap is inert by design (the day sheet is the
    /// only whole-day destination, and it needs the host).
    private func open(_ anchor: DayScheduleAnchor) {
        guard let host else { return }
        withAnimation(reduceMotion ? DayScheduleMotion.reduced : DayScheduleMotion.open) {
            host.open(DayScheduleRequest(items: items, anchor: anchor, dates: sheetDates))
        }
    }

    /// The sheet reads the same pinned clock the card renders with — under
    /// `-BPMockNow` the two surfaces must agree on what time it is.
    private var sheetDates: any DateProviding {
        #if DEBUG
        if let mock = HorizonMock.launchOverride { return FixedDateProvider(mock.now) }
        #endif
        return dates
    }

    // MARK: Mock plumbing (compiles out of Release)

    private var tickInterval: TimeInterval {
        #if DEBUG
        if HorizonMock.timeSpeed != nil { return 0.5 }
        #endif
        return 60
    }

    private func resolvedNow(_ timeline: Date) -> Date {
        #if DEBUG
        if let mock = HorizonMock.launchOverride {
            // `-BPMockNowSpeed <x>` runs the mock clock at x× so the sunset
            // swap choreography can be recorded instead of waited for.
            if let speed = HorizonMock.timeSpeed {
                let elapsed = timeline.timeIntervalSince(HorizonMock.launchInstant)
                return mock.now.addingTimeInterval(max(elapsed, 0) * speed)
            }
            return mock.now
        }
        #endif
        // `timeline` drives the 60 s refresh; the instant itself comes from
        // the module's injected clock so tests and previews stay pinned.
        _ = timeline
        return dates.now
    }

    private func resolvedSun() -> (rise: Date?, set: Date?) {
        #if DEBUG
        if let mock = HorizonMock.launchOverride { return (mock.sunrise, mock.sunset) }
        #endif
        return (sunrise, sunset)
    }
}

/// `-horizon-press-card` / `-horizon-press-seeall` invoke the two routes'
/// own closures after mount — there is no tap automation in this simulator
/// setup, and pressing the real closure is how this repo proves where a
/// button goes (same pattern as `-yourday-open-add`).
private struct HorizonDebugTapDriver: ViewModifier {
    let openDay: () -> Void
    let seeAll: () -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            let args = ProcessInfo.processInfo.arguments
            let pressCard = args.contains("-horizon-press-card")
            let pressSeeAll = args.contains("-horizon-press-seeall")
            guard pressCard || pressSeeAll else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if pressCard { openDay() }
            if pressSeeAll { seeAll() }
        }
        #else
        content
        #endif
    }
}
