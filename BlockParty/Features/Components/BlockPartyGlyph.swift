//
//  BlockPartyGlyph.swift
//  Block Party — the mark, drawn.
//
//  The brand mark reduced to what survives at small sizes: a hard square of ink
//  with an empty aperture, at any side length, in any tint.
//
//  DRAWN rather than shipped, because the repo has no raster of the frame ALONE.
//  `MarkTemplate` is the wordmark set INSIDE the frame, with rounded corners and
//  a drop shadow baked into the pixels. At the 28pt a header bar wants, the
//  wordmark collapses into a grey smear, the shadow reads as a smudge, and the
//  corners round off the one thing the mark is — square. Six letters do not fit
//  in nine points of ink, so the letters go and the frame stays.
//
//  Geometry measured off the 880×880 master artwork, not invented: outer side
//  661px, stroke 66px → stroke is 0.0998 of the side, so 0.10. The aperture
//  (0.8003 of the side) falls out of that stroke; it is not a second number to
//  tune. Corner radius is ZERO — the 1px inset on the artwork's topmost scanline
//  is antialiasing, not a rounded corner. Do not add a radius.
//
//  `strokeBorder`, never `stroke`: `stroke` straddles the path and would push the
//  ink half a line width outside the declared frame, rendering the glyph larger
//  than the `side` its caller laid out for.
//

import SwiftUI

struct BlockPartyGlyph: View {
    /// The mark's outer side length in points.
    let side: CGFloat
    /// The frame is the only thing drawn, so the tint is the whole colour story.
    var tint: Color = Hue.ink

    /// Stroke thickness as a fraction of the outer side — 66px on a 661px square.
    nonisolated private static let strokeRatio: CGFloat = 0.10

    var body: some View {
        Rectangle()
            .strokeBorder(tint, lineWidth: side * Self.strokeRatio)
            .frame(width: side, height: side)
            // Decorative by default: the mark is not tappable in v1, and the bar's
            // town-name title already carries the meaning. A caller that needs it
            // announced can re-apply `.accessibilityHidden(false)` with a label.
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Hue.paper.ignoresSafeArea()
        BlockPartyGlyph(side: 28)
    }
}
