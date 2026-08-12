//
//  BPMark.swift
//  Block Party — the mascot.
//
//  Duo's slot in every reference frame is filled by the Block Party block mark. It is a
//  LOGO, not a character: it never blinks, waves, squashes or acquires a personality.
//  It appears, it sits where Duo sits, at Duo's sizes.
//
//  There is one rendering everywhere: the supplied glossy lowercase `bp` on its
//  near-black tile. It is not flattened or recoloured when the ground changes. That
//  keeps the highlights, bevels, texture, spacing, and proportions identical to the
//  app icon instead of quietly substituting a lower-fidelity template variant.
//
//  Sizing follows the launch loader's convention: callers pass the LOCKUP side, not
//  the tile side — `BlockPartyMark.contentFraction` converts between them. Read that
//  constant; never hardcode its value here, because it is re-measured on every icon
//  re-export. Sizing by the tile makes the mark read visually smaller than intended.
//

import SwiftUI

struct BPMark: View {
    /// The LOCKUP side length in points (the lowercase letters), not the tile's.
    let side: CGFloat

    var body: some View {
        // BlockPartyMark takes the TILE side, so scale up out of the lockup side.
        BlockPartyMark(side: side / BlockPartyMark.contentFraction)
    }
}
