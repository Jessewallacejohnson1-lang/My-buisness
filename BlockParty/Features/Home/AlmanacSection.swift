//
//  AlmanacSection.swift
//  Block Party — the Daily Almanac as the masthead of today's finite edition:
//  date, greeting + live weather, sun times, an optional civic notice, and one
//  tailored suggestion. Every fact comes from a real local source.
//
//  The card opens on a small uppercase date eyebrow (AlmanacDateEyebrow). That line
//  used to live in the Today header; it moved down here so the header could shed a
//  line of chrome without the app losing the date. It is static — it does not type in.
//
//  On the FIRST open of each app launch the card writes itself in front of the
//  neighbor: the greeting types out char-by-char (ink caret), then the read
//  writes in word-by-word underneath (see TypewriterText). A pull-to-refresh replays
//  the write (Home bumps `replay`); a tab-return within the same launch — and Reduce
//  Motion — just renders, fully written, instantly. The first-open gate is
//  AlmanacReveal (an in-memory per-launch flag). DEBUG `-almanac-write` forces the
//  write regardless so it can be captured headlessly.
//
//  Sun + weather come from the shared WeatherService.current() (open-meteo, no
//  key), whose cache the utility row's weather tile has usually already primed,
//  so this is normally a cache read — no second network trip (concurrent callers
//  are coalesced into one fetch). If it fails, the masthead says sun times are
//  unavailable rather than inventing a reading.
//  The personalized server line wins when the briefing supplies one. Otherwise a
//  deterministic fallback generator uses the user's real upcoming RSVPs and a
//  rotating catalogue built from CommunityAPI plus the app's real local places.
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

    /// The day-line delivered by the briefing payload (`almanac.line`, this user's
    /// row in `almanac_daily`). It arrives with the single briefing round trip and
    /// always wins. Nil falls through to the local suggestion generator. Weather
    /// is deliberately NOT injected: `WeatherService` carries a 15-minute Open-Meteo cache, which is
    /// fresher all day than a snapshot taken once at 6 AM.
    var injectedLine: String?

    /// The RPC's town-anchored date. A local town-clock value is used until the
    /// payload arrives, so the deterministic fallback never follows device time.
    var townDate: String?

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var weather: Weather?
    @State private var weatherLoaded = false
    @State private var debugLine: String?
    @State private var generatedSuggestion: String?
    @State private var suggestionLoaded = false
    /// Flips true ~300ms after appear: the skeleton lifts to the fallback if the
    /// masthead reads have not landed by then (cache hits usually beat it).
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

    init(
        name: String? = nil,
        replay: Int = 0,
        injectedLine: String? = nil,
        townDate: String? = nil
    ) {
        self.name = name
        self.replay = replay
        self.injectedLine = injectedLine
        self.townDate = townDate
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

            // One masthead line: the greeting writes while the live Open-Meteo
            // condition and temperature sit alongside it in SF Pro. The glyph and
            // weather stay steady; only the existing greeting reveal types.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                .layoutPriority(1)
            }

            // Sun times, the optional civic notice, and the suggestion write in
            // word-by-word underneath the greeting as one stable layout snapshot.
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
        .task(id: suggestionTaskID) {
            // Start with the real in-app catalogue, then let live RSVP/trail/place
            // reads enrich it. Network failures leave the static real-place pool.
            #if DEBUG
            debugLine = Self.debugFail ? nil : Self.debugDemoLine
            #endif

            async let weatherRequest = WeatherService.current()
            if hasServerLine {
                weather = await weatherRequest
                weatherLoaded = true
                suggestionLoaded = true
                return
            }

            let date = resolvedTownDate
            let userKey = resolvedUserKey
            generatedSuggestion = Self.makeSuggestion(
                townDate: date,
                userKey: userKey,
                rsvps: [],
                trails: [],
                places: []
            )

            let api = CommunityAPI(auth: auth)
            async let rsvpRequest = try? api.getMyUpcomingRsvps()
            async let trailRequest = try? api.getTrails()
            async let placeRequest = try? api.getPlaces()

            weather = await weatherRequest
            weatherLoaded = true

            let (rsvps, trails, places) = await (rsvpRequest, trailRequest, placeRequest)
            if Task.isCancelled { return }
            generatedSuggestion = Self.makeSuggestion(
                townDate: date,
                userKey: userKey,
                rsvps: rsvps ?? [],
                trails: trails ?? [],
                places: places ?? []
            )
            suggestionLoaded = true
        }
        // The briefing line can arrive after this card first appears. A static
        // card reads it live; a completed write quietly replaces its snapshot.
        .onChange(of: injectedLine) { _, _ in
            refreshFrozenReadIfSettled()
        }
        // Skeleton grace: lift to honest fallback content after 300ms.
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            read300msReady = true
        }
        .onChange(of: debugLine) { _, _ in
            refreshFrozenReadIfSettled()
        }
        .onChange(of: generatedSuggestion) { _, _ in
            refreshFrozenReadIfSettled()
        }
        .onChange(of: weatherSummary) { _, _ in
            // A cold Open-Meteo response may miss the greeting's initial frozen
            // snapshot. Once typing ends, fold it into the same scalable line.
            if activeStage != 0 && activeStage != Int.max {
                frozenGreeting = liveGreeting
            }
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

    private var resolvedTownDate: String {
        Self.nonEmpty(townDate) ?? Self.townDateFormatter.string(from: Date())
    }

    private var resolvedUserKey: String {
        auth.userId ?? auth.email ?? "signed-out"
    }

    private var suggestionTaskID: String {
        "\(resolvedTownDate)|\(resolvedUserKey)"
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
        if let weather {
            var condition = AttributedString(" · \(weather.label), ")
            condition.font = .sansMedium(14)
            condition.foregroundColor = Hue.ink
            a += condition

            var temperature = AttributedString("\(weather.tempF)°")
            temperature.font = .monoMedium(14).monospacedDigit()
            temperature.foregroundColor = Hue.ink
            a += temperature
        }
        return a
    }

    private var weatherSummary: String? {
        weather.map { "\($0.label)|\($0.tempF)" }
    }

    /// The greeting's type size — a warm card hero (up from the old eyebrow-era 20).
    /// The inline glyph and the write caret both track it so they stay in sync.
    private let greetingSize: CGFloat = 24

    /// Time-of-day glyph shown inline before the greeting: sunrise → high sun → moon.
    /// Every state stays ink; the symbol communicates the changing time of day.
    private var greetingGlyph: (symbol: String, tint: Color) {
        switch DailyGreeting.part() {
        case .morning:   return ("sunrise.fill",    Hue.ink)
        case .afternoon: return ("sun.max.fill",    Hue.ink)
        case .evening:   return ("moon.stars.fill", Hue.ink)
        }
    }

    /// Live during a normal open (so the server line upgrades in place) and while the
    /// read reserves its height; frozen the moment the write reaches it.
    private var readContent: AttributedString {
        if activeStage == Int.max { return liveRead() }   // static open
        return frozenRead ?? liveRead()
    }

    private func liveRead() -> AttributedString {
        Almanac.mastheadBlock(
            sunLine: Almanac.sunLine(for: weather),
            civicLine: civicLine,
            suggestion: resolvedSuggestion
        )
    }

    private var resolvedSuggestion: String {
        // The payload prop is read directly so a late RPC update cannot lose a
        // race with the write chain. DEBUG demo copy follows the same server-line
        // styling path, then real-data generator, then the honest generic floor.
        if let line = Self.nonEmpty(injectedLine) { return line }
        if let line = Self.nonEmpty(debugLine) { return line }
        if let line = Self.nonEmpty(generatedSuggestion) { return line }
        return "Take a few minutes for St. Joe today."
    }

    private var hasServerLine: Bool {
        Self.nonEmpty(injectedLine) != nil || Self.nonEmpty(debugLine) != nil
    }

    private var civicLine: String? {
        AlmanacCivicLine.text(
            on: Date(),
            pickupWeekday: GarbageSchedule.defaultWeekday,
            // TODO(school-closing-source): inject the town's verified closure line
            // here when a source exists. Nil means this slot simply stays absent.
            schoolClosing: nil,
            calendar: Town.calendar
        )
    }

    // MARK: - Write chain
    //
    // Stages: 0 = greeting types · 1 = greeting done, read pending (held until the
    // day's data lands) · 2 = read writes · 3 = done · Int.max = static (no write).
    // The greeting types faster (~1.3s) than a cold weather fetch, so the read waits
    // in stage 1 and only writes the REAL read — never the pre-fetch fallback.

    private var readDataArrived: Bool {
        weatherLoaded && (hasServerLine || suggestionLoaded)
    }

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
        frozenGreeting = liveGreeting
        activeStage = 1
        startRead()
    }

    /// Snapshot the read (freezing out any later data churn) and write it. Gated on
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
        // If a server line or RSVP landed mid-write, adopt the newest full masthead.
        frozenRead = liveRead()
    }

    private func refreshFrozenReadIfSettled() {
        guard activeStage == 3 else { return }
        frozenRead = liveRead()
    }

    /// Hold a brief skeleton only on a static (non-writing) open, before the first read
    /// content resolves. It lifts when the reads resolve or after 300ms, so cached
    /// content shows directly and a slow network falls back cleanly.
    private var showReadSkeleton: Bool {
        activeStage == Int.max && !readDataArrived && !read300msReady
    }

    private var forceWrite: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-almanac-write")
        #else
        return false
        #endif
    }

    // MARK: - Suggestion inputs

    /// Maps real app/API models into the generator's network-free input types.
    private static func makeSuggestion(
        townDate: String,
        userKey: String,
        rsvps: [UpcomingEvent],
        trails: [Trail],
        places: [POI]
    ) -> String? {
        let rsvpInputs = rsvps.map {
            AlmanacSuggestionGenerator.RSVP(
                id: $0.id,
                title: $0.title,
                eventDate: $0.eventDate,
                startTime: $0.startTime,
                location: $0.location
            )
        }

        var subjects = MapSpots.all.map {
            AlmanacSuggestionGenerator.Subject(
                id: "map:\($0.id)",
                name: $0.name,
                kind: subjectKind(for: $0.category)
            )
        }
        subjects += KnownVenues.suggestions.enumerated().map { index, name in
            .init(id: "venue:\(index):\(name.lowercased())", name: name, kind: .place)
        }
        subjects += Places.all.map {
            .init(id: "editorial:\($0.id)", name: $0.name, kind: .landmark)
        }
        subjects += trails.map {
            .init(id: "trail:\($0.id)", name: $0.title, kind: .trail)
        }
        subjects += places.map {
            .init(
                id: "poi:\($0.id)",
                name: $0.name,
                kind: $0.family == .food ? .food : .business
            )
        }

        return AlmanacSuggestionGenerator.suggestion(for: .init(
            townDate: townDate,
            userKey: userKey,
            rsvps: rsvpInputs,
            subjects: subjects
        ))
    }

    private static func subjectKind(
        for category: SpotCategory
    ) -> AlmanacSuggestionGenerator.SubjectKind {
        switch category {
        case .trail: return .trail
        case .park: return .park
        case .coffee: return .food
        case .fitness, .downtown: return .place
        case .college, .chapel: return .landmark
        case .default: return .place
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let townDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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

// MARK: - Masthead formatting

/// Builds the masthead's sun/civic/suggestion rows as attributed SF Pro runs.
/// Numbers use tabular figures and every row stays monochrome ink-on-paper.
enum Almanac {
    /// Sun times always own one logical line. Missing fields are reported rather
    /// than guessed, while a partial Open-Meteo response still shows what it has.
    static func sunLine(for weather: Weather?) -> String {
        switch (weather?.sunrise, weather?.sunset) {
        case let (sunrise?, sunset?):
            return "Sunrise \(clock(sunrise)) · sunset \(clock(sunset))"
        case let (sunrise?, nil):
            return "Sunrise \(clock(sunrise))"
        case let (nil, sunset?):
            return "Sunset \(clock(sunset))"
        case (nil, nil):
            return "Sun times unavailable"
        }
    }

    /// Lines 3–5 share one attributed block so the existing word-by-word reveal
    /// reserves its final layout. A missing civic line adds no newline or spacer.
    static func mastheadBlock(
        sunLine: String,
        civicLine: String?,
        suggestion: String
    ) -> AttributedString {
        var out = run(sunLine, .sansMedium(14), Hue.inkSecondary)
        if let civicLine, !civicLine.isEmpty {
            out += run("\n", .sans(14), Hue.inkSecondary)
            out += run(civicLine, .sansMedium(14), Hue.ink)
        }
        out += run("\n", .sans(15), Hue.ink)
        out += styled(suggestion)
        return out
    }

    // Legacy nudge model remains source-compatible for rollback previews, but the
    // production masthead no longer calls it or carries a fixed landmark pointer.
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
                pointer: nil
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
                    pointer: nil
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
            pointer: nil
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

    /// "h:mm a" in the town's timezone → "8:58 PM", "5:47 AM".
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = WeatherService.townTZ
        f.dateFormat = "h:mm a"
        return f
    }()
    private static func clock(_ d: Date) -> String { clockFormatter.string(from: d) }

    /// Sentence-initial article for the weather word ("An overcast", "A clear").
    private static func article(_ word: String) -> String {
        "aeiou".contains(word.first ?? " ") ? "An" : "A"
    }

}
