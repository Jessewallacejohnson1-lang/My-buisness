//
//  TodayTopBar.swift
//  Block Party — Today's fixed top bar: a search mark leading, the wordmark centred,
//  the map disc and a notifications bell trailing.
//
//  Replaces `Masthead`, the 34pt wordmark + date line that used to scroll away with
//  the content. This bar is chrome: it is present immediately (no spring entrance),
//  it does not scroll with the content, it LEAVES on a downward scroll and returns
//  on an upward one (Jesse, 2026-09-21, naming Instagram), and it carries no rule of
//  its own — the soft scroll edge effect under it is what separates the bar from the
//  feed, a gradient rather than a cut.
//
//  The Joetown lockup was retired on 2026-09-17; the profile avatar — the ⋮-lineage
//  button that opened the town menu — was retired on 2026-09-18 (Jesse's call). For
//  two days the bar carried exactly one control, the yellow map disc, sitting where
//  the avatar used to.
//
//  On 2026-09-20 it gained two more, traced off an Alta reference (Jesse): a search
//  mark on the leading edge, and a notifications bell on the trailing edge — which
//  is the slot the map disc used to hold, so the disc slid left to make room. The
//  bar reports every tap; the shell owns every presentation.
//
//  The two new marks are BARE INK, not discs. That is what the reference does, and
//  it is also the only thing the width budget allows — see `controls`.
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
    /// stay constant.**
    ///
    /// **Nothing that changes the bar's HEIGHT may be derived from the scroll.** The
    /// bar is a `safeAreaBar` on the feed's own scroll, so its height IS that
    /// scroll's top content inset, and any offset read back off that scroll is
    /// measured against the same inset. Height-from-scroll therefore closes a loop:
    /// height → inset → offset → height. It does not degrade gracefully; it rings.
    ///
    /// It shipped that way for one commit (d1fcf40) and the feed would not scroll at
    /// all — measured with `-feed-scroll-sweep -scroll-log`, the offset ping-ponged
    /// between -0.1 and 1.0 with 1420 direction reversals in 1422 samples. Pinning
    /// the height took the same trace to 241 samples, 0 reversals, a clean 0 → 200.
    /// Dim, blur, tint off the scroll freely. Height, insets and content size never.
    static let contentHeight: CGFloat = 58

    /// How far down the feed must be before a downward swipe may take the chrome
    /// away. Short on purpose: the bar belongs to the top of the feed, and one
    /// deliberate swipe should clear it.
    static let hideAfter: CGFloat = 24

    /// The smallest movement that counts as a direction. Under this, a finger
    /// resting on the glass and the last millimetres of inertia would flip the bar
    /// back and forth — the jitter every direction-driven header has to answer.
    static let directionThreshold: CGFloat = 4

    /// Instagram's rule, and NOT the fade band this bar carried until 2026-09-21:
    /// the chrome leaves when you scroll DOWN and comes back the moment you scroll
    /// UP, wherever you happen to be in the feed. A band keyed to absolute offset
    /// can only return the bar by scrolling all the way home, which is the part
    /// Jesse did not want.
    ///
    /// Pure and total, so the whole behaviour is testable without a scroll view:
    /// the only inputs are where the scroll was, where it is, and what the bar was
    /// doing. `previousOffset` comes free from `onScrollGeometryChange`'s old
    /// value, so nothing has to be stored to compute it.
    static func chromeHidden(wasHidden: Bool, previousOffset: CGFloat, offset: CGFloat) -> Bool {
        // Home, and anywhere a rubber-band pull takes you above it, always shows
        // the bar — there is nothing below to read yet.
        guard offset > hideAfter else { return false }
        let travelled = offset - previousOffset
        if travelled > directionThreshold { return true }
        if travelled < -directionThreshold { return false }
        return wasHidden
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
    /// The OPTICAL screen inset — where the drawn ink of the outermost control
    /// lands. The row itself is padded by `rowInset`; the difference is the
    /// invisible overhang of the bare glyphs' 44pt touch boxes.
    static let inset: CGFloat = 16
    /// The map button's disc. Unchanged at 50 — it is still the only control in this
    /// bar that is an OBJECT rather than a mark, and shrinking it to match its new
    /// neighbours would have made three marks where the reference has one button.
    static let mapSide: CGFloat = 50
    /// A bare glyph's touch box. The marks themselves are ~20pt, well under the 44pt
    /// HIG target, so each one is centred in a box that meets it. The box is
    /// invisible, which is why the ROW is inset less than the ink appears to be.
    static let glyphTap: CGFloat = 44
    /// The search mark and the bell, at their measured reference sizes
    /// (19.82pt square and 20.69pt tall — see `refs/chrome/REFERENCE-SPEC.md`).
    static let searchGlyphSize: CGFloat = 20
    static let bellGlyphSize: CGFloat = 21
    /// The row's real padding: `inset` minus the touch box's overhang past the ink,
    /// so a 20pt mark in a 44pt box draws its edge on the 16pt line.
    static let rowInset: CGFloat = inset - (glyphTap - searchGlyphSize) / 2
    /// Between the map disc and the bell's touch box. The bell's ink sits 11.5pt
    /// inside its box, so the gap READS as ~19pt — which is what keeps the two
    /// trailing controls from looking like one clump.
    static let controlGap: CGFloat = 8
    /// The glyph's square, inside the disc.
    static let mapGlyphSize: CGFloat = 24
    /// The centred wordmark's height. 31 runs the lockup 151pt wide — 18 → 24 → 31
    /// over three passes on 2026-09-19, Jesse each time. It still clears the 50pt
    /// disc beside it, with the bar's 58pt content height as the hard ceiling.
    static let wordmarkHeight: CGFloat = 31
    /// How far below the controls the paper backdrop fades to clear. GUESSED
    /// (2026-09-24), pending an Instagram screen recording in `references/` —
    /// taste.md says sizes come from a Reference, and there is none yet.
    static let backdropFade: CGFloat = 16
}

struct TodayTopBar: View {
    /// The leading search mark. Like every control here, the bar only reports the
    /// tap — the shell owns what opens.
    var onOpenSearch: () -> Void = {}
    /// The map button → the town map. No longer the trailing control: it slid left
    /// to make room for the bell, and now sits between the mark and the bar's edge.
    var onOpenMap: () -> Void = {}
    /// The trailing bell → notifications.
    var onOpenNotifications: () -> Void = {}
    /// True once a downward scroll has sent the chrome off the top of the screen;
    /// false the moment the feed is scrolled back up. `FeedView` owns the state,
    /// `TodayHeader.chromeHidden` owns the rule.
    var chromeHidden: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The chrome LEAVES THE SCREEN on a downward scroll and comes straight back
        // on an upward one (Jesse, 2026-09-21, naming Instagram).
        //
        // It is REMOVED from the hierarchy rather than faded in place. That began as
        // a workaround: until 2026-09-24 the map disc was Liquid Glass, which
        // composites outside the view's own layer, so an ancestor `.opacity(0)` and
        // `.clipped()` both left it drawn over the status bar. The disc is a plain
        // solid view now, so every control fades, slides and clips together; removal
        // stays because gone chrome should not be in the hierarchy at all.
        //
        // The transition is what animates: a slide up combined with a fade, on a
        // spring. Under Reduce Motion it is the crossfade alone, which is the same
        // trade the rest of the app's chrome makes.
        //
        // The bar's HEIGHT never moves — the frame below holds 58 whether or not
        // anything is inside it. See `TodayHeader.contentHeight` for why a height
        // derived from this scroll rings instead of settling. The band the chrome
        // leaves behind is not empty: with the backdrop gone too, what shows through
        // is the feed, blurred and washed toward the page by `FeedView`'s
        // `.scrollEdgeEffectStyle(.soft, for: .top)` — a gradient, not a cut.
        ZStack {
            if !chromeHidden {
                controls
                    .transition(.offset(y: -TodayHeader.contentHeight).combined(with: .opacity))
            }
        }
        .frame(height: TodayHeader.contentHeight)
        .frame(maxWidth: .infinity)
        // Cut at the bar's own edge, so a mid-flight slide is trimmed rather than
        // drawn over the status bar.
        .clipped()
        // The paper backdrop, OUTSIDE that clip because it has to reach up behind
        // the status bar and down past the row. It arrives and leaves with the
        // controls (one animation drives both), so mid-feed the logo, icons and
        // status bar come back on paper instead of over a photo (Jesse, 2026-09-24,
        // Q2 A). At the top of the feed it is paper on paper, so nothing changes
        // there. Not the white lid of 2026-09-19: it fades to clear below the row,
        // and it is gone whenever the bar is.
        .background(alignment: .top) {
            ZStack {
                if !chromeHidden {
                    backdrop
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18)
                                : .spring(response: 0.34, dampingFraction: 0.9),
                   value: chromeHidden)
    }

    /// Full paper behind the status bar and the 58pt row, then paper-to-clear over
    /// `backdropFade`. It slides by its OWN height (`.move(edge: .top)`, measured
    /// after the safe-area extension), not the controls' 58pt, so no strip of paper
    /// is left behind mid-flight. Taps pass through to the feed underneath.
    private var backdrop: some View {
        VStack(spacing: 0) {
            Hue.paper
            LinearGradient(colors: [Hue.paper, Hue.paper.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: TodayBarMetric.backdropFade)
        }
        .frame(height: TodayHeader.contentHeight + TodayBarMetric.backdropFade)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Same shape as the controls' transition, so the two land on the same frame.
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Layers

    /// The mark centred, controls either side — the shape Instagram's feed header
    /// has trained everyone to read. All of it belongs to the top of the feed and
    /// all of it leaves together.
    ///
    /// The mark is CENTRED against the bar, not laid out between the other controls:
    /// in an `HStack` it would sit wherever the trailing button's width left it, and
    /// drift every time that button changed size. A centred overlay is fixed to the
    /// screen's midline, which is where the eye looks for a logo.
    ///
    /// It is the real artwork (`BlockPartyWordmark` → the `Wordmark` raster), not the
    /// Jost wordmark it replaced (Jesse, 2026-09-19).
    /// Three controls now, and the centred mark still has to clear them.
    ///
    /// The lockup is 150.8pt wide (`BlockPartyWordmark.aspect` 4.8657 × 31), so it
    /// claims 75.4pt either side of the midline. The trailing side consumes
    /// `rowInset 4 + glyphTap 44 + controlGap 8 + mapSide 50` = 106pt, which leaves
    /// `W/2 − 181.4`: **+6.1pt at 375, +15.1 at 393, +38.6 at 440**. Break-even is
    /// 362.8pt, below every iPhone that runs this OS. The leading side takes 48pt
    /// and is never the binding constraint.
    ///
    /// This is why the two new marks are BARE INK and not discs like the map's. A
    /// second 50pt disc trailing pushes the lane to 112pt and the clearance to
    /// **−11.9pt at 375 and −2.9pt at 393** — the mark and the control overlap on
    /// most phones. The reference draws its top-bar marks bare too, so fidelity and
    /// arithmetic agree here. (A disc LEADING would also trip
    /// `TodayHeaderTests.testBrandLockupLeavesTheLeadingHeaderAreaBlank`, which
    /// allows under 20 saturated pixels in the leading 18% of the bar against the
    /// roughly 7,800 a yellow disc puts there.)
    private var controls: some View {
        HStack(spacing: 0) {
            searchButton
            Spacer(minLength: 0)
            mapButton
            Spacer(minLength: 0).frame(width: TodayBarMetric.controlGap)
            bellButton
        }
        .padding(.horizontal, TodayBarMetric.rowInset)
        .overlay {
            brandMark
                .accessibilityAddTraits(.isHeader)
                // Decorative-adjacent: it names the app, it does not act, so it must
                // not sit in the tap path of the controls beside it.
                .allowsHitTesting(false)
        }
        // Chrome that has left the screen must stop TAKING TAPS. The first version
        // of the fade did not, and an invisible map disc swallowed touches at the
        // top of a scrolled feed. VoiceOver gets the same treatment: gone is gone.
        .allowsHitTesting(!chromeHidden)
        .accessibilityHidden(chromeHidden)
    }

    /// A bare traced mark in a 44pt touch box. Shared by the search glyph and the
    /// bell, because the only thing that differs between them is the glyph and the
    /// label — and two near-identical button bodies is how the two drift apart.
    @ViewBuilder
    private func glyphButton<Glyph: View>(
        label: String,
        hint: String,
        action: @escaping () -> Void,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        Button(action: action) {
            glyph()
                .foregroundStyle(Hue.ink)
                .frame(width: TodayBarMetric.glyphTap, height: TodayBarMetric.glyphTap)
                .contentShape(Rectangle())
        }
        // The same pop the app's other bare controls use. The map disc beside it
        // runs the same style at the Create disc's 0.92, without the tick.
        .buttonStyle(PressableStyle(scale: 0.88, haptic: true))
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        // Frozen chrome owes the reader another way in — the mark never grows with
        // Dynamic Type, so a long press has to enlarge it.
        .accessibilityShowsLargeContentViewer { Text(label) }
    }

    private var searchButton: some View {
        glyphButton(label: "Search", hint: "Find places and happenings around town", action: onOpenSearch) {
            MagnifierGlyph(size: TodayBarMetric.searchGlyphSize)
        }
    }

    private var bellButton: some View {
        glyphButton(label: "Notifications", hint: "What you have missed", action: onOpenNotifications) {
            BellGlyph(size: TodayBarMetric.bellGlyphSize)
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

    /// The yellow map disc: a SOLID circle in the exact brand yellow, the same fill
    /// and ink as the tab bar's Create disc. It sits inboard of the bell rather than
    /// on the bar's trailing edge, and it is still 50pt — still the one OBJECT among
    /// three marks.
    ///
    /// It was Liquid Glass tinted with the yellow at 68% until 2026-09-24. Two
    /// things killed it (Jesse, Q1 A): a tint is not the brand yellow (it went
    /// mustard over photos, and taste.md says exactly `#FCE804`, never a tint), and
    /// glass composites outside the view's own layer, so it arrived and left out of
    /// step with the rest of the bar. A plain view fades, slides and clips with its
    /// neighbours. `TodayHeaderTests.testMapDiscIsExactBrandYellow` guards the colour.
    ///
    /// The press is the Create disc's squish (`RootView.createButton`), without the
    /// haptic: opening the map is not a commit (Jesse, Q4 A).
    private var mapButton: some View {
        let side = TodayBarMetric.mapSide
        return Button(action: onOpenMap) {
            MapPinGlyph(size: TodayBarMetric.mapGlyphSize)
                .foregroundStyle(Hue.onCreateDisc)
                .frame(width: side, height: side)
                .background(Self.mapShape.fill(Hue.createDisc))
                .contentShape(Self.mapShape)
        }
        .buttonStyle(PressableStyle(scale: 0.92, haptic: false))
        .accessibilityLabel("Open the town map")
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
