//
//  ConcentricRectangle.swift
//  Block Party — a rounded rectangle whose corner stays concentric with its container's.
//
//  ⚠️ NAME SHADOWING — READ BEFORE USING
//  SwiftUI ships its own `ConcentricRectangle` on iOS 26, and this app targets 26.5, so the
//  SDK type is always available. This type has the same name, which means every unqualified
//  `ConcentricRectangle` inside the BlockParty module resolves to THIS one, not SwiftUI's.
//  To reach the framework shape, spell it `SwiftUI.ConcentricRectangle`.
//
//  The initializer deliberately does NOT mirror SwiftUI's (`init()`,
//  `init(corners:isUniform:)`). That is the safety feature: a call site written against the
//  framework API fails to compile here instead of silently drawing something else. The two
//  types also solve different problems — SwiftUI's reads the resolved container shape from
//  the environment (`.containerShape`), which a plain `Shape` cannot see; this one takes the
//  container's radius explicitly, for the cases where the value is known in code and the
//  environment lookup is unavailable or unwanted.
//
//  The concentric rule: two rounded rectangles look nested rather than merely stacked when
//  the gap between their corner arcs is the same width as the gap along their straight edges.
//  That holds when innerRadius == outerRadius − inset. Below zero the corner would invert, so
//  it clamps; `minimumRadius` lets a caller keep a soft corner instead of collapsing to square.
//

import SwiftUI

/// A rounded rectangle sized to sit `inset` points inside a container of `containerRadius`,
/// with the corner radius that keeps the two outlines concentric.
struct ConcentricRectangle: Shape {

    /// Corner radius of the container this shape nests inside.
    var containerRadius: CGFloat

    /// Uniform gap between this shape's edge and the container's edge.
    var inset: CGFloat

    /// Floor for the derived corner radius. Default 0 (square corners once the inset eats
    /// the container's radius); raise it to keep a soft corner on deeply inset content.
    var minimumRadius: CGFloat = 0

    /// Matches `RoundedRectangle`'s corner curve. `.continuous` is the brand default — the
    /// squircle Apple uses for cards and sheets.
    var style: RoundedCornerStyle = .continuous

    /// The concentric corner radius for a container/inset pair, clamped at `minimum`.
    ///
    /// Pure and `nonisolated` so layout code and tests can ask for the number without
    /// building a `Path`.
    nonisolated static func innerRadius(
        containerRadius: CGFloat,
        inset: CGFloat,
        minimum: CGFloat = 0
    ) -> CGFloat {
        max(minimum, containerRadius - inset)
    }

    nonisolated func path(in rect: CGRect) -> Path {
        // A corner arc wider than half the shorter side would overlap its neighbour; the
        // capsule limit is the same one `RoundedRectangle` applies internally, made explicit
        // here so the clamp is visible where the math lives.
        let capsuleLimit = min(rect.width, rect.height) / 2
        let radius = min(
            capsuleLimit,
            Self.innerRadius(
                containerRadius: containerRadius,
                inset: inset,
                minimum: minimumRadius
            )
        )
        return RoundedRectangle(cornerRadius: radius, style: style).path(in: rect)
    }

    /// Animate the container radius and the inset together, so a card that grows its corner
    /// or its padding morphs instead of snapping.
    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(containerRadius, inset) }
        set {
            containerRadius = newValue.first
            inset = newValue.second
        }
    }
}
