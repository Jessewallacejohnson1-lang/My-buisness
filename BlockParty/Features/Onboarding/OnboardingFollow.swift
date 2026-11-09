//
//  OnboardingFollow.swift
//  Block Party — "Follow 3 places", onboarding's step 8 (BP app onboarding 22, then 26): Spotify's
//  "Choose 3 or more artists" grid of the Town's Places, schools and pages in rows of 3, those that fit
//  the interests just picked first, busiest first. Following one pulls places like it up to right after
//  it. The picks wait on the phone (`OnboardingStore.follows`) and go up once a signed-up account can
//  take them (`RealLifeActions.followOn`), as following needs one (follows spec).
//

import SwiftUI

/// One thing Follow 3 suggests: what to follow, how its tile reads, the interests it fits, what it is,
/// and how many upcoming Events it has, which is how popular it counts as.
struct FollowSuggestion: Identifiable, Equatable {
    let target: FollowTarget
    var name: String
    /// A school's team id or a page's slug, which `Town.schoolTypes` names; empty on a Place.
    var key = ""
    /// "Coffee shop", "School", "City government".
    let kind: String?
    /// Search's cut-out logo, bare with its own cast shadow: a Place's from Search, a school's crest.
    var logo: SearchLogo? = nil
    /// With no cut-out logo: a logo inset on white or a photo filling the circle.
    let picture: URL?
    var isLogo = true
    /// The Town's own page draws the app's Town logo.
    var isTown = false
    var interests: Set<String> = []
    /// What it is, from its kind alone (Coffee shops and `type:coffee_shop`, School, Campus): the places
    /// like it that following it pulls up (Jesse, 2026-11-02: "similar ones appear category wise").
    var categories: Set<String> = []
    var events = 0

    var id: FollowTarget { target }
    var isSchool: Bool { categories.contains("school") }
}

enum FollowSuggestions {
    /// The interests a Place's kind (Google's type) fits on its own, before its Events say more.
    /// Any `_restaurant` is Food & dining and any `_store` Markets & shopping.
    static let kinds: [String: [String]] = [
        "coffee_shop": ["coffee"], "cafe": ["coffee"], "bakery": ["coffee", "dining"],
        "restaurant": ["dining"], "sandwich_shop": ["dining"], "ice_cream_shop": ["dining", "families_kids"],
        "bar": ["bars"], "pub": ["bars"], "wine_bar": ["bars"], "brewery": ["bars"], "cidery": ["bars"],
        "bar_and_grill": ["bars", "dining"],
        "market": ["markets"], "florist": ["markets"], "gift_shop": ["markets"], "butcher_shop": ["markets"],
        "garden_center": ["markets", "outdoors"], "farm": ["markets", "outdoors"],
        "park": ["outdoors"], "campground": ["outdoors"], "hiking_area": ["outdoors"],
        "bicycle_store": ["lakes_biking"], "marina": ["lakes_biking"], "beach": ["lakes_biking"],
        "gym": ["health"], "fitness_center": ["health"], "yoga_studio": ["health"], "spa": ["health"],
        "church": ["faith"], "place_of_worship": ["faith"],
        "art_gallery": ["art_theater"], "museum": ["art_theater"], "movie_theater": ["art_theater"],
        "performing_arts_theater": ["art_theater"],
        "library": ["books"], "book_store": ["books"],
        "bowling_alley": ["games", "play_sports"], "golf_course": ["play_sports"], "sports_complex": ["play_sports"],
        "day_care_center": ["families_kids"], "playground": ["families_kids"],
    ]

    /// How many places like it a follow pulls up, as Spotify adds about three artists.
    static let likeIt = 3
    /// The two rows under the one followed are already in sight: places like it come from further down,
    /// so a follow always shows something new rather than reshuffling what's on screen.
    static let rowsInSight = 2

    static func interests(ofKind type: String?) -> [String] {
        guard let type else { return [] }
        if let fit = kinds[type] { return fit }
        if type.hasSuffix("_restaurant") { return ["dining"] }
        if type.hasSuffix("_store") { return ["markets"] }
        return []
    }

    /// The Town's pages by what they are: its City's meetings, its own festivals, a college's campus.
    static func interests(ofPage page: TownPageRow) -> [String] {
        switch page.slug {
        case "city": ["town_meetings"]
        case "town": ["festivals"]
        default: page.kind == "College" ? ["campus"] : []
        }
    }

    /// Every Place, school and page, each with the interests its kind fits and its upcoming Events
    /// bring (an Event is a Place's by its registry entry, a school's by its games and activities, a
    /// page's by the source it names), and how many Events it has.
    static func build(places: [POI], schools: [LocalSchool], pages: [TownPageRow],
                      events: [UpcomingTags]) -> [FollowSuggestion] {
        var byPlace: [String: [UpcomingTags]] = [:], byTeam: [String: [UpcomingTags]] = [:],
            bySource: [String: [UpcomingTags]] = [:]
        for event in events {
            if let place = event.place { byPlace[place, default: []].append(event) }
            for team in Set(event.teams) { byTeam[team, default: []].append(event) }
            if let source = event.source { bySource[source, default: []].append(event) }
        }
        func with(_ s: FollowSuggestion, _ fit: [String], _ mine: [UpcomingTags]) -> FollowSuggestion {
            var s = s
            // A school fits no pick: its concert doesn't make it a Live music place (`ordered`).
            s.interests = s.isSchool ? [] : Set(fit + mine.flatMap { Interests.ofEvent($0.interests) })
            s.events = mine.count
            return s
        }
        let fromPlaces = places.map { poi in
            let fit = interests(ofKind: poi.primaryType)
            return with(FollowSuggestion(target: .init(type: .place, id: poi.id), name: SearchModel.shown(poi.name),
                                         kind: poi.primaryType.flatMap(SearchModel.label),
                                         logo: poi.searchLogo.map { SearchLogo(placeId: poi.placeId ?? poi.id, row: $0) },
                                         picture: poi.logoURL,
                                         categories: Set(fit + (poi.primaryType.map { ["type:\($0)"] } ?? []))),
                        fit, poi.entryId.flatMap { byPlace[$0] } ?? [])
        }
        let fromSchools = schools.map { school in
            let crest = school.logoUrl.flatMap(URL.init(string:))
            return with(FollowSuggestion(target: .init(type: .team, id: school.uuid), name: school.schoolName ?? school.name,
                                         key: school.id, kind: "School",
                                         // A crest's shadow in a near-neutral shade: schools carry no logo hue.
                                         logo: crest.map { SearchLogo(placeId: "team-\(school.uuid)", row: .init(url: $0, hue: 0, chroma: false)) },
                                         picture: crest, categories: ["school"]),
                        [], byTeam[school.id] ?? [])
        }
        let fromPages = pages.map { page in
            let picture = page.picture.flatMap(URL.init(string:))
            let logo = page.pictureKind == "logo" ? picture : nil
            return with(FollowSuggestion(target: .init(type: .page, id: page.id), name: page.name, key: page.slug, kind: page.kind,
                                         // A page's logo (the City's) bare with its shadow, as a place's.
                                         logo: logo.map { SearchLogo(placeId: "page-\(page.id)", row: .init(url: $0, hue: 0, chroma: false)) },
                                         picture: picture, isLogo: logo != nil, isTown: page.slug == "town",
                                         categories: [page.kind == "College" ? "campus" : page.kind == "School" ? "school" : "town"]),
                        interests(ofPage: page), page.sourceName.flatMap { bySource[$0] } ?? [])
        }
        return fromPlaces + fromSchools + fromPages
    }

    /// The grid before a search, every place in it: what fits the picks first, then the rest, each
    /// busiest first (Jesse, 2026-11-02: "show popular ones first"), A to Z between equals. Schools
    /// lead only for somebody who opened Schools on the step before (onboarding 28).
    static func ordered(_ all: [FollowSuggestion], picked: [String], schoolsFirst: Bool = false) -> [FollowSuggestion] {
        let picks = Set(picked)
        let rank = { (s: FollowSuggestion) in schoolsFirst && s.isSchool ? 0 : s.interests.isDisjoint(with: picks) ? 2 : 1 }
        return all.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            if a.events != b.events { return a.events > b.events }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Following `target` pulls up to `likeIt` places like it (sharing a category, most in common first,
    /// then busiest) from below the two rows in sight to right after it, as Spotify adds artists after
    /// the one you pick. Places above it, in sight and already followed stay put. `moved` is what was
    /// pulled.
    static func pull(_ order: [FollowSuggestion], after target: FollowTarget,
                     follows: Set<FollowTarget>) -> (order: [FollowSuggestion], moved: [FollowTarget]) {
        guard let i = order.firstIndex(where: { $0.target == target }) else { return (order, []) }
        let tapped = order[i].categories
        // From the row after the rows in sight under the followed one's row (3 to a row).
        let picks = order.indices.dropFirst((i / 3 + 1 + rowsInSight) * 3)
            .filter { !follows.contains(order[$0].target) && !order[$0].categories.isDisjoint(with: tapped) }
            .sorted { a, b in
                let sa = order[a].categories.intersection(tapped).count, sb = order[b].categories.intersection(tapped).count
                if sa != sb { return sa > sb }
                if order[a].events != order[b].events { return order[a].events > order[b].events }
                return a < b
            }
            .prefix(likeIt)
        let pulled = picks.map { order[$0] }
        let ids = Set(pulled.map(\.target))
        var next = order.filter { !ids.contains($0.target) }
        next.insert(contentsOf: pulled, at: i + 1)
        return (next, pulled.map(\.target))
    }

    /// A search: every name or kind that has the words, busiest first.
    static func search(_ all: [FollowSuggestion], _ query: String) -> [FollowSuggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { $0.name.localizedStandardContains(q) || ($0.kind?.localizedStandardContains(q) ?? false) }
            .sorted { $0.events != $1.events ? $0.events > $1.events : $0.name < $1.name }
    }

    /// A kind of school's tiles in the Town's order, under the Town's short names.
    static func tiles(_ type: Town.SchoolType, in all: [FollowSuggestion]) -> [FollowSuggestion] {
        type.schools.compactMap { school in
            guard var tile = all.first(where: { $0.key == school.key }) else { return nil }
            tile.name = school.name
            return tile
        }
    }

    /// Everything the interests step's Schools can follow, each once: a school can be two kinds.
    static func schoolTargets(in all: [FollowSuggestion]) -> [FollowTarget] {
        var seen = Set<FollowTarget>()
        return Town.schoolTypes.flatMap { tiles($0, in: all) }.map(\.target).filter { seen.insert($0).inserted }
    }

    static func collegeTargets(in all: [FollowSuggestion]) -> Set<FollowTarget> {
        Set(Town.schoolTypes.filter(\.isCollege).flatMap { tiles($0, in: all) }.map(\.target))
    }

    /// The Places, schools and pages, read together, with the upcoming Events the step read.
    static func load(events: [UpcomingTags]) async throws -> [FollowSuggestion] {
        let api = CommunityAPI(auth: AuthStore.shared)
        async let places = api.getPlaces()
        let (s, p) = try await api.followableSchoolsAndPages()
        return build(places: try await places, schools: s, pages: p, events: events)
    }

    /// The schools and pages alone, for Edit Profile's Schools: its tiles need no Place or Event.
    static func loadSchools() async throws -> [FollowSuggestion] {
        let (s, p) = try await CommunityAPI(auth: AuthStore.shared).followableSchoolsAndPages()
        return build(places: [], schools: s, pages: p, events: [])
    }
}

/// Step 8 under its question: the question scrolls away with the grid while the search stays pinned
/// under the progress bar (Spotify's), and the grid holds every place in rows of 3 (Search's logo
/// wall). Shimmering tiles while the read is out; a failed read says so and lets the Next bar go on
/// (`OnboardingFlow.nextAllowed`).
struct OnboardingFollowGrid<Heading: View>: View {
    /// nil while reading; empty when the read failed.
    let suggestions: [FollowSuggestion]?
    let interests: [String]
    /// Opened Schools on the step before, so schools lead.
    let schoolsFirst: Bool
    let follows: [FollowTarget]
    let toggle: (FollowTarget) -> Void
    @ViewBuilder let heading: Heading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    /// The grid's order once read, which follows rearrange.
    @State private var order: [FollowSuggestion]?
    /// Bumped for a place a follow pulls up, so it arrives as a new tile growing out of the one
    /// followed instead of sliding up from far down the grid.
    @State private var showing: [FollowTarget: Int] = [:]
    @State private var arrivals: [FollowTarget: Arrival] = [:]
    /// The search field's top in the scroll, read only down to just past the pin line (`scrollTop`), so
    /// scrolling further doesn't redraw the grid every frame.
    @State private var searchTop: CGFloat = 255

    /// One spring for every move (the mock's: 0.42 s, a little bounce), 44 ms between arrivals
    /// (Search's logo stagger).
    // Computed: a generic type can't store statics.
    private static var spring: Animation { .spring(response: 0.42, dampingFraction: 0.72) }
    private static var stagger: Double { 0.044 }
    private static var space: String { "follow-grid" }

    var body: some View {
        GeometryReader { geo in
            let column = FollowGridMetric.column(geo.size.width)
            let pinned = searchTop <= FollowGridMetric.scrollTop
            ZStack(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        heading
                        OnboardingSearchField(prompt: "Search places", query: $query)
                            .opacity(pinned ? 0 : 1)
                            .onGeometryChange(for: CGFloat.self) {
                                max($0.frame(in: .named(Self.space)).maxY - FollowGridMetric.search, FollowGridMetric.scrollTop - 16)
                            } action: { searchTop = $0 }
                        tiles(column)
                            .padding(.top, 20)
                    }
                    .padding(.horizontal, FollowGridMetric.gutter)
                    .padding(.top, FollowGridMetric.headingTop - FollowGridMetric.scrollTop)
                    .padding(.bottom, 200)
                    // While searching, room to stay pinned however few the results, so the field never
                    // drops away under the typing.
                    .frame(minHeight: query.isEmpty ? 0 : geo.size.height + 240, alignment: .top)
                }
                .scrollDismissesKeyboard(.immediately)
                .padding(.top, FollowGridMetric.scrollTop)

                // Once pinned, the backdrop closes over the tiles behind and just under the field.
                OnboardingBackdrop()
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: FollowGridMetric.scrollTop)
                            Color.black.frame(height: FollowGridMetric.search + 8)
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 20)
                            Spacer(minLength: 0)
                        }
                    }
                    // Comes in over the first 16 pt past the pin, so nothing under the field pops away.
                    .opacity(min(1, max(0, (FollowGridMetric.scrollTop - searchTop) / 16)))
                    .allowsHitTesting(false)

                if pinned {
                    // VoiceOver keeps the field in its slot, which it scrolls back to.
                    OnboardingSearchField(prompt: "Search places", query: $query)
                        .padding(.horizontal, FollowGridMetric.gutter)
                        .offset(y: FollowGridMetric.scrollTop - 16)
                        .accessibilityHidden(true)
                }
            }
            .coordinateSpace(.named(Self.space))
        }
        .ignoresSafeArea(.container)
        .onChange(of: suggestions, initial: true) { _, new in
            order = new.map { FollowSuggestions.ordered($0, picked: interests, schoolsFirst: schoolsFirst) }
            showing = [:]
        }
        // A tile a search hid and brought back doesn't grow out of an old follow again.
        .onChange(of: query) { arrivals = [:] }
    }

    @ViewBuilder private func tiles(_ column: CGFloat) -> some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let order, !order.isEmpty {
            let shown = q.isEmpty ? order : FollowSuggestions.search(order, q)
            if shown.isEmpty {
                Text("No places found")
                    .font(.apple(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, 4)
            }
            LazyVGrid(columns: FollowGridMetric.columns(column), alignment: .leading, spacing: FollowGridMetric.rowGap) {
                ForEach(shown.map { Tile(suggestion: $0, showing: showing[$0.target, default: 0]) }) { tile in
                    FollowTile(suggestion: tile.suggestion, on: follows.contains(tile.suggestion.target)) {
                        follow(tile.suggestion, column: column)
                    }
                    .transition(arrival(tile.suggestion.target))
                }
            }
        } else if suggestions != nil {
            // The Town feed's words for a read that failed.
            Text("Check your connection and try again.")
                .font(.apple(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, 4)
        } else {
            LazyVGrid(columns: FollowGridMetric.columns(column), alignment: .leading, spacing: FollowGridMetric.rowGap) {
                ForEach(0..<9, id: \.self) { _ in FollowTileSkeleton() }
            }
        }
    }

    /// A tap on a tile: follow or unfollow, and a follow pulls places like it up to right after it.
    private func follow(_ s: FollowSuggestion, column: CGFloat) {
        let following = follows.contains(s.target)
        toggle(s.target)
        guard !following, let order else { return }
        let (next, moved) = FollowSuggestions.pull(order, after: s.target, follows: Set(follows + [s.target]))
        guard !moved.isEmpty, let at = next.firstIndex(where: { $0.target == s.target }) else { return }
        // Followed from a search: the grid behind it reorders unseen, and the results stay as they are.
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { self.order = next; return }
        // Each grows out of the tile followed: from its own new spot, how far that tile is.
        let pitch = CGSize(width: column + FollowGridMetric.columnGap, height: FollowGridMetric.tile + FollowGridMetric.rowGap)
        var arriving: [FollowTarget: Arrival] = [:]
        for (k, target) in moved.enumerated() {
            guard let i = next.firstIndex(where: { $0.target == target }) else { continue }
            arriving[target] = Arrival(offset: CGSize(width: CGFloat(at % 3 - i % 3) * pitch.width,
                                                      height: CGFloat(at / 3 - i / 3) * pitch.height),
                                       delay: Self.stagger * Double(k))
        }
        arrivals = arriving
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Self.spring) {
            for target in moved { showing[target, default: 0] += 1 }
            self.order = next
        }
    }

    /// A pulled place grows out of the tile followed; anything else fades. Reduce Motion: only fades.
    private func arrival(_ target: FollowTarget) -> AnyTransition {
        guard let a = arrivals[target], !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: Arrive(offset: a.offset, scale: 0.35, opacity: 0),
                                 identity: Arrive(offset: .zero, scale: 1, opacity: 1))
                .animation(Self.spring.delay(a.delay)),
            removal: .opacity)
    }

    private struct Tile: Identifiable {
        let suggestion: FollowSuggestion
        let showing: Int
        var id: String { "\(suggestion.target.type.rawValue)|\(suggestion.target.id)|\(showing)" }
    }

    private struct Arrival {
        let offset: CGSize
        let delay: Double
    }
}

private struct Arrive: ViewModifier {
    let offset: CGSize
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.scaleEffect(scale).offset(offset).opacity(opacity)
    }
}

/// The grid's sizes, mock v8's: 88 pt logos on white with a plus on each, three across the 20 pt gutters,
/// 10 pt apart, 22 between rows (onboarding 36).
enum FollowGridMetric {
    static let gutter: CGFloat = 20
    static let columnGap: CGFloat = 10
    static let rowGap: CGFloat = 22
    static let art: CGFloat = 88
    /// Two lines of 13 pt names at the default text size.
    static let name: CGFloat = 34
    static let tile: CGFloat = art + 8 + name
    static let search: CGFloat = OnboardingSearchField.height
    /// The scroll's top, under the back chevron and progress line (mock v8's 98).
    static let scrollTop: CGFloat = 98
    /// The question's icon circle sits 110 pt down on every step (mock v8 `.screen`).
    static let headingTop: CGFloat = 110

    /// 114 on a 402 pt phone.
    static func column(_ width: CGFloat) -> CGFloat { (width - 2 * gutter - 2 * columnGap) / 3 }
    static func columns(_ column: CGFloat) -> [GridItem] { Array(repeating: GridItem(.fixed(column), spacing: columnGap, alignment: .top), count: 3) }
}

/// One place: its logo on white with a small plus on it, its name under it (mock v8, onboarding 36). The
/// whole tile is the button and sinks under the finger; following turns the plus to an ink check that
/// pops to 112% and back.
struct FollowTile: View {
    let suggestion: FollowSuggestion
    let on: Bool
    /// The ring around the plus, the colour behind the tile: the canvas, or white inside Interests' card.
    var ring: Color = Hue.onboardingCanvas
    let tap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1

    private static let badge: CGFloat = 28

    var body: some View {
        Button {
            Haptics.light()
            tap()
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.11)) { pop = 1.12 } completion: {
                withAnimation(.easeOut(duration: 0.11)) { pop = 1 }
            }
        } label: {
            VStack(spacing: 8) {
                FollowTileArt(suggestion: suggestion)
                    .overlay(alignment: .bottomTrailing) { badge.offset(x: 1, y: 1) }
                Text(suggestion.name)
                    .font(.apple(13, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .top)
                    // A caption under an 88 pt logo, a third of the width: past this size a word like
                    // "College" breaks in half (picked, onboarding 36; the Welcome caps the same way).
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        // Read as before: what it does and whose it is, and Selected once followed.
        .accessibilityLabel("\(on ? "Following" : "Follow"), \(suggestion.name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The plus, or an ink check once followed: a 28 pt white circle ringed in the colour behind it.
    private var badge: some View {
        Image(systemName: on ? "checkmark" : "plus")
            .font(.glyph(13, weight: .bold))
            .foregroundStyle(on ? Color.white : Hue.ink)
            .frame(width: Self.badge, height: Self.badge)
            .background(on ? Hue.ink : Hue.surface, in: Circle())
            .background(Circle().fill(ring).padding(-2.5))
            .shadow(color: Hue.ink.opacity(0.16), radius: 2, y: 1)
            .scaleEffect(pop)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: on)
    }
}

/// A tile while the places are read: a shimmering circle and a name.
struct FollowTileSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            SkeletonBlock(cornerRadius: FollowGridMetric.art / 2)
                .frame(width: FollowGridMetric.art, height: FollowGridMetric.art)
            SkeletonBlock(cornerRadius: 6)
                .frame(width: FollowGridMetric.art * 0.8, height: 12)
                .frame(height: FollowGridMetric.name, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// A place's picture at 88 pt, always on a white circle with a hairline (mock v8): Search's cut-out
/// logo inset without its cast shadow, the Town's logo, a logo or photo, or its initials.
private struct FollowTileArt: View {
    let suggestion: FollowSuggestion
    private static let side = FollowGridMetric.art
    /// A logo's margin inside the circle, so its corners stay clear of the edge.
    private static let inset = side * 0.14

    var body: some View {
        Circle().fill(Hue.surface)
            .overlay {
                if let logo = suggestion.logo {
                    CastLogo(logo: logo, side: Self.side - 2 * Self.inset, strength: 0)
                } else if suggestion.isTown {
                    Image(Town.logo).resizable().interpolation(.high).scaledToFit()
                        .padding(Self.inset)
                } else if let url = suggestion.picture {
                    FeedCardURLPhoto(url: url, loadingFill: Hue.surface)
                        .padding(suggestion.isLogo ? Self.side * 0.16 : 0)
                } else {
                    Text(initials)
                        .font(.apple(22, weight: .bold))
                        .foregroundStyle(Hue.ink)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Hue.hairline, lineWidth: 1))
            .frame(width: Self.side, height: Self.side)
            .accessibilityHidden(true)
    }

    /// "CS" of "City of St. Joseph": the first two capitals that start a word, so "of" is skipped.
    private var initials: String {
        String(suggestion.name.split(separator: " ").compactMap { $0.first }.filter(\.isUppercase).prefix(2))
    }
}

/// Six shimmering rows of round faces while Contacts is read.
struct OnboardingLoadingRows: View {
    var body: some View {
        ForEach(0..<6, id: \.self) { _ in
            HStack(spacing: 12) {
                SkeletonBlock(cornerRadius: 24).frame(width: 48, height: 48)
                SkeletonBlock(cornerRadius: 6).frame(width: 140, height: 12)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .shimmering()
            .accessibilityHidden(true)
        }
        .padding(.top, 36)
    }
}

/// The Friends-family pill's face (taste, 2026-10-19): ink Follow, grey Following once on, 32 pt
/// tall, Instagram's 104 wide or `width`.
struct OnboardingPillFace: View {
    let title: String
    let on: Bool
    var width: CGFloat?

    var body: some View {
        Text(title)
            .font(.apple(15, weight: .semibold))
            .foregroundStyle(on ? Hue.ink : Hue.surface)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, width == nil ? 16 : 0)
            .frame(minWidth: width ?? FollowMetric.listWidth, minHeight: FollowMetric.rowHeight)
            .frame(width: width)
            .background(on ? Hue.fill : Hue.ink, in: Capsule())
    }
}

/// Contacts' Add friend on the Friends-family pill (`OnboardingPillFace`). A tap sinks it, ticks,
/// and pops it to 106% as it turns.
struct OnboardingListPill: View {
    let title: String
    let on: Bool
    let name: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1

    var body: some View {
        Button {
            Haptics.light()
            action()
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.1)) { pop = 1.06 } completion: {
                withAnimation(.easeOut(duration: 0.1)) { pop = 1 }
            }
        } label: {
            OnboardingPillFace(title: title, on: on)
                // Drawn 32 pt, 44 pt to the finger.
                .contentShape(Rectangle().inset(by: (FollowMetric.rowHeight - PageMetric.tapMin) / 2))
        }
        .buttonStyle(.press(.squish))
        // It turns at once, as Instagram's does, and the pop carries the motion: a fade left one
        // frame of ink words on ink, or two words over each other.
        .scaleEffect(pop)
        .accessibilityLabel("\(title), \(name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
