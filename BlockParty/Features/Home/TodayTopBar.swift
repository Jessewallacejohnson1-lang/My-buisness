//
//  TodayTopBar.swift
//  Block Party — Today's fixed top bar: one map button, nothing else.
//
//  Replaces `Masthead`, the 34pt wordmark + date line that used to scroll away with
//  the content. This bar is chrome: it is present immediately (no spring entrance),
//  it never scrolls, and it carries no rule of its own — the scroll edge effect
//  under it is what separates the bar from the feed.
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

/// The Today bar's pure, testable pieces: its geometry and the uppercase date
/// eyebrow.
///
/// `nonisolated` because the constants are read from `nonisolated` contexts (and from
/// the test target) — the module defaults to MainActor isolation, so an isolated enum
/// here would trip the zero-warning bar. See the CLAUDE.md MainActor-default-argument
/// gotcha.
nonisolated enum TodayHeader {
    /// The bar's height, below the safe-area top inset. **Constant, and it must
    /// stay constant** — see the note on `chromeProgress`.
    static let contentHeight: CGFloat = 58
    /// How far the feed travels before the wordmark and the map disc are fully gone.
    /// Short on purpose: this chrome belongs to the top of the feed, and the first
    /// card should own the screen as soon as you commit to scrolling.
    static let chromeFadeDistance: CGFloat = 44

    /// How far out of the way the bar's chrome is: 0 at rest, 1 once it has gone.
    ///
    /// Clamped at both ends, so a rubber-band pull past the top (negative offset)
    /// cannot over-brighten the chrome and a long scroll cannot drive it past gone.
    ///
    /// **Nothing that changes the bar's HEIGHT may be derived from this.** The bar
    /// is a `safeAreaBar` on the feed's own scroll, so its height IS that scroll's
    /// top content inset, and the offset this is computed from is measured against
    /// that inset. Height-from-progress therefore closes a loop: height → inset →
    /// offset → progress → height. It does not degrade gracefully; it rings.
    ///
    /// It shipped that way for one commit (d1fcf40) and the feed would not scroll at
    /// all — measured with `-feed-scroll-sweep -scroll-log`, the offset ping-ponged
    /// between -0.1 and 1.0 with 1420 direction reversals in 1422 samples. Pinning
    /// the height took the same trace to 241 samples, 0 reversals, a clean 0 → 200.
    /// Fade, lift, dim, blur — all fine. Height, insets and content size are not.
    static func chromeProgress(contentOffsetY: CGFloat) -> Double {
        let travelled = min(max(contentOffsetY, 0), chromeFadeDistance)
        return Double(travelled / chromeFadeDistance)
    }


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
}

/// The bar's fixed geometry, in one place. `nonisolated` for the same reason as
/// `TodayHeader`: these are constants, not state.
private nonisolated enum TodayBarMetric {
    /// Trailing screen inset for the control row.
    static let inset: CGFloat = 16
    /// The map button's disc. It is the ONLY control in this bar, so it is sized
    /// like one: 50 clears the 44pt HIG target on its own, with no grow-and-hand-back
    /// padding, and reads as an object rather than as a small icon in a corner.
    static let mapSide: CGFloat = 50
    /// The glyph's square, inside the disc.
    static let mapGlyphSize: CGFloat = 24
    /// The centred wordmark's height. 31 runs the lockup 151pt wide — 18 → 24 → 31
    /// over three passes on 2026-09-19, Jesse each time. It still clears the 50pt
    /// disc beside it, with the bar's 58pt content height as the hard ceiling.
    static let wordmarkHeight: CGFloat = 31
}

struct TodayTopBar: View {
    /// The trailing map button → the town map. The shell owns the presentation;
    /// this bar only reports the tap.
    var onOpenMap: () -> Void = {}
    /// 0 at the top of the feed, 1 once the chrome has scrolled away. Drives the
    /// fade and the small lift together, off one number, so they cannot disagree
    /// mid-scroll. It never touches the bar's height.
    var chromeProgress: Double = 0

    var body: some View {
        controls
            // The chrome leaves by fading and lifting slightly — the feed is arriving
            // from below, so the header stepping up out of its way reads as one
            // movement rather than two.
            .opacity(1 - chromeProgress)
            .offset(y: -8 * chromeProgress)
        // FIXED height. The bar used to collapse to an 8pt strip as the chrome left,
        // which was fine while it lived above the scroll — as a `safeAreaBar` it is
        // the scroll's top inset, and a height that follows the scroll offset makes
        // the offset follow the height right back. See `TodayHeader.chromeProgress`.
        .frame(height: TodayHeader.contentHeight)
        .frame(maxWidth: .infinity)
        // Clipped so the lifting chrome is cut off at the bar's edge rather than
        // spilling over the first card.
        .clipped()
        // NO fill. The bar is a safe-area inset over the feed's own scroll, so what
        // sits behind it is the content itself, blurred and washed toward the page by
        // the scroll edge effect (`scrollEdgeEffectStyle(.soft)` in `FeedView`). A
        // paper fill here is exactly the white lid Jesse asked to be rid of.
    }

    // MARK: - Layers

    /// The mark centred, the map disc trailing — the shape Instagram's feed header
    /// has trained everyone to read. Both belong to the top of the feed and both
    /// leave together.
    ///
    /// The mark is CENTRED against the bar, not laid out between the other controls:
    /// in an `HStack` it would sit wherever the trailing button's width left it, and
    /// drift every time that button changed size. A centred overlay is fixed to the
    /// screen's midline, which is where the eye looks for a logo.
    ///
    /// It is the real artwork (`BlockPartyWordmark` → the `Wordmark` raster), not the
    /// Jost wordmark it replaced (Jesse, 2026-09-19).
    private var controls: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            mapButton
        }
        .padding(.horizontal, TodayBarMetric.inset)
        .overlay {
            brandMark
                .accessibilityAddTraits(.isHeader)
                // Decorative-adjacent: it names the app, it does not act, so it must
                // not sit in the tap path of the disc beside it.
                .allowsHitTesting(false)
        }
    }

    /// The logo's letterforms on the page, in ink, with no tile behind them.
    ///
    /// The square tile that used to sit here was a workaround: the painted icon had
    /// no alpha, so an unclipped mark drew its own warmer paper as a visible square.
    /// The Sep 19 logo is flat two-colour art, so `wordmark.py` could resolve the
    /// yellow field into alpha and the lockup now sits directly on the bar.
    private var brandMark: some View {
        BlockPartyWordmark(height: TodayBarMetric.wordmarkHeight)
            .foregroundStyle(Hue.ink)
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
}

/// The map mark: a place pin, drawn as an OUTLINE with a ring at its centre.
///
/// Not the SF Symbol `map` — that glyph is a hard-cornered folded sheet, and a
/// rectangle inside a circle inside a rounded bar was three silhouettes fighting.
/// Not the solid teardrop either (Jesse, 2026-09-18): filled, the mark sat as a heavy
/// black blot on a pale disc. Outlined, it is lighter on the yellow and still the
/// shape people already know as "a place".
///
/// Proportions live in `MapPinShape`, in head radii, so the mark keeps its shape and
/// its stroke ratio at any size.
struct MapPinGlyph: View {
    var size: CGFloat = 24

    var body: some View {
        MapPinShape()
            .stroke(style: StrokeStyle(
                lineWidth: size * MapPinShape.strokeFraction,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The location pin, traced 1:1 off the reference Jesse supplied (2026-09-19): a
/// nearly round head that tapers to a soft point, with a concentric ring inside.
///
/// Every proportion here was MEASURED off that reference rather than eyeballed —
/// its glyph is 32 × 35 px with a 3 px stroke, which gives a centreline head radius
/// of 14.5, a tip 17 px below the head's centre (1.172 r), and an inner ring at 5.5
/// (0.379 r).
///
/// The flanks are CURVES, not tangent lines. The first attempt ran straight lines
/// from the tip to where they touch the head, which is the geometrically obvious
/// pin — and it came out visibly pointier than the reference, because the reference
/// (like Lucide's `map-pin`, the same family of drawing) carries the head's fullness
/// most of the way down before turning in. Measured against the reference's own
/// silhouette, the straight version was ~2 px narrow at 90% of the way down.
///
/// Both the outline and the ring are subpaths of ONE shape, so a single stroke
/// renders them at identical weight — which is what the reference does.
struct MapPinShape: Shape {
    /// Tip depth below the head's centre, in head radii.
    private static let tipDistance: CGFloat = 1.172
    /// Stroke weight, in head radii.
    private static let stroke: CGFloat = 0.207
    /// The inner ring's radius, in head radii.
    private static let ring: CGFloat = 0.379

    /// The flank's control points, in head radii from the head's centre, taken from
    /// the reference's curvature and scaled to `tipDistance`. The first holds the
    /// head's width as the curve leaves the equator; the second is where it turns in.
    private static let flankHold: CGFloat = 0.496
    private static let flankTurnX: CGFloat = 0.308
    private static let flankTurnY: CGFloat = 1.012

    /// Total extent in head radii, stroke included.
    private static let width = 2 + stroke
    private static let height = 1 + tipDistance + stroke

    /// Stroke weight as a fraction of the glyph's SQUARE box, for the caller — the
    /// glyph is taller than it is wide, so height is what binds.
    static let strokeFraction: CGFloat = stroke / height

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width / Self.width, rect.height / Self.height)
        let centre = CGPoint(
            x: rect.midX,
            y: rect.midY - Self.height * r / 2 + (1 + Self.stroke / 2) * r
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + x * r, y: centre.y + y * r)
        }

        var path = Path()
        // The head: the top half of the circle, left equator over the crown to right.
        path.move(to: point(-1, 0))
        path.addArc(
            center: centre,
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        // Down the right flank and back up the left, meeting at the tip. The join
        // there is rounded by the stroke, which is how the reference ends too.
        path.addCurve(
            to: point(0, Self.tipDistance),
            control1: point(1, Self.flankHold),
            control2: point(Self.flankTurnX, Self.flankTurnY)
        )
        path.addCurve(
            to: point(-1, 0),
            control1: point(-Self.flankTurnX, Self.flankTurnY),
            control2: point(-1, Self.flankHold)
        )
        path.closeSubpath()

        path.addEllipse(in: CGRect(
            x: centre.x - Self.ring * r,
            y: centre.y - Self.ring * r,
            width: Self.ring * 2 * r,
            height: Self.ring * 2 * r
        ))
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
