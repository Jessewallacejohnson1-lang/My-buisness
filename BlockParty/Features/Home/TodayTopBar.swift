//
//  TodayTopBar.swift
//  Block Party — Today's fixed top bar: block glyph · town name · the one menu button.
//
//  Replaces `Masthead`, the 34pt wordmark + date line that used to scroll away with
//  the content. This bar is chrome: it is present immediately (no spring entrance),
//  it never scrolls, and it cross-fades a hairline in once the feed moves beneath
//  it. Today's date moved into the Almanac card as `TodayHeader.eyebrow`.
//
//  The menu button — the ⋮ affordance, the bounce, the dots leaving, the beat before
//  the drawer unfolds — is carried over from `Masthead` value for value. The one
//  addition is a Reduce Motion branch: the dots simply cross-fade (no scale, no blur,
//  no bounce) while the drawer hand-off keeps its identical timing, so the drawer
//  behaves the same either way.
//

import SwiftUI

/// The Today bar's pure, testable pieces: its geometry, the date eyebrow the Almanac
/// card prints, and the scroll threshold that raises the bar's hairline.
///
/// `nonisolated` because the constants are read from `nonisolated` contexts (and from
/// the test target) — the module defaults to MainActor isolation, so an isolated enum
/// here would trip the zero-warning bar. See the CLAUDE.md MainActor-default-argument
/// gotcha.
nonisolated enum TodayHeader {
    /// How far the content must travel before the bar grows its bottom hairline.
    static let scrollThreshold: CGFloat = 8
    /// The bar's content height, sitting below the safe-area top inset.
    static let contentHeight: CGFloat = 44
    /// The ceiling the bar never passes, even at the largest permitted Dynamic Type.
    static let maxHeight: CGFloat = 52

    /// Today's date as the Almanac's eyebrow — "SATURDAY, AUGUST 1".
    ///
    /// Formatted on the TOWN's clock, never the device's: a neighbor travelling east
    /// is still reading Saint Joseph's day, and at 23:30 Central a phone in Berlin has
    /// already rolled over to tomorrow. The `en_US` pin fixes the language and the US
    /// shape (the same pairing `UtilityFormat` uses); `d` — not `dd` — keeps a
    /// single-digit day unpadded.
    static func eyebrow(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date).uppercased(with: formatter.locale)
    }

    /// Whether the bar shows its bottom hairline at a given scroll position.
    ///
    /// `contentOffsetY` is the distance scrolled FROM REST: **positive = scrolled
    /// down, 0 = at rest, negative = rubber-banded past the top** (a pull to refresh).
    /// The comparison is therefore signed and strictly greater-than — comparing a
    /// magnitude would flash a hairline partway down every pull, and `>=` would raise
    /// it while the content is still flush against the bar.
    static func showsHairline(contentOffsetY: CGFloat) -> Bool {
        contentOffsetY > scrollThreshold
    }
}

/// The bar's fixed geometry, in one place. `nonisolated` for the same reason as
/// `TodayHeader`: these are constants, not state.
private nonisolated enum TodayBarMetric {
    /// Leading / trailing screen inset for both controls.
    static let inset: CGFloat = 16
    static let glyphSide: CGFloat = 28
    /// The menu button's circle — deliberately 38, not 36.
    static let buttonSide: CGFloat = 38
    static let dotSide: CGFloat = 4
    static let dotSpacing: CGFloat = 3
    /// Dots → button. Verbatim from `Masthead`.
    static let dotGap: CGFloat = 9
    /// Smallest breathing room between the title and either control.
    static let controlGap: CGFloat = 12
    static let titleSize: CGFloat = 17
    static let hairlineWidth: CGFloat = 0.5

    /// Full width of the trailing control (dots + gap + button).
    static let menuWidth: CGFloat = dotSide + dotGap + buttonSide

    /// Horizontal room reserved on BOTH sides of the title, so the name stays centered
    /// on screen while still truncating before it can reach either control.
    static let titleInset: CGFloat = inset + max(glyphSide, menuWidth) + controlGap
}

struct TodayTopBar: View {
    /// The one top-right button → the town menu drawer.
    var onMenu: (() -> Void)?
    /// Mirrors the drawer's presented state so the dots restore on close.
    var menuOpen: Bool = false
    /// Raised by Home once the feed has scrolled past `TodayHeader.scrollThreshold`.
    var showsHairline: Bool = false

    /// Tapped → dots gone (stays gone while the drawer is open).
    @State private var activated = false
    /// One-shot scale pulse on tap.
    @State private var bounce = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            title
            controls
        }
        // Clamped rather than fixed: 44 at rest, growing only as far as 52 if a large
        // Dynamic Type setting needs it. `fixedSize` hands the frame an unspecified
        // height so it resolves against the content instead of being stretched by the
        // enclosing VStack.
        .frame(maxWidth: .infinity,
               minHeight: TodayHeader.contentHeight,
               maxHeight: TodayHeader.maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        // The app canvas, carried up through the status bar. No fill, no material,
        // no shadow — the bar is not a separate surface.
        .background(Hue.paper.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { hairline }
        // Restore the dots when the drawer closes.
        .onChange(of: menuOpen) { _, open in
            if !open { withAnimation(.easeOut(duration: 0.28)) { activated = false } }
        }
        .onAppear(perform: debugAutoTap)
    }

    // MARK: - Layers

    /// The town name, on its own full-width layer so it is centered ON SCREEN rather
    /// than in the gap left between the two controls.
    ///
    /// The cap is applied HERE, to `BarTitle` as a whole, and not inside it. A
    /// `@ScaledMetric` resolves against the environment its view is handed, so a
    /// `.dynamicTypeSize` written further down — on the `Text` — would clamp a size
    /// that had already been computed at the app's full setting. Capping the child
    /// from outside is what actually stops the title growing.
    private var title: some View {
        BarTitle()
            // Scales up to accessibilityMedium and then holds — past that the name
            // would push the bar beyond `TodayHeader.maxHeight`. `.accessibility1` IS
            // accessibilityMedium: `DynamicTypeSize` numbers the five accessibility
            // steps, where `ContentSizeCategory` names them.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, TodayBarMetric.titleInset)
            .frame(maxWidth: .infinity)
    }

    /// The two controls, above the title layer.
    private var controls: some View {
        HStack(spacing: 0) {
            BlockPartyGlyph(side: TodayBarMetric.glyphSide)
                .accessibilityHidden(true)
            Spacer(minLength: TodayBarMetric.controlGap)
            menuButton
        }
        .padding(.horizontal, TodayBarMetric.inset)
    }

    /// A 0.5pt rule on the bar's bottom edge — hidden at rest, cross-faded in once
    /// there is content passing underneath.
    private var hairline: some View {
        Rectangle()
            .fill(Hue.hairline)
            .frame(height: TodayBarMetric.hairlineWidth)
            .opacity(showsHairline ? 1 : 0)
            .animation(.easeOut(duration: 0.20), value: showsHairline)
    }

    // MARK: - Menu button (⋮ dots + avatar-style circle)

    private var menuButton: some View {
        HStack(spacing: TodayBarMetric.dotGap) {
            // Vertical three dots — the "menu" affordance. Fades + shrinks toward the
            // button as it's tapped, then restores on close. Under Reduce Motion only
            // the fade survives.
            VStack(spacing: TodayBarMetric.dotSpacing) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Hue.inkSecondary)
                        .frame(width: TodayBarMetric.dotSide, height: TodayBarMetric.dotSide)
                }
            }
            .opacity(activated ? 0 : 1)
            .scaleEffect(reduceMotion ? 1 : (activated ? 0.4 : 1), anchor: .trailing)
            .blur(radius: reduceMotion ? 0 : (activated ? 1.5 : 0))
            // Decorative: the affordance is the button's label, not three unlabeled
            // circles landing in the VoiceOver order.
            .accessibilityHidden(true)

            Button(action: tap) {
                Image(systemName: "person")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Hue.ink)
                    .frame(width: TodayBarMetric.buttonSide, height: TodayBarMetric.buttonSide)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .scaleEffect(reduceMotion ? 1 : (bounce ? 1.12 : 1))
            .accessibilityLabel("Open town menu")
        }
    }

    /// The little reaction, then hand off to the drawer a beat later (matches the
    /// reference: the button bounces + the dots leave before the panel unfolds).
    ///
    /// The hand-off sits OUTSIDE the Reduce Motion branch on purpose — the drawer
    /// must open on the same beat whether or not the button animates.
    private func tap() {
        guard let onMenu else { return }
        let s = slowTap
        Haptics.light()
        if reduceMotion {
            // Reduce Motion: the dots simply cross-fade. No scale, no blur, no bounce.
            withAnimation(.easeOut(duration: 0.15 * s)) { activated = true }
        } else {
            withAnimation(.easeOut(duration: 0.18 * s)) { activated = true }
            withAnimation(.spring(response: 0.26 * s, dampingFraction: 0.42)) { bounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13 * s) {
                withAnimation(.spring(response: 0.34 * s, dampingFraction: 0.62)) { bounce = false }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * s) { onMenu() }
    }

    /// DEBUG-only: `-tap-menu` fires the button's tap ~1.2s after Home appears so
    /// the bounce + dots-leave + drawer hand-off can be recorded headlessly.
    private func debugAutoTap() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-tap-menu") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { tap() }
        #endif
    }

    /// DEBUG-only: `-slow-tap` stretches the tap reaction ~4× so it can be
    /// captured frame-by-frame. 1× (no-op) otherwise.
    private var slowTap: Double {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-slow-tap") ? 4 : 1
        #else
        return 1
        #endif
    }
}

/// The bar's centered town name.
///
/// A separate view purely so the Dynamic Type cap works. `@ScaledMetric` resolves
/// against the environment the view is CREATED with, so the cap has to be applied by
/// the parent (`TodayTopBar.title`) rather than to the `Text` inside — otherwise the
/// size is computed at the app's full setting and the clamp arrives too late, letting
/// the title keep growing past `TodayHeader.maxHeight`.
private struct BarTitle: View {
    /// The title's point size, scaled off the `.headline` ramp.
    ///
    /// `Font.sansSemibold(_:)` is a FIXED `.system(size:weight:)` — all of
    /// `BlockPartyFont` is fixed-point — so the title would otherwise ignore Dynamic
    /// Type entirely. This re-attaches it to the ramp while keeping the brand helper.
    /// 17 is `.headline`'s own size at the default setting, so the resting appearance
    /// is unchanged.
    @ScaledMetric(relativeTo: .headline) private var size = TodayBarMetric.titleSize

    var body: some View {
        Text(Town.name)
            .font(.sansSemibold(size))
            .foregroundStyle(Hue.ink)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
