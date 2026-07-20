//
//  ComposeSpeedDial.swift
//  Block Party — the compose "+" speed-dial.
//
//  Ported ~99% from a reference recording (a Jobber-style FAB that expands into a
//  right-aligned create-menu): tap the disc → the screen washes to near-paper and
//  recedes, the "+" rotates into a "✕", and a column of items (label + circular
//  icon) reveals; tapping the disc / backdrop snaps it shut.
//
//  Two things we add on top of the reference (see the spec:
//  docs/superpowers/specs/2026-07-12-compose-speed-dial-design.md):
//   • the items bubble in ONE AT A TIME, nearest-the-FAB first — a scale-up spring
//     with a small overshoot, ~85ms apart, super fast.
//   • each item does a little PUSH-IN on tap (PressableStyle) before it routes.
//
//  Hosted at MainTabsView (like the town-menu GlassShowcaseOverlay) so the wash + the
//  column float above the tab bar. All three surfaces anchor the "+" TOP-RIGHT and
//  drop the dial DOWN, nearest-item first. Two flavors:
//   • Explore / Calendar — a coral disc in the top-right corner (it IS the resting
//     compose FAB, replacing the old bottom ComposeFAB); its screen's own control
//     (search / info) tucks to its LEFT into a small cluster.
//   • Map — the native top-right chrome "+" triggers it; the dial is chrome-styled
//     to match the map's other floating controls.
//

import SwiftUI

// MARK: - Model

enum SpeedDialAnchor { case bottomTrailing, topTrailing }

/// What a bubble does when tapped.
enum SpeedDialAction {
    case compose(AddKind)   // jump straight into that form, skipping AddView's chooser
    case invite             // the app-invite share reveal
}

/// One bubble: a label + a circular icon. `primary` renders the coral-filled disc
/// (the lead item nearest the FAB — mirrors the reference's filled bottom item).
struct SpeedDialItem: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let primary: Bool
    let action: SpeedDialAction

    /// Context-tailored sets. Same create-kinds everywhere (Event/Club/Trail are our
    /// only postable things) + Invite. Every surface now drops the dial DOWN from a
    /// top-right "+", so all three are ordered primary-first — "Event" sits directly
    /// under the disc and leads the nearest-item-first cascade.
    static func calendar() -> [SpeedDialItem] { droppingFromTop() }
    static func explore()  -> [SpeedDialItem] { droppingFromTop() }
    static func map()      -> [SpeedDialItem] { droppingFromTop() }

    private static func droppingFromTop() -> [SpeedDialItem] {
        [ SpeedDialItem(title: "Event",             symbol: "calendar",          primary: true,  action: .compose(.event)),
          SpeedDialItem(title: "Club",              symbol: "person.2",          primary: false, action: .compose(.club)),
          SpeedDialItem(title: "Trail",             symbol: "figure.walk",       primary: false, action: .compose(.trail)),
          SpeedDialItem(title: "Invite a neighbor", symbol: "person.badge.plus", primary: false, action: .invite) ]
    }
}

// MARK: - View

struct ComposeSpeedDial: View {
    let items: [SpeedDialItem]
    /// Owned by the host (MainTabsView) so it can also recede the content behind.
    @Binding var isOpen: Bool
    var anchor: SpeedDialAnchor = .bottomTrailing
    /// Map uses the white 44pt chrome circle (matching its filter / recenter chrome);
    /// Explore/Calendar use the coral 54pt disc.
    var chromeDisc: Bool = false
    /// Explore/Calendar own their resting disc here; the Map's resting "+" is native
    /// (in SJMapView), so the overlay only draws the ✕ while open.
    var showsRestingDisc: Bool = true
    var onSelect: (SpeedDialItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Trailing space a top-anchored screen header reserves so its own control
    /// (Explore's search, Calendar's info) tucks to the LEFT of the pinned coral
    /// compose "+", forming a top-right cluster (mirrors the map's filter·pill·+).
    /// Added on top of a header's standard 18pt inset.
    static let topDiscHeaderClearance: CGFloat = 56

    private var isTop: Bool { anchor == .topTrailing }
    // Map "+" is 44pt white chrome; the coral compose disc is 48pt in the top-right
    // cluster (was a bulkier 54 when it stood alone at the bottom).
    private var discSize: CGFloat { chromeDisc ? 44 : (isTop ? 48 : 54) }
    private let iconSize: CGFloat = 44
    private var discTrailing: CGFloat { chromeDisc ? 16 : (isTop ? 16 : 20) }
    // Top-anchored discs sit in the top-right corner; the legacy bottom coral disc
    // cleared the floating tab bar.
    private var discEdge: CGFloat { isTop ? 8 : 96 }
    private var colTrailing: CGFloat { discTrailing + (discSize - iconSize) / 2 }
    private var colEdge: CGFloat { discEdge + discSize + 18 }      // clear the disc + a gap

    private var zAlignment: Alignment { isTop ? .topTrailing : .bottomTrailing }
    private var entranceAnchor: UnitPoint { isTop ? .topTrailing : .bottomTrailing }
    private var entranceRise: CGFloat { isTop ? -14 : 14 }

    var body: some View {
        ZStack(alignment: zAlignment) {
            // The screen washes to near-paper (the content recedes behind, scaled by
            // the host). Faintly translucent so a ghost shows through, like the
            // reference. Tap anywhere off the menu to close.
            if isOpen {
                Hue.canvas.opacity(0.92)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
            }

            // The bubble column, right-aligned, stacked away from the disc.
            VStack(alignment: .trailing, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    itemRow(item, index: idx)
                }
            }
            .padding(.trailing, colTrailing)
            .padding(isTop ? .top : .bottom, colEdge)
            .allowsHitTesting(isOpen)

            // Always in the tree so the + ↔ ✕ rotation persists and animates. On the
            // Map (no resting disc) it stays hidden + non-interactive until open, so
            // the native "+" underneath handles the tap, then the ✕ fades/rotates in.
            disc
                .opacity(discVisible ? 1 : 0)
                .allowsHitTesting(discVisible)
                .padding(.trailing, discTrailing)
                .padding(isTop ? .top : .bottom, discEdge)
        }
        // Pin to the anchor corner of the full screen. Without this the ZStack hugs
        // its content and only lands correctly while the full-bleed wash is present
        // (open); at rest (no wash) it would center-float. The frame has no background,
        // so its empty area stays tap-through to the screen beneath.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: zAlignment)
    }

    private var discVisible: Bool { showsRestingDisc || isOpen }

    // MARK: Bubble

    @ViewBuilder
    private func itemRow(_ item: SpeedDialItem, index: Int) -> some View {
        // Nearest-the-disc first. Bottom-anchored → last item is nearest; top-anchored
        // → first item is nearest. ~85ms apart makes each bubble a distinct beat while
        // the whole thing still lands in ~0.5s.
        let order = isTop ? index : (items.count - 1 - index)
        let delay = Double(order) * 0.085
        let anim: Animation = reduceMotion
            ? .easeInOut(duration: 0.18)
            : (isOpen
               ? .spring(response: 0.34, dampingFraction: 0.52).delay(delay)   // bubble: pronounced pop
               : .spring(response: 0.20, dampingFraction: 0.90))               // close: fast, no delay

        Button {
            select(item)
        } label: {
            HStack(spacing: 14) {
                Text(item.title)
                    .font(.sansMedium(16))
                    .foregroundStyle(Hue.ink)
                iconCircle(item)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.90, haptic: true))   // the push-in
        // The entrance: each bubble pops out of the FAB corner (scaling from small,
        // travelling toward its slot), fading in.
        .opacity(isOpen ? 1 : 0)
        .scaleEffect(isOpen ? 1 : 0.25, anchor: entranceAnchor)
        .offset(y: isOpen ? 0 : entranceRise)
        .animation(anim, value: isOpen)
    }

    private func iconCircle(_ item: SpeedDialItem) -> some View {
        Image(systemName: item.symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(item.primary ? .white : Hue.accent)
            .frame(width: iconSize, height: iconSize)
            .background(item.primary ? Hue.accent : Hue.accentSoft, in: Circle())
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    // MARK: Disc (the + ↔ ✕ toggle)

    @ViewBuilder
    private var disc: some View {
        Button {
            isOpen ? close() : open()
        } label: {
            if chromeDisc {
                // Matches the map's chrome circles (white, hairline, ink glyph).
                Circle()
                    .fill(Hue.surface)
                    .frame(width: discSize, height: discSize)
                    .overlay(Circle().stroke(Hue.mapHairline, lineWidth: 1))
                    .mapFloatShadow()
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Hue.mapInk)
                            .rotationEffect(.degrees(isOpen ? 135 : 0))
                    )
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(isOpen ? 135 : 0))
                    .frame(width: discSize, height: discSize)
                    .background(Hue.accent, in: Circle())
                    .shadow(color: Hue.accent.opacity(0.35), radius: 10, x: 0, y: 5)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.90, haptic: true))
        .accessibilityLabel(isOpen ? "Close" : "Add to the town")
    }

    // MARK: Actions

    private func open() {
        withAnimation(reduceMotion
            ? .easeOut(duration: 0.20)
            : .spring(response: 0.34, dampingFraction: 0.72)) {
            isOpen = true
        }
    }

    private func close() {
        withAnimation(reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.26, dampingFraction: 0.92)) {
            isOpen = false
        }
    }

    /// Push-in plays on press (via PressableStyle); we collapse, then route once the
    /// snap has started so the sheet doesn't yank in over an open menu.
    private func select(_ item: SpeedDialItem) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { onSelect(item) }
    }
}
