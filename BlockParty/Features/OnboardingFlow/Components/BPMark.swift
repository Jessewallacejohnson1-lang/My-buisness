//
//  BPMark.swift
//  Block Party — the mascot.
//
//  Duo's slot in every reference frame is filled by the Block Party block mark. It is a
//  LOGO, not a character: it never blinks, waves, squashes or acquires a personality.
//  It appears, it sits where Duo sits, at Duo's sizes.
//
//  Two renderings, because the ground changes:
//
//  • `.plated` — the shipped raster (`BlockPartyMark`): ink frame on its white plate.
//    Used on the paper ground. The plate is deliberate — see the decided-question note
//    in `LoaderBlockPartyMark.swift`; do not re-crop to bare ink to "de-tile" it.
//
//  • `.tinted(colour)` — `MarkTemplate`, an alpha-channel asset DERIVED from the same
//    raster (alpha = ink coverage), so the geometry cannot drift from the brand mark
//    the way a hand-rebuilt vector would. Needed for S01, where the mark is white on
//    the orange field and the aperture must let the ground through. The shipped raster
//    is RGB with no alpha, so it cannot be template-rendered directly.
//
//  Sizing follows the launch loader's convention: callers pass the INK side, not the
//  plate side — `BlockPartyMark.inkFraction` (0.7511) converts between them. Sizing by
//  the plate makes the mark read visually smaller than intended.
//

import SwiftUI

enum BPMarkStyle: Equatable {
    /// Ink frame on its white plate — for the paper ground.
    case plated
    /// Template-rendered in a colour, aperture transparent — for coloured grounds.
    case tinted(Color)
}

struct BPMark: View {
    /// The INK side length in points (the frame's outer edge), not the plate's.
    let side: CGFloat
    var style: BPMarkStyle = .plated

    var body: some View {
        switch style {
        case .plated:
            // BlockPartyMark takes the PLATE side, so scale up out of the ink side.
            BlockPartyMark(side: side / BlockPartyMark.inkFraction)

        case .tinted(let colour):
            Image("MarkTemplate")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                // The template is the full plate square; the ink occupies `inkFraction`
                // of it, so scale up to land the ink on the requested side.
                .frame(width: side / BlockPartyMark.inkFraction,
                       height: side / BlockPartyMark.inkFraction)
                .foregroundStyle(colour)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("Block Party")
        }
    }
}
