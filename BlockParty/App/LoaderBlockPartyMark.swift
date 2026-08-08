//
//  LoaderBlockPartyMark.swift
//  Block Party — the centre mark used by the launch loader.
//
//  This is the *actual app icon*, not a recreation of it. The first version drew the
//  lockup as a vector so it would scale crisply, but a hand-rebuilt mark never matches
//  the shipped icon exactly — weights and spacing drift, and the loader read as
//  "almost the icon", which is worse than either being it or not. So the loader
//  shows `LaunchMark`, which is `AppIcon.png` with its outer margin cropped off.
//
//  The icon art (Aug 2026 rebrand) is the script "BP" monogram wearing a striped
//  party hat, with confetti, in coral-orange and purple on a near-black tile. The
//  crop matters: the exported icon bakes an edge sheen and corner rounding into its
//  outer ~7%. `LaunchMark` is the same art inset by 72/1024 on every side, which
//  lands entirely inside the clean tile face, so the mark carries no edge band. The
//  squircle clip below is the iOS icon corner ratio, so the mark reads as the app
//  icon does on the home screen.
//
//  The dark tile is KEPT ON PURPOSE. Jesse's call (made on the previous icon and
//  carried forward) is that the loader mark should read as the actual app icon, tile
//  and all, the way it looks on the home screen. So the asset stays the 72/1024
//  crop and the squircle clip stays. Do not re-crop to the bare lettering to
//  "de-tile" it; that is a decided question, not an oversight.
//

import SwiftUI

struct BlockPartyMark: View {
    /// Outer side length of the mark, in points.
    let side: CGFloat

    /// Apple's icon corner ratio — the mark is clipped exactly as iOS masks an icon.
    private static let cornerRatio: CGFloat = 0.2237

    /// Fraction of the asset's side spanned by the BP lockup — the script letters plus
    /// the party hat, the part the eye actually sizes (728 px of 880), measured off
    /// `LaunchMark.png` itself. Confetti is excluded: it scatters to the tile edges and
    /// counting it would undersize the letters everywhere. Callers size the mark through
    /// this so the LOCKUP lands at a reference extent, rather than the tile doing so.
    static let contentFraction: CGFloat = 0.8273

    var body: some View {
        Image("LaunchMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * Self.cornerRatio, style: .continuous))
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Block Party")
    }
}

#Preview {
    ZStack {
        Hue.paper.ignoresSafeArea()
        BlockPartyMark(side: 160)
    }
}
