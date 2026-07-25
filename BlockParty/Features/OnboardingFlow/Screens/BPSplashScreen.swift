//
//  BPSplashScreen.swift
//  S01 — the splash.
//
//  Full-bleed orange, the mark centred in white, the wordmark near the bottom in white.
//  No buttons. Holds ~1.2s, then auto-advances.
//
//  The mark is `.tinted(.white)` rather than the plated raster: on a coloured ground the
//  aperture has to let the orange through, which the shipped RGB raster cannot do.
//
//  COPY NOTE — the spec specifies a LOWERCASE "block party" wordmark here and on S02,
//  mirroring Duolingo's lowercase wordmark. The shipped app wordmark is title-case
//  "Block Party" (`Font.logo`, Jost SemiBold). Following the spec, since copy is
//  verbatim and the direction is locked — flagging because it is a real brand deviation
//  from every other surface in the app.
//
//  The auto-advance is a plain `.task` sleep, not an animation completion, so it still
//  fires under Reduce Motion — gating navigation on an animation that may not run is a
//  documented trap in this codebase.
//

import SwiftUI

struct BPSplashScreen: View {
    let onDone: () -> Void

    /// Measured from the reference: the mark sits slightly above centre, the wordmark
    /// sits in the lower third. Both re-checked against S01 in the diff loop.
    private let holdSeconds: Double = 1.2

    var body: some View {
        ZStack {
            BP.orange.ignoresSafeArea()

            GeometryReader { geo in
                let h = geo.size.height
                ZStack {
                    // Measured off S01: the mascot is centred horizontally to the pixel,
                    // with its centre 12.5pt ABOVE the screen's vertical centre
                    // (413.5 of 852 = 0.485), and stands ~108pt tall.
                    BPMark(side: 112, style: .tinted(.white))
                        .position(x: geo.size.width / 2, y: h * 0.485)

                    Text("block party")
                        .font(.logo(30))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .position(x: geo.size.width / 2, y: h * 0.82)
                }
            }
        }
        .task {
            // `-bp-hold` parks the splash so it can be screenshotted at rest. Without it
            // the 1.2s auto-advance fires first and every capture lands mid-transition —
            // which reads as a washed-out orange, because the flow's paper ground shows
            // through the cross-fade. That cost a full diff cycle to spot.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-bp-hold") { return }
            #endif
            try? await Task.sleep(for: .seconds(holdSeconds))
            onDone()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Block Party")
    }
}
