//
//  TabBar.swift
//  Block Party — the floating tab bar, its measured geometry, and what a reserved tab shows.
//

import SwiftUI

/// The tab bar's measured geometry, in CAPSULE-LOCAL points: x = 0 at the capsule's
/// leading edge, y = 0 at its top. One set of numbers places the items and the
/// bubble, and will hit-test the finger. Source: Instagram's iOS 26 bar, measured
/// from Jesse's recording (`/Users/owner/BP app/references/instagram-tab-bar/`,
/// 2026-09-27), where it sets a value; Apple's own bar (`references/tab-bar/`)
/// where Instagram's recording cannot.
///
/// `nonisolated`: constants and pure arithmetic, callable from any context.
nonisolated enum TabBarMetric {
    /// Capsule height, and its gap to the screen's sides and physical bottom edge.
    /// Height: Instagram's capsule is 0.167x its width, 60pt at 360 (MEASURED as a
    /// ratio, so the recording's scale drops out). Gaps: 21pt, Apple's MEASURED
    /// value; Instagram's side gap matches it, its bottom gap is outside the crop.
    static let height: CGFloat = 60
    static let margin: CGFloat = 21
    /// The Selection bubble: 50pt tall, so 5pt inside the capsule top and bottom,
    /// and as wide as one tab's slot. The slots split the capsule evenly inside a
    /// 9pt side inset, so the end bubbles sit 9pt in. MEASURED on Instagram's five
    /// slots (69.4pt bubble, 68.5pt slot, first centre 43pt in); four here.
    static let sideInset: CGFloat = 9
    static let bubbleHeight: CGFloat = 50
    /// Icon point size, centred up and down: Instagram's glyph boxes are 22pt and
    /// its strokes ~1.6pt (MEASURED). At 23 the house drew 26.7pt wide on the eyes
    /// sim; 19.5 brings the widest glyph to ~22.5pt.
    static let iconSize: CGFloat = 19.5
    /// Search's traced magnifier fills its own box: Instagram's search mark, 22pt
    /// (66px @3x, MEASURED on Mobbin's Instagram tab bar, 2026-09-29).
    static let searchGlyphSize: CGFloat = 22
    /// Daily's Bp!: letters at the size Jesse picked at Check-in 1 (38pt for Bp.,
    /// 2026-10-29), 22pt tall, about Instagram's 22pt glyph box. `DailyMark.svg`'s own width.
    static let dailyMarkWidth: CGFloat = 39.15
    static let iconCentreY: CGFloat = height / 2
    /// The You tab's photo: a 25pt circle (MEASURED on Instagram's profile tab).
    static let avatarSize: CGFloat = 25
    /// How far the Friends icon's frame runs past its ink on the right and top, so its dot
    /// sits on the ink's corner: the Town bar's measure for the same symbol at 19pt (2026-10-13).
    /// MEASURED at 19.5 on BP Build (2026-11-01): the dot's centre lands at 220.5, 853.8 against
    /// the rule's 220.7, 853.7 (the ink's top right, 2pt in).
    static let friendsInkRight: CGFloat = 3.3
    static let friendsInkTop: CGFloat = 1.5
    /// How far past the first and last centres the Lens may travel. MEASURED at the
    /// right end on Apple's bar (§3.5); the left end mirrors it, GUESSED.
    static let lensOvershoot: CGFloat = 9

    /// One tab's share of the capsule, and the bubble's width.
    static func bubbleWidth(capsuleWidth: CGFloat) -> CGFloat {
        (capsuleWidth - 2 * sideInset) / CGFloat(Tab.allCases.count)
    }

    /// The Lens while held: 1.20x the bubble's width and 1.30x its height, so it
    /// stands ~4pt proud of the capsule. MEASURED on TabProbe (Air, hold (d)).
    static let lensScale = CGSize(width: 1.20, height: 1.30)
    /// Apple's whole bar swells while pressed. MEASURED 1.042x peak, 1.039x held
    /// (Instagram's 1.044x). The interactive glass draws it; this maps the finger.
    static let swell: CGFloat = 1.04
    /// Icons under the Lens centre magnify 1.2x (MEASURED §3.7), falling off
    /// linearly to 1.0 one tab away (GUESSED method: no jump between tabs).
    static let magnificationPeak: CGFloat = 0.2

    static func bubbleSize(capsuleWidth: CGFloat, held: Bool) -> CGSize {
        let rest = CGSize(width: bubbleWidth(capsuleWidth: capsuleWidth), height: bubbleHeight)
        guard held else { return rest }
        return CGSize(width: rest.width * lensScale.width, height: rest.height * lensScale.height)
    }

    /// The distance between neighbouring tab centres.
    static func pitch(capsuleWidth: CGFloat) -> CGFloat {
        centreX(of: .blockParty, capsuleWidth: capsuleWidth) - centreX(of: .town, capsuleWidth: capsuleWidth)
    }

    static func magnification(itemX: CGFloat, lensX: CGFloat, capsuleWidth: CGFloat) -> CGFloat {
        1 + magnificationPeak * max(0, 1 - abs(lensX - itemX) / pitch(capsuleWidth: capsuleWidth))
    }

    /// The Lens growing on touch-down and the bar's swell: 89% there at 37ms, 96%
    /// at 70ms, no overshoot. MEASURED; fitted as a critically damped spring.
    static let growth = Animation.spring(response: 0.06, dampingFraction: 1)
    /// The bubble travelling between tabs (a tap, a touch-down away from the
    /// selected tab, a release). MEASURED target: Apple's arrives ~270–280ms after a
    /// tap (its centre 96.5% of the way at +272ms, TabProbe) and does not overshoot.
    /// Critically damped at 0.33 matches that point; 0.45/0.8 arrived at ~350ms and
    /// overshot 2.5pt, and 0.27 read as early on the eyes sim. Fitted, not measured.
    static let travel = Animation.spring(response: 0.33, dampingFraction: 1)

    /// How long the Lens keeps its look after the finger lifts. After a tap it lasts
    /// to the end of the travel (Apple's re-forms its grey bubble ~323–353ms after
    /// touch-down); after a drag it collapses in ~76ms (MEASURED §3.6). The tap
    /// value is GUESSED from those, counted from lift rather than touch-down.
    static let landingAfterTap: Duration = .milliseconds(260)
    static let collapseAfterDrag: Duration = .milliseconds(70)

    /// The white layer behind the bar's glass that holds it in its light state.
    /// MEASURED threshold: 20% flipped, 30% held. 35% read 202–208 over a near-black
    /// photo (2026-09-27), lighter than Instagram's 192 over black, so it sits at the
    /// threshold that held.
    static let glassUnderlay: Double = 0.30
    /// The same layer under a finger, so the pressed bar lightens by Instagram's
    /// middling amount (~+30 over a dark photo, with the interactive glass's own).
    static let pressedUnderlay: Double = 0.40
    /// The Selection bubble's black: Instagram's reads 0.87x the glass on any
    /// ground (168 on 192 over black, 221 on 255 over white; MEASURED).
    static let bubbleShade: Double = 0.13

    /// While the feed reads down, the whole bar rests at 0.84x (Instagram's
    /// 462×78px against 550×92px, MEASURED), and gets there with no overshoot: half
    /// way at ~80ms, 98% at ~250ms. Fitted as a critically damped spring; the way
    /// back is GUESSED to mirror it (the recording never scrolls up).
    static let compactScale: CGFloat = 0.84
    static let compaction = Animation.spring(response: 0.3, dampingFraction: 1)

    /// A tab's centre: the middle of its slot.
    static func centreX(of tab: Tab, capsuleWidth: CGFloat) -> CGFloat {
        sideInset + bubbleWidth(capsuleWidth: capsuleWidth) * (CGFloat(tab.rawValue) + 0.5)
    }

    /// The tab a release picks: the centre nearest the finger's x. Its height does
    /// not matter — Apple's bar switches on a release 150pt above it (MEASURED on
    /// the Air probe, 2026-09-25), so there is no cancel zone.
    static func tab(atX x: CGFloat, capsuleWidth: CGFloat) -> Tab {
        Tab.allCases.min {
            abs(centreX(of: $0, capsuleWidth: capsuleWidth) - x) < abs(centreX(of: $1, capsuleWidth: capsuleWidth) - x)
        } ?? .town
    }

    /// Where the Lens sits under a finger: on it, clamped `lensOvershoot` past the
    /// end centres.
    static func lensCentreX(fingerX: CGFloat, capsuleWidth: CGFloat) -> CGFloat {
        let first = centreX(of: .town, capsuleWidth: capsuleWidth) - lensOvershoot
        let last = centreX(of: .you, capsuleWidth: capsuleWidth) + lensOvershoot
        return min(max(fingerX, first), last)
    }
}

/// The global bottom shell: one floating Liquid Glass capsule, a copy of Instagram's
/// iOS 26 bar with BP's icons (Jesse, 2026-09-27). It mounts on every tab and never
/// hides; while the Town feed reads down it shrinks, as Instagram's does.
///
/// One touch drives it, the way Apple's own bar works (TabProbe, 2026-09-25): the
/// Selection bubble lifts into a Lens under the finger on touch-down (a plain tap
/// included), follows the finger, and the tab nearest the finger's x on release is
/// picked, however far above the bar the finger ends.
struct BlockPartyTabBar: View {
    let selection: Tab
    /// Tap handler — the parent owns the page slide and the haptic, and ignores a
    /// release on the tab that is already selected.
    var onSelect: (Tab) -> Void
    /// The signed-in neighbour's photo for the You tab; nil draws the person icon.
    var avatarURL: String? = nil
    /// The feed is reading down (its top bar is away): the bar rests small. A touch
    /// brings it back to full size while the finger is down.
    var compact = false
    /// A new friend request: the quiet yellow dot on the Friends tab (`FriendsBook.dot`), as
    /// it sat on the Town bar's friends mark until 2026-11-01.
    var friendsDot = false
    /// What VoiceOver reads for Friends when the dot says something.
    var friendsLabel: String? = nil

    /// The finger while it is down, capsule-local. `@GestureState` resets itself
    /// when the system cancels the touch, so the Lens can never stay stuck up.
    @GestureState private var touch: Touch?
    /// After the finger lifts, the Lens keeps its look until the bubble lands, as
    /// Apple's does: to the end of a tap's travel, or a short collapse after a drag.
    @State private var landing = false
    @State private var landingTask: Task<Void, Never>?
    /// Taps on Daily, each one a hop of its ! (`DailyMarkGlyph`).
    @State private var dailyHops = 0
    /// Taps on Search, each one a swoop of the magnifier's shine (`MagnifierGlyph`).
    @State private var searchSwoops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Touch: Equatable {
        var x: CGFloat
        /// Past the first 4pt of travel (GUESSED threshold) the Lens tracks the
        /// finger tightly; before that, it springs over from the selected tab.
        var moved: Bool
    }

    var body: some View {
        GeometryReader { capsule in
            let width = capsule.size.width
            // Reduce Motion: no Lens, no growth, no magnification, no swell; a change
            // crossfades the bubble (see `BubbleGeometry`).
            let lens = reduceMotion ? nil : touch
            let held = lens != nil || (landing && !reduceMotion)
            let bubbleX = lens.map { TabBarMetric.lensCentreX(fingerX: $0.x, capsuleWidth: width) }
                ?? TabBarMetric.centreX(of: selection, capsuleWidth: width)
            let geometry = BubbleGeometry(x: bubbleX,
                                          size: TabBarMetric.bubbleSize(capsuleWidth: width, held: held),
                                          held: held, following: lens?.moved == true,
                                          selection: selection, reduceMotion: reduceMotion)
            ZStack(alignment: .topLeading) {
                // Under a finger the grey bubble gives way to a clear glass Lens, as
                // Instagram's does. The glass is placed straight at the finger, never
                // animated there (glass draws at its final position), and swapped with
                // the bubble in one frame, never faded. It stays mounted at zero size
                // between touches: inserted fresh, it drew two frames late and left
                // the touch-down with neither Lens nor bubble (eyes sim, 2026-09-27).
                bubble
                    .modifier(geometry)
                    .opacity(lens == nil ? 1 : 0)
                    .animation(nil, value: lens == nil)
                lensGlass
                    .frame(width: lens == nil ? 0 : geometry.size.width,
                           height: lens == nil ? 0 : geometry.size.height)
                    .position(x: bubbleX, y: TabBarMetric.height / 2)
                    .transaction { $0.animation = nil }
                Items(selection: selection, capsuleWidth: width, onSelect: onSelect,
                      avatarURL: avatarURL, lensX: lens == nil ? nil : bubbleX, dailyHops: dailyHops,
                      searchSwoops: searchSwoops, friendsDot: friendsDot, friendsLabel: friendsLabel)
            }
            .contentShape(Rectangle())
            .gesture(
                // Read in screen space and mapped onto the bar at its PRESSED size. In
                // the bar's own space a still finger kept the x it touched down at on
                // the shrunk bar, so the Lens slid off the finger as the bar grew
                // back (review, 2026-09-27). The bar scales about its centre, so its
                // centre is the same at any scale.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($touch) { value, state, _ in
                        state = Touch(x: pressedX(value.location.x, capsule: capsule),
                                      moved: state?.moved == true || abs(value.translation.width) > 4)
                    }
                    .onEnded { value in
                        land(after: abs(value.translation.width) > 4
                             ? TabBarMetric.collapseAfterDrag : TabBarMetric.landingAfterTap)
                        let tab = TabBarMetric.tab(atX: pressedX(value.location.x, capsule: capsule),
                                                   capsuleWidth: width)
                        // Every tap on Daily hops its !, and every tap on Search swoops
                        // its shine, already-picked included.
                        if tab == .blockParty && !reduceMotion { dailyHops += 1 }
                        if tab == .search && !reduceMotion { searchSwoops += 1 }
                        onSelect(tab)
                    }
            )
        }
        .frame(height: TabBarMetric.height)
        // Real Liquid Glass, untinted: near-white over paper, mid-grey over dark
        // photos — the same response the Reference measures (§1.6, §1.13).
        // Interactive, Apple's own pressed look: Instagram's bar lightens under a
        // finger (206–239 over a near-black photo, against 192 at rest; MEASURED).
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        // Keeps the glass in its LIGHT state. Over a near-black feed card the glass
        // flipped to its dark state (measured 2026-09-26, Town at
        // `-feed-scrolled-y 1200`: glass 23/255, ink invisible), and no colour-scheme
        // pin stopped it. A white layer BEHIND the glass lifts what it samples: at
        // 20% it still flipped (40/255), at 30% it held (178/255). It sits at 30%, the
        // value that held, to match Instagram's grey (`TabBarMetric.glassUnderlay`).
        // Pressed, it thickens: the interactive glass alone lightened the bar only
        // +13 (198 → 211), the bottom of Instagram's +14 to +47.
        .background {
            Capsule(style: .continuous)
                .fill(Hue.surface.onLightCanvas.opacity(touch != nil && !reduceMotion
                    ? TabBarMetric.pressedUnderlay : TabBarMetric.glassUnderlay))
                .animation(reduceMotion ? nil : TabBarMetric.growth, value: touch != nil)
                .allowsHitTesting(false)
        }
        // The Reference's brighter 1pt rim (§1.9: +60–75 over the glass). Opacity
        // tuned on the eyes sim: 0.6 read +56 over the dark card.
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Hue.surface.onLightCanvas.opacity(0.75), lineWidth: 1)
                .allowsHitTesting(false)
        }
        // No hand-made swell: the interactive glass swells the bar itself, and the
        // two together pressed it to ~1.08x, past Instagram's 1.044x (eyes sim).
        // Instagram's shrink while reading down, around the bar's own centre. A
        // finger on the bar (or its landing) holds it at full size. Under Reduce
        // Motion it still shrinks, without the spring.
        .scaleEffect(compact && touch == nil && !landing ? TabBarMetric.compactScale : 1)
        .animation(reduceMotion ? nil : TabBarMetric.compaction, value: compact && touch == nil && !landing)
        .padding(.horizontal, TabBarMetric.margin)
    }

    /// A finger's screen x, in capsule points on the bar at its pressed size (the
    /// swell; 1x under Reduce Motion, which has none).
    private func pressedX(_ screenX: CGFloat, capsule: GeometryProxy) -> CGFloat {
        let scale = reduceMotion ? 1 : TabBarMetric.swell
        return capsule.size.width / 2 + (screenX - capsule.frame(in: .global).midX) / scale
    }

    private func land(after delay: Duration) {
        guard !reduceMotion else { return }
        landingTask?.cancel()
        landing = true
        landingTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            landing = false
        }
    }

    /// The Selection bubble: translucent black at Instagram's measured shade
    /// (`TabBarMetric.bubbleShade`). It does all the sliding; under a finger the
    /// glass Lens stands in for it (`lensGlass`).
    private var bubble: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(TabBarMetric.bubbleShade))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The held Lens: real Liquid Glass on the same white layer as the bar, so it
    /// reads lighter than the bar and cannot flip dark over a dark photo either.
    private var lensGlass: some View {
        Capsule(style: .continuous)
            .fill(Hue.surface.onLightCanvas.opacity(TabBarMetric.glassUnderlay))
            .glassEffect(.regular, in: Capsule(style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Where the bubble is and how it moves. Size and look ride the measured growth
    /// spring; position rides the travel spring (or tracks the finger). Scoped this
    /// way because one `.animation` over both let the travel spring win the growth.
    struct BubbleGeometry: ViewModifier {
        var x: CGFloat
        var size: CGSize
        var held: Bool
        var following: Bool
        var selection: Tab
        var reduceMotion: Bool

        func body(content: Content) -> some View {
            if reduceMotion {
                // No travel: the old bubble fades out where it was and the new one
                // fades in, on the parent's 0.2s ease.
                content
                    .frame(width: size.width, height: size.height)
                    .position(x: x, y: TabBarMetric.height / 2)
                    .id(selection)
                    .transition(.opacity)
            } else {
                content
                    .frame(width: size.width, height: size.height)
                    .animation(TabBarMetric.growth, value: held)
                    .position(x: x, y: TabBarMetric.height / 2)
                    .animation(following ? TabBarMetric.growth : TabBarMetric.travel, value: x)
            }
        }
    }

    /// The five items, placed from `TabBarMetric`. No glass, so a test can render
    /// them alone.
    struct Items: View {
        let selection: Tab
        let capsuleWidth: CGFloat
        var onSelect: (Tab) -> Void
        /// The signed-in neighbour's photo, drawn on the You tab in place of its icon.
        var avatarURL: String? = nil
        /// The Lens centre while held; icons near it magnify.
        var lensX: CGFloat? = nil
        /// Taps on Daily so far; each one hops the Bp!'s !.
        var dailyHops = 0
        /// Taps on Search so far; each one swoops the magnifier's shine.
        var searchSwoops = 0
        /// A new friend request's dot on the Friends icon.
        var friendsDot = false
        var friendsLabel: String? = nil
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack(alignment: .topLeading) {
                // Instagram's bar: icons only, all one ink, the selected one filled.
                // Ink is the LIGHT-canvas value, fixed: glass that flips hands its
                // items a dark trait, and adaptive `Hue.ink` then drew white
                // (measured 2026-09-26).
                ForEach(Tab.allCases) { tab in
                    icon(tab)
                        .scaleEffect(magnification(tab))
                        .position(x: centreX(tab), y: TabBarMetric.iconCentreY)
                }
                .animation(TabBarMetric.growth, value: lensX)
                .accessibilityHidden(true)
                // Frozen chrome owes the reader another way in: the glyph never
                // grows, so a long press at an accessibility text size has to
                // enlarge it (docs/rules/architecture.md).
                ForEach(Tab.allCases) { tab in
                    Color.clear
                        .frame(width: TabBarMetric.pitch(capsuleWidth: capsuleWidth), height: TabBarMetric.height)
                        .contentShape(Rectangle())
                        .accessibilityShowsLargeContentViewer {
                            if tab == .blockParty {
                                Label(tab.title, image: tab.symbol)
                            } else {
                                Label(tab.title, systemImage: selection == tab ? tab.selectedSymbol : tab.symbol)
                            }
                        }
                        .position(x: centreX(tab), y: TabBarMetric.height / 2)
                }
            }
            .frame(width: capsuleWidth, height: TabBarMetric.height, alignment: .topLeading)
            // VoiceOver sees exactly five tabs, named, not the drawing: the tab
            // elements are synthetic children laid over the slots.
            .accessibilityChildren {
                ZStack(alignment: .topLeading) {
                    ForEach(Tab.allCases) { tab in
                        accessibilityElement(tab)
                    }
                }
                .frame(width: capsuleWidth, height: TabBarMetric.height, alignment: .topLeading)
            }
            .accessibilityAddTraits(.isTabBar)
        }

        @ViewBuilder
        private func icon(_ tab: Tab) -> some View {
            let selected = selection == tab
            if tab == .you, let avatarURL {
                TabAvatar(url: avatarURL, selected: selected)
            } else {
                symbol(tab, selected: selected)
                    // Outside the symbol's no-animation transaction, so the dot grows in.
                    .overlay(alignment: .topTrailing) {
                        if tab == .friends, friendsDot {
                            UnreadDot(ring: Hue.surface.onLightCanvas,
                                      inkRight: TabBarMetric.friendsInkRight, inkTop: TabBarMetric.friendsInkTop)
                        }
                    }
                    .animation(reduceMotion ? nil : Motion.smooth, value: friendsDot)
            }
        }

        private func symbol(_ tab: Tab, selected: Bool) -> some View {
            Group {
                if tab == .search {
                    MagnifierGlyph(size: TabBarMetric.searchGlyphSize, bold: selected, swoops: searchSwoops)
                } else if tab == .town {
                    HouseGlyph(filled: selected)
                } else if tab == .blockParty {
                    DailyMarkGlyph(hops: dailyHops)
                        .frame(width: TabBarMetric.dailyMarkWidth)
                        // The launch's Bp! lands here: hidden till it does (`LaunchBall`).
                        .launchLanding()
                } else {
                    Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                        .font(.glyph(TabBarMetric.iconSize))
                }
            }
            .foregroundStyle(Hue.ink.onLightCanvas)
            // Swapped, not crossfaded: under the tab switch's spring the outline
            // and the filled symbol blended into a grey blob for ~3 frames, and
            // `.contentTransition(.identity)` did not stop it.
            .transaction { $0.animation = nil }
        }

        /// One VoiceOver element per tab, over its slot, with the tab's action.
        private func accessibilityElement(_ tab: Tab) -> some View {
            let selected = selection == tab
            return Color.clear
                .frame(width: TabBarMetric.pitch(capsuleWidth: capsuleWidth), height: TabBarMetric.height)
                .position(x: centreX(tab), y: TabBarMetric.height / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tab == .friends ? friendsLabel ?? tab.title : tab.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onSelect(tab) }
        }

        private func centreX(_ tab: Tab) -> CGFloat {
            TabBarMetric.centreX(of: tab, capsuleWidth: capsuleWidth)
        }

        private func magnification(_ tab: Tab) -> CGFloat {
            guard let lensX else { return 1 }
            return TabBarMetric.magnification(itemX: centreX(tab), lensX: lensX, capsuleWidth: capsuleWidth)
        }
    }
}

/// The You tab's photo, as Instagram's profile tab draws it: a plain circle, with an ink ring when
/// selected (GUESSED ring: the recording never selects that tab). Without a photo the tab keeps the
/// person icon, ink like every icon (taste.md 2026-09-27).
private struct TabAvatar: View {
    let url: String
    let selected: Bool

    var body: some View {
        Avatar(avatarUrl: url, size: TabBarMetric.avatarSize)
            .padding(3)
            .overlay {
                if selected {
                    Circle().strokeBorder(Hue.ink.onLightCanvas, lineWidth: 1.5)
                }
            }
    }
}

/// The Town feed's "reading down" signal, carried up to the shell so the tab bar can
/// shrink with the top bar. Absent (false) on every other tab.
struct TabBarCompactKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// What a reserved tab shows until its screen is built: the slot's name and the one
/// line describing what will live there. Deliberately quiet — a named, empty room
/// reads as reserved, where a bare screen reads as broken.
struct BlankTab: View {
    let tab: Tab

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(tab.title)
                    .font(.display(22))
                    .foregroundStyle(Hue.ink)
                Text(tab.promise)
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
