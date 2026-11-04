//
//  Interests.swift
//  Block Party — the interests a neighbour picks, and the on-device name. Both are mirrored to
//  Supabase (town_profiles); UserDefaults stays the synchronous copy.
//

import Foundation

struct Interest: Identifiable, Hashable {
    let id: String
    let label: String
    /// Everyday words for it: Search's concepts and Daily's topics read them.
    let keywords: [String]
}

/// One thing to pick on the interests step: its words and the interests it saves. One can save two
/// where the screen folds two of the 25 together, so no Event's tags change (BP app onboarding 28).
struct InterestPick: Identifiable, Hashable {
    let label: String
    let ids: [String]
    var id: String { label }

    /// On when any of its interests is picked, as an older pick may hold only one of them.
    func isOn(in picked: [String]) -> Bool { ids.contains(where: picked.contains) }
}

/// A row on the interests step (X's Add Topics): it picks at once, opens to chips, or is Schools.
struct InterestRow: Identifiable {
    enum Kind {
        case pick(InterestPick)
        case chips([InterestPick])
        case schools
    }

    let id: String
    /// A placeholder until Jesse settles the real icons at Check-in 2.
    let icon: String
    let label: String
    let kind: Kind

    /// A row that picks at once, saving these.
    init(_ id: String, _ icon: String, _ label: String, saves ids: [String]) {
        self.init(id, icon, label, .pick(InterestPick(label: label, ids: ids)))
    }

    init(_ id: String, _ icon: String, _ label: String, _ kind: Kind) {
        self.id = id
        self.icon = icon
        self.label = label
        self.kind = kind
    }
}

/// The 25 interests in 8 groups (BP app onboarding 15; Students and Business & networking added
/// 2026-10-30, onboarding 21). The event scripts read the ids from the
/// `Interest(id:` lines below, so the old ids live in `legacy` as plain strings, never as those.
enum Interests {
    static let all: [Interest] = [
        // Outdoors
        Interest(id: "outdoors", label: "Outdoors & nature",
                 keywords: ["outdoors", "nature", "hike", "hiking", "trail", "walk", "park", "garden", "woods",
                            "birding", "prairie", "picnic", "arboretum", "camping"]),
        Interest(id: "lakes_biking", label: "Lakes & biking",
                 keywords: ["lake", "swim", "beach", "paddle", "kayak", "canoe", "fishing", "bike", "biking",
                            "cycling", "gravel"]),
        // Food & drink
        Interest(id: "coffee", label: "Coffee shops",
                 keywords: ["coffee", "café", "cafe", "espresso", "latte", "bakery", "tea"]),
        Interest(id: "dining", label: "Food & dining",
                 keywords: ["food", "restaurant", "dinner", "lunch", "breakfast", "brunch", "dining", "supper",
                            "fish fry", "pancake", "pizza", "eat"]),
        Interest(id: "bars", label: "Bars & breweries",
                 keywords: ["bar", "pub", "brewery", "taproom", "beer", "cider", "wine", "tasting", "cocktail",
                            "happy hour"]),
        Interest(id: "markets", label: "Markets & shopping",
                 keywords: ["market", "farmers market", "shopping", "shop", "store", "boutique", "sale",
                            "vendor", "produce", "holiday market"]),
        // Arts & music
        Interest(id: "live_music", label: "Live music",
                 keywords: ["music", "concert", "band", "open mic", "choir", "jazz", "orchestra", "recital",
                            "singing", "dj"]),
        Interest(id: "art_theater", label: "Art & theater",
                 keywords: ["art", "exhibit", "gallery", "theater", "theatre", "musical", "dance",
                            "film", "movie", "comedy", "museum"]),
        Interest(id: "crafts", label: "Crafts & making",
                 keywords: ["craft", "crafts", "making", "maker", "pottery", "knitting", "sewing", "quilt",
                            "painting class", "woodworking", "diy", "workshop"]),
        Interest(id: "talks", label: "Talks & lectures",
                 keywords: ["talk", "lecture", "speaker", "panel", "seminar", "presentation", "author",
                            "history", "learn"]),
        Interest(id: "books", label: "Library & books",
                 keywords: ["library", "book", "books", "reading", "book club", "story time", "writing", "poetry"]),
        // Fun
        Interest(id: "games", label: "Games & trivia",
                 keywords: ["games", "trivia", "bingo", "cards", "board game", "meat raffle", "raffle", "puzzle",
                            "chess", "cribbage", "bowling"]),
        Interest(id: "festivals", label: "Festivals & holidays",
                 keywords: ["festival", "fest", "fair", "parade", "holiday", "christmas", "halloween",
                            "trick or treat", "fourth of july", "celebration", "block party"]),
        // Sports & health
        Interest(id: "watch_sports", label: "Watch sports",
                 keywords: ["football", "basketball", "volleyball", "hockey", "baseball", "softball",
                            "soccer", "wrestling", "cross country", "athletics", "bennies", "johnnies", "tournament"]),
        Interest(id: "play_sports", label: "Play sports",
                 keywords: ["pickleball", "league", "rec", "pickup", "disc golf", "golf", "tennis", "fun run",
                            "5k", "run", "race", "skating", "volleyball league", "softball league"]),
        Interest(id: "health", label: "Health & wellness",
                 keywords: ["health", "wellness", "yoga", "fitness", "gym", "workout", "pilates", "meditation",
                            "clinic", "screening", "blood drive", "mental health"]),
        // Community
        Interest(id: "faith", label: "Faith & church",
                 keywords: ["church", "faith", "mass", "parish", "worship", "prayer", "abbey", "bible", "vespers",
                            "fellowship", "ministry", "monastery"]),
        Interest(id: "families_kids", label: "Families & kids",
                 keywords: ["kids", "kid", "family", "families", "children", "child", "parents", "youth", "toddler",
                            "baby", "playground", "story time", "teen"]),
        Interest(id: "campus", label: "Campus",
                 keywords: ["campus", "college", "university", "csb", "sju", "saint ben", "saint john", "bennies",
                            "johnnies", "student"]),
        Interest(id: "networking", label: "Business & networking",
                 keywords: ["networking", "business", "career", "job fair", "chamber", "mixer", "professional",
                            "entrepreneur", "small business", "rotary", "lions club"]),
        // Students (Jesse, 2026-10-30): what's on for a school age, for students and their parents
        Interest(id: "college", label: "College",
                 keywords: ["college", "college student", "university", "student life", "undergrad", "scsu",
                            "st. cloud state", "dorm"]),
        Interest(id: "high_school", label: "High school",
                 keywords: ["high school", "high schooler", "teen", "varsity", "homecoming", "prom", "jv"]),
        Interest(id: "middle_school", label: "Middle school",
                 keywords: ["middle school", "junior high", "jh", "6th grade", "7th grade", "8th grade", "tween"]),
        // Civics
        Interest(id: "town_meetings", label: "Town meetings",
                 keywords: ["city council", "council", "town hall", "school board", "commission", "city hall", "election", "vote", "civic"]),
        Interest(id: "volunteering", label: "Volunteering & giving",
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

    /// An Event's tags in today's ids: an old id counts as the first of the new ones.
    static func ofEvent(_ tags: [String]) -> [String] {
        migrate(tags.map { legacy[$0]?.first ?? $0 })
    }

    /// The interests step's 9 rows (Jesse, 2026-11-04).
    static let rows = [
        InterestRow("schools", "🏫", "Schools", .schools),
        InterestRow("families", "👨‍👩‍👧", "Families & kids", saves: ["families_kids"]),
        InterestRow("faith", "⛪️", "Faith & church", saves: ["faith"]),
        InterestRow("arts", "🎨", "Arts & music", .chips([
            InterestPick(label: "Live music", ids: ["live_music"]),
            InterestPick(label: "Art & theater", ids: ["art_theater"]),
            InterestPick(label: "Crafts & making", ids: ["crafts"]),
            InterestPick(label: "Books & talks", ids: ["books", "talks"]),
        ])),
        InterestRow("food", "🍔", "Food & drink", .chips([
            InterestPick(label: "Coffee shops", ids: ["coffee"]),
            InterestPick(label: "Food & dining", ids: ["dining"]),
            InterestPick(label: "Bars & breweries", ids: ["bars"]),
            InterestPick(label: "Markets & shopping", ids: ["markets"]),
        ])),
        InterestRow("fun", "🎲", "Fun", .chips([
            InterestPick(label: "Games & trivia", ids: ["games"]),
            InterestPick(label: "Festivals & holidays", ids: ["festivals"]),
        ])),
        InterestRow("outdoors", "🌲", "Outdoors", saves: ["outdoors", "lakes_biking"]),
        InterestRow("health", "💪", "Health & fitness", saves: ["health", "play_sports"]),
        InterestRow("town", "🏛️", "Town life", .chips([
            InterestPick(label: "Town meetings", ids: ["town_meetings"]),
            InterestPick(label: "Volunteering & giving", ids: ["volunteering"]),
        ])),
    ]

    /// Every pick the rows hold, top to bottom.
    static let picks: [InterestPick] = rows.flatMap { row -> [InterestPick] in
        switch row.kind {
        case .pick(let pick): [pick]
        case .chips(let picks): picks
        case .schools: []
        }
    }

    /// A college's interests: following anything under its kind of school picks them (Jesse,
    /// 2026-11-04), so its Events lift and the ones for its students reach you. On no chip.
    static let collegeIds = ["campus", "college"]

    /// The picks with this one turned over: on adds what it saves, off takes all of it.
    static func toggled(_ pick: InterestPick, in picked: [String]) -> [String] {
        pick.isOn(in: picked) ? picked.filter { !pick.ids.contains($0) }
                              : picked + pick.ids.filter { !picked.contains($0) }
    }

    /// How many things are picked, not how many interests they save.
    static func count(_ picked: [String]) -> Int { picks.filter { $0.isOn(in: picked) }.count }

    /// Their names, for Edit Profile's summary: what the rows call them.
    static func names(_ picked: [String]) -> [String] { picks.filter { $0.isOn(in: picked) }.map(\.label) }

    /// The picks with the college's in them, or out, by whether anything under it is followed.
    static func withCollege(_ picked: [String], following: Bool) -> [String] {
        let others = picked.filter { !collegeIds.contains($0) }
        return following ? others + collegeIds : others
    }

    /// The picks somebody can still see and take off: Watch sports and the others no longer on
    /// the rows go, so nobody keeps a lift they can't see.
    static func onRows(_ picked: [String]) -> [String] {
        let shown = picks.flatMap(\.ids) + collegeIds
        return picked.filter(shown.contains)
    }

    /// The phone's copy of your Interests and name. Only Your profile (`ProfileModel`) writes it.
    static let interestsKey = "bp.interests"
    static let legacyOnboardedKey = "bp.onboarded"   // pre-per-user, un-scoped
    static let nameKey      = "bp.displayName"

    /// Your Interests from the phone's copy; old saved picks come back in today's ids.
    static func get(_ phone: UserDefaults = .standard) -> [String] {
        migrate(phone.stringArray(forKey: interestsKey) ?? [])
    }

    /// Your name from the phone's copy.
    static func displayName(_ phone: UserDefaults = .standard) -> String? { phone.string(forKey: nameKey) }
}
