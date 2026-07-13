//
//  AlmanacSection.swift
//  Hygge — the Daily Almanac: a warm time-of-day greeting (the "Coffee and Claude"
//  hello) over St. Joe's real day (sun + weather), turned into one low-bar nudge to
//  step outside. The app's "health" pillar, rendered as PLACE — calm, neighborly,
//  real data only (never a fake number).
//
//  On the FIRST open of the day the card writes itself in front of the neighbor:
//  the greeting types out char-by-char (soft coral caret), then the read writes in
//  word-by-word underneath (see TypewriterText). Every later open the same day —
//  and under Reduce Motion — it just renders, fully written, instantly. The once-a-
//  day gate is AlmanacReveal (a UserDefaults day-stamp). DEBUG `-almanac-write`
//  forces the write regardless of the stamp so it can be captured headlessly.
//
//  Sun + weather come from the shared WeatherService.current() (open-meteo, no
//  key) that the WeatherBar above already primed, so this reads the 30-min cache
//  — no second network trip. If the fetch never lands we show a calm, number-free
//  line; if it lands without sun times we drop the clock words. We never invent.
//  The write snapshots whichever read has resolved when the greeting finishes; a
//  later AI-line upgrade lands on the next (static) open.
//
//  TODO: point the nudge at a live trail/event from CommunityAPI (getTrails /
//  getTodayEvents) instead of the fixed Lake Wobegon Trail landmark below.
//

import SwiftUI

/// The once-a-day gate for the Almanac write, keyed on the device-local day.
enum AlmanacReveal {
    private static let key = "hygge.almanac.lastWrittenDay"

    /// True on the first open of a new local day (no write recorded for today yet).
    static func shouldWriteToday() -> Bool {
        UserDefaults.standard.string(forKey: key) != DateHelpers.localDate()
    }

    static func markWrittenToday() {
        UserDefaults.standard.set(DateHelpers.localDate(), forKey: key)
    }
}

struct AlmanacSection: View {
    /// The neighbor's first name, threaded from HomeModel so a profile edit keeps
    /// the greeting in sync; falls back to the mirror / email locally.
    var name: String?

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var weather: Weather?
    @State private var aiLine: String?   // the shared AI day-summary; nil → template nudge

    /// The write is a two-stage chain: stage 0 = greeting types, stage 1 = read
    /// writes. `Int.max` means "no write" (a later open, or Reduce Motion) — every
    /// line renders `.shown`. Seeded in `init` from the day-stamp so the very first
    /// frame is already correct (no flash of the finished card before it animates).
    @State private var activeStage: Int
    /// The read snapshotted the instant the greeting finishes, so an AI-line upgrade
    /// arriving mid-write can't re-wrap the text under the cursor.
    @State private var frozenRead: AttributedString?
    /// The greeting snapshotted at write start, so an async name load (HomeModel) that
    /// resolves to a different name can't swap the greeting out from under the cursor.
    @State private var frozenGreeting: AttributedString?

    init(name: String? = nil) {
        self.name = name
        var write = AlmanacReveal.shouldWriteToday()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-almanac-write") { write = true }
        #endif
        _activeStage = State(initialValue: write ? 0 : Int.max)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Hue.accent)
                Text(DailyGreeting.part().rawValue)
                    .font(.mono(11))
                    .tracking(1.5)
                    .foregroundStyle(Hue.ink3)
            }

            // The greeting — types char-by-char with a soft coral caret on day one.
            TypewriterText(
                content: greetingContent,
                mode: .character,
                state: greetingState,
                perUnit: 0.032,
                startDelay: 0.5,           // let the card's spring settle first
                showsCaret: true,
                caretFont: .system(size: 20, weight: .semibold),
                onFinished: greetingDone
            )
            .fixedSize(horizontal: false, vertical: true)

            // The read-of-the-day — writes in word-by-word underneath the greeting.
            TypewriterText(
                content: readContent,
                mode: .word,
                state: readState,
                perUnit: 0.045,
                startDelay: 0.1,
                onFinished: readDone
            )
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.accent, lineWidth: 1.5))
        .modifier(CardShadow())
        .task {
            // Template shows instantly; both fetches ride their own caches and the
            // AI line upgrades the copy in place when it lands (on a later open).
            async let w = WeatherService.current()
            async let l = DailyAlmanac.line(auth: auth)
            weather = await w
            aiLine = await l
        }
        // When the day's data lands, write the real read (fires in the update cycle
        // with fresh state — unlike a detached Task, which would read @State stale).
        .onChange(of: readDataArrived) { _, arrived in
            if arrived { startRead() }
        }
        // Fallback: if the fetch never lands, write the calm template after a grace.
        // Keyed on activeStage, so it auto-cancels the moment the read actually starts.
        .task(id: activeStage) {
            guard activeStage == 1 else { return }
            try? await Task.sleep(for: .seconds(3.0))
            if !Task.isCancelled { startRead(force: true) }
        }
        .onAppear {
            // A writing day was seeded in init. Reduce Motion collapses it to a plain
            // (instant) render; otherwise freeze the greeting (so a late name load can't
            // change it mid-type) and stamp today so it writes only once.
            guard activeStage == 0 else { return }
            if reduceMotion && !forceWrite {
                activeStage = Int.max
                return
            }
            frozenGreeting = liveGreeting
            if !forceWrite { AlmanacReveal.markWrittenToday() }
        }
    }

    // MARK: - Content

    private var resolvedName: String? {
        name ?? Interests.displayName ?? firstNameFromEmail(auth.email)
    }

    /// Frozen for the write (so a late name load can't change it mid-type); live for a
    /// static open so it always reflects the current name.
    private var greetingContent: AttributedString {
        if activeStage == Int.max { return liveGreeting }
        return frozenGreeting ?? liveGreeting
    }

    private var liveGreeting: AttributedString {
        var a = AttributedString(DailyGreeting.line(name: resolvedName))
        a.font = .displaySemi(20)
        a.foregroundColor = Hue.ink
        return a
    }

    /// Live during a normal open (so the AI line upgrades in place) and while the
    /// read reserves its height; frozen the moment the write reaches it.
    private var readContent: AttributedString {
        if activeStage == Int.max { return liveRead() }   // static open
        return frozenRead ?? liveRead()
    }

    private func liveRead() -> AttributedString {
        let nudge = Almanac.nudge(for: weather)
        if let aiLine {
            return Almanac.styled(aiLine, numberTint: nudge.iconTint)
        }
        return Almanac.readBlock(nudge)
    }

    // MARK: - Write chain
    //
    // Stages: 0 = greeting types · 1 = greeting done, read pending (held until the
    // day's data lands) · 2 = read writes · 3 = done · Int.max = static (no write).
    // The greeting types faster (~1.3s) than a cold weather fetch, so the read waits
    // in stage 1 and only writes the REAL read — never the pre-fetch fallback.

    private var readDataArrived: Bool { weather != nil || aiLine != nil }

    private var greetingState: TypewriterState {
        if activeStage == Int.max { return .shown }
        return activeStage == 0 ? .writing : .shown
    }

    private var readState: TypewriterState {
        if activeStage == Int.max { return .shown }
        if activeStage < 2 { return .hidden }      // greeting writing, or read pending
        return activeStage == 2 ? .writing : .shown
    }

    /// Greeting finished → move to "read pending", then start immediately only if the
    /// data is already here (otherwise onChange / the timeout will start it).
    private func greetingDone() {
        guard activeStage == 0 else { return }
        activeStage = 1
        startRead()
    }

    /// Snapshot the read (freezing out any later AI-line churn) and write it. Gated on
    /// the data having arrived so we never write the pre-fetch fallback while the real
    /// read is still in flight — `force` (the timeout) writes the calm fallback anyway
    /// if the fetch never lands. Guarded on stage 1 so every caller is safe.
    private func startRead(force: Bool = false) {
        guard activeStage == 1, force || readDataArrived else { return }
        frozenRead = liveRead()
        activeStage = 2
    }

    private func readDone() {
        guard activeStage == 2 else { return }
        activeStage = 3
    }

    private var forceWrite: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-almanac-write")
        #else
        return false
        #endif
    }
}

// MARK: - Nudge generator

/// Turns a real reading into one calm line + supporting line, keyed on the
/// signals the day actually gives us: daylight left (sunset − now), the weather
/// label/temp, and the season. Coral (accent) tints the "get out" days; a calm
/// sky tint carries the rest/indoor days — the color itself is an honest signal.
///
/// Lines are AttributedString so numbers can carry a monospaced-digit run inline
/// (house rule: numbers stay tabular) while the prose is the system font.
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

    // MARK: Attributed runs — hero + body in the system font, numbers monospaced-digit.

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

    /// The template read as ONE attributed block (hero + detail + optional pointer),
    /// so the daily "write" can reveal it word-by-word as a single flowing set of
    /// lines. Each run keeps its own font, so the hierarchy survives concatenation.
    static func readBlock(_ nudge: Nudge) -> AttributedString {
        var out = nudge.line
        out += run("\n", .sans(15), Hue.ink2)
        out += nudge.detail
        if let pointer = nudge.pointer {
            out += run("\n", .sans(13), Hue.ink3)
            out += run(pointer, .sans(13), Hue.ink3)
        }
        return out
    }

    /// Render an AI-written line: numeric runs (times, temps, counts) in Geist Mono
    /// tinted with the day's mood color, prose in DM Sans — so the AI line honors
    /// "every number is mono" exactly like the template.
    static func styled(_ line: String, numberTint: Color) -> AttributedString {
        let ns = line as NSString
        // A contiguous run of digits (with optional : . , inside) + optional trailing °:
        // matches 8:58, 84°, 2.5, 20 — leaves words like "noon" in DM Sans.
        let re = try! NSRegularExpression(pattern: "[0-9]+(?:[.,:][0-9]+)*°?")
        var out = AttributedString("")
        var idx = 0
        for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let r = m.range
            if r.location > idx {
                out += run(ns.substring(with: NSRange(location: idx, length: r.location - idx)), .sans(16), Hue.ink)
            }
            out += run(ns.substring(with: r), .monoMedium(15), numberTint)
            idx = r.location + r.length
        }
        if idx < ns.length {
            out += run(ns.substring(from: idx), .sans(16), Hue.ink)
        }
        return out
    }

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
