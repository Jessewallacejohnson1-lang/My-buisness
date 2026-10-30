//
//  Interests.swift
//  Block Party — the interests a neighbour picks, and the on-device name. Both are mirrored to
//  Supabase (town_profiles); UserDefaults stays the synchronous copy.
//

import Foundation

struct Interest: Identifiable, Hashable {
    let id: String
    let label: String
    let section: String
    /// Everyday words for it: onboarding's search, Search's concepts and Daily's topics all read them.
    let keywords: [String]
}

/// The 25 interests in 8 groups (BP app onboarding 15; Students and Business & networking added
/// 2026-10-30, onboarding 21). The event scripts read the ids from the
/// `Interest(id:` lines below, so the old ids live in `legacy` as plain strings, never as those.
enum Interests {
    static let all: [Interest] = [
        // Outdoors
        Interest(id: "outdoors", label: "Outdoors & nature", section: "Outdoors",
                 keywords: ["outdoors", "nature", "hike", "hiking", "trail", "walk", "park", "garden", "woods",
                            "birding", "prairie", "picnic", "arboretum", "camping"]),
        Interest(id: "lakes_biking", label: "Lakes & biking", section: "Outdoors",
                 keywords: ["lake", "swim", "beach", "paddle", "kayak", "canoe", "fishing", "bike", "biking",
                            "cycling", "gravel"]),
        // Food & drink
        Interest(id: "coffee", label: "Coffee shops", section: "Food & drink",
                 keywords: ["coffee", "café", "cafe", "espresso", "latte", "bakery", "tea"]),
        Interest(id: "dining", label: "Food & dining", section: "Food & drink",
                 keywords: ["food", "restaurant", "dinner", "lunch", "breakfast", "brunch", "dining", "supper",
                            "fish fry", "pancake", "pizza", "eat"]),
        Interest(id: "bars", label: "Bars & breweries", section: "Food & drink",
                 keywords: ["bar", "pub", "brewery", "taproom", "beer", "cider", "wine", "tasting", "cocktail",
                            "happy hour"]),
        Interest(id: "markets", label: "Markets & shopping", section: "Food & drink",
                 keywords: ["market", "farmers market", "shopping", "shop", "store", "boutique", "sale",
                            "vendor", "produce", "holiday market"]),
        // Arts & music
        Interest(id: "live_music", label: "Live music", section: "Arts & music",
                 keywords: ["music", "concert", "band", "open mic", "choir", "jazz", "orchestra", "recital",
                            "singing", "dj"]),
        Interest(id: "art_theater", label: "Art & theater", section: "Arts & music",
                 keywords: ["art", "exhibit", "gallery", "theater", "theatre", "musical", "dance",
                            "film", "movie", "comedy", "museum"]),
        Interest(id: "crafts", label: "Crafts & making", section: "Arts & music",
                 keywords: ["craft", "crafts", "making", "maker", "pottery", "knitting", "sewing", "quilt",
                            "painting class", "woodworking", "diy", "workshop"]),
        Interest(id: "talks", label: "Talks & lectures", section: "Arts & music",
                 keywords: ["talk", "lecture", "speaker", "panel", "seminar", "presentation", "author",
                            "history", "learn"]),
        Interest(id: "books", label: "Library & books", section: "Arts & music",
                 keywords: ["library", "book", "books", "reading", "book club", "story time", "writing", "poetry"]),
        // Fun
        Interest(id: "games", label: "Games & trivia", section: "Fun",
                 keywords: ["games", "trivia", "bingo", "cards", "board game", "meat raffle", "raffle", "puzzle",
                            "chess", "cribbage", "bowling"]),
        Interest(id: "festivals", label: "Festivals & holidays", section: "Fun",
                 keywords: ["festival", "fest", "fair", "parade", "holiday", "christmas", "halloween",
                            "trick or treat", "fourth of july", "celebration", "block party"]),
        // Sports & health
        Interest(id: "watch_sports", label: "Watch sports", section: "Sports & health",
                 keywords: ["football", "basketball", "volleyball", "hockey", "baseball", "softball",
                            "soccer", "wrestling", "cross country", "athletics", "bennies", "johnnies", "tournament"]),
        Interest(id: "play_sports", label: "Play sports", section: "Sports & health",
                 keywords: ["pickleball", "league", "rec", "pickup", "disc golf", "golf", "tennis", "fun run",
                            "5k", "run", "race", "skating", "volleyball league", "softball league"]),
        Interest(id: "health", label: "Health & wellness", section: "Sports & health",
                 keywords: ["health", "wellness", "yoga", "fitness", "gym", "workout", "pilates", "meditation",
                            "clinic", "screening", "blood drive", "mental health"]),
        // Community
        Interest(id: "faith", label: "Faith & church", section: "Community",
                 keywords: ["church", "faith", "mass", "parish", "worship", "prayer", "abbey", "bible", "vespers",
                            "fellowship", "ministry", "monastery"]),
        Interest(id: "families_kids", label: "Families & kids", section: "Community",
                 keywords: ["kids", "kid", "family", "families", "children", "child", "parents", "youth", "toddler",
                            "baby", "playground", "story time", "teen"]),
        Interest(id: "campus", label: "Campus", section: "Community",
                 keywords: ["campus", "college", "university", "csb", "sju", "saint ben", "saint john", "bennies",
                            "johnnies", "student"]),
        Interest(id: "networking", label: "Business & networking", section: "Community",
                 keywords: ["networking", "business", "career", "job fair", "chamber", "mixer", "professional",
                            "entrepreneur", "small business", "rotary", "lions club"]),
        // Students (Jesse, 2026-10-30): what's on for a school age, for students and their parents
        Interest(id: "college", label: "College", section: "Students",
                 keywords: ["college", "college student", "university", "student life", "undergrad", "scsu",
                            "st. cloud state", "dorm"]),
        Interest(id: "high_school", label: "High school", section: "Students",
                 keywords: ["high school", "high schooler", "teen", "varsity", "homecoming", "prom", "jv"]),
        Interest(id: "middle_school", label: "Middle school", section: "Students",
                 keywords: ["middle school", "junior high", "jh", "6th grade", "7th grade", "8th grade", "tween"]),
        // Civics
        Interest(id: "town_meetings", label: "Town meetings", section: "Civics",
                 keywords: ["city council", "council", "town hall", "school board", "commission", "city hall", "election", "vote", "civic"]),
        Interest(id: "volunteering", label: "Volunteering & giving", section: "Civics",
                 keywords: ["volunteer", "volunteering", "giving", "donate", "donation", "charity", "fundraiser",
                            "food shelf", "drive", "benefit"]),
    ]

    /// The 18 interests before 2026-10-25 and where each went. A pick that split keeps both
    /// halves, so nobody loses something they chose. Only ids that are gone are here: `books`
    /// stays itself, or every read would add Talks & lectures back after someone took it off. The live migration `interests_21` uses the
    /// same map for profiles; events keep the first half until they're re-tagged (ticket 21).
    static let legacy: [String: [String]] = [
        "trails_hiking": ["outdoors"], "parks_gardens": ["outdoors"],
        "lakes_swimming": ["lakes_biking"], "biking": ["lakes_biking"],
        "farmers_market": ["markets"], "breweries": ["bars"],
        "art_exhibits": ["art_theater", "crafts"],
        "sports_leagues": ["watch_sports", "play_sports"],
        "fitness_yoga": ["health"], "health_wellness": ["health"],
    ]

    /// Saved ids in today's terms: old ones mapped over, unknown ones dropped, no repeats, the
    /// order kept.
    static func migrate(_ ids: [String]) -> [String] {
        var out: [String] = []
        for id in ids.flatMap({ legacy[$0] ?? [$0] }) where !out.contains(id) && all.contains(where: { $0.id == id }) {
            out.append(id)
        }
        return out
    }

    /// The groups in order, each with its interests.
    static let sections: [(title: String, items: [Interest])] = {
        var order: [String] = []
        var groups: [String: [Interest]] = [:]
        for i in all {
            if groups[i.section] == nil { order.append(i.section) }
            groups[i.section, default: []].append(i)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }()

    /// Onboarding's search: the interests whose name or everyday words start with what's typed,
    /// word by word ("pickleball" finds Play sports, "church" Faith & church). Never a new one.
    static func search(_ query: String) -> [Interest] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { interest in
            ([interest.label] + interest.keywords).contains { phrase in
                let p = phrase.lowercased()
                return p.hasPrefix(q) || p.split(separator: " ").contains { $0.hasPrefix(q) } || q.hasPrefix(p + " ")
            }
        }
    }

    /// "Popular in St. Joseph": the interests with the most upcoming Events, each Event's
    /// interests given as a list. Only interests with at least `minimum` Events count, and the
    /// row is empty, so hidden, when fewer than 3 do. An Event's old id counts as the first of the
    /// new ones, as the server maps it: an old game is Watch sports, not Play sports too.
    /// An Event's tags in today's ids: an old id counts as the first of the new ones.
    static func ofEvent(_ tags: [String]) -> [String] {
        migrate(tags.map { legacy[$0]?.first ?? $0 })
    }

    static func popular(_ events: [[String]], limit: Int = 6, minimum: Int = 3) -> [String] {
        var counts: [String: Int] = [:]
        for tags in events {
            for id in Set(ofEvent(tags)) { counts[id, default: 0] += 1 }
        }
        let order = all.map(\.id)
        let ranked = order.filter { (counts[$0] ?? 0) >= minimum }
            .sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        return ranked.count < 3 ? [] : Array(ranked.prefix(limit))
    }

    private static let interestsKey = "bp.interests"
    private static let legacyOnboardedKey = "bp.onboarded"   // pre-per-user, un-scoped
    private static let nameKey      = "bp.displayName"

    /// Onboarded flag is scoped per signed-in user id, so a second account on the
    /// same device is never treated as onboarded just because a prior user was.
    private static func onboardedKey(_ uid: String) -> String { "bp.onboarded.\(uid)" }

    /// Old saved picks come back in today's ids.
    static func get() -> [String] { migrate(UserDefaults.standard.stringArray(forKey: interestsKey) ?? []) }
    static func set(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: interestsKey) }

    /// Human labels for interest ids (array or set), dropping any unknown id.
    static func labels(for ids: some Sequence<String>) -> [String] {
        ids.compactMap { id in all.first { $0.id == id }?.label }
    }

    static var displayName: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    static func isOnboarded(uid: String) -> Bool {
        let d = UserDefaults.standard
        if d.string(forKey: onboardedKey(uid)) == "1" { return true }
        // Legacy fallback: a pre-per-user install stored one un-scoped flag for the
        // single signed-in user. Honor it for the current user until the next
        // sign-out clears it, so an existing user isn't bounced back into onboarding.
        return d.string(forKey: legacyOnboardedKey) == "1"
    }

    static func setOnboarded(uid: String) { UserDefaults.standard.set("1", forKey: onboardedKey(uid)) }

    /// Wipe the per-session identity mirror (interests + name) and the legacy
    /// un-scoped onboarded flag on sign-out, so a different account on the same
    /// device never inherits the previous user's name/interests or onboarded state.
    /// Per-user onboarded keys are left intact (they're already scoped by uid).
    static func clearMirror() {
        let d = UserDefaults.standard
        d.removeObject(forKey: interestsKey)
        d.removeObject(forKey: nameKey)
        d.removeObject(forKey: legacyOnboardedKey)
    }
}
