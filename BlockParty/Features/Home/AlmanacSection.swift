//
//  AlmanacSection.swift
//  Block Party — the Daily Almanac: a warm time-of-day greeting (the "Coffee and Claude"
//  hello) over St. Joe's real day (sun + weather), turned into one low-bar nudge to
//  step outside. The app's "health" pillar, rendered as PLACE — calm, neighborly,
//  real data only (never a fake number).
//
//  The card opens on a small uppercase date eyebrow (AlmanacDateEyebrow). That line
//  used to live in the Today header; it moved down here so the header could shed a
//  line of chrome without the app losing the date. It is static — it does not type in.
//
//  On the FIRST open of each app launch the card writes itself in front of the
//  neighbor: the greeting types out char-by-char (soft coral caret), then the read
//  writes in word-by-word underneath (see TypewriterText). A pull-to-refresh replays
//  the write (Home bumps `replay`); a tab-return within the same launch — and Reduce
//  Motion — just renders, fully written, instantly. The first-open gate is
//  AlmanacReveal (an in-memory per-launch flag). DEBUG `-almanac-write` forces the
//  write regardless so it can be captured headlessly.
//
//  Sun + weather come from the shared WeatherService.current() (open-meteo, no
//  key), whose cache the utility row's weather tile has usually already primed,
//  so this is normally a cache read — no second network trip (concurrent callers
//  are coalesced into one fetch). If the fetch never lands we show a calm, number-free
//  line; if it lands without sun times we drop the clock words. We never invent.
//  The write snapshots whichever read has resolved when the greeting finishes; a
//  later AI-line upgrade lands on the next (static) open.
//
//  TODO(jesse): point the nudge at a live trail/event from CommunityAPI (getTrails /
//  getTodayEvents) instead of the fixed Lake Wobegon Trail landmark below.
//

import SwiftUI
import UIKit   // UIAccessibility.isReduceMotionEnabled — read in init, before @Environment exists

/// First-open gate for the Almanac write, scoped to the app LAUNCH (not the day):
/// the card writes itself the first time Home appears each launch, and again on any
/// pull-to-refresh (driven by AlmanacSection's `replay` nonce from Home). A fresh
/// launch resets it, so every time you open the app the Almanac greets you by writing
/// itself — while a tab-return within the same launch stays instant, and Reduce Motion
/// never animates. Main-actor only (mutated from SwiftUI view lifecycle).
@MainActor
enum AlmanacReveal {
    static var hasWrittenThisLaunch = false
}

struct AlmanacSection: View {
    /// The neighbor's first name, threaded from HomeModel so a profile edit keeps
    /// the greeting in sync; falls back to the mirror / email locally.
    var name: String?

    /// A monotonic token from Home, bumped on pull-to-refresh: each change replays the
    /// write. The first open of the launch writes automatically (seeded in init).
    var replay: Int = 0

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var weather: Weather?
    @State private var aiLine: String?   // this user's AI day-line; nil → template nudge
    /// True once the AI-line fetch has RESOLVED (even to nil) — lets us tell "still
    /// loading" apart from "loaded, no line", so the loading skeleton knows when to lift.
    @State private var lineLoaded = false
    /// Flips true ~300ms after appear: the skeleton lifts to the fallback if the AI
    /// line hasn't landed by then (a cache hit usually beats it, and shows directly).
    @State private var read300msReady = false

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

    init(name: String? = nil, replay: Int = 0) {
        self.name = name
        self.replay = replay
        // First open of the launch writes itself; a tab-return within the launch, or
        // Reduce Motion, renders instantly. Reduce Motion is read HERE (not only in
        // onAppear) so the very first frame is already correct — no flash of the
        // finished card before it would animate.
        var write = !AlmanacReveal.hasWrittenThisLaunch && !UIAccessibility.isReduceMotionEnabled
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-almanac-write") { write = true }
        // Force the resting (already-written) card so a screenshot captures the read
        // fully rendered, not mid-write.
        if ProcessInfo.processInfo.arguments.contains("-almanac-static") { write = false }
        #endif
        _activeStage = State(initialValue: write ? 0 : Int.max)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The day's date, moved DOWN out of the Today header and re-homed here as a
            // quiet eyebrow: the header sheds a line of chrome without the app losing
            // the date. Static chrome — it never types in and never joins the write
            // sequence, so it renders immediately on both the writing and static paths.
            AlmanacDateEyebrow()
                // The eyebrow sits 8pt above the greeting, tighter than this VStack's
                // 12pt rhythm, so it reads as a label ON the greeting rather than as a
                // sibling line: pull the last 4pt back.
                .padding(.bottom, -4)

            // The greeting — a warm, inviting hello with a time-of-day glyph inline to
            // its left: a sunrise at dawn, the high sun midday, the moon at night (the
            // town's real part of day — the same one the read speaks in). It types
            // char-by-char with a soft coral caret on day one; the glyph sits steady.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: greetingGlyph.symbol)
                    .font(.system(size: greetingSize - 1, weight: .semibold))
                    .foregroundStyle(greetingGlyph.tint)
                    .offset(y: 1)   // nudge the glyph to sit centered on the first line
                    .accessibilityHidden(true)

                TypewriterText(
                    content: greetingContent,
                    mode: .character,
                    state: greetingState,
                    perUnit: 0.032,
                    startDelay: 0.5,           // let the card's spring settle first
                    showsCaret: true,
                    caretFont: .system(size: greetingSize, weight: .bold),
                    onFinished: greetingDone
                )
                // The greeting stays a ONE-LINE hero, always: short hellos render big at
                // full size; a wordier line (or a long name) auto-dims to fit rather than
                // ever wrapping to a second line. The read below is unaffected.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            }

            // The read-of-the-day — writes in word-by-word underneath the greeting.
            // On a static open we hold a brief skeleton (<=300ms) so a fast cache-hit
            // AI line renders directly instead of flashing the template first.
            if showReadSkeleton {
                AlmanacReadSkeleton()
            } else {
                TypewriterText(
                    content: readContent,
                    mode: .word,
                    state: readState,
                    perUnit: 0.045,
                    startDelay: 0.3,   // a breath after the greeting lands, before the read writes
                    onFinished: readDone
                )
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .modifier(CardShadow())
        .task {
            // Both fetches ride their own caches; the AI line swaps into the read in
            // place when it lands (same open), else the template fallback stands.
            #if DEBUG
            if let demo = Self.debugDemoLine { aiLine = demo; lineLoaded = true }
            #endif
            async let w = WeatherService.current()
            async let l = DailyAlmanac.line(auth: auth)
            weather = await w
            #if DEBUG
            if Self.debugDemoLine != nil { return }        // canned line already set
            if Self.debugFail { lineLoaded = true; return } // force the template fallback
            #endif
            aiLine = await l
            lineLoaded = true
        }
        // Skeleton grace: lift to the fallback if the AI line hasn't landed in 300ms.
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            read300msReady = true
        }
        // A slow AI line that lands after the read already settled swaps in silently.
        // (During a static open the read is live and swaps on its own; this covers the
        // post-write resting state.)
        .onChange(of: aiLine) { _, line in
            guard let line, activeStage == 3 else { return }
            frozenRead = Almanac.styled(line)
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
            // A first-open write was seeded in init (Reduce Motion & tab-returns already
            // skipped it there). Freeze the greeting so a late name load can't change it
            // mid-type, and mark this launch written so a tab-return stays instant.
            guard activeStage == 0 else { return }
            frozenGreeting = liveGreeting
            if !forceWrite { AlmanacReveal.hasWrittenThisLaunch = true }
        }
        // Pull-to-refresh (Home bumps `replay`) re-writes the card in sync with the
        // spring-back — the greeting's startDelay lets the spring settle first. Reduce
        // Motion still renders instantly.
        .onChange(of: replay) { _, _ in
            guard replay > 0, !reduceMotion || forceWrite else { return }
            frozenRead = nil
            frozenGreeting = liveGreeting
            activeStage = 0
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
        a.font = .display(greetingSize)      // bold hero — was semibold 20
        a.foregroundColor = Hue.ink
        return a
    }

    /// The greeting's type size — a warm card hero (up from the old eyebrow-era 20).
    /// The inline glyph and the write caret both track it so they stay in sync.
    private let greetingSize: CGFloat = 24

    /// Time-of-day glyph shown inline before the greeting: sunrise → high sun → moon.
    /// The sun carries the warmth (honey) tint; the moon the calm night (sky) tint —
    /// the same one the read uses once the sun's down. An honest signal, not decoration.
    private var greetingGlyph: (symbol: String, tint: Color) {
        switch DailyGreeting.part() {
        case .morning:   return ("sunrise.fill",    Hue.ink)
        case .afternoon: return ("sun.max.fill",    Hue.ink)
        case .evening:   return ("moon.stars.fill", Hue.ink)
        }
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
            return Almanac.styled(aiLine)
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
        // If the AI line landed while the template was writing, swap it in now (silent).
        if let aiLine { frozenRead = Almanac.styled(aiLine) }
    }

    /// Hold a brief skeleton only on a static (non-writing) open, before the first read
    /// content resolves. Lifts the moment the AI line lands, the fetch resolves, or 300ms
    /// passes — so a cache-hit line shows directly and a slow one falls back cleanly.
    private var showReadSkeleton: Bool {
        activeStage == Int.max && aiLine == nil && !lineLoaded && !read300msReady
    }

    private var forceWrite: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-almanac-write")
        #else
        return false
        #endif
    }

    #if DEBUG
    /// `-almanac-demo-line "<text>"` — inject a canned AI line (renders `**bold**`),
    /// so the personalized card can be screenshotted without a deployed function.
    private static var debugDemoLine: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-almanac-demo-line"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    /// `-almanac-fail` — simulate the API failing so the on-device template fallback shows.
    private static var debugFail: Bool {
        ProcessInfo.processInfo.arguments.contains("-almanac-fail")
    }
    #endif
}

/// The date line the Today header used to carry, rendered as a small uppercase eyebrow
/// at the top of the almanac card ("SATURDAY, AUGUST 1"). The visible text comes from
/// `TodayHeader.eyebrow` — the one definition of the app's date line, on the town's
/// clock — so the header and this card can never drift apart.
private struct AlmanacDateEyebrow: View {
    /// Captured ONCE, then used for both the visible text and the spoken label, so the
    /// two can't straddle midnight and disagree about what day it is.
    private let today = Date()

    var body: some View {
        Text(TodayHeader.eyebrow(for: today))
            .font(.sansSemibold(11))
            .tracking(0.6)
            .foregroundStyle(Hue.inkSecondary)
            .lineLimit(1)
            // VoiceOver reads a fully-uppercased string as an acronym and can spell it
            // out letter by letter, so it hears the natural-case date while the eye
            // still gets the uppercase eyebrow. Same day, same words — only the casing.
            .accessibilityLabel(Self.spoken(today))
    }

    /// "Saturday, August 1" — the same fields, town clock, and `en_US` locale as
    /// `TodayHeader.eyebrow`, minus the uppercasing. Pinned to `Town.timeZone` for the
    /// reason `UtilityFormat` pins its formatters: this is the TOWN's date, so a phone
    /// in another zone must not slide it a day.
    private static let spokenFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = Town.timeZone
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static func spoken(_ date: Date) -> String { spokenFormatter.string(from: date) }
}

/// A calm two-bar placeholder for the read while the day's line loads (<=300ms). Ink-on-
/// paper `fill` gray, no shimmer — motion is reserved for confirmation, not loading.
private struct AlmanacReadSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Hue.fill)
                .frame(height: 15)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Hue.fill)
                .frame(height: 15)
                .frame(maxWidth: 210)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
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
                icon: "sun.max", iconTint: Hue.ink,
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
                detail = body("First light is back around ")
                    + bodyNum(clock(sunrise)) + body(".")
            } else {
                detail = body("See you outside tomorrow.")
            }
            return Nudge(icon: "moon.stars.fill", iconTint: Hue.ink,
                         line: hero("Sun's down for the day."), detail: detail, pointer: nil)
        }

        // Cold / snow → stay-in leaning, but still a small brisk nudge.
        if w.state == .snow || temp <= 32 {
            return Nudge(
                icon: "snowflake", iconTint: Hue.ink,
                line: hero("It's ") + heroNum("\(temp)°") + hero(" out."),
                detail: body("Cold and \(labelLower) — but a brisk ") + bodyNum("10")
                    + body("-minute loop still counts. Keep it close to home."),
                pointer: "Try a short stretch of the Lake Wobegon Trail."
            )
        }

        // Rain / storm → a window-side kind of day.
        if w.state == .rain || w.state == .storm {
            let detail: AttributedString
            if let sunset = w.sunset {
                detail = body("Sun's up till ") + bodyNum(clock(sunset))
                    + body(", but it's coming down — take the next dry break outside.")
            } else {
                detail = body("It's coming down out there — take the next dry break outside.")
            }
            return Nudge(icon: "cloud.rain.fill", iconTint: Hue.ink,
                         line: hero("Wet one today."), detail: detail, pointer: nil)
        }

        // Clear-ish, but the light's almost gone → catch the last of it.
        if let sunset = w.sunset {
            let mins = Int(sunset.timeIntervalSince(now) / 60)
            if mins <= 60 {
                let m = max(1, mins)
                return Nudge(
                    icon: "sunset.fill", iconTint: Hue.ink,
                    line: hero("About ") + heroNum("\(m)")
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
            line = hero("Sun's up till ") + heroNum(clock(sunset)) + hero(".")
        } else {
            line = hero("A good day to be outside.")
        }
        return Nudge(
            icon: "sun.max.fill", iconTint: Hue.ink,
            line: line,
            detail: body("\(article(labelLower)) \(labelLower) ") + bodyNum("\(temp)°")
                + body(" \(timeWord) — ") + bodyNum("20")
                + body(" minutes outside can reset the day."),
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
    private static func heroNum(_ s: String) -> AttributedString {
        run(s, .system(size: 19, weight: .bold, design: .monospaced), Hue.ink)
    }
    private static func body(_ s: String) -> AttributedString { run(s, .sans(15), Hue.inkSecondary) }
    private static func bodyNum(_ s: String) -> AttributedString { run(s, .monoMedium(14), Hue.inkSecondary) }

    /// The template read as ONE attributed block (hero + detail + optional pointer),
    /// so the daily "write" can reveal it word-by-word as a single flowing set of
    /// lines. Each run keeps its own font, so the hierarchy survives concatenation.
    static func readBlock(_ nudge: Nudge) -> AttributedString {
        var out = nudge.line
        out += run("\n", .sans(15), Hue.inkSecondary)
        out += nudge.detail
        if let pointer = nudge.pointer {
            out += run("\n", .sans(13), Hue.inkSecondary)
            out += run(pointer, .sans(13), Hue.inkSecondary)
        }
        return out
    }

    /// Render an AI-written line. Emphasis is carried by **double asterisks** in the
    /// copy — the almanac prompt bolds at most two data points (a time, temperature, or
    /// count). Those spans become semibold ink with tabular digits; everything else is
    /// regular ink. Emphasis is weight, never colour (brand rule), and the asterisks
    /// themselves are stripped. A line with no `**` simply renders all prose.
    static func styled(_ line: String) -> AttributedString {
        var out = AttributedString("")
        var rest = Substring(line)
        while let open = rest.range(of: "**") {
            let before = rest[rest.startIndex..<open.lowerBound]
            if !before.isEmpty { out += prose(String(before)) }
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "**") else {
                // Unmatched "**" — render the remainder (asterisks and all) as prose.
                out += prose(String(rest[open.lowerBound...]))
                return out
            }
            let bold = afterOpen[afterOpen.startIndex..<close.lowerBound]
            if !bold.isEmpty { out += emphasis(String(bold)) }
            rest = afterOpen[close.upperBound...]
        }
        if !rest.isEmpty { out += prose(String(rest)) }
        return out
    }

    private static func prose(_ s: String) -> AttributedString { run(s, .sans(16), Hue.ink) }
    private static func emphasis(_ s: String) -> AttributedString {
        run(s, .system(size: 16, weight: .semibold).monospacedDigit(), Hue.ink)
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
