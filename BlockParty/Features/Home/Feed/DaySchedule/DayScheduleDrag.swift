//
//  DayScheduleDrag.swift
//  Block Party — the arithmetic behind hand-built drag-to-dismiss.
//
//  A `.sheet` gave this away for free. Presenting in-hierarchy means owning it, and
//  the two things that make a system sheet feel right are both decisions, not
//  gestures:
//
//    1. THE TRANSLATION IS NOT LINEAR IN BOTH DIRECTIONS. Downward the card tracks
//       the finger exactly, because it is going somewhere. Upward there is nowhere
//       to go — the sheet is already at its resting detent — so the pull is rubber
//       banded: it gives a little, then asymptotically stops. UIScrollView's own
//       curve, `(1 - 1/(x/limit + 1)) * limit`, so it feels like the rest of iOS.
//
//    2. DISTANCE ALONE IS THE WRONG TEST. A fast flick two centimetres down means
//       "close it"; a slow drag the same distance means "let me see what is under
//       here". So the verdict is taken on the PROJECTED resting point — where the
//       finger's momentum would carry the card — not on where it was released.
//
//  Pure and `nonisolated` so both are assertable in a plain unit test rather than
//  only in a gesture nobody can automate here.
//

import CoreGraphics
import Foundation

nonisolated enum DayScheduleDrag {
    /// How far an upward pull can stretch, no matter how hard it is pulled.
    static let rubberBandLimit: CGFloat = 64

    /// The shortest projected travel that still counts as a dismissal, whatever the
    /// screen height. Guards a small viewport from a hair-trigger.
    static let minimumDismissDistance: CGFloat = 96

    /// …and the same threshold as a share of the viewport, so a tall screen asks
    /// for a proportionally longer pull.
    static let dismissHeightFraction: CGFloat = 0.22

    /// How far ahead the release velocity is projected. A quarter of a second is
    /// the window a flick reads as "and keep going".
    static let velocityProjection: CGFloat = 0.25

    /// The card's offset for a raw gesture translation.
    ///
    /// - Parameter rubberBands: false under Reduce Motion, where an upward pull
    ///   simply does not move the card at all — the spec asks for no rubber
    ///   banding, and a stiff surface is the honest version of that.
    static func translation(for raw: CGFloat, rubberBands: Bool = true) -> CGFloat {
        // Downward: one-to-one. The card is following the finger toward the exit.
        guard raw < 0 else { return raw }
        guard rubberBands else { return 0 }

        let pull = -raw
        let given = (1 - 1 / (pull / rubberBandLimit + 1)) * rubberBandLimit
        return -given
    }

    /// Where the card would come to rest if it were let go now.
    static func projectedTranslation(_ translation: CGFloat, velocity: CGFloat) -> CGFloat {
        translation + velocity * velocityProjection
    }

    /// The dismissal threshold for a viewport.
    static func dismissDistance(viewportHeight: CGFloat) -> CGFloat {
        max(minimumDismissDistance, viewportHeight * dismissHeightFraction)
    }

    /// Should letting go here close the day?
    static func dismisses(
        translation: CGFloat,
        velocity: CGFloat,
        viewportHeight: CGFloat
    ) -> Bool {
        projectedTranslation(translation, velocity: velocity)
            > dismissDistance(viewportHeight: viewportHeight)
    }
}
