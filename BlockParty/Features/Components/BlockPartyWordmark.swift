//
//  BlockPartyWordmark.swift
//  Block Party — the logo's letterforms, alone and tintable.
//
//  The Sep 19, 2026 logo is a flat two-colour lockup, so unlike the painted render
//  it replaced, the letterforms CAN be lifted off their yellow field: `Wordmark` is
//  their tight crop with the field resolved into alpha, exported as a template
//  image by `scripts/brand/wordmark.py`.
//
//  That is what makes this view possible at all. The mark used to have to ship as a
//  square tile — the art's own ground was a warmer paper than `Hue.paper`, so an
//  unclipped mark drew a visible square against the bar. With alpha, the wordmark
//  sits on the page with nothing behind it and takes whatever ink colour it is given.
//
//  Use this wherever the logo appears on the app's own ground. `BlockPartyMark` is
//  still the right thing where the APP ICON is what is meant — the launch loader, an
//  invite card — because that is the icon as the home screen shows it, field and all.
//

import SwiftUI

struct BlockPartyWordmark: View {
    /// Cap height to descender, in points. The width follows from the artwork.
    let height: CGFloat

    /// Width over height of the exported crop (1051 × 216), so a caller only ever
    /// picks one number. Re-measure on every re-export — `wordmark.py` prints it.
    static let aspect: CGFloat = 4.8657

    var body: some View {
        Image("Wordmark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: height * Self.aspect, height: height)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Block Party")
    }
}

#Preview {
    ZStack {
        Hue.paper.ignoresSafeArea()
        VStack(spacing: 24) {
            BlockPartyWordmark(height: 18).foregroundStyle(Hue.ink)
            BlockPartyWordmark(height: 40).foregroundStyle(Hue.ink)
        }
    }
}
