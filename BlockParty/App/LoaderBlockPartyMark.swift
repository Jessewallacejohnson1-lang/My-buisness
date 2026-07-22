//
//  LoaderBlockPartyMark.swift
//  Block Party — the centre mark used by the launch loader.
//
//  This is the *actual app icon*, not a recreation of it. The first version drew the
//  lockup as a vector (ink frame + "Block / Party" in Jost) so it would scale
//  crisply, but a hand-rebuilt wordmark never matches the shipped icon exactly — the
//  frame weight, the inset and the line spacing all drifted, and the loader read as
//  "almost the icon", which is worse than either being it or not. So the loader now
//  shows `LaunchMark`, which is `AppIcon.png` with its outer margin cropped off.
//
//  The crop matters: the exported icon bakes in a rounded plate and a soft drop
//  shadow in its outer ~5%. Full-bleed, that shadow shows up as a grey smudge along
//  the bottom edge of the mark. `LaunchMark` is the same art inset by 72/1024 on
//  every side, which lands entirely inside the clean white plate (sampled 253–254),
//  so the mark carries no shadow band. The squircle clip below is the iOS icon
//  corner ratio, so the mark reads as the app icon does on the home screen.
//
//  The white plate is KEPT ON PURPOSE. A pass once cropped the asset down to the bare
//  ink frame to drop the plate — cleaner against paper in the abstract, but Jesse's
//  call is that the loader mark should read as the actual app icon, plate and all, the
//  way it looks on the home screen. So the asset stays the 72/1024 plate crop and the
//  squircle clip stays. Do not re-crop to the ink to "de-tile" it; that is a decided
//  question, not an oversight. (The plate is ~1.5% off paper — a soft tile, intended.)
//

import SwiftUI

struct BlockPartyMark: View {
    /// Outer side length of the mark, in points.
    let side: CGFloat

    /// Apple's icon corner ratio — the mark is clipped exactly as iOS masks an icon.
    private static let cornerRatio: CGFloat = 0.2237

    /// Fraction of the asset's side taken up by the ink frame (661 px of 880), measured
    /// off `LaunchMark.png` itself. The loader sizes the plate through this so that the
    /// INK — the part the eye actually compares against the reference logo — lands at the
    /// reference's extent, rather than the white plate doing so.
    static let inkFraction: CGFloat = 0.7511

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
