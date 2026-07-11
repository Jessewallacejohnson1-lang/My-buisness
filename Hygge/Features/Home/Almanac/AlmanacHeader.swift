//
//  AlmanacHeader.swift
//  Hygge — Zone 1 of the remade Today tab: one living, weather-reactive hero
//  card. Replaces TodayInStJoeCard as the top element (see
//  docs/superpowers/specs/2026-07-11-today-tab-remake-design.md §4 Zone 1).
//
//  Composes, over the shared WeatherBackground: current temp + condition + H/L,
//  a sun row ("↑sunrise ↓sunset"), a moon-phase chip (MoonPhase.swift — local
//  synodic-month math, no network), "daylight left" (sunset − now) when
//  available, the AI "read of the day" line (DailyAlmanac.line), an optional
//  "on this day in St. Joe" fact (OnThisDay.swift — hidden, never fabricated,
//  when nil), and the daily-quest momentum ring.
//
//  Quest progress: DailyQuest (Backend/Models.swift) carries no numeric target —
//  it's one town-wide daily prompt, not a checklist — so the ring is honestly
//  binary: empty until `questDone`, then draws to full with a spring-pop +
//  success haptic. `questCount` (the real per-day neighbor tally HomeModel
//  already tracks) still shows as a caption. No streak counter (house rule).
//
//  Weather + the AI line + the moon + the on-this-day fact are all loaded
//  internally via `.task`, mirroring how TodayInStJoeCard loads its own
//  `weather` — HomeModel stays focused on agenda/quest/feed state and simply
//  hands this view the quest slice it already owns.
//
//  Reuse: WeatherBackground (backdrop), WeatherService (temp/H-L/sun times),
//  DailyAlmanac.line(auth:) (AI sentence), moonInfo(for:) (MoonPhase.swift),
//  onThisDay(auth:) (OnThisDay.swift).
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
        ZStack(alignment: .topLeading) {
            WeatherBackground(state: weather?.state)

            // Scrim so white text stays legible over any sky, same recipe as
            // TodayInStJoeCard.
            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.60)],
                           startPoint: .top, endPoint: .bottom)

            content
                .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            weatherRow
            divider
            skyRow

            if let dayLine {
                Text(dayLine)
                    .font(.sans(15))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            }

            if let fact {
                onThisDayRow(fact)
            }

            divider
            questRow
            CompanionSlot()
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
    }

    /// Place · condition · big temp + H/L.
    private var weatherRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("St. Joseph, Minnesota")
                    .font(.sansSemibold(14))
                    .foregroundStyle(.white)
                Text(weather?.label ?? "Checking the sky…")
                    .font(.sans(12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 8)
            if let w = weather {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(w.tempF)°")
                        .font(.monoMedium(36))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("H \(w.highF)°  L \(w.lowF)°")
                        .font(.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 5, y: 1)
    }

    /// Sun times · moon phase chip · daylight left.
    private var skyRow: some View {
        HStack(spacing: 10) {
            if let sunrise = weather?.sunrise, let sunset = weather?.sunset {
                Text("↑\(clock(sunrise))  ↓\(clock(sunset))")
                    .font(.mono(13))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
            }

            moonChip

            Spacer(minLength: 8)

            if let daylight = daylightLeftLabel {
                Text(daylight)
                    .font(.monoMedium(12))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
    }

    private var moonChip: some View {
        HStack(spacing: 5) {
            Image(systemName: moon.symbol)
                .font(.system(size: 12, weight: .medium))
            Text(moon.phaseName)
                .font(.sans(12))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.white.opacity(0.16))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func onThisDayRow(_ f: AlmanacFact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("On this day —")
                .font(.sansSemibold(12))
                .foregroundStyle(.white.opacity(0.75))
            Text(f.fact)
                .font(.sans(13))
                .foregroundStyle(.white.opacity(0.92))
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
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if quest != nil {
                    HStack(spacing: 10) {
                        questButton
                        if questCount > 0 {
                            Text("\(questCount) neighbor\(questCount == 1 ? "" : "s") today")
                                .font(.mono(11))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// A binary momentum ring — DailyQuest has no numeric target, so drawing a
    /// synthesized fraction would be a fabricated number. Empty until complete,
    /// then a full coral ring with a spring-pop + success haptic.
    private var questRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: questDone ? 1 : 0)
                .stroke(Hue.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: questDone)
            Image(systemName: questDone ? "checkmark" : "leaf.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(questDone ? Hue.accent : .white.opacity(0.85))
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
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(questDone ? Color.white.opacity(0.18) : Hue.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(questDone)
    }

    // MARK: - Formatting

    /// "h:mm" in the town's timezone — same convention as AlmanacSection's
    /// clock formatter, so sunrise/sunset read identically across the app.
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = WeatherService.townTZ
        f.dateFormat = "h:mm"
        return f
    }()
    private func clock(_ d: Date) -> String { Self.clockFormatter.string(from: d) }

    /// Sunset − now, formatted "3h 42m of daylight left" / "12m of daylight
    /// left"; nil once the sun's already down (never a negative duration).
    private var daylightLeftLabel: String? {
        guard let sunset = weather?.sunset else { return nil }
        let secs = sunset.timeIntervalSinceNow
        guard secs > 0 else { return nil }
        let mins = Int(secs / 60)
        let h = mins / 60, m = mins % 60
        let value = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "\(value) of daylight left"
    }
}
