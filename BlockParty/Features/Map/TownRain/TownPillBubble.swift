//
//  TownPillBubble.swift
//  Block Party — the press feedback on the map's "Saint Joseph" pill.
//
//  The pill is what drops a brand mark onto the map, so the press itself gets an
//  acknowledgement: the pill swells a touch, and one ring blooms out of its own
//  silhouette and dissolves — a bubble leaving the surface. It is the only cue that
//  fires at the instant of the tap; the camera fly and the falling mark both take a
//  beat to read.
//
//  Monochrome by the house rule — the ring is `Hue.ink` at low opacity, not a tint.
//  Under Reduce Motion the ring still appears and dissolves but nothing scales (§11),
//  so the press is still acknowledged without motion.
//

import SwiftUI

extension View {
    /// Blooms a ring out of this view's capsule silhouette whenever `nonce` changes.
    func townPillBubble(nonce: Int) -> some View {
        modifier(TownPillBubble(nonce: nonce))
    }
}

private struct TownPillBubble: ViewModifier {
    let nonce: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 at the instant of the press, 1 once the ring has fully bloomed and gone.
    /// Starts at 1 so nothing shows before the first tap.
    @State private var bloom: CGFloat = 1
    /// The pill's own swell.
    @State private var swell: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(swell)
            .overlay {
                Capsule()
                    .stroke(Hue.ink, lineWidth: Self.ringWidth)
                    .scaleEffect(reduceMotion ? 1 : 1 + Self.ringGrowth * bloom)
                    .opacity(Double(Self.ringOpacity * (1 - bloom)))
                    .allowsHitTesting(false)
            }
            .onChange(of: nonce) { _, _ in bubble() }
    }

    private func bubble() {
        bloom = 0
        withAnimation(.easeOut(duration: Self.bloomDuration)) { bloom = 1 }

        guard !reduceMotion else { return }             // §11: the ring alone carries it
        withAnimation(Motion.snappy) { swell = Self.swellScale }
        // Settle back on the way out, so the pill reads as one press rather than two
        // separate movements.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.swellHold) {
            withAnimation(Motion.snappy) { swell = 1 }
        }
    }

    /// Just past the pill's edge — a bubble leaving the surface, not a shockwave.
    private static let ringGrowth: CGFloat = 0.26
    private static let ringOpacity: CGFloat = 0.30
    private static let ringWidth: CGFloat = 1.5
    private static let bloomDuration: TimeInterval = 0.5
    private static let swellScale: CGFloat = 1.06
    private static let swellHold: TimeInterval = 0.14
}
