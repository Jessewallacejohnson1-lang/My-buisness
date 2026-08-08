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
//  The icon art (Aug 2026 rebrand, refined Aug 8) is the script "BP" monogram alone, in
//  ONE accent hue — coral-orange `#FA5A34` on an `ink` tile. It is now generated from
//  vector (`docs/brand/block-party-mark.svg`) rather than a 3-D render: the confetti, the
//  gloss, the purple, the party hat and the baked edge sheen are all gone, which is what
//  lets the mark survive at 40 pt. The hat is still implemented and one flag away — see
//  `HAT` in `scripts/brand/export.py`.
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

    /// Fraction of the asset's side spanned by the BP lockup — the script letters, the
    /// part the eye actually sizes (780 px of 880), measured off `LaunchMark.png` itself.
    /// Callers size the mark through this so the LOCKUP lands at a reference extent,
    /// rather than the tile doing so.
    ///
    /// Was 0.8273 while the icon was the 3-D render. The refined mark drops the confetti,
    /// so the lockup grows to fill the tile it used to share (0.71 -> 0.76 of the 1024
    /// icon) and this number rises with it. Re-measure with `docs/brand/` whenever the
    /// icon is re-exported — a stale value silently mis-sizes every loader mark.
    static let contentFraction: CGFloat = 0.8864

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
