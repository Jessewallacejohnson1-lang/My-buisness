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
    let name: String
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
}

enum FollowSuggestions {
    /// The interests a Place's kind (Google's type) fits on its own, before its Events say more.
    /// Any `_restaurant` is Food & dining and any `_store` Markets & shopping.
    static let kinds: [String: [String]] = [
        "coffee_shop": ["coffee"], "cafe": ["coffee"], "bakery": ["coffee", "dining"],
        "restaurant": ["dining"], "sandwich_shop": ["dining"], "ice_cream_shop": ["dining", "families_kids"],
        "bar": ["bars"], "pub": ["bars"], "wine_bar": ["bars"], "brewery": ["bars"],
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

    /// A school fits Watch sports; its Events say the rest (concerts, plays).
    static let school = ["watch_sports"]

    /// How many places like it a follow pulls up, as Spotify adds about three artists.
    static let likeIt = 3

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
            s.interests = Set(fit + mine.flatMap { Interests.ofEvent($0.interests) })
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
                                         kind: "School",
                                         // A crest's shadow in a near-neutral shade: schools carry no logo hue.
                                         logo: crest.map { SearchLogo(placeId: "team-\(school.uuid)", row: .init(url: $0, hue: 0, chroma: false)) },
                                         picture: crest, categories: ["school"]),
                        Self.school, byTeam[school.id] ?? [])
        }
        let fromPages = pages.map { page in
            with(FollowSuggestion(target: .init(type: .page, id: page.id), name: page.name, kind: page.kind,
                                  picture: page.picture.flatMap(URL.init(string:)),
                                  isLogo: page.pictureKind == "logo", isTown: page.slug == "town",
                                  categories: [page.kind == "College" ? "campus" : "town"]),
                 interests(ofPage: page), page.sourceName.flatMap { bySource[$0] } ?? [])
        }
        return fromPlaces + fromSchools + fromPages
    }

    /// The grid before a search, every place in it: what fits the picks first, then the rest, each
    /// busiest first (Jesse, 2026-11-02: "show popular ones first"), A to Z between equals.
    static func ordered(_ all: [FollowSuggestion], picked: [String]) -> [FollowSuggestion] {
        let picks = Set(picked)
        return all.sorted { a, b in
            let fa = !a.interests.isDisjoint(with: picks), fb = !b.interests.isDisjoint(with: picks)
            if fa != fb { return fa }
            if a.events != b.events { return a.events > b.events }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Following `target` pulls up to `likeIt` places like it (sharing a category, most in common first,
    /// then busiest) from further down to right after it, as Spotify adds artists after the one you
    /// pick. Places above it and ones already followed stay put. `moved` is what changed place.
    static func pull(_ order: [FollowSuggestion], after target: FollowTarget,
                     follows: Set<FollowTarget>) -> (order: [FollowSuggestion], moved: [FollowTarget]) {
        guard let i = order.firstIndex(where: { $0.target == target }) else { return (order, []) }
        let tapped = order[i].categories
        let picks = order.indices.dropFirst(i + 1)
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
        let moved = pulled.enumerated().filter { order[i + 1 + $0.offset].target != $0.element.target }.map(\.element.target)
        return (next, moved)
    }

    /// A search: every name or kind that has the words, busiest first.
    static func search(_ all: [FollowSuggestion], _ query: String) -> [FollowSuggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { $0.name.localizedStandardContains(q) || ($0.kind?.localizedStandardContains(q) ?? false) }
            .sorted { $0.events != $1.events ? $0.events > $1.events : $0.name < $1.name }
    }

    /// The Places, schools and pages, read together, with the upcoming Events Popular already read.
    static func load(events: [UpcomingTags]) async throws -> [FollowSuggestion] {
        let api = CommunityAPI(auth: AuthStore.shared)
        async let places = api.getPlaces()
        let (s, p) = try await api.followableSchoolsAndPages()
        return build(places: try await places, schools: s, pages: p, events: events)
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
    /// The search field's resting top, read from its slot in the scroll; it pins at `scrollTop`.
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
            let pinned = min(1, max(0, (FollowGridMetric.scrollTop + 16 - searchTop) / 16))
            ZStack(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        heading
                        // The search field's slot: the field floats over it, and stays once it reaches the top.
                        Color.clear
                            .frame(height: FollowGridMetric.search)
                            .padding(.top, 24)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY - FollowGridMetric.search } action: {
                                searchTop = $0
                            }
                        tiles(column)
                            .padding(.top, 20)
                    }
                    .padding(.horizontal, FollowGridMetric.gutter)
                    .padding(.top, 128 - FollowGridMetric.scrollTop)
                    .padding(.bottom, 200)
                }
                .scrollDismissesKeyboard(.immediately)
                .padding(.top, FollowGridMetric.scrollTop)
                .accessibilitySortPriority(0)

                // Once pinned, the backdrop closes over the tiles behind and just under the field.
                OnboardingBackdrop()
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: FollowGridMetric.scrollTop)
                            Color.black.frame(height: FollowGridMetric.search)
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
                            Spacer(minLength: 0)
                        }
                    }
                    .opacity(pinned)
                    .allowsHitTesting(false)

                OnboardingSearchField(prompt: "Search places", query: $query)
                    .padding(.horizontal, FollowGridMetric.gutter)
                    .offset(y: max(searchTop, FollowGridMetric.scrollTop) - 24)
                    .accessibilitySortPriority(1)
            }
            .coordinateSpace(.named(Self.space))
        }
        .ignoresSafeArea(.container)
        .onChange(of: suggestions, initial: true) { _, new in
            order = new.map { FollowSuggestions.ordered($0, picked: interests) }
            showing = [:]
        }
    }

    @ViewBuilder private func tiles(_ column: CGFloat) -> some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let order, !order.isEmpty {
            let shown = q.isEmpty ? order : FollowSuggestions.search(order, q)
            if shown.isEmpty {
                Text("No places found")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, 4)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(column), spacing: FollowGridMetric.columnGap), count: 3),
                      alignment: .leading, spacing: FollowGridMetric.rowGap) {
                ForEach(shown.map { Tile(suggestion: $0, showing: showing[$0.target, default: 0]) }) { tile in
                    FollowTile(suggestion: tile.suggestion, on: follows.contains(tile.suggestion.target), width: column) {
                        follow(tile.suggestion, column: column)
                    }
                    .transition(arrival(tile.suggestion.target))
                }
            }
        } else if suggestions != nil {
            // The Town feed's words for a read that failed.
            Text("Check your connection and try again.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, 4)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(column), spacing: FollowGridMetric.columnGap), count: 3),
                      alignment: .leading, spacing: FollowGridMetric.rowGap) {
                ForEach(0..<9, id: \.self) { _ in
                    VStack(spacing: 8) {
                        SkeletonBlock(cornerRadius: FollowGridMetric.art / 2).frame(width: FollowGridMetric.art, height: FollowGridMetric.art)
                        SkeletonBlock(cornerRadius: 6).frame(width: column * 0.7, height: 12)
                            .frame(height: FollowGridMetric.name, alignment: .top)
                        SkeletonBlock(cornerRadius: FollowMetric.rowHeight / 2).frame(width: column, height: FollowMetric.rowHeight)
                    }
                    .shimmering()
                    .accessibilityHidden(true)
                }
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

/// The grid's sizes: Search's 80 pt logos, Instagram's 104 x 32 pill, three across the 32 pt gutters.
enum FollowGridMetric {
    static let gutter: CGFloat = 32
    static let columnGap: CGFloat = 13
    static let rowGap: CGFloat = 18
    static let art: CGFloat = 80
    /// Two lines of 13 pt names, so every pill in a row lines up.
    static let name: CGFloat = 34
    static let tile: CGFloat = art + 8 + name + 8 + FollowMetric.rowHeight
    static let search: CGFloat = 44
    /// The scroll's top, under the back chevron and progress bar.
    static let scrollTop: CGFloat = 104

    /// 104 on a 402 pt phone, Instagram's pill width.
    static func column(_ width: CGFloat) -> CGFloat { (width - 2 * gutter - 2 * columnGap) / 3 }
}

/// One place: its logo, its name and Follow under it. The whole tile is the button (Spotify's), and sinks
/// under the finger; following turns the pill at once with its 106% pop while the logo hops.
private struct FollowTile: View {
    let suggestion: FollowSuggestion
    let on: Bool
    let width: CGFloat
    let tap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: CGFloat = 1
    @State private var hop: CGFloat = 0

    var body: some View {
        Button {
            Haptics.light()
            let following = !on
            tap()
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.1)) { pop = 1.06 } completion: {
                withAnimation(.easeOut(duration: 0.1)) { pop = 1 }
            }
            guard following else { return }
            withAnimation(.easeOut(duration: 0.12)) { hop = -6 } completion: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { hop = 0 }
            }
        } label: {
            VStack(spacing: 8) {
                FollowTileArt(suggestion: suggestion)
                    .offset(y: hop)
                Text(suggestion.name)
                    .font(.sansSemibold(13))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: width, height: FollowGridMetric.name, alignment: .top)
                OnboardingPillFace(title: on ? "Following" : "Follow", on: on, width: min(FollowMetric.listWidth, width))
                    .scaleEffect(pop)
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingPress(scale: 0.94))
        .accessibilityLabel("\(on ? "Following" : "Follow"), \(suggestion.name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A place's picture at 80 pt: Search's bare logo with its cast shadow, the Town's logo, or in a circle
/// its logo inset on white, its photo, or its initials.
private struct FollowTileArt: View {
    let suggestion: FollowSuggestion
    private static let side = FollowGridMetric.art

    var body: some View {
        Group {
            if let logo = suggestion.logo {
                CastLogo(logo: logo, side: Self.side)
            } else if suggestion.isTown {
                Image(Town.logo).resizable().interpolation(.high).scaledToFit()
            } else {
                Circle().fill(Hue.surface)
                    .overlay {
                        if let url = suggestion.picture {
                            FeedCardURLPhoto(url: url, loadingFill: Hue.surface)
                                .padding(suggestion.isLogo ? Self.side * 0.16 : 0)
                        } else {
                            Text(initials)
                                .font(.sansHeadline(22))
                                .foregroundStyle(Hue.ink)
                        }
                    }
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Hue.hairline, lineWidth: 1))
            }
        }
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
            .font(.sansSemibold(14))
            .foregroundStyle(on ? Hue.ink : Hue.surface)
            .lineLimit(1)
            .padding(.horizontal, width == nil ? 16 : 0)
            .frame(minWidth: width ?? FollowMetric.listWidth, minHeight: FollowMetric.rowHeight)
            .frame(width: width)
            .background(on ? Hue.fill : Hue.ink, in: Capsule())
    }
}

/// Contacts' Add friend on the Friends-family pill (`OnboardingPillFace`). A tap sinks it to 94%, ticks,
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
        .buttonStyle(OnboardingPress(scale: 0.94))
        // It turns at once, as Instagram's does, and the pop carries the motion: a fade left one
        // frame of ink words on ink, or two words over each other.
        .scaleEffect(pop)
        .accessibilityLabel("\(title), \(name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
