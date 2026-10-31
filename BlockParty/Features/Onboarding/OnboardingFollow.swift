//
//  OnboardingFollow.swift
//  Block Party — "Follow 3 places", onboarding's step 8 (BP app onboarding 22, mock v7): Instagram's
//  "Try following 5+" list of the Town's Places, schools and pages, those that fit the interests just
//  picked first. The picks wait on the phone (`OnboardingStore.follows`) and go up once a signed-up
//  account can take them (`RealLifeActions.followOn`), as following needs one (follows spec).
//

import SwiftUI

/// One thing Follow 3 suggests: what to follow, how its row reads, the interests it fits, and how
/// many upcoming Events it has, which orders it among those that fit the same interest.
struct FollowSuggestion: Identifiable, Equatable {
    let target: FollowTarget
    let name: String
    /// "Coffee shop", "School", "City government".
    let kind: String?
    let picture: URL?
    /// A logo sits inset on white; a photo fills the square.
    var isLogo = true
    /// The Town's own page draws the app's Town logo.
    var isTown = false
    var interests: Set<String> = []
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

    /// The rows the list shows before anything is searched: the mock's at least 8.
    static let shown = 8

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
            with(FollowSuggestion(target: .init(type: .place, id: poi.id), name: SearchModel.shown(poi.name),
                                  kind: poi.primaryType.flatMap(SearchModel.label),
                                  picture: poi.searchLogo?.url ?? poi.logoURL),
                 interests(ofKind: poi.primaryType), poi.entryId.flatMap { byPlace[$0] } ?? [])
        }
        let fromSchools = schools.map { school in
            with(FollowSuggestion(target: .init(type: .team, id: school.uuid), name: school.schoolName ?? school.name,
                                  kind: "School",
                                  picture: school.logoUrl.flatMap(URL.init(string:))),
                 Self.school, byTeam[school.id] ?? [])
        }
        let fromPages = pages.map { page in
            with(FollowSuggestion(target: .init(type: .page, id: page.id), name: page.name, kind: page.kind,
                                  picture: page.picture.flatMap(URL.init(string:)),
                                  isLogo: page.pictureKind == "logo", isTown: page.slug == "town"),
                 interests(ofPage: page), page.sourceName.flatMap { bySource[$0] } ?? [])
        }
        return fromPlaces + fromSchools + fromPages
    }

    /// The list before a search: what fits the picks, taking turns in the order they were picked
    /// (each interest's busiest first), so every pick shows near the top and schools mix in rather
    /// than crowd; then the busiest of the rest, up to `shown` rows in all.
    static func ordered(_ all: [FollowSuggestion], picked: [String]) -> [FollowSuggestion] {
        let busiest = { (a: FollowSuggestion, b: FollowSuggestion) in
            a.events != b.events ? a.events > b.events : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        var queues = picked.map { id in all.filter { $0.interests.contains(id) }.sorted(by: busiest) }
        var out: [FollowSuggestion] = [], taken = Set<FollowTarget>()
        while queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices {
                while let next = queues[i].first {
                    queues[i].removeFirst()
                    if taken.insert(next.target).inserted { out.append(next); break }
                }
            }
        }
        let rest = all.filter { !taken.contains($0.target) }.sorted(by: busiest)
        return out + rest.prefix(max(0, shown - out.count))
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

/// Step 8's answer under its question: the line, the search, "Suggested for you" and the rows, each
/// with its Follow pill. Shimmering rows while the read is out; a failed read says so and lets the
/// Next bar go on (`OnboardingFlow.nextAllowed`).
struct OnboardingFollowList: View {
    /// nil while reading; empty when the read failed.
    let suggestions: [FollowSuggestion]?
    let interests: [String]
    let follows: [FollowTarget]
    let toggle: (FollowTarget) -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Picked from what you love. Their events show up first.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, 8)
            OnboardingSearchField(prompt: "Search places", query: $query)
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) { rows }
                    .padding(.top, 4)
                    .padding(.bottom, 200)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    @ViewBuilder private var rows: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suggestions, !suggestions.isEmpty {
            let shown = q.isEmpty ? FollowSuggestions.ordered(suggestions, picked: interests)
                                  : FollowSuggestions.search(suggestions, q)
            if q.isEmpty {
                Text("Suggested for you")
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
            }
            if shown.isEmpty {
                Text("No places found")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, 24)
            }
            ForEach(shown) { s in
                SuggestionRow(suggestion: s, on: follows.contains(s.target)) { toggle(s.target) }
            }
        } else if suggestions != nil {
            // The Town feed's words for a read that failed.
            Text("Check your connection and try again.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, 24)
        } else {
            OnboardingLoadingRows(round: false)
        }
    }
}

/// Six shimmering rows while a list is read: Follow 3's square pictures, Contacts' round faces.
struct OnboardingLoadingRows: View {
    let round: Bool

    var body: some View {
        ForEach(0..<6, id: \.self) { _ in
            HStack(spacing: 12) {
                SkeletonBlock(cornerRadius: round ? 24 : 14).frame(width: 48, height: 48)
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

/// One row, the mock's: a 48 pt picture, the name and kind, the Follow pill.
private struct SuggestionRow: View {
    let suggestion: FollowSuggestion
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SuggestionPicture(suggestion: suggestion)
            VStack(alignment: .leading, spacing: 0) {
                Text(suggestion.name)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                if let kind = suggestion.kind {
                    Text(kind)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            OnboardingListPill(title: on ? "Following" : "Follow", on: on, name: suggestion.name, action: toggle)
        }
        .padding(.vertical, 8)
    }
}

/// A Place's picture as the mock draws it, a 48 pt square with 14 pt corners on a hairline: its logo
/// inset on white, its photo filling it, the Town's logo, or its initials.
private struct SuggestionPicture: View {
    let suggestion: FollowSuggestion
    private static let side: CGFloat = 48
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        shape.fill(Hue.surface)
            .overlay {
                if suggestion.isTown {
                    Image(Town.logo).resizable().interpolation(.high).scaledToFit()
                } else if let url = suggestion.picture {
                    FeedCardURLPhoto(url: url, loadingFill: Hue.surface)
                        .padding(suggestion.isLogo ? Self.side * 0.16 : 0)
                } else {
                    Text(initials)
                        .font(.sansHeadline(17))
                        .foregroundStyle(Hue.ink)
                }
            }
            .frame(width: Self.side, height: Self.side)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Hue.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }

    /// "CS" of "City of St. Joseph": the first two capitals that start a word, so "of" is skipped.
    private var initials: String {
        String(suggestion.name.split(separator: " ").compactMap { $0.first }.filter(\.isUppercase).prefix(2))
    }
}

/// Follow, and Contacts' Add friend, as the mock's pill (Instagram's 32 pt capsule, 104 pt wide): ink
/// Follow, grey Following once on. A tap sinks it to 94%, ticks, and pops it to 106% as it turns.
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
            Text(title)
                .font(.sansSemibold(14))
                .foregroundStyle(on ? Hue.ink : Hue.surface)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minWidth: FollowMetric.listWidth, minHeight: FollowMetric.rowHeight)
                .background(on ? Hue.fill : Hue.ink, in: Capsule())
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
