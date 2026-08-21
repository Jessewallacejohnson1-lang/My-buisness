//
//  HorizonMetrics.swift
//  BlockParty
//
//  Geometry for the "Your day" horizon card. Points, at standard iPhone
//  width. The sky and rail are edge-to-edge inside the card; only the text
//  below the horizon uses the content inset.
//

import CoreGraphics
import Foundation

nonisolated enum HorizonMetrics {
    /// The strip is a whole-day tape at fixed density: 12 hours visible
    /// across the card's inner width (~30 pt/hour, so a minute is ~0.5 pt
    /// and the ±8 min event magnet is a feelable ~4 pt). Approved
    /// decision 1.
    static let visibleHours: CGFloat = 12

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
    /// Distance below the horizon where each text row's glyphs start, at
    /// standard type — the y positions the contrast sweep samples. The
    /// primary offset is the SAME constant the card lays out with; the
    /// label offset is derived from the label metrics above, so a layout
    /// nudge moves the sweep with it instead of silently un-measuring it.
    static let primaryTextBelowHorizon: CGFloat = 22
    /// primary top + 17pt line height + line spacing, at standard type.
    static let secondaryTextBelowHorizon: CGFloat = 44
    static var hourLabelBelowHorizon: CGFloat {
        hourLabelBaseline - hourLabelSize - skyHeight
    }
    /// The fixed frame rail labels centre in.
    static let railLabelWidth: CGFloat = 40
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
    /// Hour labels within this distance of the now notch yield to its
    /// label. At the tape's ~30 pt/hour density the labeled four-hour grid
    /// sits 120 pt apart, so 28 clears every collision. Measured.
    static let nowLabelClearance: CGFloat = 28
    /// Ended stubs (stated end, or start + the app-wide assumed two hours)
    /// drop to this fraction of their normal opacity.
    static let pastStubOpacityFactor: Double = 0.45

    // The scrub lift — every number verbatim from the approved spec.
    static let pickupHoldSeconds: Double = 0.25
    static let liftScale: CGFloat = 1.06
    static let liftResponse: Double = 0.32
    static let liftDamping: Double = 0.72
    /// Resting shadow drops from the old 20% to the spec's 8% (flagged at
    /// the Phase 1 gate — the 20% was itself a recorded call).
    static let restShadowOpacity: Double = 0.08
    static let restShadowRadius: CGFloat = 10
    static let restShadowY: CGFloat = 4
    static let liftShadowOpacity: Double = 0.28
    static let liftShadowRadius: CGFloat = 32
    static let liftShadowY: CGFloat = 14
    static let scrimOpacity: Double = 0.25
    static let scrimFadeSeconds: Double = 0.22
    /// The floating time pill sits this far above the sun disc — in the
    /// UNCLIPPED lifted layer, because near midday it overflows the card.
    static let pillGapAboveDisc: CGFloat = 34
    static let pillTextSize: CGFloat = 13
    /// Provisional Phase 1 pill chrome (white text on this black).
    static let pillBackgroundOpacity: Double = 0.55
    /// The pill's rendered height at its fixed 13 pt type (15.5 pt line
    /// + 2×5 padding) — the bubble-avoidance math reads this.
    static let pillEstimatedHeight: CGFloat = 26
    /// The sun disc's "lens" state while scrubbing.
    static let discLensScale: CGFloat = 1.12
    static let lensGlowOpacity: Double = 0.5
    static let magnetEaseSeconds: Double = 0.18
    static let glideResponse: Double = 0.55
    static let glideDamping: Double = 0.86

    // Phase 2 — scrubTime drives the world.
    /// The resting minute-drift ease (the strip's 0.5 pt/min creep and the
    /// sky's minute color drift ride it; off for the whole scrub session).
    static let restDriftSeconds: Double = 0.8
    /// Stub wake: within ±15 min of the marker a stub rises to full
    /// presence — 0.5→1.0 opacity, scaleY 1.15, spring 0.25/0.6 (spec).
    static let stubWakeWindow: TimeInterval = 15 * 60
    static let stubWakeScaleY: CGFloat = 1.15
    static let stubWakeResponse: Double = 0.25
    static let stubWakeDamping: Double = 0.6
    /// A woken stub's halo brightens from `haloOpacity` to this.
    static let stubWakeHaloOpacity: Double = 0.5
    /// Event line + event bubble: pure in-place crossfade, only when the
    /// string actually changes (spec 0.16 s easeInOut).
    static let eventLineFadeSeconds: Double = 0.16
    /// The on-an-event bubble (Jesse's gate spec): a capsule filled with
    /// the event's stub color, white text (brand ink when white fails
    /// contrast on a light fill), with a small tail pointing down at the
    /// stub, floating just above the stub's tip. The time pill yields
    /// upward while the bubble is present (`pillBubbleGap`).
    static let bubbleTextSize: CGFloat = 11
    static let bubbleHorizontalPadding: CGFloat = 9
    /// Fixed body height so the pill-avoidance math needs no measuring
    /// (the 11 pt label never scales — rail type is fixed, like ticks).
    static let bubbleBodyHeight: CGFloat = 21
    static let bubbleTailWidth: CGFloat = 10
    static let bubbleTailHeight: CGFloat = 5
    static let bubbleGapAboveStub: CGFloat = 1
    static let bubbleMaxWidth: CGFloat = 200
    /// Minimum clearance between the pill's bottom and the bubble's top.
    static let pillBubbleGap: CGFloat = 4
    /// The bar white bubble text must clear on its tint before the ink
    /// fallback takes over (small-text WCAG).
    static let bubbleInkContrastBar: Double = 4.5
    /// Top edge of the bubble's body over a stub of the given lane — the
    /// same number the card's pill uses to yield, so the two views cannot
    /// disagree about the clearance.
    static func bubbleBodyTop(overYoursStub: Bool) -> CGFloat {
        skyHeight
            - (overYoursStub ? yourStubHeight : publicStubHeight)
            - bubbleGapAboveStub - bubbleTailHeight - bubbleBodyHeight
    }
    /// The pill's digit roll (contentTransition(.numericText())).
    static let pillDigitRollSeconds: Double = 0.15
    /// Reduce Motion exits crossfade the card to the now-state instead of
    /// gliding the strip (plan's accessibility rule).
    static let reduceMotionExitFadeSeconds: Double = 0.25
}
