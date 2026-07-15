//
//  TownSearch.swift
//  Hygge — reference-aware search for the Explore ("search tab") suggestions
//  dropdown AND its focused results list.
//
//  "Reference" = you don't have to type the exact name. Three things make a
//  related word find the right thing, and all three lean on data the app already
//  keeps (no new content, no invented counts — the on-brand "real data only" bar):
//    1. Synonym / alias expansion — the keyword taxonomies in `Interests`
//       (~130 synonyms: "pint"→brew, "story time"→families), plus venue aliases in
//       `MapSpots` / `Places` ("csb"→Saint Ben's, "local blend"→Downtown).
//    2. Typo tolerance — a bounded Levenshtein on tokens ("cofee"→coffee,
//       "millstreem"→Millstream).
//    3. Ranking — exact name › name prefix › substring › alias › fuzzy token,
//       so the closest thing sits on top.
//
//  Pure, synchronous, tiny-data (a handful of places, a few dozen happenings) —
//  no network, no Google Places. The billed type-ahead stays in
//  VenueAutocompleteField; this is free, local, and reference-aware.
//

import Foundation

// MARK: - Suggestion model

/// One row in the Explore search dropdown. Carries everything the view/handler
/// needs so neither has to re-look-up the entity.
struct Suggestion: Identifiable {
    enum Group: Int { case place = 0, happening = 1, concept = 2 }

    /// What tapping the row does. Places open their detail sheet; everything else
    /// commits a search (fills the query, optionally selects a category).
    enum Action {
        case openPlace(Place)
        case openPark(Park)
        case runSearch(term: String, filter: TownSearch.SearchFilter?)
    }

    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let group: Group
    let action: Action
    let score: Double

    /// Detail-opening rows get a chevron; search-committing rows get the "insert
    /// into search" arrow (Google's affordance).
    var opensDetail: Bool {
        if case .runSearch = action { return false }
        return true
    }
}

// MARK: - Search engine

enum TownSearch {
    /// The four category buckets a committed happening/search can drop the Explore
    /// list into. Mapped to `ActivitiesView.Filter` by the view (kept decoupled so
    /// this logic file never imports SwiftUI or a View type).
    enum SearchFilter { case events, clubs, trails, parks }

    // MARK: Public API

    /// Ranked suggestions for a non-empty query, grouped place → happening → concept.
    static func suggestions(query: String,
                            events: [UpcomingEvent],
                            clubs: [ClubView],
                            trails: [Trail],
                            parks: [Park]) -> [Suggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return popular() }

        var places: [Suggestion] = []
        var happenings: [Suggestion] = []
        var concepts: [Suggestion] = []

        // Places — the showcase locations (Downtown, Saint Ben's, …) and the city
        // parks. Both have real detail sheets, so these rows open directly.
        for p in Places.all {
            if let s = score(q, name: p.name, extra: [p.tagline] + p.description, aliases: p.kw ?? []) {
                places.append(Suggestion(id: "place:\(p.slug)", icon: "mappin.circle.fill",
                                         title: p.name, subtitle: p.tagline,
                                         group: .place, action: .openPlace(p), score: s))
            }
        }
        for pk in parks {
            if let s = score(q, name: pk.title, extra: [pk.address, pk.description] + pk.features, aliases: []) {
                places.append(Suggestion(id: "park:\(pk.id)", icon: "tree.fill",
                                         title: pk.title, subtitle: pk.features.first ?? "City park",
                                         group: .place, action: .openPark(pk), score: s))
            }
        }

        // Happenings — real events / clubs / trails. Tapping fills the query with
        // the exact title and drops the list into that category so the card shows.
        for e in events {
            if let s = score(q, name: e.title, extra: [e.location ?? ""], aliases: []) {
                happenings.append(Suggestion(id: "event:\(e.id)", icon: "calendar",
                                             title: e.title, subtitle: eventSubtitle(e),
                                             group: .happening,
                                             action: .runSearch(term: e.title, filter: .events), score: s))
            }
        }
        for c in clubs {
            if let s = score(q, name: c.name, extra: [c.host ?? "", c.vibe ?? "", c.schedule ?? "", c.location ?? ""], aliases: []) {
                happenings.append(Suggestion(id: "club:\(c.id)", icon: "person.2.fill",
                                             title: c.name, subtitle: c.schedule ?? c.location ?? c.vibe,
                                             group: .happening,
                                             action: .runSearch(term: c.name, filter: .clubs), score: s))
            }
        }
        for t in trails {
            if let s = score(q, name: t.title, extra: [t.location ?? "", t.description ?? ""], aliases: []) {
                happenings.append(Suggestion(id: "trail:\(t.id)", icon: "figure.hiking",
                                             title: t.title, subtitle: t.location ?? t.difficulty,
                                             group: .happening,
                                             action: .runSearch(term: t.title, filter: .trails), score: s))
            }
        }

        // Concepts — the interest taxonomy. A hit ("pint" → Breweries & Taprooms)
        // becomes a "Search …" row whose term re-expands in the results list.
        for interest in Interests.all {
            if let s = score(q, name: interest.label, extra: [], aliases: interest.keywords) {
                concepts.append(Suggestion(id: "concept:\(interest.id)", icon: conceptIcon(interest.id),
                                           title: interest.label, subtitle: nil,
                                           group: .concept,
                                           action: .runSearch(term: interest.keywords.first ?? interest.label, filter: nil),
                                           score: s))
            }
        }

        return rank(places, cap: 4) + rank(happenings, cap: 4) + rank(concepts, cap: 4)
    }

    /// The focused-but-empty dropdown: a few tappable starter concepts. No data to
    /// persist, works day one.
    static func popular() -> [Suggestion] {
        let picks: [(label: String, term: String, icon: String)] = [
            ("Coffee shops",       "coffee",  "cup.and.saucer.fill"),
            ("Trails & hiking",    "hike",    "figure.hiking"),
            ("Live music",         "music",   "music.note"),
            ("Parks & green space","park",    "tree.fill"),
            ("Breweries",          "brew",    "mug.fill"),
            ("Families & kids",    "kid",     "figure.2.and.child.holdinghands"),
        ]
        return picks.enumerated().map { i, p in
            Suggestion(id: "pop:\(p.term)", icon: p.icon, title: p.label, subtitle: nil,
                       group: .concept, action: .runSearch(term: p.term, filter: nil),
                       score: Double(100 - i))
        }
    }

    /// Does `fields` match `query` — as a reference, not just a literal name? Used
    /// by the Explore results list so it's as smart as the dropdown. Backward-
    /// compatible: it only ever ADDS matches over the old substring behaviour.
    static func matches(_ query: String, _ fields: [String]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let joined = fields.joined(separator: " ")
        // Direct: substring / prefix / typo hit anywhere in the fields.
        if score(q, name: joined, extra: [], aliases: []) != nil { return true }
        // Reference: the query names a concept/venue whose sibling keywords appear.
        let hay = norm(joined)
        for term in expandedTerms(q) where !term.isEmpty {
            if hay.contains(term) { return true }
        }
        return false
    }

    // MARK: Ranking / scoring

    private static func rank(_ items: [Suggestion], cap: Int) -> [Suggestion] {
        Array(items.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id   // stable, deterministic
        }.prefix(cap))
    }

    /// A relevance score for `query` against an entity, or nil for no match.
    /// Bands, high → low: exact name, name prefix, name substring, alias, then a
    /// fuzzy token band (every query token must land somewhere — AND semantics).
    static func score(_ query: String, name: String, extra: [String] = [], aliases: [String] = []) -> Double? {
        let q = norm(query)
        guard !q.isEmpty else { return nil }

        let nn = norm(name)
        if nn == q { return 1000 }
        if nn.hasPrefix(q) { return 900 - Double(min(nn.count, 60)) }   // shorter, tighter names first
        if aliasHit(query, name) { return 800 }   // word-boundary, so "art" ≠ "heart"

        for a in aliases {
            let an = norm(a)
            if an.isEmpty { continue }
            if an == q { return 780 }
            if aliasHit(query, a) { return 720 }   // token-boundary, not mid-word substring
        }

        // Fuzzy token band: split everything into tokens; every query token must
        // fuzzy-hit some field token. Averages the per-token strength.
        let hayTokens = tokenize(([name] + extra + aliases).joined(separator: " "))
        guard !hayTokens.isEmpty else { return nil }
        let qTokens = tokenize(q)
        guard !qTokens.isEmpty else { return nil }

        var total = 0.0
        for qt in qTokens {
            guard let best = bestTokenScore(qt, hayTokens) else { return nil }
            total += best
        }
        return 400 + total / Double(qTokens.count)
    }

    /// Best match strength of one query token against a bag of field tokens.
    private static func bestTokenScore(_ q: String, _ tokens: [String]) -> Double? {
        var best: Double? = nil
        for t in tokens {
            var s: Double? = nil
            if t == q {
                s = 100
            } else if t.hasPrefix(q) {
                s = 80                                   // typeahead: "co" → "coffee"
            } else {
                // No mid-token substring (that let "art" match "party"); only a
                // bounded typo. Levenshtein only on tokens long enough to typo.
                let allow = q.count >= 6 ? 2 : (q.count >= 4 ? 1 : 0)
                if allow > 0 && abs(q.count - t.count) <= allow {
                    let d = levenshtein(q, t)
                    if d <= allow { s = 50 - Double(d) * 12 }
                }
            }
            if let s, best == nil || s > best! { best = s }
        }
        return best
    }

    // MARK: Reference expansion (for the results list)

    /// Expand a raw query into the set of literal terms that should count as a
    /// match in the results list: the query itself, plus — when the query names a
    /// concept or a curated venue — that group's sibling keywords. So "coffee"
    /// also matches a club at "Local Blend", and "csb" also matches "Saint Ben's".
    static func expandedTerms(_ query: String) -> [String] {
        let q = norm(query)
        guard q.count >= 2 else { return [q] }
        var terms: Set<String> = [q]
        let qTokens = Set(tokenize(q))

        for interest in Interests.all {
            let labelTokens = tokenize(interest.label)
            let hitLabel = qTokens.contains { qt in labelTokens.contains { $0 == qt || $0.hasPrefix(qt) } }
            let hitKw = interest.keywords.contains { aliasHit(query, $0) }
            if hitLabel || hitKw {
                for kw in interest.keywords { terms.insert(norm(kw)) }
            }
        }

        for spot in MapSpots.all {
            let hit = aliasHit(query, spot.name)
                || spot.keywords.contains { aliasHit(query, $0) }
            if hit {
                terms.insert(norm(spot.name))
                for kw in spot.keywords { terms.insert(norm(kw)) }
            }
        }

        return Array(terms)
    }

    // MARK: Text primitives

    /// Lowercased, diacritic-folded, trimmed — the canonical form everything
    /// compares in ("Café" == "cafe").
    static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split into alphanumeric tokens (drops punctuation / separators).
    static func tokenize(_ s: String) -> [String] {
        norm(s).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
    }

    /// Whole-token relation between a query and an alias/keyword: every query token
    /// must prefix-match (≥2 chars) or equal an alias token. So "coff"→"coffee",
    /// "csb"→"csb", "local blend"→"local blend" all hit — but "art" does NOT hit
    /// "party" and "a" does not hit "tap" (no mid-word substring, no 1-char flood).
    /// This replaces the raw `contains` that over-expanded reference matches.
    static func aliasHit(_ query: String, _ alias: String) -> Bool {
        let aTokens = tokenize(alias)
        let qTokens = tokenize(query)
        guard !aTokens.isEmpty, !qTokens.isEmpty else { return false }
        return qTokens.allSatisfy { qt in
            aTokens.contains { $0 == qt || (qt.count >= 2 && $0.hasPrefix(qt)) }
        }
    }

    /// Classic bounded edit distance (two-row DP). Datasets are tiny, so no early
    /// cut-off is needed; callers already gate on length before calling.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    // MARK: Display helpers

    private static func eventSubtitle(_ e: UpcomingEvent) -> String? {
        let date = e.eventDate.isEmpty ? nil : DateHelpers.prettyDate(e.eventDate)
        let parts = [date, e.location].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A glyph for a concept row, keyed to the interest id (falls back to a
    /// magnifying glass for anything unmapped).
    private static func conceptIcon(_ id: String) -> String {
        switch id {
        case "trails_hiking":  return "figure.hiking"
        case "lakes_swimming": return "drop.fill"
        case "parks_gardens":  return "tree.fill"
        case "biking":         return "bicycle"
        case "coffee":         return "cup.and.saucer.fill"
        case "dining":         return "fork.knife"
        case "farmers_market": return "basket.fill"
        case "breweries":      return "mug.fill"
        case "live_music":     return "music.note"
        case "art_exhibits":   return "paintpalette.fill"
        case "faith":          return "building.columns.fill"
        case "festivals":      return "party.popper.fill"
        case "books":          return "book.fill"
        case "fitness_yoga":   return "figure.yoga"
        case "sports_leagues": return "sportscourt.fill"
        case "health_wellness":return "heart.fill"
        case "families_kids":  return "figure.2.and.child.holdinghands"
        case "volunteering":   return "hands.sparkles.fill"
        default:               return "magnifyingglass"
        }
    }
}
