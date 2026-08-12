//
//  HorizonMetrics.swift
//  BlockParty
//
//  Geometry for the "Your day" horizon card. Points, at standard iPhone
//  width. The sky and rail are edge-to-edge inside the card; only the text
//  below the horizon uses the content inset.
//

import CoreGraphics

nonisolated enum HorizonMetrics {
    /// The fixed axis window: 7:00 AM – 10:00 PM town time, the waking day.
    /// The rail never re-windows; items outside clamp to the overflow
    /// markers and the sky alone follows the sun.
    static let axisStartHour = 7
    static let axisEndHour = 22

    /// Card height target (may exceed at accessibility type sizes).
    static let cardHeight: CGFloat = 164
    /// Card top → horizon. The horizon line sits at this y.
    static let skyHeight: CGFloat = 96
    /// Leading/trailing inset for everything below the horizon.
    static let contentInset: CGFloat = 16

    // Rail (below-horizon tick zone)
    static let tickHeight: CGFloat = 4
    static let labeledTickHeight: CGFloat = 6
    static let tickWidth: CGFloat = 1
    /// Hour label baseline, from card top.
    static let hourLabelBaseline: CGFloat = 115
    static let hourLabelSize: CGFloat = 12

    // Ground content — the two-line copy stack. 118pt of sky + tick zone,
    // then 17pt semibold primary, 13pt secondary, 8pt bottom: 164 exactly.
    static let primaryTextSize: CGFloat = 17
    static let secondaryTextSize: CGFloat = 13
    static let copyLineSpacing: CGFloat = 2
    static let copyBottomPadding: CGFloat = 8

    // Sky details
    static let horizonLineHeight: CGFloat = 1
    static let solarDotDiameter: CGFloat = 2.5
    static let solarDotOpacity: Double = 0.85
    /// The sky's reflection below the horizon: bottom stop at 45% fading to
    /// clear over 48 pt — running under the tick zone to the top of the
    /// copy, so the sky lands on the ground the text stands on rather than
    /// quitting at the ruler. Text contrast is verified against the
    /// COMPOSITE at the text's y, not the bare fill (see the palette sweep).
    static let reflectionHeight: CGFloat = 48
    static let reflectionOpacity: Double = 0.45
    /// Distance below the horizon where each copy line's cap height starts,
    /// at standard type — the y the contrast sweep samples.
    static let primaryTextBelowHorizon: CGFloat = 22
    static let secondaryTextBelowHorizon: CGFloat = 44
    /// Horizontal vignette on the sky region only: the sky deepening away
    /// from the light. Top stop × 0.55 luminance at this opacity.
    static let vignetteOpacity: Double = 0.20

    // Stubs
    static let yourStubHeight: CGFloat = 22
    static let publicStubHeight: CGFloat = 13
    static let yourStubMinWidth: CGFloat = 5
    static let publicStubMinWidth: CGFloat = 4
    static let yourStubRadius: CGFloat = 2.5
    static let publicStubRadius: CGFloat = 2
    static let publicStubOpacity: Double = 0.55
    static let stubCapFadeFraction: CGFloat = 0.4
    static let haloWidthScale: CGFloat = 1.6
    static let haloBlur: CGFloat = 3
    static let haloOpacity: Double = 0.30
    static let railEdgeFade: CGFloat = 20
    static let publicLaneCap = 14
    static let overlapInset: CGFloat = 1

    // Now, in the scene's own language: sun/moon disc + light pillar in the
    // sky, ink notch below the horizon. No text or UI glyphs above the line.
    static let discDiameter: CGFloat = 9
    /// The disc never rises closer than this to the card's top edge.
    static let discTopMargin: CGFloat = 14
    static let discRimOpacity: Double = 0.20
    static let discGlowRadius: CGFloat = 12
    static let discGlowOpacity: Double = 0.35
    static let moonOpacity: Double = 0.90
    static let pillarWidth: CGFloat = 1.5
    static let pillarOpacity: Double = 0.65
    static let notchWidth: CGFloat = 2.5
    static let notchHeight: CGFloat = 6
    /// Hour labels within this distance of the now notch yield to its label.
    /// One rail hour is ~24pt at standard width, so the spec's ~24 left an
    /// exactly-on-the-hour "12p now" collision — 28 clears it. Measured.
    static let nowLabelClearance: CGFloat = 28
    /// Ended stubs (stated end, or start + the app-wide assumed two hours)
    /// drop to this fraction of their normal opacity.
    static let pastStubOpacityFactor: Double = 0.45

    // Overflow marker
    static let overflowBarWidth: CGFloat = 3
    static let overflowTextSize: CGFloat = 10
}
