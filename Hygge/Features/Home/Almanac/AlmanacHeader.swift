//
//  AlmanacHeader.swift
//  Hygge — Zone 1 of the remade Today tab: the living almanac, in the app's clean
//  white-card-with-coral-accent style (not a full-bleed weather hero). A white
//  card with a coral accent border, the little weather (sun) icon, and plain ink
//  text — the "old" almanac look, carrying the living content.
//
//  Composes: current temp + condition + H/L, a sun row ("↑sunrise ↓sunset") + a
//  moon-phase chip (MoonPhase.swift — local synodic math, no network), the AI
//  "read of the day" line (DailyAlmanac.line, numbers in mono via Almanac.styled),
//  an optional "on this day in St. Joe" fact (OnThisDay.swift — hidden, never
//  fabricated, when nil), and the daily-quest momentum ring.
//
//  Quest progress: DailyQuest carries no numeric target — one town-wide daily
//  prompt, not a checklist — so the ring is honestly binary: empty until
//  `questDone`, then draws full with a spring-pop + success haptic. `questCount`
//  (the real per-day neighbor tally) shows as a caption. No streak counter.
//
//  Weather + AI line + moon + on-this-day load internally via `.task`, mirroring
//  AlmanacSection; HomeModel stays focused on agenda/quest/feed and hands this the
//  quest slice it already owns.
//

import SwiftUI

struct AlmanacHeader: View {
    let quest: DailyQuest?
    let questCount: Int
    let questDone: Bool
    let onCompleteQuest: () -> Void

    @EnvironmentObject private var auth: AuthStore

    @State private var weather: Weather?
    @State private var dayLine: String?          // DailyAlmanac's AI sentence; nil → hidden
    @State private var fact: AlmanacFact?         // OnThisDay's curated fact; nil → hidden (usual case)
    @State private var moon: MoonInfo = moonInfo(for: Date())
    @State private var ringScale: CGFloat = 1.0   // quest-complete spring-pop

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            weatherRow
            divider
            skyRow

            if let dayLine {
                Text(Almanac.styled(dayLine, numberTint: Hue.accent))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let fact {
                onThisDayRow(fact)
            }

            divider
            questRow
            CompanionSlot()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(Hue.accent, lineWidth: 1.5)
        )
        .modifier(CardShadow())
        .task {
            moon = moonInfo(for: Date())
            async let w = WeatherService.current()
            async let l = DailyAlmanac.line(auth: auth)
            async let f = onThisDay(auth: auth)
            weather = await w
            dayLine = await l
            fact = await f
        }
    }

    // MARK: - Layout

    private var divider: some View {
        Rectangle().fill(Hue.hairline).frame(height: 1)
    }

    /// The little sun icon · place · condition — with the big temp + H/L trailing.
    private var weatherRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: weatherIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Hue.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("St. Joseph, Minnesota")
                    .font(.sansSemibold(14))
                    .foregroundStyle(Hue.ink)
                Text(weather?.label ?? "Checking the sky…")
                    .font(.sans(12))
                    .foregroundStyle(Hue.ink3)
            }

            Spacer(minLength: 8)

            if let w = weather {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(w.tempF)°")
                        .font(.monoMedium(34))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink)
                    Text("H \(w.highF)°  L \(w.lowF)°")
                        .font(.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink3)
                }
            }
        }
    }

    /// Sun times · moon-phase chip. (Daylight-left is dropped — the sunset time and
    /// the day-line already carry it, and it was crowding this row.)
    private var skyRow: some View {
        HStack(spacing: 12) {
            if let sunrise = weather?.sunrise, let sunset = weather?.sunset {
                Text("↑\(clock(sunrise))   ↓\(clock(sunset))")
                    .font(.mono(13))
                    .monospacedDigit()
                    .foregroundStyle(Hue.ink2)
            }

            Spacer(minLength: 6)

            moonChip
        }
    }

    private var moonChip: some View {
        HStack(spacing: 5) {
            Image(systemName: moon.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Hue.ink2)
            Text(moon.phaseName)
                .font(.sans(12))
                .foregroundStyle(Hue.ink2)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Hue.paper100)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Hue.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func onThisDayRow(_ f: AlmanacFact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("ON THIS DAY")
                .font(.mono(10))
                .tracking(0.8)
                .foregroundStyle(Hue.accent)
            Text(f.fact)
                .font(.sans(13))
                .foregroundStyle(Hue.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Quest momentum ring + title + Mark-done CTA + the real neighbor count.
    private var questRow: some View {
        HStack(alignment: .center, spacing: 14) {
            questRing

            VStack(alignment: .leading, spacing: 6) {
                Text(quest?.title ?? "No quest set today")
                    .font(.sansSemibold(14))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if quest != nil {
                    HStack(spacing: 10) {
                        questButton
                        if questCount > 0 {
                            Text("\(questCount) neighbor\(questCount == 1 ? "" : "s") today")
                                .font(.mono(11))
                                .monospacedDigit()
                                .foregroundStyle(Hue.ink3)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// A binary momentum ring — DailyQuest has no numeric target, so a synthesized
    /// fraction would be a fabricated number. Empty until complete, then a full
    /// coral ring with a spring-pop + success haptic.
    private var questRing: some View {
        ZStack {
            Circle()
                .stroke(Hue.paper300, lineWidth: 4)
            Circle()
                .trim(from: 0, to: questDone ? 1 : 0)
                .stroke(Hue.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: questDone)
            Image(systemName: questDone ? "checkmark" : "leaf.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(questDone ? Hue.accent : Hue.ink3)
        }
        .frame(width: 44, height: 44)
        .scaleEffect(ringScale)
        .onChange(of: questDone) { _, done in
            guard done else { return }
            Haptics.success()
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { ringScale = 1.18 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65).delay(0.16)) { ringScale = 1.0 }
        }
    }

    @ViewBuilder
    private var questButton: some View {
        Button {
            guard !questDone else { return }
            onCompleteQuest()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: questDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(questDone ? "Done today" : "Mark done")
                    .font(.sansSemibold(13))
            }
            .foregroundStyle(questDone ? Hue.ink2 : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(questDone ? Hue.paper100 : Hue.accent)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(questDone ? Hue.hairline : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(questDone)
    }

    // MARK: - Formatting

    /// Weather-condition glyph — a little sun by default (and on clear days), the
    /// matching icon for wet/snowy/stormy skies (the states AlmanacSection keys on).
    private var weatherIcon: String {
        switch weather?.state {
        case .snow:  return "snowflake"
        case .rain:  return "cloud.rain.fill"
        case .storm: return "cloud.bolt.fill"
        default:     return "sun.max.fill"
        }
    }

    /// "h:mm" in the town's timezone — same convention as AlmanacSection's clock,
    /// so sunrise/sunset read identically across the app.
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = WeatherService.townTZ
        f.dateFormat = "h:mm"
        return f
    }()
    private func clock(_ d: Date) -> String { Self.clockFormatter.string(from: d) }
}
