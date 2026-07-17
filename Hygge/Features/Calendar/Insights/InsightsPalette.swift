//
//  InsightsPalette.swift
//  Hygge — reference-fidelity color carve-out for the Upcoming "Insights" face.
//
//  These hexes are sampled directly from the reference recording
//  (Screen Recording 2026-07-14 at 5.50.51 PM.mov) and are a deliberate,
//  documented carve-out from the app's one-job-each accent system — the same
//  license `EventCategory.tint` and `BasemapPalette` take. A rich multi-card
//  dashboard reads as its own visual world; forcing it into `Hue.*` would lose
//  the reference. This is the FIRST pass (placeholder content, matched 1:1 to
//  the reference); real calendar data is wired in a follow-up.
//

import SwiftUI

enum InsightsPalette {
    // Page
    static let canvas = Color(hex: 0xFAF6F7)
    static let sectionLabel = Color(hex: 0x9A9AA2)   // "Streaks" / "Stats" / "Calendar"

    // Streak hero card — dark indigo → plum, with translucent 3D blobs
    static let streakTop = Color(hex: 0x2A2740)
    static let streakBottom = Color(hex: 0x7A3B59)
    static let blobBlue = Color(hex: 0x6E79D6)
    static let blobCoral = Color(hex: 0xE0655E)
    static let blobPlum = Color(hex: 0x8A4E74)

    // Entries card — periwinkle
    static let entriesTop = Color(hex: 0x8493E8)
    static let entriesBottom = Color(hex: 0x6F6BAB)

    // Bento — Journaled (coral→rose), Written (salmon), Visited (purple→navy)
    static let journaledTop = Color(hex: 0xDD5A5A)
    static let journaledBottom = Color(hex: 0xA5536F)
    static let writtenTop = Color(hex: 0xDD7E80)
    static let writtenBottom = Color(hex: 0xDF6568)
    static let visitedTop = Color(hex: 0x756DAC)
    static let visitedBottom = Color(hex: 0x343351)

    // Calendar mini-card
    static let calendarCard = Color(hex: 0xFFFFFF)
    static let calendarNav = Color(hex: 0x6C5CE7)     // ‹ › chevrons (periwinkle-violet)
    static let calendarTitle = Color(hex: 0x1C1B22)
    static let weekday = Color(hex: 0xB6B6BE)
    static let eventDay = Color(hex: 0xE0655E)     // YOUR day dot (coral) — clears 3:1 on white
    static let townDot = Color(hex: 0x83838B)      // a town-happening day dot (neutral gray, ≥3:1 on white)
    static let todayFill = Color(hex: 0xFF6B57)    // today's filled circle (app coral)

    // Text on colored cards
    static let onDark = Color.white
    static let onDarkMuted = Color.white.opacity(0.72)

    // Card treatment
    static let cardRadius: CGFloat = 30
    static let cardGap: CGFloat = 11
}

/// Soft ambient shadow tuned to the reference's card lift (softer + lower than
/// mapFloatShadow, which is for floating map chrome).
extension View {
    func insightsCardShadow() -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }
}
