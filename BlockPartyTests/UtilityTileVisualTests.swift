//
//  UtilityTileVisualTests.swift
//  BlockPartyTests — Phase 3 (design + motion) of the Utility Row, guarding the two
//  visual decisions that can silently break the row's WCAG budget.
//
//  1. The symbol WATERMARK is INK (#111111 @ 0.10), not white. Ink darkens the
//     gradient it sits on, so white text over it gets MORE contrast (4.76–14.22:1
//     becomes 5.50–14.74:1). A white watermark at the same alpha lightens it — the
//     library stop drops to 4.03:1 and fails. The tile view is a SwiftUI body with no
//     test seam, so what is pinned here is the arithmetic that makes ink the only
//     defensible choice; a later "make the watermark white" change then has to walk
//     past a test that spells out why it fails.
//  2. The loading state no longer DIMS the gradient. Rendering it at 0.4 over
//     Hue.paper measured 1.82:1 under white text — worse than any state the row can
//     otherwise reach. `loadingGradientOpacity` is 1.0 and this file records the
//     defect it replaces.
//
//  The watermark is a symbol SHAPE, not a full-bleed veil, so a given pixel of text
//  sits over either the bare stop or the watermarked one. Both bounds are asserted
//  ≥ 4.5:1 here, so every partial-coverage pixel in between passes too.
//
//  Reference ratios below were computed independently from the WCAG 2.1 formula
//  (sRGB linearize → 0.2126R + 0.7152G + 0.0722B → (L1+.05)/(L2+.05)), compositing
//  in sRGB — the same order the display uses, and the same order UtilityContrast uses.
//

import XCTest
@testable import BlockParty

@MainActor
final class UtilityTileVisualTests: XCTestCase {

    /// WCAG 2.1 AA minimum for normal-size text.
    private static let wcagAAThreshold: Double = 4.5

    /// Tolerance for the pinned reference ratios (computed independently).
    private static let referenceAccuracy: Double = 0.02

    /// `Hue.paper` #FAFAF7 as a raw hex — the page the Utility Row sits on, and what
    /// a dimmed gradient would blend into. `Hue` vends a SwiftUI `Color`, which the
    /// contrast math cannot read back, so the token is restated here.
    private static let paperHex: UInt32 = 0xFAFAF7

    /// The library tile's LIGHTER stop — the worst-case purple, and the stop both
    /// counterfactuals below are measured on.
    private static let libraryLighterStop: UInt32 = 0xA14BCD

    /// The loading opacity that shipped before Phase 3, kept only to prove it failed.
    private static let retiredLoadingOpacity: Double = 0.4

    // MARK: - Fixtures

    /// Every gradient token the Utility Row can render, named for diagnosis.
    private func allGradientTokens() -> [(name: String, stops: [UInt32])] {
        let staticTokens: [(name: String, stops: [UInt32])] = [
            ("weather",   UtilityTileGradient.weather),
            ("garbage",   UtilityTileGradient.garbage),
            ("roads",     UtilityTileGradient.roads),
            ("library",   UtilityTileGradient.library),
            ("customize", UtilityTileGradient.customize),
        ]
        let weatherTokens = WeatherState.allCases.map { state in
            (name: "weather(for: .\(state.rawValue))", stops: UtilityTileGradient.weather(for: state))
        }
        return staticTokens + weatherTokens
    }

    /// `base` as it renders once `overlay` has been laid over it at `alpha`: mixed in
    /// sRGB and rounded back to 8 bits, which is what the display actually shows.
    ///
    /// Needed because the production API composites INK only (by design) — the WHITE
    /// watermark and the dimmed-gradient counterfactuals are deliberately not
    /// expressible through it, so the surface is built here and handed to the real
    /// `UtilityContrast.ratio(white:on:)` for the luminance math.
    private func composite(_ overlay: UInt32, at alpha: Double, over base: UInt32) -> UInt32 {
        func mix(_ shift: UInt32) -> UInt32 {
            let top = Double((overlay >> shift) & 0xFF)
            let bottom = Double((base >> shift) & 0xFF)
            return UInt32((alpha * top + (1 - alpha) * bottom).rounded())
        }
        return (mix(16) << 16) | (mix(8) << 8) | mix(0)
    }

    // MARK: - The ink watermark can only ever help

    func testInkWatermarkRaisesContrastOnEveryGradientStop() {
        // Arrange
        let tokens = allGradientTokens()
        XCTAssertEqual(tokens.count, 11, "Expected 5 static tokens + 6 weather states")
        let inkAlpha = UtilityTileMetrics.watermarkAlpha

        for token in tokens {
            XCTAssertEqual(token.stops.count, 2, "\(token.name): a gradient token is a [top, bottom] hex pair")

            for (index, stop) in token.stops.enumerated() {
                // Act — the bare stop, and the same stop under the ink watermark.
                let bare = UtilityContrast.ratio(white: 1.0, on: stop)
                let watermarked = UtilityContrast.ratio(white: 1.0, on: stop, overlaidByInk: inkAlpha)

                // Assert — white text still clears AA over the watermarked surface…
                XCTAssertGreaterThanOrEqual(
                    watermarked,
                    Self.wcagAAThreshold,
                    String(
                        format: "%@ stop %d (#%06X): ink watermark at %.2f measures %.2f:1 (bare %.2f:1), below the %.1f:1 floor",
                        token.name, index, stop, inkAlpha, watermarked, bare, Self.wcagAAThreshold
                    )
                )

                // …and ink only ever DARKENS the surface, so contrast must improve.
                // A regression here means the watermark is lightening the tile —
                // i.e. it is no longer ink.
                XCTAssertGreaterThan(
                    watermarked,
                    bare,
                    String(
                        format: "%@ stop %d (#%06X): watermarked %.2f:1 is not better than bare %.2f:1 — the watermark is not darkening the tile",
                        token.name, index, stop, watermarked, bare
                    )
                )
            }
        }
    }

    // MARK: - Why the watermark is ink and not white

    func testWatermarkAlphaIsInkNotWhite() {
        // Arrange — the shipped alpha, and the worst-case (lightest) gradient stop.
        let alpha = UtilityTileMetrics.watermarkAlpha
        XCTAssertEqual(alpha, 0.10, "The watermark alpha is 0.10; both counterfactuals below are measured at it")

        // Act — the same stop, the same alpha, the only difference being the ink.
        let overInk = UtilityContrast.ratio(
            white: 1.0, on: Self.libraryLighterStop, overlaidByInk: alpha
        )
        let whiteWatermarkSurface = composite(0xFFFFFF, at: alpha, over: Self.libraryLighterStop)
        let overWhite = UtilityContrast.ratio(white: 1.0, on: whiteWatermarkSurface)

        // Assert — ink PASSES…
        XCTAssertEqual(overInk, 5.53, accuracy: Self.referenceAccuracy)
        XCTAssertGreaterThanOrEqual(
            overInk,
            Self.wcagAAThreshold,
            String(format: "ink watermark at %.2f on #%06X measures %.2f:1", alpha, Self.libraryLighterStop, overInk)
        )

        // …and a WHITE watermark at the identical alpha FAILS. This is the whole
        // reason the watermark is ink: swapping the colour is not a taste change.
        XCTAssertEqual(overWhite, 4.03, accuracy: Self.referenceAccuracy)
        XCTAssertLessThan(
            overWhite,
            Self.wcagAAThreshold,
            String(
                format: "a white watermark at %.2f on #%06X measures %.2f:1 — if this now passes, the counterfactual has stopped being a counterfactual",
                alpha, Self.libraryLighterStop, overWhite
            )
        )
    }

    // MARK: - The loading state must not dim the gradient

    func testLoadingStateDoesNotDimTheGradient() {
        // Arrange / Act
        let opacity = UtilityTileMetrics.loadingGradientOpacity

        // Assert — a loading tile renders its gradient at FULL strength. The tokens
        // were tuned for an opaque surface; anything less blends toward the page.
        XCTAssertEqual(
            opacity, 1.0,
            "A loading tile must not dim its gradient — the stops only clear 4.5:1 at full opacity"
        )

        // The defect this replaced: the gradient at 0.4 blended into Hue.paper, which
        // left white text at ~1.82:1 — the worst contrast the row has ever shipped.
        let dimmedSurface = composite(
            Self.libraryLighterStop, at: Self.retiredLoadingOpacity, over: Self.paperHex
        )
        let dimmedRatio = UtilityContrast.ratio(white: 1.0, on: dimmedSurface)

        XCTAssertEqual(dimmedRatio, 1.82, accuracy: Self.referenceAccuracy)
        XCTAssertLessThan(
            dimmedRatio,
            Self.wcagAAThreshold,
            String(
                format: "#%06X at %.1f over paper measures %.2f:1 — the retired loading opacity must stay a documented failure",
                Self.libraryLighterStop, Self.retiredLoadingOpacity, dimmedRatio
            )
        )
    }

    // MARK: - Watermark geometry

    func testWatermarkGeometryConstants() {
        // Arrange / Act / Assert — the watermark is a single oversized glyph bled off
        // the tile: 72pt inside a 148×92 tile, at 0.10 so it reads as texture, not as
        // a second icon competing with the 13pt label glyph.
        XCTAssertEqual(UtilityTileMetrics.watermarkSize, 72)
        XCTAssertEqual(UtilityTileMetrics.watermarkAlpha, 0.10)
    }
}
