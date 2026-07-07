//
//  Interests.swift
//  Hygge — on-device interests + name for onboarding and "Suggested for you".
//  Interests/name are mirrored to Supabase (town_profiles); UserDefaults stays
//  the synchronous source for keyword matching. Matching is plain keyword-contains.
//

import Foundation

struct Interest: Identifiable, Hashable {
    let id: String
    let label: String
    let section: String
    let keywords: [String]
    /// Asset name for the onboarding photo card (seed art now; a real St. Joe
    /// photo drops in under the same name later — see InterestImage.image(for:)).
    var imageName: String { "interest-\(id)" }
}

enum Interests {
    static let all: [Interest] = [
        // Outdoors & Nature
        Interest(id: "trails_hiking", label: "Trails & Hiking", section: "Outdoors & Nature",
                 keywords: ["hike", "hiking", "trail", "walk", "lake wobegon trail", "woodland", "nature"]),
        Interest(id: "lakes_swimming", label: "Lakes & Swimming", section: "Outdoors & Nature",
                 keywords: ["lake", "swim", "swimming", "beach", "paddle", "kayak", "canoe", "dock"]),
        Interest(id: "parks_gardens", label: "Parks & Gardens", section: "Outdoors & Nature",
                 keywords: ["park", "garden", "millstream", "picnic", "playground", "green space"]),
        Interest(id: "biking", label: "Biking", section: "Outdoors & Nature",
                 keywords: ["bike", "biking", "cycle", "cycling", "ride", "gravel"]),
        // Food & Drink
        Interest(id: "coffee", label: "Coffee Shops", section: "Food & Drink",
                 keywords: ["coffee", "café", "cafe", "espresso", "local blend", "bad habit", "latte"]),
        Interest(id: "dining", label: "Restaurants & Dining", section: "Food & Drink",
                 keywords: ["restaurant", "dinner", "lunch", "dining", "krewe", "brunch", "supper", "food", "eat"]),
        Interest(id: "farmers_market", label: "Farmers Market", section: "Food & Drink",
                 keywords: ["farmers market", "market", "produce", "vendor", "farm", "stand"]),
        Interest(id: "breweries", label: "Breweries & Taprooms", section: "Food & Drink",
                 keywords: ["brew", "brewery", "taproom", "beer", "cider", "tap", "pint"]),
        // Community & Culture
        Interest(id: "live_music", label: "Live Music", section: "Community & Culture",
                 keywords: ["music", "concert", "band", "live", "open mic", "choir", "jam", "sing"]),
        Interest(id: "art_exhibits", label: "Art & Exhibits", section: "Community & Culture",
                 keywords: ["art", "exhibit", "gallery", "paint", "craft", "pottery", "maker", "studio"]),
        Interest(id: "faith", label: "Faith & Fellowship", section: "Community & Culture",
                 keywords: ["church", "faith", "mass", "parish", "worship", "prayer", "abbey", "st. john", "fellowship"]),
        Interest(id: "festivals", label: "Festivals & Fairs", section: "Community & Culture",
                 keywords: ["festival", "fair", "fest", "parade", "joetown", "celebration", "block party"]),
        Interest(id: "books", label: "Library & Books", section: "Community & Culture",
                 keywords: ["book", "read", "library", "story", "author", "lecture", "class", "learn", "study"]),
        // Active & Wellness
        Interest(id: "fitness_yoga", label: "Fitness & Yoga", section: "Active & Wellness",
                 keywords: ["yoga", "fitness", "gym", "workout", "pilates", "stretch"]),
        Interest(id: "sports_leagues", label: "Sports & Leagues", section: "Active & Wellness",
                 keywords: ["sport", "league", "softball", "soccer", "pickleball", "hockey", "ball", "team", "game"]),
        Interest(id: "health_wellness", label: "Health & Wellness", section: "Active & Wellness",
                 keywords: ["health", "wellness", "clinic", "screening", "meditation", "care", "mental"]),
        // Families & Social
        Interest(id: "families_kids", label: "Families & Kids", section: "Families & Social",
                 keywords: ["kid", "family", "child", "parent", "youth", "story time", "playgroup", "mom", "dad"]),
        Interest(id: "volunteering", label: "Volunteering & Service", section: "Families & Social",
                 keywords: ["volunteer", "service", "donate", "charity", "food shelf", "drive", "give", "help"]),
    ]

    /// Sections in display order, each with its interests (grouping preserved).
    static let sections: [(title: String, items: [Interest])] = {
        var order: [String] = []
        var groups: [String: [Interest]] = [:]
        for i in all {
            if groups[i.section] == nil { order.append(i.section) }
            groups[i.section, default: []].append(i)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }()

    private static let interestsKey = "hygge.interests"
    private static let onboardedKey = "hygge.onboarded"
    private static let nameKey      = "hygge.displayName"

    static func get() -> [String] { UserDefaults.standard.stringArray(forKey: interestsKey) ?? [] }
    static func set(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: interestsKey) }

    /// Human labels for interest ids (array or set), dropping any unknown id.
    static func labels(for ids: some Sequence<String>) -> [String] {
        ids.compactMap { id in all.first { $0.id == id }?.label }
    }

    static var displayName: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    static func isOnboarded() -> Bool { UserDefaults.standard.string(forKey: onboardedKey) == "1" }
    static func setOnboarded() { UserDefaults.standard.set("1", forKey: onboardedKey) }

    /// Does `haystack` match any chosen interest? Trails always count toward the
    /// outdoors buckets so a trail row always surfaces for outdoorsy folks.
    static func matches(_ haystack: String, _ ids: [String], isTrail: Bool = false) -> Bool {
        if ids.isEmpty { return false }
        if isTrail && (ids.contains("trails_hiking") || ids.contains("parks_gardens")) { return true }
        let text = haystack.lowercased()
        for id in ids {
            if let interest = all.first(where: { $0.id == id }),
               interest.keywords.contains(where: { text.contains($0) }) {
                return true
            }
        }
        return false
    }
}
