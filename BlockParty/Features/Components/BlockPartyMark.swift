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
//  The icon art (Sep 19, 2026 revision) is the WORDMARK LOCKUP — black "BlockParty."
//  on a yellow field, shipped 1:1 from `docs/brand/source-logo-1254.png`. It replaced
//  the Aug 25 wave figure (a painted figure inside broadcast arcs), which Jesse cut
//  on 2026-09-19; that art and the coral "bp" tiles before it are both retired and
//  their masters are gone from the repo.
//
//  `LaunchMark` is the same art inset by 36/1024 on every side, kept from the wave
//  figure's export so `contentFraction` stays the only number that moves. The
//  squircle clip below is the iOS icon corner ratio, so the mark reads as the app
//  icon does on the home screen.
//
//  The yellow ground is KEPT ON PURPOSE here. This view means "the app icon", so it
//  ships the icon whole, the way the home screen shows it. Where the logo is meant to
//  sit on the app's own page instead — the Today bar — use `BlockPartyWordmark`,
//  which is the letterforms alone on alpha.
//

import SwiftUI

struct BlockPartyMark: View {
    /// Outer side length of the mark, in points.
    let side: CGFloat

    /// Apple's icon corner ratio — the mark is clipped exactly as iOS masks an icon.
    private static let cornerRatio: CGFloat = 0.2237

    /// Fraction of the asset's side spanned by the artwork — the lockup's long edge,
    /// the part the eye actually sizes (1051 px of the 1166 px launch crop), measured
    /// off the source by `scripts/brand/wordmark.py`. Callers size the mark through
    /// this so the ARTWORK lands at a reference extent, rather than the field doing so.
    ///
    /// History: 0.8273 (confetti render) -> 0.8864 (flat vector) -> 0.8614 (script BP
    /// render) -> 0.8591 (lowercase bp render) -> 0.9727 (wave figure) -> 0.9014
    /// (wordmark lockup). It moves on EVERY re-export, so re-measure and update it
    /// every time — a stale value silently mis-sizes every loader mark rather than
    /// failing loudly.
    static let contentFraction: CGFloat = 0.9014

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
