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
                // NOT `.glassEffect`. Measured, twice: a Liquid Glass surface pulls
                // what sits near it into its own layer, so the highlight flattened to
                // a 2/255 difference and the pin came back refracted into a ghost.
                // Glass is the right material for a bar or a sheet, where the point is
                // what shows THROUGH; this control's point is the gloss ON it, which
                // needs ordinary compositing to survive.
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Hue.mapWash)
                gloss
                MapPinGlyph(size: TodayBarMetric.mapGlyphSize)
                    .foregroundStyle(Hue.ink)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(MapDiscPressStyle())
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.16), radius: 11, y: 6)
        .accessibilityLabel("Open the town map")
    }

    /// Sheen, shade, specular, crescent, bounce light, rim — the six layers that turn
    /// a flat tinted circle into something that looks wet. All clipped to the disc, so
    /// the button keeps one silhouette however bright the highlight runs.
    private var gloss: some View {
        let side = TodayBarMetric.mapSide
        return ZStack {
            // The sheen: the whole upper half lifted, falling off before the middle.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.38), .white.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            // The shade under the equator. THIS is what makes the disc read as a ball
            // rather than a flat circle with a white smudge on it: a surface is convex
            // because its value ramps top to bottom, and a specular only lands as a
            // highlight if there is something darker for it to be brighter THAN.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Hue.ink.opacity(0.16)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
            // The specular hit, up and left of centre.
            Ellipse()
                .fill(.white.opacity(0.8))
                .frame(width: side * 0.42, height: side * 0.17)
                .blur(radius: side * 0.028)
                .offset(x: -side * 0.08, y: -side * 0.25)
            // The crescent just inside the top-left rim — the second half of a glass
            // highlight, where the surface curves away from the light.
            Circle()
                .inset(by: 1.5)
                .trim(from: 0.56, to: 0.88)
                .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .blur(radius: 0.7)
            // Bounce light along the bottom rim. Without it a glossy ball reads as a dome.
            Ellipse()
                .fill(.white.opacity(0.34))
                .frame(width: side * 0.46, height: side * 0.16)
                .blur(radius: side * 0.075)
                .offset(y: side * 0.31)
            // Rim light: bright where the light lands, almost gone underneath.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.9), .white.opacity(0.2), .white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
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

/// The map mark: a place pin, drawn.
///
/// Not the SF Symbol `map`. That glyph is a hard-cornered folded sheet, and inside a
/// circle inside a rounded bar it read as three silhouettes fighting — a rectangle
/// where every other edge is a curve. A pin is all curve, it is the one mark every
/// map app has trained people to read, and it says "a place in town" rather than
/// "a document". Geometry is specified in a 24-point box and scaled, so the mark
/// keeps its proportions at any size.
///
/// The head is cut out rather than drawn as a separate ring: one even-odd filled
/// path means the hole is always concentric and can never drift from the shell at a
/// fractional scale.
struct MapPinGlyph: View {
    var size: CGFloat = 24

    /// The design box every coordinate is expressed in.
    private static let box: CGFloat = 24

    var body: some View {
        MapPinShape()
            .fill(style: FillStyle(eoFill: true))
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
        path.move(to: pt(12, 21.8))
        path.addCurve(to: pt(5.4, 9.4), control1: pt(9.1, 17.6), control2: pt(5.4, 13.4))
        path.addCurve(to: pt(12, 2.8), control1: pt(5.4, 5.8), control2: pt(8.3, 2.8))
        path.addCurve(to: pt(18.6, 9.4), control1: pt(15.7, 2.8), control2: pt(18.6, 5.8))
        path.addCurve(to: pt(12, 21.8), control1: pt(18.6, 13.4), control2: pt(14.9, 17.6))
        path.closeSubpath()

        // The hole. Even-odd, so this subpath subtracts from the shell above.
        path.addEllipse(in: CGRect(x: 9.3 * s, y: 6.7 * s, width: 5.4 * s, height: 5.4 * s))
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
