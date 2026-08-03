//
//  UtilityRowMotionTests.swift
//  BlockPartyTests — the Utility Row's Phase-3 motion pass. The row stays a
//  full-bleed HORIZONTAL scroll of 148x92 tiles; what changes is how it arrives and
//  how it reacts, and both of those are token-and-arithmetic, not pixels.
//
//  Two things here are pure logic and therefore worth locking:
//
//  1. The first-appearance cascade must run ONCE PER APP SESSION. A row that plays
//     its stagger from `.onAppear` replays it on every tab switch back to Today and
//     on every scroll-back — the same trap `AlmanacReveal.hasWrittenThisLaunch`
//     already solves for the almanac's write. The latch, not the animation, is the
//     testable part.
//  2. The bento radius is currently a hardcoded 22 in `UtilityTileMetrics` carrying
//     a "deliberate match" comment. A comment cannot fail a build; an assertion can.
//     Promoting 22 to `Radius.bento` and pinning the tile to it means the tile and
//     the Calendar bento can no longer drift apart silently.
//
//  Motion VALUES are not asserted — see `testMotionTokensExist` for why.
//

import XCTest
import SwiftUI
@testable import BlockParty

@MainActor
final class UtilityRowMotionTests: XCTestCase {

    /// Tolerance for the stagger arithmetic — `3 * 0.04` is not exactly 0.12 in
    /// binary floating point, so the delays are compared with accuracy.
    private static let delayAccuracy: TimeInterval = 0.0001

    override func setUp() {
        super.setUp()
        // The launch latch is process-global state; clear it so no case can inherit
        // (or leak) a "already played" from another.
        UtilityRowEntrance.resetForTesting()
    }

    // MARK: - The latch: once per launch, not once per appearance

    func testEntrancePlaysOncePerLaunchNotPerAppearance() {
        // Arrange — a fresh launch: the row has not cascaded yet.
        XCTAssertFalse(
            UtilityRowEntrance.hasPlayedThisLaunch,
            "A fresh launch must be able to play the entrance"
        )

        // Act — the row appears for the first time and plays its cascade.
        UtilityRowEntrance.markPlayed()

        // Assert — and every LATER appearance in the same launch is a no-op: leaving
        // Today and coming back, or scrolling the row off and back on, must not
        // re-trigger the rise. This is the whole point of the latch.
        for appearance in 1...5 {
            XCTAssertTrue(
                UtilityRowEntrance.hasPlayedThisLaunch,
                "Appearance \(appearance) must still see the entrance as played — the cascade cannot replay"
            )
        }

        // …and marking again (a second row instance, a re-render) must not unlatch it.
        UtilityRowEntrance.markPlayed()
        XCTAssertTrue(UtilityRowEntrance.hasPlayedThisLaunch, "markPlayed() must be idempotent")
    }

    // MARK: - The cascade arithmetic

    func testStaggerDelayIsPerTileIndex() {
        // Arrange / Act / Assert — the delay is a function of the tile's POSITION,
        // so weather leads with no delay and each following tile trails by one
        // stagger. Nothing here depends on when a tile happened to appear.
        XCTAssertEqual(UtilityRowEntrance.delay(forTileAt: 0), 0, accuracy: Self.delayAccuracy)
        XCTAssertEqual(UtilityRowEntrance.delay(forTileAt: 1), 0.04, accuracy: Self.delayAccuracy)
        XCTAssertEqual(UtilityRowEntrance.delay(forTileAt: 3), 0.12, accuracy: Self.delayAccuracy)
    }

    func testEntranceGeometryConstants() {
        // Arrange / Act / Assert — 0.04s per tile is quick enough that a five-tile
        // row is fully in under 0.2s, and a 10pt rise is a settle, not a fly-in
        // (the sheet cascade's `StaggeredAppear` uses the same idea at 8pt).
        XCTAssertEqual(UtilityRowEntrance.stagger, 0.04, accuracy: Self.delayAccuracy)
        XCTAssertEqual(UtilityRowEntrance.riseOffset, 10)
    }

    // MARK: - The bento radius, tokenised

    func testBentoRadiusTokenMatchesTheTileMetric() {
        // Arrange / Act / Assert — 22 joins the canonical radius scale…
        XCTAssertEqual(Radius.bento, 22)

        // …and this is the assertion that earns the token: the tile must READ the
        // token rather than restate the number. A comment saying "== bento
        // (hardcoded, deliberate match)" cannot fail a build when one of the two
        // moves; this can.
        XCTAssertEqual(
            UtilityTileMetrics.corner,
            Radius.bento,
            "The Utility tile corner must be the bento token, not a parallel literal"
        )
    }

    // MARK: - Motion tokens

    func testMotionTokensExist() {
        // SwiftUI's `Animation` is opaque — it hands back no response/damping to read,
        // so there is deliberately NOTHING asserted about the spring values here. What
        // this case buys is a compile-time pin: the three tokens must exist, live on
        // `Motion`, and be spelled exactly this way.
        //
        // The values themselves belong in `Motion.swift` because the house rule bans
        // inline springs in views — `UtilityRowView` currently hardcodes
        // `.spring(response: 0.44, dampingFraction: 0.82)` for the expand, and that
        // literal is what `Motion.bentoExpand` replaces.

        // Arrange / Act
        let tokens: [Animation] = [Motion.bentoExpand, Motion.tilePress, Motion.tileEntrance]

        // Assert
        XCTAssertEqual(tokens.count, 3, "Three named tokens: bento expand, tile press, tile entrance")
    }
}
