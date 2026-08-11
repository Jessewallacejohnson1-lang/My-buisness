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
        VStack(alignment: .leading, spacing: M.headerToRail) {
            header

            // Recompute every 60 s and on scene activation. The sky moves at
            // the speed of the actual sky — no ambient animation.
            TimelineView(.periodic(from: .now, by: tickInterval)) { context in
                HorizonCard(
                    now: resolvedNow(context.date),
                    sunrise: resolvedSun().rise,
                    sunset: resolvedSun().set,
                    items: items,
                    isLoading: isLoading,
                    onOpenDay: openDay,
                    onSeeAll: onSeeAll
                )
            }
        }
        .padding(.horizontal, M.pageMargin)
        .modifier(DayScheduleDemoOpener(items: items, open: open))
        .modifier(HorizonDebugTapDriver(openDay: openDay, seeAll: onSeeAll))
    }

    /// Same tokens as the rail header it replaces — the heading itself is
    /// out of scope and must not move (see YourDayRail.header for the
    /// baseline-alignment history).
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(YourDayRailCopy.header)
                .font(.dayDisplaySemi(M.headerSize))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let countLabel = YourDayRailCopy.countLabel(items.count) {
                Text(countLabel)
                    .font(.sansMedium(M.bodySize))
                    .foregroundStyle(Hue.inkSecondary)
                    .monospacedDigit()
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
            host.open(DayScheduleRequest(items: items, anchor: anchor, dates: dates))
        }
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
