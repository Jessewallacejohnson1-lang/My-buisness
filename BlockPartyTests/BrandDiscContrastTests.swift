//
//  BrandDiscContrastTests.swift
//  BlockPartyTests — the Town bar's map disc is the app's one solid yellow control,
//  and yellow is the one brand colour that will happily render a glyph invisible.
//
//  #FCE804 has a relative luminance of 0.784 — it is nearly as bright as paper. That
//  makes the choice of what is drawn ON it a correctness question rather than a taste
//  one: white on our yellow is 1.26:1.
//
//  Two things are pinned here:
//
//  1. `Hue.onBrandDiscHex` restates `Hue.ink`'s LIGHT value as a literal, because
//     `Hue` is `nonisolated` and `Color.onLightCanvas` — the property the map's
//     fixed-canvas palettes route through — is MainActor-isolated, so the derivation
//     the other call sites use would cost a warning in the token layer. A restated
//     value can drift from its source. This is what stops it.
//  2. The ratios themselves, including the two counterfactuals, so that "why is the
//     glyph dark rather than white" survives as a measurement rather than
//     as a claim in a comment.
//

import SwiftUI
import UIKit
import XCTest
@testable import BlockParty

@MainActor
final class BrandDiscContrastTests: XCTestCase {

    /// WCAG AA for a non-text graphical object. The glyph clears it many times over;
    /// the point of the floor is that a future re-tint cannot quietly fall under it.
    private static let graphicalObjectThreshold = 3.0

    // MARK: Fixtures

    /// A `Color`'s value in one appearance, packed the way `UtilityContrast` wants.
    private func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return channel(r) << 16 | channel(g) << 8 | channel(b)
    }

    private func ratio(_ a: UInt32, on b: UInt32) -> Double {
        let la = UtilityContrast.luminance(a), lb = UtilityContrast.luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: - The restated value cannot drift

    func testOnBrandDiscIsInksLightValue() {
        XCTAssertEqual(
            Hue.onBrandDiscHex, hex(Hue.ink, .light),
            """
            `Hue.onBrandDiscHex` is a hand-written copy of `Hue.ink`'s light column, \
            and the two have diverged. Update the literal — or, if `ink` moved on \
            purpose, re-measure its contrast on `brandDisc` before you do.
            """
        )
    }

    func testBrandDiscIsTheBrandYellowAtFullStrength() {
        XCTAssertEqual(
            hex(Hue.brandDisc, .light), Hue.brandYellowHex,
            "The brand disc must be THE brand yellow, not a second one. See DESIGN.md."
        )
        XCTAssertEqual(
            hex(Hue.brandDisc, .dark), Hue.brandYellowHex,
            "The disc is a fixed canvas — the same yellow in both appearances, which is why what sits on it is pinned to the light ramp."
        )
    }

    // MARK: - The glyph is legible, in both appearances

    func testGlyphClearsAAOnTheDiscInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let measured = ratio(hex(Hue.onBrandDisc, style), on: hex(Hue.brandDisc, style))
            XCTAssertGreaterThan(
                measured, Self.graphicalObjectThreshold,
                String(format: "The glyph measures %.2f:1 on the disc in %@ appearance.",
                       measured, style == .dark ? "dark" : "light")
            )
        }
    }

    /// The pinning is not belt-and-braces: following the system here really would
    /// erase the glyph.
    func testFollowingTheSystemRampWouldEraseTheGlyphInDarkMode() {
        let naive = ratio(hex(Hue.ink, .dark), on: Hue.brandYellowHex)
        XCTAssertLessThan(
            naive, Self.graphicalObjectThreshold,
            """
            `Hue.ink`'s dark value now has usable contrast on the brand yellow, so the \
            reason `onBrandDisc` is pinned to the light ramp no longer holds. Re-read \
            the token's comment before simplifying it away.
            """
        )
    }

    /// Why the glyph is never white. If this ever passes 3:1 the brand yellow has
    /// changed into a different colour.
    func testAWhiteGlyphWouldNotBeLegibleOnOurYellow() {
        let white = ratio(0xFFFFFF, on: Hue.brandYellowHex)
        XCTAssertLessThan(
            white, Self.graphicalObjectThreshold,
            String(format: "White on the brand yellow measures %.2f:1.", white)
        )
    }
}
