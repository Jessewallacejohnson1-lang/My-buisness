//
//  AlmanacSection.swift
//  Hygge — the Daily Almanac: reads out St. Joe's real day (sun + weather) and
//  turns it into one low-bar nudge to step outside. The app's "health" pillar,
//  rendered as PLACE — calm, neighborly, real data only (never a fake number).
//
//  Sun + weather come from the shared WeatherService.current() (open-meteo, no
//  key) that the WeatherBar above already primed, so this reads the 30-min cache
//  — no second network trip. If the fetch never lands we show a calm, number-free
//  line; if it lands without sun times we drop the clock words. We never invent.
//
//  TODO: point the nudge at a live trail/event from CommunityAPI (getTrails /
//  getTodayEvents) instead of the fixed Lake Wobegon Trail landmark below.
//

import SwiftUI

struct AlmanacSection: View {
    @State private var weather: Weather?

    var body: some View {
        let nudge = Almanac.nudge(for: weather)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: nudge.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(nudge.iconTint)
                Text("ALMANAC")
                    .font(.mono(11))
                    .tracking(1.5)
                    .foregroundStyle(Hue.ink3)
            }

            Text(nudge.line)
                .fixedSize(horizontal: false, vertical: true)

            Text(nudge.detail)
                .fixedSize(horizontal: false, vertical: true)

            if let pointer = nudge.pointer {
                Text(pointer)
                    .font(.sans(13))
                    .foregroundStyle(Hue.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Hue.paper100)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .task { weather = await WeatherService.current() }
    }
}

// MARK: - Nudge generator

/// Turns a real reading into one calm line + supporting line, keyed on the
/// signals the day actually gives us: daylight left (sunset − now), the weather
/// label/temp, and the season. Coral (accent) tints the "get out" days; a calm
/// sky tint carries the rest/indoor days — the color itself is an honest signal.
///
/// Lines are AttributedString so numbers can carry Geist Mono inline (house rule:
/// every number is mono) while the prose stays Spectral/DM Sans.
enum Almanac {
    struct Nudge {
        let icon: String
        let iconTint: Color
        let line: AttributedString    // the hero line
        let detail: AttributedString  // the supporting line
        let pointer: String?          // a real local place, only when going out is the ask
    }

    static func nudge(for weather: Weather?, now: Date = Date()) -> Nudge {
        guard let w = weather else {
            return Nudge(
                icon: "sun.max", iconTint: Hue.accent,
                line: hero("A few minutes outside today."),
                detail: body("Fresh air beats a screen — even a short loop counts."),
                pointer: nil
            )
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WeatherService.townTZ
        let hour = cal.component(.hour, from: now)
        let month = cal.component(.month, from: now)
        let timeWord = hour < 12 ? "morning" : (hour < 17 ? "afternoon" : "evening")
        let temp = w.tempF
        let labelLower = w.label.lowercased()

        // Sun's down for the day → rest, not a nudge.
        if let sunset = w.sunset, now > sunset {
            let detail: AttributedString
            if let sunrise = w.sunrise {
                detail = body("Rest easy — first light's back around ")
                    + bodyNum(clock(sunrise)) + body(".")
            } else {
                detail = body("Rest easy — see you outside tomorrow.")
            }
            return Nudge(icon: "moon.stars.fill", iconTint: Hue.sky600,
                         line: hero("Sun's down for the day."), detail: detail, pointer: nil)
        }

        // Cold / snow → cozy, but still a small brisk nudge.
        if w.state == .snow || temp <= 32 {
            return Nudge(
                icon: "snowflake", iconTint: Hue.sky600,
                line: hero("It's ") + heroNum("\(temp)°", Hue.sky600) + hero(" out."),
                detail: body("Cold and \(labelLower) — but a brisk ") + bodyNum("10")
                    + body("-minute loop still beats the couch. Then earn your cocoa."),
                pointer: "The Lake Wobegon Trail is quiet in the snow."
            )
        }

        // Rain / storm → a window-side kind of day.
        if w.state == .rain || w.state == .storm {
            let detail: AttributedString
            if let sunset = w.sunset {
                detail = body("Sun's up till ") + bodyNum(clock(sunset))
                    + body(", but it's coming down — a window-side coffee counts too.")
            } else {
                detail = body("It's coming down out there — a window-side coffee counts too.")
            }
            return Nudge(icon: "cloud.rain.fill", iconTint: Hue.sky600,
                         line: hero("Wet one today."), detail: detail, pointer: nil)
        }

        // Clear-ish, but the light's almost gone → catch the last of it.
        if let sunset = w.sunset {
            let mins = Int(sunset.timeIntervalSince(now) / 60)
            if mins <= 60 {
                let m = max(1, mins)
                return Nudge(
                    icon: "sunset.fill", iconTint: Hue.accent,
                    line: hero("About ") + heroNum("\(m)", Hue.accent)
                        + hero(" minute\(m == 1 ? "" : "s") of daylight left."),
                    detail: body("Catch the last of it — a short walk before ")
                        + bodyNum(clock(sunset)) + body("."),
                    pointer: trailPointer(month: month)
                )
            }
        }

        // Default: a clear, mild day with time to spare → get outside.
        let line: AttributedString
        if let sunset = w.sunset {
            line = hero("Sun's up till ") + heroNum(clock(sunset), Hue.accent) + hero(".")
        } else {
            line = hero("A good day to be outside.")
        }
        return Nudge(
            icon: "sun.max.fill", iconTint: Hue.accent,
            line: line,
            detail: body("\(article(labelLower)) \(labelLower) ") + bodyNum("\(temp)°")
                + body(" \(timeWord) — ") + bodyNum("20")
                + body(" quiet minutes outside beats any screen."),
            pointer: trailPointer(month: month)
        )
    }

    // MARK: Attributed runs — hero (Spectral) + body (DM Sans), numbers in Geist Mono.

    private static func run(_ s: String, _ font: Font, _ color: Color) -> AttributedString {
        var a = AttributedString(s)
        a.font = font
        a.foregroundColor = color
        return a
    }
    private static func hero(_ s: String) -> AttributedString { run(s, .displaySemi(20), Hue.ink) }
    private static func heroNum(_ s: String, _ tint: Color) -> AttributedString { run(s, .monoMedium(19), tint) }
    private static func body(_ s: String) -> AttributedString { run(s, .sans(15), Hue.ink2) }
    private static func bodyNum(_ s: String) -> AttributedString { run(s, .monoMedium(14), Hue.ink2) }

    /// "h:mm" in the town's timezone → "8:58", "5:47".
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = WeatherService.townTZ
        f.dateFormat = "h:mm"
        return f
    }()
    private static func clock(_ d: Date) -> String { clockFormatter.string(from: d) }

    /// Sentence-initial article for the weather word ("An overcast", "A clear").
    private static func article(_ word: String) -> String {
        "aeiou".contains(word.first ?? " ") ? "An" : "A"
    }

    /// A real St. Joe landmark (the Lake Wobegon Trail — see MapSpots/KnownVenues),
    /// with a defensible seasonal note. Winter is carried by the cold branch.
    private static func trailPointer(month: Int) -> String {
        switch month {
        case 3, 4, 5:   return "The Lake Wobegon Trail is greening up."
        case 9, 10, 11: return "The Lake Wobegon Trail is worth it for the color."
        default:        return "The Lake Wobegon Trail is a good one."
        }
    }
}
