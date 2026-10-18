//
//  ExploreKit.swift
//  Block Party — shared press/appear motion, the bookmark glyph and button, and the
//  phone's old saved list (now the map's Places).
//

import SwiftUI
import Combine

// MARK: - Motion primitives

/// Card / control press feedback: a tap "pop". On the press-DOWN edge a one-shot
/// keyframe plays start-to-finish — scale in to `scale`, then spring back with a
/// tiny overshoot — so it reads even on a fast tap (a plain scale-while-held barely
/// shows when the finger is down for a fraction of a second). `haptic: true` adds a
/// light tick on press-down for button-like controls; content rows/cards leave it
/// off. Honors Reduce Motion (no scale; the haptic still fires).
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var haptic: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Pop(label: configuration.label,
            isPressed: configuration.isPressed,
            restingScale: scale,
            haptic: haptic)
    }

    /// The trigger-driven pop. A per-press counter (bumped on the down edge) drives a
    /// keyframe timeline that always runs to completion, independent of hold duration.
    private struct Pop<Label: View>: View {
        let label: Label
        let isPressed: Bool
        let restingScale: CGFloat
        let haptic: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var taps = 0

        var body: some View {
            // Press in to `target`, then overshoot ABOVE 100% before settling. The
            // explicit overshoot is what makes the pop read even when the press-in is
            // shallow (a 0.97 scale alone is ~1px and invisible); the bounce past 1.0
            // is the satisfying "click". Reduce Motion flattens the whole track.
            let target: CGFloat = reduceMotion ? 1 : restingScale
            let peak: CGFloat = reduceMotion ? 1 : 1.05
            label
                .keyframeAnimator(initialValue: CGFloat(1), trigger: taps) { view, s in
                    view.scaleEffect(s)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(target, duration: 0.10)   // press in
                        CubicKeyframe(peak, duration: 0.13)     // overshoot past 100%
                        SpringKeyframe(CGFloat(1), duration: 0.30, spring: Spring(duration: 0.30, bounce: 0.26))
                    }
                }
                .onChange(of: isPressed) { _, pressed in
                    guard pressed else { return }
                    if haptic { Haptics.light() }
                    taps &+= 1
                }
        }
    }
}

/// Staggered fade-and-rise as feed items mount. Honors Reduce Motion (instant).
private struct AppearStagger: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true; return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)
                    .delay(Double(min(index, 8)) * 0.05)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Fade+rise in, delayed by list position. Cap the visible stagger at ~8 items.
    func appearStagger(_ index: Int) -> some View { modifier(AppearStagger(index: index)) }
}

/// A staggered "pop": each item scales up from just-below-full with a fade, one
/// after another — the Wolt Discovery entrance where the category row lands one
/// tile at a time, left → right. Distinct from
/// `appearStagger` (a whole-section fade+rise): this is per-item and *scales*, so
/// each element reads as its own little pop instead of the row sliding up as one.
///
/// Craft notes (Emil Kowalski's framework, same as SpringReveal):
///   • Never from scale(0) — starts at 0.80 + a small rise + opacity so nothing
///     pops from nothing but the grow-in still reads clearly.
///   • Deliberately MORE pronounced than the Wolt reference (which is a quiet
///     scale+fade): a bigger scale delta, a short rise, and a real spring bounce
///     (overshoot past 1.0) make each tile visibly *pop*, and a slightly wider
///     ~85ms stagger lets the eye catch them landing one at a time.
///   • `base` holds the cascade a beat after the screen lands, so it plays on a
///     settled screen instead of being swallowed by the tab-slide / splash-dismiss.
///   • Only transform + opacity animate — GPU-friendly, no layout thrash.
///   • Reduce Motion drops the movement to a gentle crossfade (comprehension, no pop).
private struct PopIn: ViewModifier {
    let index: Int
    /// Shifts the whole cascade later, e.g. to begin just after the screen settles.
    var base: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    // Left-to-right cascade — wider ~85ms spacing so each tile's pop is distinct;
    // cap so a long row never drags.
    private var delay: Double { base + Double(min(index, 8)) * 0.085 }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.80, anchor: .center)
            .offset(y: shown || reduceMotion ? 0 : 9)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.22)) { shown = true }
                    return
                }
                // A real bounce (overshoot past 1.0) is what makes the pop pop —
                // bounce 0.38 stays playful without looking toylike.
                withAnimation(.spring(duration: 0.42, bounce: 0.38).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Pop each item in one at a time — scale-up (0.85→1 with a hair of overshoot)
    /// + fade, delayed by list position. `base` shifts the cascade start later.
    func popIn(_ index: Int, base: Double = 0) -> some View {
        modifier(PopIn(index: index, base: base))
    }
}

// MARK: - Saved (bookmark) state

/// The viewer's saved list on this phone, persisted in UserDefaults: the map's Places
/// (pin sheet, pin badges). Event saves live on the server (`RealLifeActions`); ones
/// made here before that move up once (`RealLifeActions.moveUp`) and leave this list.
@MainActor
final class SavedStore: ObservableObject {
    static let shared = SavedStore()
    @Published private(set) var ids: Set<String>
    let key: String

    /// `key` other than the phone's own is for tests.
    init(key: String = "bp.saved.ids") {
        self.key = key
        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func isSaved(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    func remove(_ id: String) {
        guard ids.remove(id) != nil else { return }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    /// The Event saves on this phone have moved up to the server (`RealLifeActions.moveUp`).
    var movedUp: Bool {
        get { UserDefaults.standard.bool(forKey: key + ".movedUp") }
        set { UserDefaults.standard.set(newValue, forKey: key + ".movedUp") }
    }
}

/// Every bookmark in the app: an outline, and when saved the brand yellow filling it
/// exactly, `Hue.brandDisc` #FCE804 (Jesse, 2026-09-27: every saved bookmark in BP,
/// on the feed cards, the event page, the map's pin sheet and pin badge, and
/// `SaveBookmarkButton`). The caller's font sizes it and the caller's foreground
/// style inks the outline; the fill always keeps its own yellow.
struct BookmarkGlyph: View {
    let saved: Bool

    /// Pulls the fill's edge about half a stroke in at every size the app draws
    /// (7 to 24 pt), still under the outline, never short of it.
    private static let fillScale: CGFloat = 0.9

    var body: some View {
        ZStack {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Hue.brandDisc)
                // A touch smaller than the outline, so the fill's soft edge stays under
                // the stroke. Full size, it showed as a device pixel of olive outside the
                // ink (112,107,52 on the event page, measured 2026-09-27).
                .scaleEffect(Self.fillScale)
                .opacity(saved ? 1 : 0)
            Image(systemName: "bookmark")
        }
        // One layer, so a shadow the caller puts on it falls under the whole mark. Per
        // layer, the pin sheet bar's shadow of the outline landed on the fill and dulled
        // #FCE804 to #F9E504 (measured 2026-09-27).
        .compositingGroup()
    }
}

/// The floating bookmark on a card photo: an ink outline, brand yellow inside when saved,
/// in a white circle the size of Airbnb's heart on its cards (Daily's Suggestions,
/// measured 2026-10-05). The tap area around it is 44pt. Saved is the shared one
/// (`RealLifeActions`); with no account yet, a tap opens sign in.
struct SaveBookmarkButton: View {
    let item: FeedCardItem
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var signInShown = false
    /// `actions.saveFailureCount` at the last tap: a tap mid-shake stills it.
    @State private var tappedAt = 0

    var body: some View {
        let saved = actions.saved(item)
        let failures = actions.saveFailureCount(item.id)
        Button {
            guard actions.canAct else { signInShown = true; return }
            tappedAt = failures
            withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) { actions.toggleSave(item) }
        } label: {
            BookmarkGlyph(saved: saved)
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.ink)
                .symbolEffect(.bounce, value: saved)
                .frame(width: 28, height: 28)
                .background(Hue.surface)
                .clipShape(Circle())
                .mapFloatShadow()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // It squishes like the event page's save, not fades (taste.md: press).
        .buttonStyle(FeedCardJoinPressStyle(reduceMotion: reduceMotion))
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .accessibilityLabel(saved ? "Remove from saved" : "Save for later")
        .signInSheet(isPresented: $signInShown)
        // On screen: a save that fails may shake here.
        .onAppear { actions.bookmarkOpened(item.id) }
        .onDisappear { actions.bookmarkClosed(item.id) }
    }
}
