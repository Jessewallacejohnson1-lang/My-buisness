//
//  ActivitiesView.swift
//  Hygge — "Explore": a Wolt-Discovery-style browse surface, re-skinned to
//  Hygge's coral-on-white brand. A town header (with expandable search) + a row
//  of category tiles pin the top; below, when nothing is filtered, a discovery
//  layout unfolds — a featured "this week" carousel, a happening-this-week shelf,
//  a neighborly compose banner, and the "Around St. Joe" directory. Tap a tile
//  (or search) to drop into a focused, filtered list of that category.
//
//  Coral (Hue.accent) is the one accent; every surface is built from the shared
//  tokens + ExploreKit primitives. Discovery chrome lives in ExploreDiscovery.swift.
//

import SwiftUI
import MapKit

struct ActivitiesView: View {
    /// The global composer, injected by MainTabsView (same sheet Home/Map open).
    var onCompose: (() -> Void)? = nil

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = ActivitiesModel()
    /// The viewer's personal saved list — powers the "Saved" tile.
    @ObservedObject private var saved = SavedStore.shared

    @State private var filter: Filter = ActivitiesView.initialFilter()
    @State private var timeFrame: TimeFrame = ActivitiesView.initialTimeFrame()
    @State private var query = ActivitiesView.launchSearch?.query ?? ""
    /// A search session is active — the header shows the slim committed bar and the
    /// results list is filtered (vs. the resting town pill + discovery).
    @State private var searching = ActivitiesView.launchSearch != nil
    /// The frosted-glass typing overlay is up (`fullScreenCover`). Focus lives
    /// inside `ExploreSearchOverlay`; this only gates presentation.
    @State private var searchPresented = false
    /// DEBUG-only guard so the auto-open for `-explore-search…` fires just once.
    @State private var didAutoSearch = false
    @State private var trailsShowingMap = false
    /// A curated place / park picked from the search dropdown, presented as its
    /// detail sheet (both are `Identifiable`, so `.sheet(item:)` drives them).
    @State private var presentedPlace: Place?
    @State private var presentedPark: Park?
    /// A place/park chosen from a guess, held until the search cover has fully
    /// dismissed — then presented in the cover's `onDismiss` (no present-while-
    /// dismissing race, no fixed delay).
    @State private var pendingPlace: Place?
    @State private var pendingPark: Park?

    /// DEBUG-only: `-explore-filter events|clubs|trails|parks|saved` starts on a given
    /// chip so simulator verification can screenshot each card state headlessly.
    /// Mirrors the `-open-tab` / `-force-nonadmin` flags. No effect in release builds.
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

    /// DEBUG-only: start a search session on launch so its states can be
    /// screenshotted headlessly (no UI driving needed):
    ///   `-explore-search-open`            → the focused-but-empty glass overlay ("Popular")
    ///   `-explore-search <query>`         → the glass overlay with recommendations for <query>
    ///   `-explore-search-committed <query>`→ the committed state (slim bar + filtered results, no glass)
    /// `present` controls whether the glass overlay auto-opens (see `explore`'s `.onAppear`).
    private static func initialSearch() -> (query: String, present: Bool)? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-explore-search"), i + 1 < args.count {
            return (args[i + 1], true)
        }
        if args.contains("-explore-search-open") {
            return ("", true)
        }
        if let i = args.firstIndex(of: "-explore-search-committed"), i + 1 < args.count {
            return (args[i + 1], false)
        }
        #endif
        return nil
    }
    /// Parsed once (launch args don't change), reused by the two `@State` seeds and
    /// the DEBUG auto-open in `explore`'s `.onAppear`.
    private static let launchSearch: (query: String, present: Bool)? = initialSearch()

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
        case all = "All", events = "Events", clubs = "Clubs", trails = "Trails", parks = "Parks", saved = "Saved"

        /// The category tiles shown under the town header (Wolt's icon squares).
        /// `.all` is the unselected discovery state, so it isn't a tile.
        static let tiles: [Filter] = [.events, .clubs, .trails, .parks, .saved]

        var icon: String {
            switch self {
            case .all:    return "square.grid.2x2.fill"
            case .events: return "calendar"
            case .clubs:  return "person.2.fill"
            case .trails: return "figure.hiking"
            case .parks:  return "tree.fill"
            case .saved:  return "bookmark.fill"
            }
        }
    }

    /// A date window applied to events only (clubs/trails/parks have no date).
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
        .sheet(item: $presentedPlace) { PlaceDetailView(place: $0) }
        .sheet(item: $presentedPark) { ParkDetailView(park: $0) }
        // The focused search overlay covers the whole screen (tab bar included).
        // `.clear` presentation background lets our own frosted glass be the only
        // backdrop; the cover is toggled without animation so the overlay's own
        // cross-fade is the transition.
        .fullScreenCover(isPresented: $searchPresented, onDismiss: presentPendingDetail) {
            ExploreSearchOverlay(query: $query,
                                 suggestions: searchSuggestions,
                                 onPick: onSuggestion,
                                 onCancel: cancelSearch,
                                 onSubmit: submitSearch)
                .presentationBackground(.clear)
        }
    }

    // MARK: - Explore scroll

    private var explore: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                ExploreTownHeader(searching: searching, query: query,
                                  onOpen: openSearch, onCancel: cancelSearch)
                    // Keep the search button LEFT of the pinned compose "+" (top-right).
                    .padding(.trailing, ComposeSpeedDial.topDiscHeaderClearance)
                    .padding(.top, 6)
                    .appearStagger(0)
                categoryTiles
                content
                Color.clear.frame(height: 96)
            }
            .padding(.top, 6)
        }
        .background(Hue.surface)
        .refreshable { await model.load(api) }
        .scrollDismissesKeyboard(.interactively)
        // The compose "+" is now the ComposeSpeedDial, hosted by MainTabsView.
        #if DEBUG
        .onAppear {
            // DEBUG `-explore-search…` marked a session active; present the glass
            // overlay a beat after the screen settles so it renders for a headless
            // screenshot (mirrors a real tap on the search circle).
            guard searching, !didAutoSearch else { return }
            didAutoSearch = true
            if ActivitiesView.launchSearch?.present == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { setSearchPresented(true) }
            }
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && !model.loaded {
            ProgressView().tint(Hue.gray)
                .frame(maxWidth: .infinity).padding(.top, 90)
        } else if model.failed {
            failedState.padding(.horizontal, 18)
        } else if isDiscovery {
            discovery
        } else {
            focused
        }
    }

    /// A real outage (not an empty town) — distinct from `emptyState` so an offline
    /// glance isn't misread as "St. Joe has nothing going on."
    private var failedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Hue.gray)
            Text("Couldn't reach St. Joe")
                .font(.sansBold(16)).foregroundStyle(Hue.mapInk)
            Text("Check your connection, then pull to refresh.")
                .font(.sans(14)).foregroundStyle(Hue.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52).padding(.horizontal, 24)
    }

    // MARK: - Category tiles

    private var categoryTiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                // Each tile pops in one at a time (scale+fade), left → right — the
                // Wolt Discovery entrance, tuned frame-by-frame to the reference.
                // `base` holds a beat so the cascade clears the tab-slide / splash
                // and plays on a settled screen (as it does in the reference).
                ForEach(Array(Filter.tiles.enumerated()), id: \.element) { i, f in
                    ExploreCategoryTile(title: f.rawValue, icon: f.icon, selected: filter == f) {
                        toggleFilter(f)
                    }
                    .popIn(i, base: 0.22)
                }
            }
            .padding(.horizontal, 18)
            // Headroom so the pop's rise + bounce-overshoot are never clipped by the
            // horizontal scroll view's bounds.
            .padding(.vertical, 12)
        }
    }

    private func toggleFilter(_ f: Filter) {
        Haptics.selection()
        // Tapping the active tile drops back to the discovery ("All") view.
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            filter = (filter == f) ? .all : f
        }
    }
    private func selectFilter(_ f: Filter) {
        Haptics.selection()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { filter = f }
    }

    private func presentInvite(_ event: UpcomingEvent) {
        ShareCenter.shared.present(.event(title: event.title,
                                          dateLabel: DateHelpers.prettyDate(event.eventDate),
                                          time: event.startTime,
                                          location: event.location))
    }

    // MARK: - Search suggestions (the Google-style dropdown)

    /// Ranked recommendations for the current query, or Popular starters when the
    /// field is focused but empty. Recomputed per render — the data is tiny and
    /// local, so there's no debounce and no per-keystroke animation to manage.
    private var searchSuggestions: [Suggestion] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return TownSearch.popular() }
        return TownSearch.suggestions(query: q, events: model.events,
                                      clubs: model.clubs, trails: model.trails, parks: model.parks)
    }

    /// Toggle the `fullScreenCover` WITHOUT its default slide — the overlay owns
    /// its own cross-fade on both edges, so the cover must appear/vanish instantly.
    private func setSearchPresented(_ v: Bool) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { searchPresented = v }
    }

    /// Open the frosted search overlay (from the resting circle or the committed
    /// bar). `searching` also flips the header to its slim-bar form underneath.
    private func openSearch() {
        Haptics.selection()
        searching = true
        setSearchPresented(true)
    }

    /// Leave search entirely — back to the resting town header + discovery.
    private func cancelSearch() {
        query = ""
        searching = false
        setSearchPresented(false)
    }

    /// A guess was tapped (the overlay has already faded itself out). A Place/Park
    /// opens its detail (held until the cover's `onDismiss` so there's no present-
    /// while-dismissing race); a text guess commits — the query + category apply and
    /// the slim committed bar + filtered results take over behind the vanished glass.
    private func onSuggestion(_ s: Suggestion) {
        Haptics.selection()
        switch s.action {
        case .openPlace(let p):
            pendingPlace = p
            cancelSearch()            // dismisses the cover → presentPendingDetail() fires
        case .openPark(let p):
            pendingPark = p
            cancelSearch()
        case .runSearch(let term, let f):
            query = term
            filter = mapFilter(f)
            timeFrame = .upcoming     // a stale Today/Week frame must not hide the very item tapped
            searching = true          // keep the committed bar; results show behind
            setSearchPresented(false)
        }
    }

    /// Commit the typed text as a plain reference-aware search (keyboard "Search").
    /// Empty text just closes the overlay.
    private func submitSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { cancelSearch(); return }
        filter = .all
        timeFrame = .upcoming
        searching = true
        setSearchPresented(false)
    }

    /// Present a place/park detail chosen from a guess, once the search cover has
    /// fully dismissed (called from the cover's `onDismiss`).
    private func presentPendingDetail() {
        if let p = pendingPlace { pendingPlace = nil; presentedPlace = p }
        else if let p = pendingPark { pendingPark = nil; presentedPark = p }
    }

    private func mapFilter(_ f: TownSearch.SearchFilter?) -> Filter {
        switch f {
        case .events: return .events
        case .clubs:  return .clubs
        case .trails: return .trails
        case .parks:  return .parks
        case nil:     return .all
        }
    }

    // MARK: - Discovery (unfiltered)

    @ViewBuilder
    private var discovery: some View {
        if !featuredEvents.isEmpty {
            FeaturedCarousel(events: featuredEvents, onInvite: presentInvite)
                .appearStagger(2)
        }

        if !weekEvents.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ExploreSectionHeader(title: "Happening this week") {
                    SeeAllPill { selectFilter(.events) }
                }
                .padding(.horizontal, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(weekEvents) { EventShelfCard(event: $0) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 2)
                }
            }
            .appearStagger(3)
        }

        // The always-present horizontal photo shelf (Wolt's collection row) —
        // St. Joe's parks, which are a fixed civic dataset, so discovery is never
        // a lonely single card even in a quiet week.
        if !model.parks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ExploreSectionHeader(title: "Parks & green space") {
                    SeeAllPill { selectFilter(.parks) }
                }
                .padding(.horizontal, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(model.parks) { ExplorePlaceCard(park: $0) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 2)
                }
            }
            .appearStagger(4)
        }

        ExploreComposeBanner(action: onCompose)
            .padding(.horizontal, 18)
            .appearStagger(5)

        VStack(alignment: .leading, spacing: 22) {
            ExploreSectionHeader(title: "Around St. Joe") { EmptyView() }
            directory
        }
        .padding(.horizontal, 18)
        .appearStagger(6)
    }

    /// The vertical directory shown in discovery — clubs and trails. Events get
    /// the hero carousel and parks get the horizontal shelf, so neither repeats.
    @ViewBuilder
    private var directory: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if showSuggested { suggestedSection }
            if showWobegon {
                WobegonExploreCard(openURL: { openURL($0) })
            }
            ForEach(mainClubs) { c in
                ClubExploreCard(club: c) { Task { await model.toggleJoin(api, c) } }
            }
            ForEach(mainTrails) { t in
                TrailExploreCard(trail: t, openURL: { openURL($0) })
            }
        }
    }

    // MARK: - Focused (a category tile, Saved, or a search query)

    @ViewBuilder
    private var focused: some View {
        VStack(alignment: .leading, spacing: 16) {
            if filter == .events {
                ExploreSectionHeader(title: timeFrame == .upcoming ? "Upcoming events" : timeFrame.rawValue) {
                    timeFrameMenu
                }
                .padding(.horizontal, 18)
            }
            if filter == .trails {
                trailsMapLink.padding(.horizontal, 18)
            }

            if focusedEmpty {
                emptyState
            } else {
                feedList.padding(.horizontal, 18)
            }
        }
    }

    /// The vertical, filtered card list (events included). Lazy so off-screen
    /// cards — and each TrailExploreCard's `.task`-driven geocode — only
    /// materialize when scrolled into view.
    @ViewBuilder
    private var feedList: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
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
            ForEach(Array(parks.enumerated()), id: \.element.id) { i, p in
                ParkExploreCard(park: p, openURL: { openURL($0) }).appearStagger(i)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: savedMode ? "bookmark" : "square.grid.2x2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Hue.accent.opacity(0.7))
            Text(emptyTitle)
                .font(.sansBold(16)).foregroundStyle(Hue.mapInk)
            Text(emptyBody)
                .font(.sans(14)).foregroundStyle(Hue.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52).padding(.horizontal, 24)
    }
    private var emptyTitle: String {
        if !queryEmpty { return "No matches" }
        if savedMode { return "Nothing saved yet" }
        return "Nothing here yet"
    }
    private var emptyBody: String {
        if !queryEmpty { return "Try a different search." }
        if savedMode { return "Tap the bookmark on any card to save it here for later." }
        return "Real clubs, events, and trails show up here once neighbors post them."
    }

    // MARK: - Time-frame menu (events focus)

    /// The time-frame picker, surfaced in the Events section header. Resting
    /// (Upcoming) is a coral glyph on white; any active window flips it to a
    /// filled coral disc, matching the active-tile idiom.
    private var timeFrameMenu: some View {
        let active = timeFrame != .upcoming
        return Menu {
            Picker("Time frame", selection: $timeFrame) {
                ForEach(TimeFrame.allCases, id: \.self) { tf in
                    Label(tf.rawValue, systemImage: tf.icon).tag(tf)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if active {
                    Text(timeFrame.rawValue).font(.sansSemibold(13))
                }
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? .white : Hue.accent)
            .padding(.horizontal, active ? 12 : 0)
            .frame(height: 30)
            .frame(minWidth: 30)
            .background(active ? Hue.accent : Hue.bgSubtle)
            .clipShape(Capsule())
            .shadow(color: active ? Hue.accent.opacity(0.32) : .black.opacity(0.04),
                    radius: active ? 5 : 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onChange(of: timeFrame) { _, _ in Haptics.selection() }
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

    // MARK: - Discovery data (featured + this-week events)

    /// The soonest upcoming events, one card per recurring series — the carousel.
    private var featuredEvents: [UpcomingEvent] {
        Array(groupRecurring(model.events).map(\.lead).prefix(5))
    }
    /// Events inside the next 7 days (inclusive of today) that AREN'T already in
    /// the featured carousel — the weekly shelf. Deduping keeps a quiet town from
    /// showing the same happening twice; it only appears with real extra content.
    private var weekEvents: [UpcomingEvent] {
        let featuredIds = Set(featuredEvents.map(\.id))
        let lo = DateHelpers.localDate()
        let hi = DateHelpers.localDate(DateHelpers.addDays(6))
        let within = model.events.filter { !$0.eventDate.isEmpty && $0.eventDate >= lo && $0.eventDate <= hi }
        return Array(groupRecurring(within).map(\.lead).filter { !featuredIds.contains($0.id) }.prefix(8))
    }

    // MARK: - Mode

    private var queryEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var savedMode: Bool { filter == .saved }
    /// Discovery = nothing filtered and no active search.
    private var isDiscovery: Bool { filter == .all && queryEmpty }
    private var focusedEmpty: Bool {
        events.isEmpty && mainClubs.isEmpty && mainTrails.isEmpty && parks.isEmpty
            && !showWobegon && !showSuggested
    }

    // MARK: - Filtered data

    private var showEvents: Bool { filter == .all || filter == .events || savedMode }
    private var showClubs: Bool { filter == .all || filter == .clubs || savedMode }
    private var showTrails: Bool { filter == .all || filter == .trails || savedMode }
    private var showParks: Bool { filter == .all || filter == .parks || savedMode }

    /// Reference-aware field match for the filtered results list — the same engine
    /// the suggestions dropdown uses, so a related word ("pint", "csb", a small
    /// typo) filters the list, not just the literal name. Empty query passes all.
    private func matches(_ haystack: String...) -> Bool {
        TownSearch.matches(query, haystack)
    }
    /// In Saved mode every list is narrowed to the viewer's bookmarked ids.
    private func savedPass(_ id: String) -> Bool { !savedMode || saved.isSaved(id) }

    private var events: [UpcomingEvent] {
        showEvents ? model.events.filter { withinFrame($0.eventDate) && matches($0.title, $0.location ?? "") && savedPass($0.id) } : []
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
        showClubs ? model.clubs.filter { matches($0.name, $0.host ?? "", $0.vibe ?? "", $0.schedule ?? "", $0.location ?? "") && savedPass($0.id) } : []
    }
    private var trails: [Trail] {
        showTrails ? model.trails.filter { matches($0.title, $0.location ?? "", $0.description ?? "") && savedPass($0.id) } : []
    }
    private var parks: [Park] {
        showParks ? model.parks.filter { matches($0.title, $0.address, $0.description) && savedPass($0.id) } : []
    }

    /// Lake Wobegon (the bundled signature trail) heads the trails, unfiltered
    /// searches only — and only when saved, in Saved mode.
    private var showWobegon: Bool { showTrails && queryEmpty && savedPass("wobegon-trail") }

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
        ActivityTile(id: event.id, tag: "Event", title: event.title, metaLine: metaLine) {
            photo
        } trailing: {
            EventInviteCircle(event: event)
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let url = event.imageUrl.flatMap(URL.init) {
            // The organizer's own uploaded photo wins — it's the truest picture of
            // this specific happening.
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: ActivityCoralPanel(glyph: "calendar")
                }
            }
        } else if let localName = KnownLocalPhoto.name(forTitle: event.title) {
            PhotoView(name: localName).scaledToFill()
        } else {
            VenuePhoto(venueName: event.location ?? event.title,
                       hint: event.location != nil ? event.title : nil, maxWidth: 1200) { ActivityCoralPanel(glyph: "calendar") }
        }
    }
    /// One line on the tile foot: the recurrence summary ("Every Friday · 3 PM"),
    /// or this occurrence's date · time.
    private var metaLine: String {
        recurrenceOverride
            ?? (DateHelpers.prettyDate(event.eventDate) + (event.startTime.map { " · \($0)" } ?? ""))
    }
}

private struct ClubExploreCard: View {
    let club: ClubView
    var onJoin: () -> Void
    var body: some View {
        ActivityTile(id: club.id, tag: "Club", title: club.name, metaLine: metaLine) {
            VenuePhoto(venueName: club.location ?? club.name,
                       hint: club.location != nil ? club.name : nil, maxWidth: 1200) { ActivityCoralPanel(glyph: "person.2.fill") }
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
    /// One line on the foot: the meeting schedule, else the real member count,
    /// else the club's vibe.
    private var metaLine: String? {
        if let s = club.schedule, !s.isEmpty { return s }
        if club.memberCount > 0 { return "\(club.memberCount) member\(club.memberCount == 1 ? "" : "s")" }
        if let v = club.vibe, !v.isEmpty { return v }
        return nil
    }
}

private struct TrailExploreCard: View {
    let trail: Trail
    var openURL: (URL) -> Void

    @State private var coord: CLLocationCoordinate2D?

    var body: some View {
        ActivityTile(id: trail.id, tag: "Trail", title: trail.title, metaLine: metaLine) {
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
                default: ActivityCoralPanel(glyph: "figure.hiking")
                }
            }
        } else if let localName = KnownLocalPhoto.name(forTitle: trail.title) {
            PhotoView(name: localName).scaledToFill()
        } else {
            VenuePhoto(venueName: trail.title, hint: trail.location, maxWidth: 1200) { ActivityCoralPanel(glyph: "figure.hiking") }
        }
    }

    /// One line on the foot: difficulty · length (whichever the trail carries).
    private var metaLine: String? {
        let parts = [trail.difficulty, trail.length].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct ParkExploreCard: View {
    let park: Park
    var openURL: (URL) -> Void

    @State private var coord: CLLocationCoordinate2D?
    @State private var showDetail = false

    var body: some View {
        Button {
            Haptics.light()
            showDetail = true
        } label: {
            ActivityTile(id: park.id, tag: "Park", title: park.title, metaLine: metaLine) {
                photo
            } trailing: {
                Button {
                    Haptics.light()
                    let label = "\(park.title), \(park.address)"
                    if let url = mapsURL(label: label, coord: coord) { openURL(url) }
                } label: {
                    exploreCircleIcon("map.fill")
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Directions")
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .task { coord = park.coordinate }   // curated pin — no geocode round-trip
        .sheet(isPresented: $showDetail) { ParkDetailView(park: park) }
    }

    @ViewBuilder
    private var photo: some View {
        if let localName = KnownLocalPhoto.name(forTitle: park.title) {
            PhotoView(name: localName).scaledToFill()
        } else {
            VenuePhoto(venueName: park.title, hint: park.address,
                       coordinate: park.coordinate, maxWidth: 1200) { ActivityCoralPanel(glyph: "tree.fill") }
        }
    }

    /// One line on the foot: acreage · first feature (whichever the park carries).
    private var metaLine: String? {
        var parts: [String] = []
        if let acres = park.acres { parts.append("\(acres) ac") }
        if let first = park.features.first { parts.append(first) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct WobegonExploreCard: View {
    var openURL: (URL) -> Void
    // Lake Wobegon trailhead under the water tower, 610 County Rd 2 — resolved from the single source of truth (KnownVenues)
    private let coord = KnownVenues.coordinate(for: "Wobegon Trailhead")
        ?? CLLocationCoordinate2D(latitude: 45.5697, longitude: -94.3180)

    var body: some View {
        ActivityTile(id: "wobegon-trail", tag: "Trail",
                     title: "Lake Wobegon Trail",
                     metaLine: "Easy · 65 mi paved") {
            PhotoView(name: "wobegon-trail").scaledToFill()
        } trailing: {
            Button {
                Haptics.light()
                if let url = mapsURL(label: "Lake Wobegon Trailhead, 610 County Rd 2, St. Joseph MN", coord: coord) { openURL(url) }
            } label: {
                exploreCircleIcon("map.fill")
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Directions")
        }
    }
}

/// A circular share button that presents the app-wide share reveal (`ShareCenter`).
private struct EventInviteCircle: View {
    let event: UpcomingEvent

    private var dateLabel: String { DateHelpers.prettyDate(event.eventDate) }

    var body: some View {
        Button {
            ShareCenter.shared.present(.event(title: event.title,
                                              dateLabel: dateLabel,
                                              time: event.startTime,
                                              location: event.location))
        } label: {
            exploreCircleIcon("square.and.arrow.up")
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel("Invite a neighbor")
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
