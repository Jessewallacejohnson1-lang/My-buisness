//
//  Interests.swift
//  Hygge — on-device interests for onboarding + "Suggested for you".
//  Ported from apps/mobile/src/lib/interests.ts (taxonomy verbatim). Stored in
//  UserDefaults (per-device, no backend); matching is plain keyword contains.
//

import Foundation

struct Interest: Identifiable, Hashable {
    let id: String
    let label: String
    let keywords: [String]
}

enum Interests {
    static let all: [Interest] = [
        Interest(id: "outdoors", label: "Outdoors & Trails", keywords: ["hike", "walk", "run", "bike", "nature", "park", "river", "trail", "outdoor"]),
        Interest(id: "music_arts", label: "Music & Arts", keywords: ["music", "art", "choir", "band", "craft", "paint", "theater", "sing", "dance"]),
        Interest(id: "food", label: "Food & Drink", keywords: ["food", "coffee", "dinner", "potluck", "bake", "brew", "market", "meal", "supper"]),
        Interest(id: "families", label: "Families & Kids", keywords: ["kid", "family", "parent", "story", "playgroup", "youth", "child", "mom", "dad"]),
        Interest(id: "faith", label: "Faith & Fellowship", keywords: ["church", "faith", "prayer", "bible", "parish", "worship", "mass", "fellowship"]),
        Interest(id: "sports", label: "Sports & Fitness", keywords: ["sport", "fitness", "yoga", "gym", "league", "ball", "swim", "workout", "pickleball"]),
        Interest(id: "books", label: "Books & Learning", keywords: ["book", "read", "class", "learn", "study", "library", "lecture", "write"]),
        Interest(id: "service", label: "Service & Volunteering", keywords: ["volunteer", "service", "give", "clean", "donate", "help", "charity", "drive"]),
        Interest(id: "games", label: "Games & Social", keywords: ["game", "cards", "trivia", "social", "meetup", "hang", "board"]),
    ]

    private static let interestsKey = "hygge.interests"
    private static let onboardedKey = "hygge.onboarded"

    static func get() -> [String] { UserDefaults.standard.stringArray(forKey: interestsKey) ?? [] }
    static func set(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: interestsKey) }

    static func isOnboarded() -> Bool { UserDefaults.standard.string(forKey: onboardedKey) == "1" }
    static func setOnboarded() { UserDefaults.standard.set("1", forKey: onboardedKey) }

    /// Does `haystack` match any chosen interest? Trails always count toward Outdoors.
    static func matches(_ haystack: String, _ ids: [String], isTrail: Bool = false) -> Bool {
        if ids.isEmpty { return false }
        if isTrail && ids.contains("outdoors") { return true }
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
