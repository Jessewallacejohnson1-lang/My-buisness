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
    static let hourLabelBaseline: CGFloat = 113
    static let hourLabelSize: CGFloat = 10

    // Ground content
    static let countsBaseline: CGFloat = 137
    static let countsSize: CGFloat = 13
    static let buttonTop: CGFloat = 128
    static let buttonBottom: CGFloat = 152

    // Sky details
    static let horizonLineHeight: CGFloat = 1
    static let solarDotDiameter: CGFloat = 2.5
    static let solarDotOpacity: Double = 0.85
    /// The sky's reflection below the horizon: bottom stop at 30% fading to
    /// clear over 32 pt. The text zone starts below the fade, on solid fill.
    static let reflectionHeight: CGFloat = 32
    static let reflectionOpacity: Double = 0.30

    // Stubs
    static let yourStubHeight: CGFloat = 22
    static let publicStubHeight: CGFloat = 13
    static let yourStubMinWidth: CGFloat = 5
    static let publicStubMinWidth: CGFloat = 4
    static let yourStubRadius: CGFloat = 2.5
    static let publicStubRadius: CGFloat = 2
    static let publicStubOpacity: Double = 0.5
    static let stubCapFadeFraction: CGFloat = 0.4
    static let haloWidthScale: CGFloat = 1.6
    static let haloBlur: CGFloat = 3
    static let haloOpacity: Double = 0.22
    static let railEdgeFade: CGFloat = 20
    static let publicLaneCap = 14
    static let overlapInset: CGFloat = 1

    // Now line
    static let nowLineWidth: CGFloat = 1.5
    static let nowLineHeight: CGFloat = 30

    // Overflow marker
    static let overflowBarWidth: CGFloat = 3
    static let overflowTextSize: CGFloat = 10
}
