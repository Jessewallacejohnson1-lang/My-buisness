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
//  The crop matters, and it has tightened twice. The exported icon is the framed
//  wordmark on a white plate, with a rounded corner and a soft drop shadow baked into
//  its outer ~5%. Cropping to 72/1024 removed the shadow but kept the plate, and on
//  `Hue.paper` that plate read as a faint white tile — only about a 1.5% luminance
//  step, but enough to look like a sticker pasted onto the page.
//
//  So the asset is now cropped to the ink itself: the dark bounding box of
//  `AppIcon.png` is a clean 661 px square centred at 182…842, and `LaunchMark` is
//  that box plus a 3 px margin for the anti-aliased edge. No plate, no shadow, and
//  no corner radius left to clip — just the mark, ink on paper, which is what the
//  brand system asks for. It still reads as the app icon because it IS the app
//  icon's mark; only the icon-shaped plate iOS supplies for the home screen is gone.
//

import SwiftUI

struct BlockPartyMark: View {
    /// Outer side length of the mark, in points.
    let side: CGFloat

    /// Fraction of the asset's side taken up by the ink frame (661 px of 666), measured
    /// off `LaunchMark.png` itself. The loader sizes the mark through this so that the
    /// INK — the part the eye actually compares against the reference logo — lands at the
    /// reference's extent.
    ///
    /// This was 0.7511 while the asset still carried the white plate; cropping to the ink
    /// took it to ~0.99, and `Loader.markSide` divides by it, so the two move together and
    /// the rendered ink stays put. Re-measure it if the crop ever changes again.
    static let inkFraction: CGFloat = 0.9925

    var body: some View {
        Image("LaunchMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: side, height: side)
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
