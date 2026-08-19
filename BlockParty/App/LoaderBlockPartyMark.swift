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
//  The icon art (Aug 12, 2026 revision) is the geometric lowercase "bp" monogram —
//  the glossy 3-D render, coral-orange on a near-black tile, shipped 1:1 from
//  `docs/brand/source-render-1254.png`. Jesse's call: the icon must match that artwork
//  exactly, gloss and bevel included, so it is NOT redrawn or flattened.
//
//  `scripts/brand/exact.swift` produces all three assets from that render. It crops to
//  the tile FACE (the largest centred square inside the tile, measured by
//  `tile.swift`) and scales to 1024, because an iOS icon must be full-bleed. Do not
//  ship the source frame directly: it has the black surround and its own rounded
//  corners baked in. Verify any re-export with `scripts/brand/masksim.swift`, which
//  applies Apple's 0.2237 corner mask over a light ground — that is where a dark
//  double-corner or a sliced bezel shows up. As measured, iOS's mask radius is WIDER
//  than the render's baked rounding, so it cuts safely inside it.
//
//  The older script-BP vector alternate remains a historical design artifact only.
//  It is not a fallback and must never be substituted on a live brand surface.
//
//  `LaunchMark` is the same art inset by 72/1024 on every side. That inset originally
//  existed to crop off the old render's edge sheen and baked corner rounding; the flat
//  export has neither, so the crop is now purely a contract the callers rely on. It is
//  kept so `contentFraction` stays the only number that moves. The squircle clip below
//  is the iOS icon corner ratio, so the mark reads as the app icon does on the home
//  screen.
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

    /// Fraction of the asset's side spanned by the bp lockup — the lowercase letters,
    /// the part the eye actually sizes (756 px of 880), measured off `LaunchMark.png`
    /// itself
    /// by `scripts/brand/exact.swift`. Callers size the mark through this so the LOCKUP
    /// lands at a reference extent, rather than the tile doing so.
    ///
    /// History: 0.8273 (confetti render) -> 0.8864 (flat vector) -> 0.8614 (script BP
    /// render) -> 0.8591 (lowercase bp render). It moves on EVERY re-export, so
    /// re-measure and update it every time — a stale value silently mis-sizes every
    /// loader mark rather than failing loudly.
    static let contentFraction: CGFloat = 0.8591

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
