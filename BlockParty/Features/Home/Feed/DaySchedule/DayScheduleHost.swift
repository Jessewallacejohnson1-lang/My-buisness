//
//  DayScheduleHost.swift
//  Block Party — the day sheet, presented in the app's own hierarchy.
//
//  This is the replacement for `.sheet`, and the reason for it is one sentence:
//  `matchedGeometryEffect` does not cross a presentation boundary, so a rail card
//  and a timeline row can only morph into one another if they share a hierarchy.
//  See `DaySchedulePresentation` for the full note.
//
//  WHERE IT MOUNTS. On `MainTabsView`, not on the Today tab, because the custom tab
//  bar is a sibling of the tab content and would otherwise float on top of a
//  full-height sheet and cover its "Add to today" button. This is the same lane the
//  town menu's `GlassShowcaseOverlay` uses.
//
//  WHAT HAD TO BE HAND-BUILT, now that the system is not doing it:
//    * the `.large` resting detent and the 20pt top corner radius;
//    * drag-to-dismiss — rubber-banded translation, velocity-aware verdict
//      (`DayScheduleDrag`), attached to a grab strip along the card's top edge and
//      NOWHERE ELSE, because a gesture over the timeline would claim the touch on
//      press-down and kill the scroll (the CLAUDE.md rule that already shipped once
//      as "the feed only scrolls at the top");
//    * the modal accessibility container — `.isModal` plus hiding everything
//      behind it, which `.sheet` used to do for free and which is the easiest of
//      these to lose silently;
//    * the backdrop, which is the one item on the list that is BETTER hand-built:
//      the system dim is not configurable, and the spec asks for
//      `.ultraThinMaterial` under 35% black.
//
//  DISMISSAL REVERSES THE MORPH rather than fading: closing withdraws the sheet's
//  half of the matched pair in the same transaction that restores the rail's, so
//  the accent bar flies back down into the card it came out of.
//

import SwiftUI

struct DayScheduleHost<Content: View>: View {
    @ObservedObject var presentation: DaySchedulePresentation
    let namespace: Namespace.ID
    /// Injected only by previews and the demo; production shares one store for the
    /// whole session so a tick survives closing and re-opening the day.
    let completion: DayCompletionStore?
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The live drag translation. Zero at rest, positive downward.
    @State private var dragOffset: CGFloat = 0
    /// The card's own height, for the velocity-aware dismiss threshold.
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            content
                .environment(\.daySchedule, presentation)
                .environment(\.dayScheduleNamespace, namespace)
                // What `.sheet` used to do for free: everything behind a modal is
                // unreachable to VoiceOver, or the reader walks straight out of the
                // day and into the feed underneath it.
                .accessibilityHidden(presentation.isOpen)

            ZStack(alignment: .top) {
                if let request = presentation.request {
                    backdrop
                    card(request)
                }
            }
            // Belt AND braces, and the braces are load-bearing. Every entry point
            // already wraps the state change in `withAnimation`, and that is enough
            // for the OPEN — but measured frame by frame off a recording, the
            // CLOSE dropped its transition and the card vanished in a single frame
            // while the matched accent bar carried on flying home without it.
            // Binding the animation to `isOpen` here re-attaches it to the removal
            // regardless of which transaction the caller was in.
            .animation(motion, value: presentation.isOpen)
        }
    }

    private var motion: Animation {
        reduceMotion ? DayScheduleMotion.reduced : DayScheduleMotion.open
    }

    // MARK: - The backdrop

    /// `.ultraThinMaterial` under 35% black. The town stays legible through it —
    /// the day is over the neighbourhood, not instead of it.
    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(DayScheduleMetrics.backdropDim)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        // The × is the labelled way out; a scrim tap is a shortcut for pointers,
        // and announcing it would put a second "close" in front of a reader.
        .accessibilityHidden(true)
        .transition(.opacity)
    }

    // MARK: - The card

    private func card(_ request: DayScheduleRequest) -> some View {
        DayScheduleSheet(
            items: request.items,
            anchor: request.anchor,
            namespace: namespace,
            dates: request.dates,
            onDismiss: dismiss,
            completion: completion
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: DayScheduleMetrics.sheetCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: DayScheduleMetrics.sheetCornerRadius,
                style: .continuous
            )
        )
        .shadow(
            color: .black.opacity(DayScheduleMetrics.sheetShadowOpacity),
            radius: DayScheduleMetrics.sheetShadowRadius,
            x: 0,
            y: DayScheduleMetrics.sheetShadowY
        )
        .overlay(alignment: .top) { dragHandle }
        // The resting detent. Top-aligned inside the safe area is where a system
        // `.large` sheet sits; the card then runs off the bottom of the screen.
        .padding(.top, DayScheduleMetrics.restingTopInset)
        .ignoresSafeArea(.container, edges: .bottom)
        .offset(y: dragOffset)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        // Deliberately a cross-fade and NOT a slide. The accent bar's morph is the
        // motion here; a card sliding up underneath a bar flying into it gives the
        // eye two stories at once, and the bar loses.
        .transition(.opacity)
    }

    /// The only place on the card that answers a drag. Everything below it is the
    /// timeline's own scroll.
    private var dragHandle: some View {
        HStack(spacing: 0) {
            // The close button's 44pt target, left alone.
            Color.clear
                .frame(width: DayScheduleMetrics.dragHandleLeading)
                .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .gesture(drag)
        }
        .frame(height: DayScheduleMetrics.dragHandleHeight)
        .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragOffset = DayScheduleDrag.translation(
                    for: value.translation.height,
                    rubberBands: !reduceMotion
                )
            }
            .onEnded { value in
                let closes = DayScheduleDrag.dismisses(
                    translation: value.translation.height,
                    velocity: value.velocity.height,
                    viewportHeight: cardHeight
                )
                if closes {
                    dismiss()
                } else {
                    withAnimation(motion) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Leaving

    /// One exit for the ×, the scrim, and the drag. The offset returns to zero in
    /// the SAME transaction that withdraws the sheet, so a half-dragged card
    /// reverses its own morph instead of snapping first and fading second.
    private func dismiss() {
        withAnimation(motion) {
            dragOffset = 0
            presentation.close()
        }
    }
}

// MARK: - Mounting

extension View {
    /// Mount the day sheet's presentation lane on this view.
    ///
    /// Everything inside gains `\.daySchedule` and `\.dayScheduleNamespace`, which
    /// is how the Your Day rail — several views down, and with no other way to
    /// reach a presenter that has to live above the tab bar — opens the day and
    /// shares the namespace that makes the morph possible.
    func dayScheduleHost(
        _ presentation: DaySchedulePresentation,
        namespace: Namespace.ID,
        completion: DayCompletionStore? = nil
    ) -> some View {
        DayScheduleHost(
            presentation: presentation,
            namespace: namespace,
            completion: completion
        ) {
            self
        }
    }
}
