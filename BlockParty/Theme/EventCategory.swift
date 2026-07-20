//
//  EventCategory.swift
//  Block Party — the event category taxonomy + its calendar iconography.
//
//  Mirrors the Expo app's INTERESTS list (apps/mobile/src/lib/interests.ts, also
//  exported as EventCategory in @hygge/core) so the two backend-twins share one
//  vocabulary: the raw values ARE the interest ids (outdoors, music_arts, …).
//  `club_events.category` is a nullable text column — a null / legacy / unknown
//  row resolves to `.other` (see `from(_:)`) so a category icon never renders blank.
//
//  Each case carries a filled SF Symbol glyph on an ink ground. Category is conveyed
//  by glyph, not colour; every tint resolves to the canonical ink token.
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

    /// Filled SF Symbol — reads cleanly in white at ~22pt on the ink circle,
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

    /// Category tint is monochrome; the glyph carries the category distinction.
    var tint: Color {
        switch self {
        case .outdoors:  return Hue.ink
        case .musicArts: return Hue.ink
        case .food:      return Hue.ink
        case .families:  return Hue.ink
        case .faith:     return Hue.ink
        case .sports:    return Hue.ink
        case .books:     return Hue.ink
        case .service:   return Hue.ink
        case .games:     return Hue.ink
        case .other:     return Hue.ink
        }
    }
}
