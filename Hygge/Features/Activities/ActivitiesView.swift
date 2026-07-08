//
//  ActivitiesView.swift
//  Hygge — "Explore": an AllTrails-style browse surface on a clean white page.
//  Rounded search + coral category chips + big photo cards for events, clubs,
//  and trails. Coral (Hue.accent) is the one accent; cards carry a saved
//  bookmark, a real-data metadata row, and a coral primary action.
//

import SwiftUI
import MapKit

struct ActivitiesView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = ActivitiesModel()

    @State private var filter: Filter = ActivitiesView.initialFilter()
    @State private var timeFrame: TimeFrame = ActivitiesView.initialTimeFrame()
    @State private var query = ""
    @State private var trailsShowingMap = false

    /// DEBUG-only: `-explore-filter events|clubs|trails` starts on a given chip so
    /// simulator verification can screenshot each card state headlessly. Mirrors
    /// the `-open-tab` / `-force-nonadmin` flags. No effect in release builds.
    private static func initialFilter() -> Filter {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-explore-filter"), i + 1 < args.count,
           let f = Filter(rawValue: args[i + 1].capitalized) {
            return f
        }
        #endif
        return .all
    }

    /// DEBUG-only: `-explore-timeframe today|week|month|upcoming` starts on a given
    /// time frame so each filtered state can be screenshotted headlessly.
    private static func initialTimeFrame() -> TimeFrame {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-explore-timeframe"), i + 1 < args.count {
            switch args[i + 1] {
            case "today":    return .today
            case "week":     return .week
            case "month":    return .month
            case "upcoming": return .upcoming
            default: break
            }
        }
        #endif
        return .upcoming
    }

    @Environment(\.openURL) private var openURL

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    enum Filter: String, CaseIterable {
        case all = "All", events = "Events", clubs = "Clubs", trails = "Trails"
        var icon: String {
            switch self {
            case .all:    return "square.grid.2x2.fill"
            case .events: return "calendar"
            case .clubs:  return "person.2.fill"
            case .trails: return "figure.hiking"
            }
        }
    }

    /// A date window applied to events only (clubs/trails have no date).
    enum TimeFrame: String, CaseIterable {
        case upcoming = "Upcoming", today = "Today", week = "This week", month = "This month"
        var icon: String {
            switch self {
            case .upcoming: return "infinity"
            case .today:    return "sun.max"
            case .week:     return "calendar"
            case .month:    return "calendar.badge.clock"
            }
        }
    }

    var body: some View {
        Group {
            if filter == .trails && trailsShowingMap {
                TrailsMapView(trails: trails, onBack: { trailsShowingMap = false })
            } else {
                explore
            }
        }
        .task { await model.load(api) }
    }

    // MARK: - Explore scroll

    private var explore: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Extra top room so the search pill clears the brand badge pinned
                // to the top-right safe-area corner (see RootView / brandBadge()).
                searchBar.padding(.top, 44)
                categoryChips

                if filter == .trails {
                    trailsMapLink.padding(.horizontal, 18)
                }

                if model.loading && !model.loaded {
                    ProgressView().tint(Hue.gray)
                        .frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    feed.padding(.horizontal, 18)
                }

                Color.clear.frame(height: 96)
            }
        }
        .background(Hue.surface)
        .refreshable { await model.load(api) }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Search + chips

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Hue.gray)
            TextField("Search St. Joe", text: $query)
                .font(.sans(15))
                .foregroundStyle(Hue.mapInk)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.15)) { query = "" } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(Hue.grayLight)
                }
                .buttonStyle(.plain)
            } else {
                if timeFrame != .upcoming {
                    Text(timeFrame.rawValue)
                        .font(.mono(12)).monospacedDigit()
                        .foregroundStyle(Hue.accent)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                timeFrameMenu
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: timeFrame)
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(Hue.bgSubtle)
        .clipShape(Capsule())
        .padding(.horizontal, 18)
    }

    /// The time-frame picker on the search pill's trailing circle. Resting
    /// (Upcoming) is a coral glyph on white; any active window flips it to a
    /// filled coral disc, matching the active-chip idiom.
    private var timeFrameMenu: some View {
        let active = timeFrame != .upcoming
        return Menu {
            Picker("Time frame", selection: $timeFrame) {
                ForEach(TimeFrame.allCases, id: \.self) { tf in
                    Label(tf.rawValue, systemImage: tf.icon).tag(tf)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? .white : Hue.accent)
                .frame(width: 30, height: 30)
                .background(active ? Hue.accent : Hue.surface)
                .clipShape(Circle())
                .shadow(color: active ? Hue.accent.opacity(0.35) : .black.opacity(0.05),
                        radius: active ? 5 : 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onChange(of: timeFrame) { _, _ in Haptics.selection() }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Filter.allCases, id: \.self) { f in
                    let on = f == filter
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { filter = f }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: f.icon).font(.system(size: 14, weight: .semibold))
                            Text(f.rawValue).font(.sansSemibold(14))
                        }
                        .foregroundStyle(on ? .white : Hue.mapInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(on ? Hue.accent : Hue.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(on ? Color.clear : Hue.mapHairline, lineWidth: 1.5))
                        .shadow(color: on ? Hue.accent.opacity(0.28) : .black.opacity(0.04),
                                radius: on ? 8 : 3, x: 0, y: on ? 4 : 1)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
        }
    }

    private var trailsMapLink: some View {
        HStack {
            Text("Trails near St. Joe")
                .font(.sansSemibold(15)).foregroundStyle(Hue.mapInk)
            Spacer()
            Button {
                Haptics.selection()
                trailsShowingMap = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "map.fill").font(.system(size: 12, weight: .semibold))
                    Text("Map").font(.sansSemibold(13))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Hue.accent).clipShape(Capsule())
                .shadow(color: Hue.accent.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Feed

    @ViewBuilder
    private var feed: some View {
        let empty = events.isEmpty && mainClubs.isEmpty && mainTrails.isEmpty
            && !showWobegon && !showSuggested
        if empty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if showSuggested { suggestedSection }

                if showWobegon {
                    WobegonExploreCard(openURL: { openURL($0) }).appearStagger(0)
                }
                ForEach(Array(groupRecurring(events).enumerated()), id: \.element.id) { i, g in
                    EventExploreCard(event: g.lead, recurrenceOverride: g.recurrenceLabel).appearStagger(i)
                }
                ForEach(Array(mainClubs.enumerated()), id: \.element.id) { i, c in
                    ClubExploreCard(club: c) { Task { await model.toggleJoin(api, c) } }
                        .appearStagger(i)
                }
                ForEach(Array(mainTrails.enumerated()), id: \.element.id) { i, t in
                    TrailExploreCard(trail: t, openURL: { openURL($0) }).appearStagger(i)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Hue.accent.opacity(0.7))
            Text(query.isEmpty ? "Nothing here yet" : "No matches")
                .font(.sansBold(16)).foregroundStyle(Hue.mapInk)
            Text(query.isEmpty
                 ? "Real clubs, events, and trails show up here once neighbors post them."
                 : "Try a different search.")
                .font(.sans(14)).foregroundStyle(Hue.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52).padding(.horizontal, 24)
    }

    // MARK: - Suggested (interest-matched), de-duplicated from the main feed

    @ViewBuilder
    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Suggested for you")
                .font(.sansBold(16)).foregroundStyle(Hue.mapInk)
            ForEach(suggestedClubs) { c in
                ClubExploreCard(club: c) { Task { await model.toggleJoin(api, c) } }
            }
            ForEach(suggestedTrails) { TrailExploreCard(trail: $0, openURL: { openURL($0) }) }
        }
    }

    // MARK: - Filtered data

    private var showEvents: Bool { filter == .all || filter == .events }
    private var showClubs: Bool { filter == .all || filter == .clubs }
    private var showTrails: Bool { filter == .all || filter == .trails }
    private var queryEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func matches(_ haystack: String...) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return haystack.contains { $0.lowercased().contains(q) }
    }

    private var events: [UpcomingEvent] {
        showEvents ? model.events.filter { withinFrame($0.eventDate) && matches($0.title, $0.location ?? "") } : []
    }

    /// Is a YYYY-MM-DD event date inside the selected time window? Applies to
    /// events only — clubs/trails have no date and are never hidden by a frame.
    private func withinFrame(_ ymd: String) -> Bool {
        guard !ymd.isEmpty else { return timeFrame == .upcoming }
        switch timeFrame {
        case .upcoming: return true
        case .today:    return ymd == DateHelpers.localDate()
        case .week:
            // Today + the next 6 days = a 7-day window inclusive of today.
            let lo = DateHelpers.localDate()
            let hi = DateHelpers.localDate(DateHelpers.addDays(6))
            return ymd >= lo && ymd <= hi
        case .month:
            return ymd.prefix(7) == DateHelpers.localDate().prefix(7)
        }
    }
    private var clubs: [ClubView] {
        showClubs ? model.clubs.filter { matches($0.name, $0.host ?? "", $0.vibe ?? "", $0.schedule ?? "", $0.location ?? "") } : []
    }
    private var trails: [Trail] {
        showTrails ? model.trails.filter { matches($0.title, $0.location ?? "", $0.description ?? "") } : []
    }

    /// Lake Wobegon (the bundled signature trail) heads the trails, unfiltered searches only.
    private var showWobegon: Bool { showTrails && queryEmpty }

    // MARK: - Suggested for you (interest-matched)

    private var interestIds: [String] { Interests.get() }
    private var showSuggested: Bool {
        filter == .all && queryEmpty && (!suggestedClubs.isEmpty || !suggestedTrails.isEmpty)
    }
    private var suggestedClubs: [ClubView] {
        guard !interestIds.isEmpty else { return [] }
        return model.clubs.filter { Interests.matches("\($0.name) \($0.vibe ?? "") \($0.schedule ?? "") \($0.host ?? "")", interestIds) }
    }
    private var suggestedTrails: [Trail] {
        guard !interestIds.isEmpty else { return [] }
        return model.trails.filter { Interests.matches("\($0.title) \($0.description ?? "") \($0.location ?? "")", interestIds, isTrail: true) }
    }

    /// Main lists drop anything already surfaced in "Suggested for you".
    private var suggestedClubIds: Set<String> { Set(showSuggested ? suggestedClubs.map(\.id) : []) }
    private var suggestedTrailIds: Set<String> { Set(showSuggested ? suggestedTrails.map(\.id) : []) }
    private var mainClubs: [ClubView] { clubs.filter { !suggestedClubIds.contains($0.id) } }
    private var mainTrails: [Trail] { trails.filter { !suggestedTrailIds.contains($0.id) } }
}

// MARK: - Recurring-event grouping

/// One event, or a run of the same event collapsed across multiple dates.
private struct EventGroup: Identifiable {
    let lead: UpcomingEvent       // soonest occurrence — the card represents this row
    let recurrenceLabel: String?  // nil for singletons (card shows its own date)
    var id: String { lead.id }
}

/// A stable per-time bucket key. Uses parsed clock minutes when the free-text
/// time is parseable (so "3 PM" / "3:00 PM" merge), otherwise the normalized raw
/// string — so distinct unparseable times ("19:00" vs "20:00", "Sunset" vs "TBD",
/// or a real time vs. untimed) never collapse together. The m/s prefix keeps an
/// all-digit raw string from colliding with a minutes value.
private func eventTimeKey(_ startTime: String?) -> String {
    let mins = DateHelpers.minutesOf(startTime)
    if mins < 24 * 60 { return "m\(mins)" }
    return "s" + (startTime?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
}

/// Collapse repeated occurrences (same title + location + time) into one card.
/// Input is server-sorted event_date ascending; grouping never drops a row, it
/// only folds a series behind its next occurrence. Preserves first-seen order.
private func groupRecurring(_ evs: [UpcomingEvent]) -> [EventGroup] {
    var order: [String] = []
    var buckets: [String: [UpcomingEvent]] = [:]
    for e in evs {
        let key = e.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            + "|" + (e.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            + "|" + eventTimeKey(e.startTime)
        if buckets[key] == nil { buckets[key] = []; order.append(key) }
        buckets[key]?.append(e)
    }
    var groups: [EventGroup] = []
    for key in order {
        let items = (buckets[key] ?? []).sorted { $0.eventDate < $1.eventDate }
        guard let lead = items.first else { continue }
        let label = items.count >= 2 ? recurrenceLabel(items.map(\.eventDate), time: lead.startTime) : nil
        groups.append(EventGroup(lead: lead, recurrenceLabel: label))
    }
    // Hold each series at its soonest occurrence; break same-day ties by start
    // time, then by id so the order is deterministic across re-renders.
    return groups.sorted {
        if $0.lead.eventDate != $1.lead.eventDate { return $0.lead.eventDate < $1.lead.eventDate }
        let a = DateHelpers.minutesOf($0.lead.startTime)
        let b = DateHelpers.minutesOf($1.lead.startTime)
        if a != b { return a < b }
        return $0.lead.id < $1.lead.id
    }
}

/// An honest recurrence phrase for ≥2 dates. Only claims a cadence the dates
/// actually show; an irregular run (or a real skip) falls back to a plain count.
private func recurrenceLabel(_ dates: [String], time: String?) -> String {
    let n = dates.count
    var gaps: [Int] = []
    for i in 1..<n {
        guard let g = DateHelpers.daysBetween(dates[i - 1], dates[i]) else {
            return recurrenceCountLabel(dates)
        }
        gaps.append(g)
    }
    let weekday = DateHelpers.weekdayLabel(dates[0])
    let sameWeekday = !weekday.isEmpty && dates.allSatisfy { DateHelpers.weekdayLabel($0) == weekday }
    let suffix = sharedTimeSuffix(time)
    if sameWeekday && gaps.allSatisfy({ (6...8).contains($0) }) {
        return "Every \(fullWeekday(weekday))\(suffix)"
    }
    if sameWeekday && gaps.allSatisfy({ (13...15).contains($0) }) {
        return "Every other \(fullWeekday(weekday))\(suffix)"
    }
    if gaps.allSatisfy({ (27...31).contains($0) }) {
        return "Monthly\(suffix)"
    }
    return recurrenceCountLabel(dates)
}

/// Fallback when the dates form no clean cadence: next date + how many follow.
private func recurrenceCountLabel(_ dates: [String]) -> String {
    "\(DateHelpers.prettyDate(dates[0])) · +\(dates.count - 1) more"
}

/// " · 3 PM" using the group's shared start-time string (the group is keyed by
/// time, so the lead's string is representative); "" when untimed. Mirrors the
/// singleton card, which also shows the raw start_time verbatim.
private func sharedTimeSuffix(_ time: String?) -> String {
    guard let t = time?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return "" }
    return " · \(t)"
}

private func fullWeekday(_ short: String) -> String {
    ["Sun": "Sunday", "Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday",
     "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday"][short] ?? short
}

// MARK: - Cards

private struct EventExploreCard: View {
    let event: UpcomingEvent
    /// When this event is one date of a recurring run, the collapsed summary
    /// ("Every Friday · 3 PM"). `event` is the next occurrence — its RSVP,
    /// invite share, and live-glow all use that real, concrete date.
    var recurrenceOverride: String? = nil

    var body: some View {
        ExploreCard(id: event.id, title: event.title, subtitle: event.location, meta: meta) {
            VenuePhoto(venueName: event.location ?? event.title,
                       hint: event.location != nil ? event.title : nil) { ExploreBlankPhoto() }
        } trailing: {
            EventInviteCircle(event: event)
        }
    }
    private var meta: [MetaItem] {
        let leadText = recurrenceOverride
            ?? (DateHelpers.prettyDate(event.eventDate) + (event.startTime.map { " · \($0)" } ?? ""))
        var m: [MetaItem] = [MetaItem(
            icon: recurrenceOverride != nil ? "arrow.triangle.2.circlepath" : "calendar",
            text: leadText,
            coral: true)]
        if event.goingCount > 0 {
            m.append(MetaItem(icon: "person.2.fill", text: "\(event.goingCount) going"))
        }
        return m
    }
}

private struct ClubExploreCard: View {
    let club: ClubView
    var onJoin: () -> Void
    var body: some View {
        ExploreCard(id: club.id, title: club.name,
                    subtitle: club.location ?? club.host.map { "with \($0)" },
                    meta: meta) {
            VenuePhoto(venueName: club.location ?? club.name,
                       hint: club.location != nil ? club.name : nil) { ExploreBlankPhoto() }
        } trailing: {
            Button {
                Haptics.light()
                onJoin()
            } label: {
                exploreCircleIcon(club.joined ? "checkmark" : "plus", filled: club.joined)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(club.joined ? "Joined" : "Join")
        }
    }
    private var meta: [MetaItem] {
        var m: [MetaItem] = []
        if let s = club.schedule, !s.isEmpty { m.append(MetaItem(icon: "clock", text: s, coral: true)) }
        if club.memberCount > 0 {
            m.append(MetaItem(icon: "person.2.fill", text: "\(club.memberCount) member\(club.memberCount == 1 ? "" : "s")"))
        }
        if m.isEmpty, let v = club.vibe, !v.isEmpty { m.append(MetaItem(icon: nil, text: v)) }
        return m
    }
}

private struct TrailExploreCard: View {
    let trail: Trail
    var openURL: (URL) -> Void

    @State private var coord: CLLocationCoordinate2D?

    var body: some View {
        ExploreCard(id: trail.id, title: trail.title, subtitle: trail.location, meta: meta) {
            photo
        } trailing: {
            Button {
                Haptics.light()
                let label = "\(trail.title) \(trail.location ?? "St. Joseph MN")"
                if let url = mapsURL(label: label, coord: coord) { openURL(url) }
            } label: {
                exploreCircleIcon("map.fill")
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Directions")
        }
        .task {
            coord = await GeocoderService.shared.coordinate(for: "\(trail.title) \(trail.location ?? "St. Joseph MN")")
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let url = trail.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: ExploreBlankPhoto()
                }
            }
        } else {
            VenuePhoto(venueName: trail.title, hint: trail.location) { ExploreBlankPhoto() }
        }
    }

    private var meta: [MetaItem] {
        var m: [MetaItem] = []
        if let d = trail.difficulty, !d.isEmpty { m.append(MetaItem(icon: "figure.hiking", text: d, coral: true)) }
        if let l = trail.length, !l.isEmpty { m.append(MetaItem(icon: "ruler", text: l)) }
        return m
    }
}

private struct WobegonExploreCard: View {
    var openURL: (URL) -> Void
    // College Ave (MN-75) trailhead verified via OSM/Nominatim
    private let coord = CLLocationCoordinate2D(latitude: 45.5607, longitude: -94.3194)

    var body: some View {
        ExploreCard(id: "wobegon-trail",
                    title: "Lake Wobegon Trail",
                    subtitle: "St. Joseph, Minnesota",
                    meta: [MetaItem(icon: "figure.hiking", text: "Easy", coral: true),
                           MetaItem(icon: "ruler", text: "Paved rail-trail")]) {
            PhotoView(name: "wobegon-trail").scaledToFill()
        } trailing: {
            Button {
                Haptics.light()
                if let url = mapsURL(label: "Lake Wobegon Trail, St. Joseph MN", coord: coord) { openURL(url) }
            } label: {
                exploreCircleIcon("map.fill")
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Directions")
        }
    }
}

/// A circular share button that renders the invite card + presents the OS sheet.
private struct EventInviteCircle: View {
    let event: UpcomingEvent
    @State private var shareItems: [Any]?

    private var dateLabel: String { DateHelpers.prettyDate(event.eventDate) }
    private var inviteText: String {
        var s = "Come to \(event.title) with me — \(dateLabel)"
        if let t = event.startTime, !t.isEmpty { s += " at \(t)" }
        if let l = event.location, !l.isEmpty { s += ", \(l)" }
        return s + ". (via Hygge)"
    }

    var body: some View {
        Button {
            Haptics.light()
            var items: [Any] = [inviteText]
            if let img = renderCard() { items.insert(img, at: 0) }
            shareItems = items
        } label: {
            exploreCircleIcon("square.and.arrow.up")
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel("Invite a neighbor")
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let shareItems { ActivityView(items: shareItems) }
        }
    }

    @MainActor private func renderCard() -> UIImage? {
        let r = ImageRenderer(content: InviteCard(title: event.title, dateLabel: dateLabel,
                                                  time: event.startTime, location: event.location))
        r.scale = 3
        return r.uiImage
    }
}

// MARK: - Shared helpers

/// A Google Maps URL for a labelled place, pinned to coordinates when known.
private func mapsURL(label: String, coord: CLLocationCoordinate2D? = nil) -> URL? {
    var c = URLComponents()
    c.scheme = "https"; c.host = "maps.google.com"; c.path = "/"
    if let coord {
        c.queryItems = [
            URLQueryItem(name: "q",  value: "\(coord.latitude),\(coord.longitude)"),
            URLQueryItem(name: "ll", value: "\(coord.latitude),\(coord.longitude)"),
            URLQueryItem(name: "z",  value: "15"),
        ]
    } else {
        c.queryItems = [URLQueryItem(name: "q", value: label)]
    }
    return c.url
}
