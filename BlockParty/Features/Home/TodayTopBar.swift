//
//  TodayTopBar.swift
//  Block Party — Today's fixed top bar: a friends mark leading, the wordmark centred,
//  the map disc and a notifications bell trailing.
//
//  Replaces `Masthead`, the 34pt wordmark + date line that used to scroll away with
//  the content. This bar is chrome: it is present immediately (no spring entrance),
//  it does not scroll with the content, it LEAVES on a downward scroll and returns
//  on an upward one (Jesse, 2026-09-21, naming Instagram), and it carries no rule of
//  its own — the feed shows through a soft blurred edge (`StatusEdge`, `BarEdge`).
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
//  On 2026-09-29 search moved down to the tab bar, into Business's slot, and a
//  friends mark (Apple's `person.2.fill`) took the leading edge (Jesse).
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
    /// bar is a `safeAreaInset` on the feed's own scroll, so its height IS that
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

    /// How far down the feed must be before the direction rule may take the chrome
    /// away: the bar's own height. Up to there the feed carries the bar out 1:1
    /// (`homeTravel`), as Instagram's header rides the scroll out of the top of its
    /// feed (Jesse, 2026-09-27); was 24 while the bar left on a spring instead.
    static let hideAfter: CGFloat = contentHeight

    /// How far the feed has carried the bar off the top: the scroll offset, 0 at
    /// home and the bar's full height once it has gone. The bar moves up by this
    /// and fades with it, so it follows the finger and stops where the finger stops
    /// (`references/soft-top-edge/instagram-top.mov`, the first 0.7 s). An offset,
    /// never a height — see `contentHeight`.
    static func homeTravel(offset: CGFloat) -> CGFloat {
        min(max(offset, 0), contentHeight)
    }

    /// How far the scroll must travel in ONE direction, accumulated since that
    /// direction started, before the bar flips. Under this, a finger resting on
    /// the glass and the last millimetres of inertia would flip the bar back and
    /// forth — the jitter every direction-driven header has to answer.
    ///
    /// Accumulated, not per frame: this was a 4pt per-frame threshold until
    /// 2026-09-24, and a slow drag (1–3pt a frame, deceleration tails included)
    /// never passed it, so the bar ignored slow drags entirely (taste.md: chrome
    /// follows the finger at any speed). 12pt is suggested by a peer session's
    /// measurement; tune on device.
    static let flipDistance: CGFloat = 12

    /// Where the current scroll direction started. Moves to the previous offset
    /// only when the direction REVERSES, so a slow drag keeps one anchor and its
    /// travel adds up. At or above home it follows the offset, so the first run
    /// down from the top is measured from where it actually starts.
    static func directionAnchor(anchor: CGFloat, previousOffset: CGFloat, offset: CGFloat) -> CGFloat {
        guard offset > hideAfter else { return offset }
        let step = offset - previousOffset
        let run = previousOffset - anchor
        if step != 0, run != 0, (step > 0) != (run > 0) { return previousOffset }
        return anchor
    }

    /// Instagram's rule, and NOT the fade band this bar carried until 2026-09-21:
    /// the chrome leaves when you scroll DOWN and comes back the moment you scroll
    /// UP, wherever you happen to be in the feed. A band keyed to absolute offset
    /// can only return the bar by scrolling all the way home, which is the part
    /// Jesse did not want.
    ///
    /// Pure and total, so the whole behaviour is testable without a scroll view:
    /// the only inputs are where the current direction started (`anchor`, from
    /// `directionAnchor`), where the scroll is, and what the bar was doing.
    static func chromeHidden(wasHidden: Bool, floating: Bool, anchor: CGFloat, offset: CGFloat) -> Bool {
        // Home, and anywhere a rubber-band pull takes you above it, always shows
        // the bar — there is nothing below to read yet. Inside its own height the
        // feed carries it (`homeTravel`).
        guard offset > hideAfter else { return false }
        // Carried its full height out of home, the bar has already gone: it counts
        // as away at once, however the finger wobbled on the way down, so the next
        // upward scroll floats it back. Waiting for the direction rule here left it
        // faded out and still "showing" — nothing brought it back mid-feed.
        guard floating else { return true }
        let travelled = offset - anchor
        if travelled >= flipDistance { return true }
        if travelled <= -flipDistance { return false }
        return wasHidden
    }

    /// Is the bar floating over the feed, rather than sitting at home on the paper?
    /// Instagram's side buttons are bare marks at the top of the feed and sit in
    /// frosted circles once the bar has come back over the feed (recorded
    /// 2026-09-27, `references/soft-top-edge/instagram-top.mov`).
    ///
    /// Floating starts the moment the bar leaves mid-feed, so it comes BACK with its
    /// circles and never grows them on screen; the first scroll down from home, before
    /// the bar leaves, stays bare. Only home ends it.
    static func chromeFloating(wasFloating: Bool, hidden: Bool, offset: CGFloat) -> Bool {
        guard offset > 0 else { return false }
        return wasFloating || hidden
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
    /// The map button's disc: Instagram's button circle, 44pt (MEASURED 2026-09-27,
    /// `references/soft-top-edge/instagram-top.mov`; Jesse: same size as theirs).
    /// Was 50 until then.
    static let mapSide: CGFloat = 44
    /// A side button's touch box, and the frosted circle drawn in it while the bar
    /// floats: Instagram's circle, 44pt (MEASURED, as above).
    static let glyphTap: CGFloat = 44
    /// The friends mark's point size: 25pt wide and 17pt tall in ink. Its Reference
    /// (`BP app/references/friends-icon/jesse.png`, SF's `person.2.fill`) is a crop
    /// with no scale, so the size is eyeballed against the bell (Jesse, 2026-09-29).
    static let friendsGlyphSize: CGFloat = 19
    /// The bell, at its measured reference size (20.69pt tall — see
    /// `refs/chrome/REFERENCE-SPEC.md`).
    static let bellGlyphSize: CGFloat = 21
    /// The row's padding: Instagram's circles sit 16pt in from the screen's edges,
    /// and its marks stay put inside them whether or not the circle shows (MEASURED,
    /// as above). Was 4 until 2026-09-27, which put the bare ink itself on 16pt.
    static let rowInset: CGFloat = 16
    /// Between the map disc and the bell's touch box: 4pt (Jesse, 2026-09-27), so the
    /// centred logo still clears the disc on a 375pt phone. Instagram has no third
    /// button to measure.
    static let controlGap: CGFloat = 4
    /// The glyph's square, inside the disc: the old 24 scaled with the disc
    /// (24 × 44/50). PICKED.
    static let mapGlyphSize: CGFloat = 21
    /// How white the frosted circle is over the blurred feed. Instagram's reads
    /// 68–83% of the way from what is behind it to white (MEASURED over wood, a
    /// keyboard, a grey room, a black video). At 0.6 ours read 68–74%; 0.68 lands
    /// on Instagram's middle. Tuned on the simulator.
    static let discWhite: Double = 0.68
    /// The offline pill: 32pt tall, 8pt under the bar's row. PICKED, from the
    /// Particle News Reference at 393pt wide.
    static let offlinePillHeight: CGFloat = 32
    static let offlinePillGap: CGFloat = 8
    /// The centred wordmark's height. 31 runs the lockup 151pt wide — 18 → 24 → 31
    /// over three passes on 2026-09-19, Jesse each time. It still clears the map
    /// disc beside it, with the bar's 58pt content height as the hard ceiling.
    static let wordmarkHeight: CGFloat = 31
    /// Instagram's top edge, MEASURED (2026-09-29, `references/soft-top-edge/SPEC.md`,
    /// from `instagram-top.mov`): the feed under it is blurred and mixed toward the
    /// page, both thinning in a straight line from the top of the screen to nothing
    /// at the bar's lower edge — about 7.5pt of blur (Gaussian sigma) and 45% haze at
    /// the top. With the bar away the same edge has slid up with the bar, so only its
    /// weaker lower part is left, ending just below the status bar. Built in two parts
    /// so the bar's part can leave with the bar: the status edge (always there, over
    /// the bar) and the bar edge (behind the bar while it floats), which together
    /// make the measured whole.
    ///
    /// How far below the status bar the status edge runs (Instagram's: ~5pt).
    static let statusEdgeTail: CGFloat = 4
    /// The status edge's blur at the very top of the screen: the whole edge's, slid
    /// up by the bar's height.
    static let statusBlurTop: CGFloat = 5
    /// The page colour laid over it at the top. Less than the measured 24%: the blur
    /// itself pales the photo, and the two together read 24% (tuned on the simulator).
    static let statusHaze: Double = 0.19
    /// The bar edge's blur at the top of the screen: stacked on the status edge's, the
    /// whole edge's 7.5pt.
    static let barBlurTop: CGFloat = 6
    /// The bar edge's page colour: level behind the status bar, thinning to nothing
    /// across the bar row (`barHazeEnds` of the way down), less than the whole edge's
    /// by what the status edge and the blur already give.
    static let barHaze: Double = 0.08
    /// Where the status bar ends on the bar edge, as a fraction of its height: 72 of
    /// 126pt on a 68pt status bar, 66 of 120 on a 62. Only the haze's bend sits there.
    static let barHazeEnds: CGFloat = 0.56
    /// The blur UIKit's `systemUltraThinMaterial` effect reaches at full strength, as
    /// a Gaussian sigma in points — what turns a wanted blur into how far in to stop
    /// the effect (`PartialBlurView`). MEASURED on the simulator: at 20 the edges
    /// blur within ±0.5pt of what they ask for.
    static let blurAtFull: CGFloat = 20
}

/// How far the feed has carried the Town bar off the top of the screen, in points.
/// A box of its own so the scroll can write it every frame and only the bar reads it.
@Observable
final class BarTravel {
    var points: CGFloat = 0
}

struct TodayTopBar: View {
    /// The leading friends mark (search until 2026-09-29, when it moved to the tab
    /// bar). Like every control here, the bar only reports the tap — the shell owns
    /// what opens.
    var onOpenFriends: () -> Void = {}
    /// The map button → the town map. No longer the trailing control: it slid left
    /// to make room for the bell, and now sits between the mark and the bar's edge.
    var onOpenMap: () -> Void = {}
    /// The trailing bell → notifications.
    var onOpenNotifications: () -> Void = {}
    /// True once a downward scroll has sent the chrome off the top of the screen;
    /// false the moment the feed is scrolled back up. `FeedView` owns the state,
    /// `TodayHeader.chromeHidden` owns the rule.
    var chromeHidden: Bool = false
    /// True while the bar floats over the feed rather than sitting at home on the
    /// paper: friends and the bell sit in frosted circles, as Instagram's buttons do.
    /// `TodayHeader.chromeFloating` owns the rule.
    var chromeFloating: Bool = false
    /// How far the feed has carried the bar off the top (`TodayHeader.homeTravel`).
    /// Written every frame of the first 58pt of scroll, so it arrives in its own
    /// observable box: this bar reads it and nothing above it re-runs.
    var travel = BarTravel()
    /// A read failed while the Town feed shows its kept list: a pill under the bar
    /// says so, and leaves and comes back with the bar (ticket 11).
    var offline = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The bar rides the scroll only out of HOME. Once it has come back over the
    /// feed it floats where it is, and the direction rule moves it.
    private var carried: CGFloat { chromeFloating ? 0 : travel.points }

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
        // spring (a short ease under Reduce Motion). Out of home it does not animate
        // at all: the feed carries the bar, 1:1 with the finger.
        //
        // The bar's HEIGHT never moves — the frame below holds 58 whether or not
        // anything is inside it. See `TodayHeader.contentHeight` for why a height
        // derived from this scroll rings instead of settling.
        ZStack {
            if !chromeHidden {
                controls
                    .frame(height: TodayHeader.contentHeight)
                    // Behind the bar while it floats over the feed: the part of
                    // Instagram's edge that belongs to the bar, so it leaves and comes
                    // back with it. At home there is only the page behind the bar.
                    .background(alignment: .top) {
                        if chromeFloating {
                            BarEdge()
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    // Under the bar, outside its fixed height, so the cards never move
                    // for it.
                    .overlay(alignment: .bottom) {
                        if offline {
                            OfflinePill()
                                .alignmentGuide(.bottom) { $0[.top] - TodayBarMetric.offlinePillGap }
                                .transition(.opacity)
                        }
                    }
                    .animation(motion, value: offline)
                    .offset(y: -carried)
                    .opacity(1 - carried / TodayHeader.contentHeight)
                    .transition(.offset(y: -TodayHeader.contentHeight).combined(with: .opacity))
            }
        }
        .frame(height: TodayHeader.contentHeight)
        .frame(maxWidth: .infinity)
        // NOT clipped at the bar's edge: Instagram's header slides up under the clock
        // and comes back down from behind it whole (recorded 2026-09-27). A clip
        // sliced the circles flat on top for a frame on the way in.
        //
        // The status edge sits OVER the bar, as Instagram's does: the header the feed
        // carries out of home rides up under it and blurs and pales on the way, and
        // a bar leaving mid-feed slides under it the same way. It stops a few points
        // below the status bar, above the circles and the logo at rest.
        .statusEdge()
        .animation(motion, value: chromeHidden)
        .animation(motion, value: chromeFloating)
    }

    /// The bar's one motion: a spring, or under Reduce Motion a short ease.
    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.9)
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
    /// `rowInset 16 + glyphTap 44 + controlGap 4 + mapSide 44` = 108pt, which leaves
    /// `W/2 − 183.4`: **+4.1pt at 375, +13.1 at 393, +36.6 at 440**. Break-even is
    /// 366.8pt, below every iPhone that runs this OS. The leading side takes 60pt
    /// and is never the binding constraint.
    ///
    /// Friends and the bell are bare marks at home and only sit in frosted circles
    /// while the bar floats (`chromeFloating`), as Instagram's do. The map disc is
    /// the one control that is always an object. (A disc LEADING would trip
    /// `TodayHeaderTests.testBrandLockupLeavesTheLeadingHeaderAreaBlank`, which
    /// allows under 20 saturated pixels in the leading 18% of the bar against the
    /// roughly 7,800 a yellow disc puts there.)
    private var controls: some View {
        HStack(spacing: 0) {
            friendsButton
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

    /// A bar mark in a 44pt touch box: bare at home, in a frosted circle while
    /// the bar floats. Shared by the friends glyph and the bell, because the only
    /// thing that differs between them is the glyph and the label — and two
    /// near-identical button bodies is how the two drift apart.
    @ViewBuilder
    private func glyphButton<Glyph: View>(
        label: String,
        hint: String = "",
        action: @escaping () -> Void,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        Button(action: action) {
            glyph()
                // The circle is always light, so the ink on it is the light-canvas
                // ink; bare on the paper it stays the page's own ink.
                .foregroundStyle(chromeFloating ? Hue.ink.onLightCanvas : Hue.ink)
                .frame(width: TodayBarMetric.glyphTap, height: TodayBarMetric.glyphTap)
                .background {
                    if chromeFloating {
                        Frosted(shape: Circle()).transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
        }
        // The same pop the app's other bare controls use. The map disc beside it
        // runs the same style at 0.92, without the tick.
        .buttonStyle(PressableStyle(scale: 0.88, haptic: true))
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        // Frozen chrome owes the reader another way in — the mark never grows with
        // Dynamic Type, so a long press has to enlarge it.
        .accessibilityShowsLargeContentViewer { Text(label) }
    }

    /// Apple's own two-person mark: laid over the Reference it differs by ~1px of
    /// antialiasing, so nothing here is traced.
    private var friendsButton: some View {
        glyphButton(label: "Friends", action: onOpenFriends) {
            Image(systemName: "person.2.fill")
                .font(.glyph(TodayBarMetric.friendsGlyphSize))
                .accessibilityHidden(true)
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

    /// The yellow map disc: a SOLID circle in the exact brand yellow (`Hue.brandDisc`),
    /// with `Hue.onBrandDisc` ink. It sits inboard of the bell rather than
    /// on the bar's trailing edge, at Instagram's 44pt button size — the one control
    /// that is always an object.
    ///
    /// It was Liquid Glass tinted with the yellow at 68% until 2026-09-24. Two
    /// things killed it (Jesse, Q1 A): a tint is not the brand yellow (it went
    /// mustard over photos, and taste.md says exactly `#FCE804`, never a tint), and
    /// glass composites outside the view's own layer, so it arrived and left out of
    /// step with the rest of the bar. A plain view fades, slides and clips with its
    /// neighbours. `TodayHeaderTests.testMapDiscIsExactBrandYellow` guards the colour.
    ///
    /// The press is a 0.92 squish without the haptic: opening the map is not a
    /// commit (Jesse, Q4 A).
    private var mapButton: some View {
        let side = TodayBarMetric.mapSide
        return Button(action: onOpenMap) {
            MapPinGlyph(size: TodayBarMetric.mapGlyphSize)
                .foregroundStyle(Hue.onBrandDisc)
                .frame(width: side, height: side)
                .background(Self.mapShape.fill(Hue.brandDisc))
                .contentShape(Self.mapShape)
        }
        .buttonStyle(PressableStyle(scale: 0.92, haptic: false))
        .accessibilityLabel("Open the town map")
    }
}

/// Instagram's status-bar edge: the feed under the clock blurred and mixed toward
/// the page, both thinning to nothing just below the status bar. Always there, and
/// over the bar (`TodayTopBar.body`). Mixed toward the page's own colour, so over the
/// page at home it is invisible, in either appearance.
///
/// Not a material: every material blurs ~19pt and fogs the photo grey (the edge
/// shipped that way 2026-09-27), where Instagram's blurs 5–9pt and keeps the colour.
/// Not the system soft scroll edge either: it needs `.safeAreaBar`, which flipped the
/// bar dark over photos (2026-09-24), and it cannot shrink when the bar leaves, since
/// the bar's height is the scroll's inset (`TodayHeader.contentHeight`).
private struct StatusEdge: View {
    var body: some View {
        ProgressiveBlur(top: TodayBarMetric.statusBlurTop)
            .overlay(LinearGradient(colors: [Hue.paper.opacity(TodayBarMetric.statusHaze),
                                             Hue.paper.opacity(0)],
                                    startPoint: .top, endPoint: .bottom))
    }
}

extension View {
    /// The status edge laid over the top of a screen: Today's bar, and Daily's page.
    /// Daily fades it out at rest, over its yellow: the haze would make a near-yellow,
    /// and so does the blur, which pulls in a lighter band at the screen's top
    /// (measured 2026-10-01: #F7E61F over #FAE703). Faded, not masked: a SwiftUI mask
    /// over this UIKit blur kept the app from ever going idle, and the UI tests waited
    /// minutes at every step (2026-10-01).
    func statusEdge(opacity: Double = 1) -> some View {
        overlay(alignment: .top) {
            Color.clear
                .frame(height: TodayBarMetric.statusEdgeTail)
                .background(StatusEdge().ignoresSafeArea(edges: .top))
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The rest of Instagram's edge while the bar floats over the feed: stronger behind
/// the status bar, thinning to nothing at the bar's lower edge. On top of the status
/// edge it makes the measured whole.
private struct BarEdge: View {
    var body: some View {
        // One blur over the whole height: two stacked blurs meeting at the status
        // bar's edge drew a seam there, each blurring only what was on its own side.
        ProgressiveBlur(top: TodayBarMetric.barBlurTop)
            .overlay(LinearGradient(stops: [
                .init(color: Hue.paper.opacity(TodayBarMetric.barHaze), location: 0),
                .init(color: Hue.paper.opacity(TodayBarMetric.barHaze), location: TodayBarMetric.barHazeEnds),
                .init(color: Hue.paper.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom))
    }
}

/// The math of a blur that thins from top to bottom, built from stacked blurs.
nonisolated enum EdgeBlur {
    /// One blur in the stack: its sigma in points, and its mask — solid from the top
    /// down to `solidTo`, thinning to clear at `clearAt` (fractions of the height).
    struct Layer {
        var sigma: CGFloat
        var solidTo: CGFloat
        var clearAt: CGFloat
    }

    /// Stacked blurs compound — each blurs what the ones under it already blurred —
    /// so their sigmas add as squares. Cut the height into `steps` bands; each band
    /// gets a layer that thins across it and carries the variance that band adds, so
    /// at every band's edge the stack blurs exactly `top → 0` in a straight line.
    static func layers(top: CGFloat, steps: Int) -> [Layer] {
        func variance(_ t: CGFloat) -> CGFloat { (top * (1 - t)) * (top * (1 - t)) }
        return (1...steps).reversed().map { step in
            let upper = CGFloat(step - 1) / CGFloat(steps)
            let lower = CGFloat(step) / CGFloat(steps)
            return Layer(sigma: (variance(upper) - variance(lower)).squareRoot(),
                         solidTo: upper, clearAt: lower)
        }
    }
}

/// A blur that thins from `top` (a sigma in points) to nothing, as a stack of UIKit
/// blurs (`EdgeBlur.layers`).
private struct ProgressiveBlur: UIViewRepresentable {
    var top: CGFloat

    func makeUIView(context: Context) -> UIView {
        let stack = UIView()
        stack.isUserInteractionEnabled = false
        for layer in EdgeBlur.layers(top: top, steps: 2) {
            let blur = PartialBlurView(fraction: layer.sigma / TodayBarMetric.blurAtFull,
                                       solidTo: layer.solidTo, clearAt: layer.clearAt)
            blur.frame = stack.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            stack.addSubview(blur)
        }
        return stack
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

/// UIKit's blur effect stopped part of the way in: the one public route to a blur
/// lighter than a material's. A paused animator holds it there — finished at its
/// current point instead, the blur went to nothing. It is set again each time the
/// view lands in a window, the app comes back, or the appearance changes, since
/// each of those rebuilds the effect.
private final class PartialBlurView: UIVisualEffectView {
    private let fraction: CGFloat
    private var animator: UIViewPropertyAnimator?

    init(fraction: CGFloat, solidTo: CGFloat, clearAt: CGFloat) {
        self.fraction = min(fraction, 1)
        super.init(effect: nil)
        let ramp = GradientMaskView()
        ramp.gradient.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        ramp.gradient.locations = [0, NSNumber(value: Double(solidTo)), NSNumber(value: Double(clearAt))]
        mask = ramp
        NotificationCenter.default.addObserver(self, selector: #selector(arm),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PartialBlurView, _) in
            view.arm()
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        mask?.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Next turn of the run loop: SwiftUI inserts views with UIKit animations
        // switched off, and an animator started then lands on the full effect.
        if window != nil { DispatchQueue.main.async { [weak self] in self?.arm() } }
    }

    @objc private func arm() {
        animator?.stopAnimation(true)
        effect = nil
        // A paused animation never finishes, so XCUITest would wait out its 60 s
        // idle timeout before every step; the UI tests run without the blur.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-tests") { return }
        #endif
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [unowned self] in
            effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        animator.fractionComplete = fraction
        self.animator = animator
    }

    // A paused animator must be stopped before it is released, or UIKit traps.
    isolated deinit {
        animator?.stopAnimation(true)
    }
}

private final class GradientMaskView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
}

/// The frosted circle behind friends and the bell while the bar floats over the
/// feed — Instagram's button circle, which reads mostly white with a tint of the
/// photo behind it (MEASURED 2026-09-27). A material, not Liquid Glass: glass
/// composites outside its view's layer, so in this bar it arrives and leaves out
/// of step with the slide (the map disc, until 2026-09-24), and it flips dark over
/// a dark photo (the tab bar). A material fades, slides and clips with its mark.
private struct Frosted<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Hue.surface.onLightCanvas.opacity(TodayBarMetric.discWhite)))
            // Instagram's brighter rim, as the tab bar draws it.
            .overlay(shape.strokeBorder(Hue.surface.onLightCanvas.opacity(0.75), lineWidth: 1))
            .environment(\.colorScheme, .light)
            .allowsHitTesting(false)
    }
}

/// The Town feed's offline pill: the map sheet's crossed-out wifi and words, ink on
/// the bar's frosted white. Particle News's "No Internet Connection" pill is the
/// Reference (BP app `references/town-fresh-order/`).
private struct OfflinePill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash").font(.sansMedium(11))
            Text(FeedStateCopy.offline)
        }
        .font(.sans(13))
        .foregroundStyle(Hue.ink.onLightCanvas)
        .padding(.horizontal, 14)
        .frame(height: TodayBarMetric.offlinePillHeight)
        .background(Frosted(shape: Capsule()))
        // VoiceOver hears it once as an announcement when it appears (FeedView).
        .accessibilityElement(children: .combine)
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
