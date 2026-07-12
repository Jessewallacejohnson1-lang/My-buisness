//
//  WeatherWidget.swift
//  Hygge — the weather widget at the top of Today. The numbers of the day: the
//  weather icon (a coral sun by day, a blue moon after dark), place + condition,
//  current temp + today's high/low, a LIVE daylight countdown that becomes a
//  good-night message once the sun's down, sunrise/sunset, and the moon phase.
//
//  Night flips the accent from coral to blue (Hue.sky600) — the icon, the border,
//  the countdown, the sun times, the moon chip — so the card reads as evening at a
//  glance. Real data only: WeatherService (open-meteo, no key, 30-min cache) never
//  shows a fabricated number; MoonPhase is local math; day/night comes from the
//  real sunrise/sunset.
//

import SwiftUI

struct WeatherWidget: View {
    @State private var weather: Weather?
    @State private var moon: MoonInfo = moonInfo(for: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: weatherIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
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

            if weather?.sunrise != nil, weather?.sunset != nil {
                Rectangle().fill(Hue.hairline).frame(height: 1)

                // Live daylight countdown → good-night message once the sun's down.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownRow(now: context.date)
                }

                HStack(spacing: 12) {
                    if let sunrise = weather?.sunrise, let sunset = weather?.sunset {
                        Text("↑\(clock(sunrise))   ↓\(clock(sunset))")
                            .font(.mono(13))
                            .monospacedDigit()
                            .foregroundStyle(isNight ? accent : Hue.ink2)
                    }
                    Spacer(minLength: 6)
                    moonChip
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(accent, lineWidth: 1.5)
        )
        .modifier(CardShadow())
        .task {
            moon = moonInfo(for: Date())
            weather = await WeatherService.current()
        }
    }

    /// The live countdown: "3h 42m 15s of daylight left" during the day (ticking),
    /// a warm good-night once the sun's down.
    @ViewBuilder
    private func countdownRow(now: Date) -> some View {
        HStack(spacing: 8) {
            if let sunrise = weather?.sunrise, let sunset = weather?.sunset {
                if now >= sunrise, now < sunset {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                    HStack(spacing: 0) {
                        Text(durationHMS(sunset.timeIntervalSince(now)))
                            .font(.monoMedium(15)).monospacedDigit()
                            .foregroundStyle(accent)
                        Text(" of daylight left")
                            .font(.sans(14))
                            .foregroundStyle(Hue.ink2)
                    }
                } else {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                    HStack(spacing: 0) {
                        Text("Good night, St. Joe")
                            .font(.sansSemibold(14))
                            .foregroundStyle(accent)
                        Text(" — first light at \(clock(sunrise))")
                            .font(.sans(13))
                            .foregroundStyle(Hue.ink2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var moonChip: some View {
        HStack(spacing: 5) {
            Image(systemName: moon.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isNight ? accent : Hue.ink2)
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

    // MARK: - Day/night + formatting

    /// True once the sun's down (past sunset or before sunrise), from the real sun
    /// times; falls back to the weather state when times are unavailable.
    private var isNight: Bool {
        guard let sunrise = weather?.sunrise, let sunset = weather?.sunset else {
            return weather?.state == .clearNight
        }
        let now = Date()
        return now >= sunset || now < sunrise
    }

    /// Coral by day, a calm blue after dark.
    private var accent: Color { isNight ? Hue.sky600 : Hue.accent }

    /// A blue moon after dark; otherwise the little sun (or wet/snowy/stormy glyph).
    private var weatherIcon: String {
        if isNight { return "moon.stars.fill" }
        switch weather?.state {
        case .snow:  return "snowflake"
        case .rain:  return "cloud.rain.fill"
        case .storm: return "cloud.bolt.fill"
        default:     return "sun.max.fill"
        }
    }

    /// "3h 42m 15s" / "42m 15s" / "15s" — seconds included so the timer ticks.
    private func durationHMS(_ secs: TimeInterval) -> String {
        let total = max(0, Int(secs))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = WeatherService.townTZ
        f.dateFormat = "h:mm"
        return f
    }()
    private func clock(_ d: Date) -> String { Self.clockFormatter.string(from: d) }
}
