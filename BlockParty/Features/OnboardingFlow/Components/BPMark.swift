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
//  • `.plated` — the shipped raster (`BlockPartyMark`): the BP lockup (script letters
//    + party hat + confetti) on its near-black tile. Used on the paper ground. The
//    tile is deliberate — see the decided-question note in `LoaderBlockPartyMark.swift`;
//    do not re-crop to the bare lettering to "de-tile" it.
//
//  • `.tinted(colour)` — `MarkTemplate`, an alpha-channel asset DERIVED from the same
//    raster (alpha = artwork coverage), so the geometry cannot drift from the brand
//    mark the way a hand-rebuilt vector would. Needed for S01, where the mark is white
//    on the orange field and the letter counters must let the ground through. The
//    shipped raster is RGB with no alpha, so it cannot be template-rendered directly.
//
//  Sizing follows the launch loader's convention: callers pass the LOCKUP side, not
//  the tile side — `BlockPartyMark.contentFraction` converts between them. Read that
//  constant; never hardcode its value here, because it is re-measured on every icon
//  re-export. Sizing by the tile makes the mark read visually smaller than intended.
//

import SwiftUI

enum BPMarkStyle: Equatable {
    /// The icon art on its near-black tile — for the paper ground.
    case plated
    /// Template-rendered in a colour, aperture transparent — for coloured grounds.
    case tinted(Color)
}

struct BPMark: View {
    /// The LOCKUP side length in points (letters + hat extent), not the tile's.
    let side: CGFloat
    var style: BPMarkStyle = .plated

    var body: some View {
        switch style {
        case .plated:
            // BlockPartyMark takes the TILE side, so scale up out of the lockup side.
            BlockPartyMark(side: side / BlockPartyMark.contentFraction)

        case .tinted(let colour):
            Image("MarkTemplate")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                // The template is the full tile square; the lockup occupies
                // `contentFraction` of it, so scale up to land it on the requested side.
                .frame(width: side / BlockPartyMark.contentFraction,
                       height: side / BlockPartyMark.contentFraction)
                .foregroundStyle(colour)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("Block Party")
        }
    }
}
