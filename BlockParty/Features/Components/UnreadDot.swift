//
//  UnreadDot.swift
//  Block Party — the quiet dot for something new: Instagram's unread dot in size and spot, in exact
//  BP yellow, with no number (Jesse, 2026-10-13: an ink dot on the two-person mark read as a third
//  head). The Town bar's bell wears it, and the Friends tab for a new friend request (BP app
//  docs/plans/five-tabs, ticket 02; Jesse said yes to yellow in the tab bar at its Check-in 1).
//

import SwiftUI

/// Laid over a glyph's top right with `.overlay(alignment: .topTrailing)`.
struct UnreadDot: View {
    /// The ring's colour: whatever the dot sits on, so it reads as cut out of the glyph.
    var ring: Color
    /// How far the glyph's frame runs past its ink on the right and top, so the dot sits on the
    /// ink's corner, not the frame's (measured per glyph).
    var inkRight: CGFloat = 0
    var inkTop: CGFloat = 0

    /// Instagram's unread dot on its heart, measured at 7.5pt (±0.5) with a 1.5pt ring, centred
    /// 2pt inside the icon's top right (BP app references/friends/ig-heart-dot.jpg).
    static let side: CGFloat = 7.5
    static let ringWidth: CGFloat = 1.5
    static let inset: CGFloat = 2

    var body: some View {
        let reach = Self.side / 2 + Self.ringWidth
        Circle()
            .fill(Hue.brandDisc)
            .frame(width: Self.side, height: Self.side)
            .padding(Self.ringWidth)
            .background(Circle().fill(ring))
            .offset(x: reach - Self.inset - inkRight, y: Self.inset - reach + inkTop)
            .transition(.scale.combined(with: .opacity))
    }
}
