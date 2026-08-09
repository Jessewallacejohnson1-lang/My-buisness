//
//  UtilityTileView.swift
//  Block Party — one Utility Row tile. Structural clone of the Calendar bento box
//  (`Radius.bento` continuous corners, gradient, soft shadow) that tap-EXPANDS in
//  place (compact ⇄ expanded, same spring as the bento). Renders generically from a
//  descriptor + state — no per-tile code, so a future tile needs none here.
//
//  The tile is a `Button`, NOT a tap gesture. A card-level gesture claims the touch
//  on press-DOWN and out-competes the enclosing ScrollView's pan; this tile sits in a
//  horizontal scroll inside the vertical page scroll, so that mistake costs two pans
//  (it shipped once in FeedEventCard — see CLAUDE.md). Press feedback therefore comes
//  from a ButtonStyle's `isPressed`, which composes with scrolling instead of
//  fighting it.
//

import SwiftUI

enum UtilityTileMetrics {
    static let width: CGFloat = 148          // fixed scroll-tile width (spec); height/radius/fonts match the bento
    static let gap: CGFloat = 10
    static let compactH: CGFloat = 92        // == bento compact height
    static let expandedH: CGFloat = compactH * 2 + gap

    /// The bento corner, read from the shared token rather than restated. The tile
    /// and the Calendar bento are one object at two sizes; a "deliberate match"
    /// comment can't fail a build when one of them moves, and `Radius.bento` can.
    static let corner: CGFloat = Radius.bento

    /// Opacity for EVERY white text layer on a tile — one constant so the whole
    /// row can be checked (and kept) at WCAG 4.5:1 in one place. 1.0: the gradient
    /// tokens were tuned for OPAQUE white and clear 4.76–10.20:1 there, while
    /// dimming to 0.9 / 0.8 measured 3.64–4.24:1 and failed. Hierarchy is carried
    /// by the size/weight ladder (13pt semibold label · 28pt bold value · 12pt
    /// secondary), never by alpha.
    static let textOpacity: Double = 1.0

    // MARK: - Watermark

    /// The oversized glyph behind a tile's content is INK, and that is a contrast
    /// decision rather than a taste one. Ink DARKENS the gradient it sits on, so
    /// white text over the watermarked pixels gets MORE contrast (4.76–14.22:1
    /// becomes 5.50–14.74:1). White at the same alpha lightens it and drops the
    /// purple library stop to 4.03:1 — a fail. See `UtilityTileVisualTests`.
    static let watermarkAlpha: Double = 0.10

    /// One oversized glyph, not a second icon: 72pt inside a 148×92 tile reads as
    /// texture next to the 13pt label glyph.
    static let watermarkSize: CGFloat = 72

    /// `Hue.ink` #111111 — the same number the contrast math composites, so the
    /// measured surface and the painted one cannot drift.
    static let watermarkColorHex: UInt32 = UtilityContrast.inkHex

    /// How far the glyph hangs past the bottom-trailing corner before the tile's
    /// rounded rect clips it. It bleeds off the box; it does not sit parked in it.
    static let watermarkBleed: CGFloat = 14

    // MARK: - Loading

    /// Gradient opacity while a tile is loading. **1.0 replaced 0.4**: dimming
    /// blended the gradient toward `Hue.paper` while the tile's label stayed fully
    /// opaque on top of it, which measured 1.75–1.82:1 — the worst contrast the row
    /// has ever shipped. The loading tile now keeps its gradient at full strength
    /// and says "loading" with the shimmering value block alone.
    static let loadingGradientOpacity: Double = 1.0

    // MARK: - Motion

    /// Finger-down scale. Small enough to read as pressure, not as a shrink.
    static let pressScale: CGFloat = 0.97

    /// Compact ⇄ expanded cross-fade: the arriving layer waits `contentFadeInDelay`
    /// and then eases in over `contentFadeIn`, while the leaving layer goes over the
    /// shorter `contentFadeOut` with no delay — so the box is never showing two
    /// full-strength layers at once.
    static let contentFadeIn: Double = 0.18
    static let contentFadeInDelay: Double = 0.06
    static let contentFadeOut: Double = 0.12

    /// How far the expanded content rises while it fades in.
    static let contentRise: CGFloat = 8

    /// A value changing under a tile that is already on screen (weather ticking over).
    static let valueFade: Double = 0.20

    /// The Reduce Motion substitute for every animation on this row: one flat
    /// opacity cross-fade. No scale, no offset, no stagger, no spring.
    static let reduceMotionFade: Animation = .easeInOut(duration: 0.15)
}

/// Press feedback for a bento tile — the scale lives here (and only here) because a
/// ButtonStyle's `isPressed` yields to the enclosing ScrollView's pan, where a
/// card-level gesture would steal it.
struct UtilityTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressedScale(configuration: configuration)
    }

    /// A real `View`, not `makeBody`'s result directly: a `ButtonStyle` is not a
    /// `View`, so `@Environment` read on the style itself is never injected.
    private struct PressedScale: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(scale)
                .animation(reduceMotion ? UtilityTileMetrics.reduceMotionFade : Motion.tilePress,
                           value: configuration.isPressed)
        }

        /// Reduce Motion drops the scale entirely — press stops being a movement.
        private var scale: CGFloat {
            guard !reduceMotion, configuration.isPressed else { return 1 }
            return UtilityTileMetrics.pressScale
        }
    }
}

struct UtilityTileView: View {
    let descriptor: UtilityTileDescriptor
    let state: UtilityTileState
    let isExpanded: Bool
    let staleAfter: TimeInterval?
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: tap) { surface }
            .buttonStyle(UtilityTilePressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(a11yLabel)
            .accessibilityHint(expandHint)
    }

    /// Tap only does something when there is something to show. A `.loading` /
    /// `.failed` tile — and roads on an all-clear day — has no expanded rows, so
    /// toggling would grow the box 92 → 194 for a label, a divider and empty space.
    /// Swallowing it HERE (rather than rendering an empty expansion) also keeps
    /// `UtilityRowModel.toggleExpand`'s expand haptic from firing on a no-op.
    private func tap() {
        guard isTappable else { return }
        onTap()
    }

    /// The tile itself — everything inside the button's label.
    private var surface: some View {
        let height = isExpanded ? UtilityTileMetrics.expandedH : UtilityTileMetrics.compactH
        return ZStack {
            // Frame EACH content to the tile size (like the bento) so the taller
            // expanded content can't inflate the ZStack and shift the compact
            // content out of the clip.
            //
            // The `.frame` sits OUTSIDE `.animation(_:value:)` on purpose: that
            // modifier scopes every animatable change BELOW it, so a frame inside it
            // would resize each layer on the cross-fade curve (0.12 / 0.18+0.06)
            // while the ZStack's own frame rides the ambient `Motion.bentoExpand`
            // spring (0.44s) from UtilityRowView. The layers are centred, so that
            // mismatch slides the content ~44pt as it fades. Only opacity — and the
            // expanded layer's rise — belong on the cross-fade; height stays on the
            // spring, in step with the box.
            compactContent
                .opacity(isExpanded ? 0 : 1)
                .animation(crossFade(incoming: !isExpanded), value: isExpanded)
                .frame(width: UtilityTileMetrics.width, height: height)
            expandedContent
                .opacity(isExpanded ? 1 : 0)
                .offset(y: expandedRise)
                .animation(crossFade(incoming: isExpanded), value: isExpanded)
                .frame(width: UtilityTileMetrics.width, height: height)
        }
        .frame(width: UtilityTileMetrics.width, height: height)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: UtilityTileMetrics.corner, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)   // == insightsCardShadow
        .contentShape(RoundedRectangle(cornerRadius: UtilityTileMetrics.corner, style: .continuous))
    }

    // MARK: - Background (gradient + ink watermark)

    /// Gradient with the ink watermark on top of it and the content on top of both.
    /// Lives in `.background` so an oversized glyph can never move the layout, and
    /// the tile's `clipShape` (applied above) is what bleeds it off the corner.
    private var tileBackground: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(isLoading ? UtilityTileMetrics.loadingGradientOpacity : 1)
            watermark
        }
    }

    /// The tile's own glyph at 72pt, inked at 10% and bled off the bottom-trailing
    /// corner. Decorative: hidden from VoiceOver and untouchable, so it can't take a
    /// tap away from the button. Uses `descriptor.symbol` — the FIXED tile glyph, not
    /// the provider's live one, so the texture doesn't shuffle when a value changes.
    private var watermark: some View {
        Image(systemName: descriptor.symbol)
            .font(.system(size: UtilityTileMetrics.watermarkSize))
            // Painted THROUGH `watermarkColorHex`, not from `Hue.ink` directly: the
            // constant's promise (the measured surface and the painted one cannot
            // drift) is only true if the render actually reads it.
            .foregroundStyle(Color(hex: UtilityTileMetrics.watermarkColorHex))
            .opacity(UtilityTileMetrics.watermarkAlpha)
            .offset(x: UtilityTileMetrics.watermarkBleed, y: UtilityTileMetrics.watermarkBleed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Compact

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            labelRow
                .layoutPriority(1)   // guard: the label always claims its height
            Spacer(minLength: 2)
            valueView
            if let secondary = displaySecondary {
                Text(secondary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(UtilityTileMetrics.textOpacity))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)   // …so does the secondary — never squeezed out
                    .contentTransition(.opacity)
                    .animation(valueChange, value: secondary)
            }
        }
        // Width-only fill + leading (matches the bento, which uses no maxHeight —
        // the tile's fixed frame + the Spacer distribute the height).
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder private var valueView: some View {
        switch state {
        case .loading:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.35))
                .frame(width: 84, height: 26)
                .shimmering()
        case .failed:
            Text("—").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
        case .loaded(let value):
            Text(value.content.primary)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(valueTransition(for: value.content.primary))
                .animation(valueChange, value: value.content.primary)
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            labelRow
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            ForEach(content?.expanded ?? []) { row in
                HStack(spacing: 6) {
                    if let symbol = row.symbol {
                        Image(systemName: symbol).font(.system(size: 11)).frame(width: 15)
                    }
                    Text(row.label)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(UtilityTileMetrics.textOpacity))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.value)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        // The row glyphs carry no style of their own; white here keeps them on the
        // gradient's text ladder instead of inheriting the button's tint.
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    // MARK: - Shared

    private var labelRow: some View {
        HStack(spacing: 5) {
            if let symbol = symbolName {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            }
            Text(descriptor.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if content?.badge == .warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(UtilityTileMetrics.textOpacity))
    }

    // MARK: - Motion

    /// The compact ⇄ expanded swap. The tile GROWS in place (92 → 194 with the
    /// content cross-faded), so there is deliberately no `matchedGeometryEffect`
    /// here — nothing moves between containers for it to match.
    private func crossFade(incoming: Bool) -> Animation {
        guard !reduceMotion else { return UtilityTileMetrics.reduceMotionFade }
        return incoming
            ? .easeOut(duration: UtilityTileMetrics.contentFadeIn)
                .delay(UtilityTileMetrics.contentFadeInDelay)
            : .easeOut(duration: UtilityTileMetrics.contentFadeOut)
    }

    /// Expanded content starts below its resting place and rises as it fades in.
    /// Reduce Motion removes the travel and leaves the fade.
    private var expandedRise: CGFloat {
        guard !reduceMotion, !isExpanded else { return 0 }
        return UtilityTileMetrics.contentRise
    }

    private var valueChange: Animation {
        reduceMotion ? UtilityTileMetrics.reduceMotionFade
                     : .easeInOut(duration: UtilityTileMetrics.valueFade)
    }

    /// A numeric value ROLLS; everything else cross-fades. The weather temperature is
    /// the live numeric case — an odometer roll on "Open" → "Closed" would read as a
    /// glitch, and Reduce Motion turns the roll off entirely.
    private func valueTransition(for primary: String) -> ContentTransition {
        guard !reduceMotion, primary.first?.isNumber == true else { return .opacity }
        return .numericText()
    }

    // MARK: - Derived

    private var content: UtilityTileContent? {
        if case let .loaded(value) = state { return value.content }
        return nil
    }

    private var isLoading: Bool { if case .loading = state { return true }; return false }

    /// Is there anything BEHIND the tap? `expandedContent` renders
    /// `content?.expanded`, so with no rows the expansion is a label, a divider and
    /// empty space — the box must not grow for that.
    private var isExpandable: Bool { !(content?.expanded.isEmpty ?? true) }

    /// `isExpandable` OR already open: a live tile can lose its rows while expanded
    /// (roads' last notice clears under an open tile), and a tile the user cannot
    /// collapse is worse than one that never opened.
    private var isTappable: Bool { isExpandable || isExpanded }

    /// Empty string = no hint, which is the honest answer for a tile that does not
    /// respond to a tap. A `nil`-vs-value branch on the modifier itself would change
    /// the button's view identity every time a provider's rows appear or clear, which
    /// resets the press state and the cross-fade mid-flight.
    private var expandHint: String {
        guard isTappable else { return "" }
        return isExpanded ? "Collapse" : "Expand for detail"
    }

    private var symbolName: String? { content?.symbol ?? descriptor.symbol }

    private var colors: [Color] { gradientStops.map { Color(hex: $0) } }

    /// The gradient this tile paints, in precedence order:
    /// muted (the provider is reporting an ABSENCE) → the provider's per-value
    /// override → the registry's static token.
    ///
    /// Muted outranks a per-value override deliberately: "nothing to report" is a
    /// statement about the whole tile, so a provider that computes a colour AND
    /// reports an absence still renders calm. Without this branch `isMuted` is
    /// produced and never rendered, and roads on an all-clear day paints the same
    /// full-strength amber as a live warning.
    private var gradientStops: [UInt32] {
        if content?.isMuted == true { return UtilityTileGradient.muted }
        return content?.gradientHex ?? descriptor.gradient
    }

    /// The secondary line, or a ">Nd ago" note when a live tile's value is stale.
    private var displaySecondary: String? {
        guard case let .loaded(value) = state else { return nil }
        if let staleAfter, Date().timeIntervalSince(value.updatedAt) > staleAfter {
            return "Updated \(UtilityFormat.relative(value.updatedAt))"
        }
        return value.content.secondary
    }

    private var a11yLabel: String {
        var parts = [descriptor.displayName]
        switch state {
        case .loading: parts.append("loading")
        case .failed:  parts.append("unavailable")
        case .loaded(let value):
            parts.append(value.content.primary)
            if value.content.badge == .warning { parts.append("alert") }
            if let secondary = displaySecondary { parts.append(secondary) }
            if isExpanded {
                for row in value.content.expanded { parts.append("\(row.label): \(row.value)") }
            }
        }
        return parts.joined(separator: ", ")
    }
}
