//
//  LoaderBlockPartyMark.swift
//  Block Party — the centre mark used by the launch loader.
//
//  This is the *actual app icon*, not a recreation of it. The first version drew the
//  lockup as a vector so it would scale crisply, but a hand-rebuilt mark never matches
//  the shipped icon exactly — weights and spacing drift, and the loader read as
//  "almost the icon", which is worse than either being it or not. So the loader
//  shows `LaunchMark`, which is the app icon's own export with its outer margin
//  cropped off.
//
//  The icon (Oct 8, 2026 revision) is Jesse's Icon Composer file, `BlockParty/AppIcon.icon`:
//  "Block / Party." stacked on two lines, black on a yellow gradient, with its own dark,
//  tinted and clear looks. It replaced the one-line wordmark lockup of Sep 19, which
//  replaced the Aug 25 wave figure; those masters are retired.
//
//  `LaunchMark` is Icon Composer's Default export (1024 px) inset by 36 px on every side,
//  which drops the glass rim; corners outside the export's mask are filled yellow. The
//  squircle clip below is the iOS icon corner ratio, so the mark reads as the app icon
//  does on the home screen. Re-export it whenever the .icon changes.
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
