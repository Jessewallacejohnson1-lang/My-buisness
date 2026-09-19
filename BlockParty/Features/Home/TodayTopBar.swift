//
//  TodayTopBar.swift
//  Block Party — Today's fixed top bar: one map button, nothing else.
//
//  Replaces `Masthead`, the 34pt wordmark + date line that used to scroll away with
//  the content. This bar is chrome: it is present immediately (no spring entrance),
//  it never scrolls, and it cross-fades a hairline in once the feed moves beneath
//  it.
//
//  The Joetown lockup was retired on 2026-09-17; the profile avatar — the ⋮-lineage
//  button that opened the town menu — was retired on 2026-09-18 (Jesse's call). What
//  is left is a single trailing control: a translucent yellow disc carrying the map
//  glyph, sitting where the avatar used to. The bar reports the tap; the shell owns
//  the map presentation.
//
//  NOTE: with the avatar gone, nothing in this bar opens `TownMenuView` any more.
//  The menu plumbing (`onMenu` / `showMenu` / `GlassShowcaseOverlay`) is still wired
//  through Home and RootView, so re-attaching it is a one-line change wherever its
//  next entry point lands.
//

import SwiftUI

/// The Today bar's pure, testable pieces: its geometry, the uppercase date eyebrow,
/// and the scroll threshold that raises the bar's hairline.
///
/// `nonisolated` because the constants are read from `nonisolated` contexts (and from
/// the test target) — the module defaults to MainActor isolation, so an isolated enum
/// here would trip the zero-warning bar. See the CLAUDE.md MainActor-default-argument
/// gotcha.
nonisolated enum TodayHeader {
    /// How far the content must travel before the bar grows its bottom hairline.
    static let scrollThreshold: CGFloat = 8
    /// The bar's content height, sitting below the safe-area top inset. Grown from
    /// 44 on 2026-09-18 to carry the larger map disc without pinning it against the
    /// status bar and the hairline at once.
    static let contentHeight: CGFloat = 58
    /// The ceiling the bar never passes, even at the largest permitted Dynamic Type.
    static let maxHeight: CGFloat = 66

    /// Today's date as an uppercase eyebrow — "SATURDAY, AUGUST 1".
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
    /// Trailing screen inset for the control row.
    static let inset: CGFloat = 16
    static let hairlineWidth: CGFloat = 0.5

    /// The map button's disc. It is the ONLY control in this bar, so it is sized
    /// like one: 50 clears the 44pt HIG target on its own, with no grow-and-hand-back
    /// padding, and reads as an object rather than as a small icon in a corner.
    static let mapSide: CGFloat = 50
    /// The glyph's square, inside the disc.
    static let mapGlyphSize: CGFloat = 24
}

struct TodayTopBar: View {
    /// The trailing map button → the town map. The shell owns the presentation;
    /// this bar only reports the tap.
    var onOpenMap: () -> Void = {}
    /// Raised by Home once the feed has scrolled past `TodayHeader.scrollThreshold`.
    var showsHairline: Bool = false

    var body: some View {
        controls
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
    }

    // MARK: - Layers

    /// The one trailing control. The leading side intentionally stays empty now that
    /// the bP glyph, the Joetown wordmark, and the profile avatar have all left this
    /// screen.
    private var controls: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            mapButton
        }
        .padding(.horizontal, TodayBarMetric.inset)
    }

    /// A TRUE circle, deliberately — the one exception to this system's 12pt rounded
    /// squares (Jesse's call, 2026-09-18). It inherits the round silhouette the
    /// avatar held in this corner, so the swap reads as a change of purpose rather
    /// than a change of layout.
    private static let mapShape = Circle()

    /// The glossy yellow map disc, top right — the bar's only control.
    ///
    /// The gloss is built in three layers over the glass, not faked with one white
    /// fill: a specular cap across the top third, a rim that is bright where the
    /// light lands and almost gone at the bottom, and two shadows (one tight and
    /// close for contact, one wide and soft for lift). That is what separates a
    /// glossy object from a flat tinted circle.
    private var mapButton: some View {
        let side = TodayBarMetric.mapSide
        return Button(action: onOpenMap) {
            ZStack {
                // Mostly flat, and genuinely see-through: a thin material with the
                // wash on top, not a shaded ball. The earlier version modelled a
                // sphere — specular, sub-equator shade, bounce light — and read as a
                // plastic badge stuck on the page. Glass in the reference is a
                // SURFACE: flat, transparent, with one soft sheen and a rim to catch
                // the edge. That is all that survives here.
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Hue.mapWash)
                sheen
                MapPinGlyph(size: TodayBarMetric.mapGlyphSize)
                    .foregroundStyle(Hue.ink)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(MapDiscPressStyle())
        // One soft, close shadow — enough to lift the disc off the paper, not enough
        // to make it hover.
        .shadow(color: .black.opacity(0.09), radius: 5, y: 2)
        .accessibilityLabel("Open the town map")
    }

    /// The only two light layers left: a faint sheen across the top third and a rim
    /// that is brighter where the light lands. Roughly 80% flat — enough curvature to
    /// read as glass, not enough to read as a ball.
    private var sheen: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.03), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.12), .white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        }
        .clipShape(Circle())
        .allowsHitTesting(false)
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
}

/// The map mark: a place pin, drawn as an OUTLINE with a solid centre.
///
/// Not the SF Symbol `map` — that glyph is a hard-cornered folded sheet, and a
/// rectangle inside a circle inside a rounded bar was three silhouettes fighting.
/// Not the solid teardrop either (Jesse, 2026-09-18): filled, the mark sat as a heavy
/// black blot on a pale disc. Outlined, it reads as a ring with a dot at the middle —
/// lighter on the yellow, and the shape people already know as "a place".
///
/// Geometry is specified in a 24-point box and scaled, so the mark keeps its
/// proportions and its stroke ratio at any size.
struct MapPinGlyph: View {
    var size: CGFloat = 24

    /// The design box every coordinate is expressed in.
    private static let box: CGFloat = 24
    /// Stroke weight in box units. Scaled with everything else, so the outline never
    /// goes spindly at 20pt or clubby at 40.
    private static let stroke: CGFloat = 2.1

    var body: some View {
        ZStack {
            MapPinShape()
                .stroke(style: StrokeStyle(lineWidth: Self.stroke, lineJoin: .round))
            // The centre. Solid, and sized against the outline rather than the box, so
            // the ring keeps its breathing room at every scale.
            Circle()
                .frame(width: 5.1, height: 5.1)
                .offset(y: -1.6)
        }
        .frame(width: Self.box, height: Self.box)
        .scaleEffect(size / Self.box)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The teardrop, built from cubics rather than arcs: an arc's sweep direction flips
/// with the coordinate system and is easy to get backwards, while four curves render
/// identically everywhere and can be tuned point by point.
struct MapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

        var path = Path()
        // Tip, up the left flank, over the crown, down the right flank, back to tip.
        path.move(to: pt(12, 21.2))
        path.addCurve(to: pt(5.6, 9.6), control1: pt(9.2, 17.3), control2: pt(5.6, 13.4))
        path.addCurve(to: pt(12, 3.2), control1: pt(5.6, 6.1), control2: pt(8.5, 3.2))
        path.addCurve(to: pt(18.4, 9.6), control1: pt(15.5, 3.2), control2: pt(18.4, 6.1))
        path.addCurve(to: pt(12, 21.2), control1: pt(18.4, 13.4), control2: pt(14.8, 17.3))
        path.closeSubpath()
        return path
    }
}

/// The disc's press reaction: a quick squash that springs back, with the gloss
/// riding along. No dim — the yellow is the button's identity and a grey flash
/// would read as the control failing rather than as a press.
private struct MapDiscPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.90 : 1))
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}
