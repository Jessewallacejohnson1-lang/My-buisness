//
//  EventCategory.swift
//  Hygge — the event category taxonomy + its calendar iconography.
//
//  Mirrors the Expo app's INTERESTS list (apps/mobile/src/lib/interests.ts, also
//  exported as EventCategory in @hygge/core) so the two backend-twins share one
//  vocabulary: the raw values ARE the interest ids (outdoors, music_arts, …).
//  `club_events.category` is a nullable text column — a null / legacy / unknown
//  row resolves to `.other` (see `from(_:)`) so a category icon never renders blank.
//
//  Each case carries a filled SF Symbol glyph (white, on the colored circle) and a
//  tint. The tints are a small local palette in raw hex — the same reference-fidelity
//  carve-out the calendar already used for its order-based SlotTint and the map uses
//  for BasemapPalette / SpotCategory.tint: a real calendar reads deliberately
//  multi-color, and these hues don't map onto the app's one-job-each accents. `.other`
//  stays a calm neutral so an uncategorized row never shouts.
//

import SwiftUI

enum EventCategory: String, CaseIterable, Identifiable, Hashable {
    case outdoors
    case musicArts = "music_arts"
    case food
    case families
    case faith
    case sports
    case books
    case service
    case games
    case other

    var id: String { rawValue }

    /// Resolve a raw DB string → a category, with `.other` for nil / empty / legacy /
    /// unrecognized values. Case- and whitespace-tolerant so hand-entered rows still land.
    static func from(_ raw: String?) -> EventCategory {
        guard let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !key.isEmpty else { return .other }
        return EventCategory(rawValue: key) ?? .other
    }

    /// Short human label — the composer chip + the icon's accessibility text.
    var label: String {
        switch self {
        case .outdoors:  return "Outdoors"
        case .musicArts: return "Music & Arts"
        case .food:      return "Food & Drink"
        case .families:  return "Families & Kids"
        case .faith:     return "Faith"
        case .sports:    return "Sports & Fitness"
        case .books:     return "Books & Learning"
        case .service:   return "Service"
        case .games:     return "Games & Social"
        case .other:     return "Other"
        }
    }

    /// Filled SF Symbol — reads cleanly in white at ~22pt on the colored circle,
    /// the same filled-glyph choice SpotCategory.filledSymbol makes for map pins.
    var glyph: String {
        switch self {
        case .outdoors:  return "figure.hiking"
        case .musicArts: return "music.note"
        case .food:      return "fork.knife"
        case .families:  return "figure.and.child.holdinghands"
        case .faith:     return "hands.and.sparkles.fill"
        case .sports:    return "figure.run"
        case .books:     return "book.fill"
        case .service:   return "heart.fill"
        case .games:     return "gamecontroller.fill"
        case .other:     return "calendar"
        }
    }

    /// Category tint — a small reference-fidelity palette in raw hex (see file note).
    /// Distinct, warm-leaning hues that each carry a white glyph; `.other` is a calm
    /// warm gray so unlabeled rows stay quiet.
    var tint: Color {
        switch self {
        case .outdoors:  return Color(hex: 0x4FA96A)   // green — outdoors reads green everywhere
        case .musicArts: return Color(hex: 0x8E7BF0)   // violet
        case .food:      return Color(hex: 0xF08A3C)   // orange
        case .families:  return Color(hex: 0xE0A43B)   // honey
        case .faith:     return Color(hex: 0x6C7A9C)   // slate blue
        case .sports:    return Color(hex: 0xE05C4B)   // tomato
        case .books:     return Color(hex: 0x2FA6A0)   // teal
        case .service:   return Color(hex: 0xE0648A)   // rose
        case .games:     return Color(hex: 0x5B6EE0)   // indigo
        case .other:     return Color(hex: 0x9A8F86)   // warm gray — calm fallback
        }
    }
}
