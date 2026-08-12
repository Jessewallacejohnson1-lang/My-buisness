//
//  BlockPartyGlyph.swift
//  Block Party — the exact app mark at compact chrome sizes.
//
//  The old Today header drew a hollow square instead of showing the app artwork.
//  The supplied lowercase `bp` mark was chosen explicitly for every brand surface,
//  so compact chrome now uses the same lossless raster as launch and onboarding.
//  `BlockPartyMark` owns the Apple-corner clip and high-quality interpolation.
//

import SwiftUI

struct BlockPartyGlyph: View {
    /// The icon tile's outer side length in points.
    let side: CGFloat

    var body: some View {
        BlockPartyMark(side: side)
            // Decorative by default: the bar's town-name title already carries the
            // meaning. A caller can re-apply a label when the mark stands alone.
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Hue.paper.ignoresSafeArea()
        BlockPartyGlyph(side: 28)
    }
}
