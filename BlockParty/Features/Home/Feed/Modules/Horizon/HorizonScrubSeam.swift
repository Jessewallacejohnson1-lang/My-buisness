//
//  HorizonScrubSeam.swift
//  BlockParty
//
//  The feed-level half of the horizon card's scrub interaction.
//
//  This file was `YourDayHorizonSection.swift`. The Your Day section it used to
//  hold went with the Today strip-down; what remains is the seam the card still
//  drives — the lifted-frame state it raises and the scrim that dims everything
//  around it. Nothing mounts the scrim while Today has no modules; it stays here
//  as the matching half of `HorizonCard.publishLift`, which is still live in the
//  `-horizon-card-gallery`.
//

import Combine
import SwiftUI

/// The feed-level half of the scrub interaction. The card raises it when a
/// scrub session begins (lifted frame + exit hook) and lowers it on exit; the
/// host above the card reads it for the scrim and the scroll lock, and the
/// scrim's tap calls back down through `exitTapped`. Only this enter/exit state
/// ever leaves the card's subtree — per-frame scrubTime stays put (the perf
/// gate's isolation rule).
@MainActor
final class HorizonScrubHost: ObservableObject {
    struct Lift: Equatable {
        /// Global-space frame of the LIFTED (scaled) card.
        let frame: CGRect
        let cornerRadius: CGFloat
    }

    @Published private(set) var lift: Lift?
    /// Deliberately not published — assigning the hook must not re-render
    /// the feed.
    private var onExitTap: (() -> Void)?

    func raise(_ lift: Lift, onExitTap: @escaping () -> Void) {
        if self.lift != lift { self.lift = lift }
        self.onExitTap = onExitTap
    }

    func lower() {
        guard lift != nil else { return }
        lift = nil
        onExitTap = nil
    }

    func exitTapped() { onExitTap?() }
}

extension EnvironmentValues {
    /// Injected by whatever screen mounts the horizon card. Nil in galleries and
    /// previews — the card still scrubs there, nothing above it dims or locks
    /// (the `\.daySchedule` nil-host pattern).
    @Entry var horizonScrub: HorizonScrubHost?
}

/// A light blur + black 25% over everything except the lifted card: ONE
/// even-odd shape whose cutout tracks the card's frame, so the card
/// itself never re-mounts — gesture continuity and the live TimelineView
/// clock come free (approved decision 5, mechanism i; blur added by
/// Jesse's mid-Phase-3 spec: the world outside the card softens while it
/// dims). The blur is `.ultraThinMaterial` — the lightest system
/// material, never a hand-rolled backdrop filter. A tap anywhere on the
/// dimmed region ends the scrub; taps inside the cutout fall through to
/// the live card beneath.
struct HorizonScrubScrim: View {
    let lift: HorizonScrubHost.Lift
    let onTap: () -> Void

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let cutout = lift.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            let shape = CutoutShape(cutout: cutout, radius: lift.cornerRadius)
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(HorizonMetrics.scrimOpacity)
            }
            .mask(shape.fill(style: FillStyle(eoFill: true)))
            .contentShape(shape, eoFill: true)
            .onTapGesture(perform: onTap)
        }
        // The scrim is a pointer shortcut, not the accessible way out (the
        // day-sheet backdrop's rule).
        .accessibilityHidden(true)
    }

    private struct CutoutShape: Shape {
        let cutout: CGRect
        let radius: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addRect(rect)
            path.addRoundedRect(
                in: cutout,
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous)
            return path
        }
    }
}
