//
//  ActivityTile.swift
//  Hygge — the photo-forward browse tile for the Explore lists. A full-bleed
//  photo (or a unified-coral panel when none resolves) with the category tag +
//  title + one concise meta line overlaid on the foot, and the type action +
//  bookmark floating top-right. Text moves ONTO the image so the title/subtitle/
//  meta stack no longer takes space below it.
//
//  Ports the RN twin's ActivityTile (apps/mobile/src/components/ActivityTile.tsx)
//  and shares FeaturedEventCard's scrim + coral-panel idiom, so a vertical tile
//  and the featured hero read as one system. White surface, coral (Hue.accent)
//  the one accent.
//

import SwiftUI

/// One photo-forward tile for the vertical browse lists (events, clubs, trails,
/// parks). A real photo when the wrapper resolves one; otherwise
/// `ActivityCoralPanel`, which keeps the white type legible — never a light blank.
struct ActivityTile<Photo: View, Trailing: View>: View {
    let id: String
    /// The uppercase category overline (EVENT / CLUB / TRAIL / PARK).
    let tag: String
    let title: String
    /// One concise fact kept on the tile — the native app has no detail sheet to
    /// hold it: a dateline, "12 members", "Easy · 5.8 mi", etc. nil hides the line.
    var metaLine: String? = nil
    var height: CGFloat = 200
    @ViewBuilder var photo: () -> Photo
    /// The type action (Join / directions / invite) — floats top-right, left of
    /// the bookmark the tile adds itself.
    @ViewBuilder var trailing: () -> Trailing

    private let textShadow = Color.black.opacity(0.35)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            photo()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()

            // One scrim, clear at top → deep at the foot, so the overlaid tag /
            // title / meta always read (a bright photo included). Matches the
            // featured hero's scrim, a hair deeper for the extra meta line.
            LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.66)],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                Text(tag.uppercased())
                    .font(.sansSemibold(11))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: textShadow, radius: 6, y: 1)
                Text(title)
                    .font(.sansBold(23))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: textShadow, radius: 8, y: 1)
                if let metaLine, !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.monoMedium(12)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .shadow(color: textShadow, radius: 6, y: 1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        .modifier(CardShadow())
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                trailing()
                SaveBookmarkButton(id: id)
            }
            .padding(12)
        }
    }
}

/// The unified-coral fallback shown when no real photo resolves — a warm coral
/// gradient (light → accent → deep) with a faint category glyph, so the white
/// tag / title / meta always read. Coral is THE accent; the glyph is barely-there
/// texture. Mirrors FeaturedEventCard.coralPanel and the RN twin's coral tile.
struct ActivityCoralPanel: View {
    var glyph: String = "sparkles"
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Hue.moss400, Hue.accent, Hue.accentPressed],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: glyph)
                .font(.system(size: 116, weight: .light))
                .foregroundStyle(.white.opacity(0.12))
                .rotationEffect(.degrees(-8))
                .offset(x: 24, y: -16)
        }
    }
}
