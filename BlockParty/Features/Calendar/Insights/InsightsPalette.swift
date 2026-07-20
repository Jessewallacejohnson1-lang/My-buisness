//
//  InsightsPalette.swift
//  Block Party — monochrome token aliases for the Upcoming "Insights" face.
//

import SwiftUI

enum InsightsPalette {
    // Page
    static let canvas = Hue.paper
    static let sectionLabel = Hue.inkSecondary

    // Streak hero card
    static let streakTop = Hue.ink
    static let streakBottom = Hue.ink
    static let blobBlue = Hue.ink
    static let blobCoral = Hue.ink
    static let blobPlum = Hue.ink

    // Entries card
    static let entriesTop = Hue.inkSecondary
    static let entriesBottom = Hue.ink

    // Bento cards
    static let journaledTop = Hue.ink
    static let journaledBottom = Hue.inkSecondary
    static let writtenTop = Hue.inkSecondary
    static let writtenBottom = Hue.ink
    static let visitedTop = Hue.ink
    static let visitedBottom = Hue.ink

    // Calendar mini-card
    static let calendarCard = Hue.surface
    static let calendarNav = Hue.ink
    static let calendarTitle = Hue.ink
    static let weekday = Hue.inkSecondary
    static let eventDay = Hue.ink
    static let todayFill = Hue.ink

    // Text on ink cards
    static let onDark = Hue.surface
    static let onDarkMuted = Hue.surface.opacity(0.72)

    // Card treatment
    static let cardRadius: CGFloat = Radius.card
    static let cardGap: CGFloat = 11
}

/// Soft ambient shadow tuned to the reference's card lift (softer + lower than
/// mapFloatShadow, which is for floating map chrome).
extension View {
    func insightsCardShadow() -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }
}
