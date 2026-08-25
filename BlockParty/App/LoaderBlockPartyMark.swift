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
//  The icon art (Aug 25, 2026 revision) is the WAVE FIGURE — a painted black figure,
//  arms raised, inside three concentric yellow broadcast arcs on warm paper, shipped
//  1:1 from `docs/brand/source-logo-1024.png`. Jesse's call: the icon is the painted
//  render exactly, brushstroke texture and all, so it is NOT redrawn or flattened.
//  (The Aug 12 coral "bp" tile render is retired; its tile-crop pipeline in
//  `scripts/brand/exact.swift`/`tile.swift` does not apply to this full-bleed art.)
//
//  `LaunchMark` is the same art inset by 36/1024 on every side — the old 72 inset
//  would clip the artwork, whose top edge sits 40 px from the frame. The inset is
//  kept so `contentFraction` stays the only number that moves. The squircle clip
//  below is the iOS icon corner ratio, so the mark reads as the app icon does on
//  the home screen.
//
//  The paper ground is KEPT ON PURPOSE. Jesse's call (made on the previous icon and
//  carried forward) is that the loader mark should read as the actual app icon,
//  background and all, the way it looks on the home screen. So the asset stays the
//  inset crop and the squircle clip stays. Do not cut the figure out of its paper;
//  that is a decided question, not an oversight.
//

import SwiftUI

struct BlockPartyMark: View {
    /// Outer side length of the mark, in points.
    let side: CGFloat

    /// Apple's icon corner ratio — the mark is clipped exactly as iOS masks an icon.
    private static let cornerRatio: CGFloat = 0.2237

    /// Fraction of the asset's side spanned by the artwork — the outer wave arcs and
    /// figure, the part the eye actually sizes (926 px of the 952 px launch crop),
    /// measured off the source by the Aug 25 export script. Callers size the mark
    /// through this so the ARTWORK lands at a reference extent, rather than the
    /// paper frame doing so.
    ///
    /// History: 0.8273 (confetti render) -> 0.8864 (flat vector) -> 0.8614 (script BP
    /// render) -> 0.8591 (lowercase bp render) -> 0.9727 (wave-figure logo). It moves
    /// on EVERY re-export, so re-measure and update it every time — a stale value
    /// silently mis-sizes every loader mark rather than failing loudly.
    static let contentFraction: CGFloat = 0.9727

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
