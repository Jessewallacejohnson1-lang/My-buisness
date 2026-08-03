//
//  UtilityContrastTests.swift
//  BlockPartyTests — the Utility Row tiles are the app's ONE approved colour
//  exception, and the whole exception is paid for by white text clearing WCAG
//  4.5:1. The gradients were tuned for FULL-opacity white; rendering the label at
//  .white.opacity(0.9) and the secondary line at 0.8 measured 4.18–4.24:1 and
//  3.64–3.73:1, failing 18 of 33 layers. These tests lock the fix in: every
//  gradient stop clears 4.5:1 at opaque white, the shared text-opacity constant
//  IS 1.0, and the contrast math itself is pinned to independently computed
//  reference values so a bug in the helper can't mask a real failure.
//

import XCTest
@testable import BlockParty

@MainActor
final class UtilityContrastTests: XCTestCase {

    /// WCAG 2.1 AA minimum for normal-size text.
    private static let wcagAAThreshold: Double = 4.5

    /// Tolerance for the pinned reference ratios (computed independently).
    private static let referenceAccuracy: Double = 0.02

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

    // MARK: - Every stop must carry opaque white text

    func testEveryGradientStopClearsThresholdForOpaqueWhiteText() {
        // Arrange
        let tokens = allGradientTokens()
        XCTAssertEqual(tokens.count, 11, "Expected 5 static tokens + 6 weather states")

        for token in tokens {
            XCTAssertEqual(token.stops.count, 2, "\(token.name): a gradient token is a [top, bottom] hex pair")

            for (index, stop) in token.stops.enumerated() {
                // Act
                let ratio = UtilityContrast.ratio(white: 1.0, on: stop)

                // Assert
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    Self.wcagAAThreshold,
                    String(
                        format: "%@ stop %d (#%06X): white 1.0 measures %.2f:1, below the %.1f:1 floor",
                        token.name, index, stop, ratio, Self.wcagAAThreshold
                    )
                )
            }
        }
    }

    // MARK: - The durable guard: no tile text layer may dim its white

    func testNoTileTextLayerUsesReducedOpacityWhite() {
        // Arrange
        let textOpacity = UtilityTileMetrics.textOpacity

        // Assert — hierarchy is carried by the size/weight ladder, never by alpha.
        XCTAssertEqual(
            textOpacity, 1.0,
            "Tile text must be full-opacity white; hierarchy comes from size/weight, not alpha"
        )

        // …and the constant must actually hold every gradient above the floor,
        // so lowering it can never pass this file.
        for token in allGradientTokens() {
            for (index, stop) in token.stops.enumerated() {
                let ratio = UtilityContrast.ratio(white: textOpacity, on: stop)
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    Self.wcagAAThreshold,
                    String(
                        format: "%@ stop %d (#%06X): white at opacity %.2f measures %.2f:1",
                        token.name, index, stop, textOpacity, ratio
                    )
                )
            }
        }
    }

    // MARK: - Pin the arithmetic itself

    func testContrastMathMatchesKnownReferenceValues() {
        // Arrange / Act / Assert — values computed independently from the WCAG 2.1
        // formula (sRGB linearize → 0.2126R + 0.7152G + 0.0722B → (L1+.05)/(L2+.05)),
        // white composited over the opaque stop at the given alpha.

        // Full-opacity white on the weather tile's lighter stop — the tuned floor.
        XCTAssertEqual(
            UtilityContrast.ratio(white: 1.0, on: 0x3677AF), 4.76,
            accuracy: Self.referenceAccuracy
        )

        // The old label alpha (0.9) on the library tile's lighter stop — a FAIL.
        XCTAssertEqual(
            UtilityContrast.ratio(white: 0.9, on: 0xA14BCD), 4.18,
            accuracy: Self.referenceAccuracy
        )

        // The old secondary alpha (0.8) on the garbage tile's lighter stop — a FAIL.
        XCTAssertEqual(
            UtilityContrast.ratio(white: 0.8, on: 0x1F8438), 3.64,
            accuracy: Self.referenceAccuracy
        )
    }
}
