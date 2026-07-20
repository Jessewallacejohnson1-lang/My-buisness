//
//  ExploreKit.swift
//  Block Party — the AllTrails-style "Explore" building blocks: a photo-card shell,
//  a coral metadata row, a saved-bookmark toggle, and shared press/appear motion.
//
//  White surface with ink active states. Reused by ActivitiesView.
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

/// The viewer's personal saved list — local to the device, persisted in
/// UserDefaults. Not a backend count (nothing inflated), just this user's marks.
@MainActor
final class SavedStore: ObservableObject {
    static let shared = SavedStore()
    @Published private(set) var ids: Set<String>
    private let key = "hygge.saved.ids"

    private init() { ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    func isSaved(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

/// The floating bookmark on a card photo. Coral fill when saved, ink when not.
struct SaveBookmarkButton: View {
    let id: String
    @ObservedObject private var store = SavedStore.shared

    var body: some View {
        let saved = store.isSaved(id)
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) { store.toggle(id) }
        } label: {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(saved ? Hue.ink : Hue.ink)
                .symbolEffect(.bounce, value: saved)
                .frame(width: 38, height: 38)
                .background(Hue.surface)
                .clipShape(Circle())
                .mapFloatShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "Remove from saved" : "Save for later")
    }
}

// MARK: - Metadata row (the "★ rating · Moderate · 5.8 mi" line, with real data)

/// One dot-separated fact on a card. The first item usually leads in coral.
struct MetaItem: Identifiable {
    let id = UUID()
    let icon: String?
    let text: String
    var coral: Bool = false
}

/// A coral-led, dot-separated metadata line. Numbers are mono per the type rules.
@ViewBuilder
func exploreMetaRow(_ items: [MetaItem]) -> some View {
    HStack(spacing: 7) {
        ForEach(Array(items.enumerated()), id: \.offset) { i, m in
            if i > 0 {
                Text("·").font(.mono(12)).foregroundStyle(Hue.inkSecondary)
            }
            HStack(spacing: 4) {
                if let ic = m.icon {
                    Image(systemName: ic).font(.system(size: 11, weight: .semibold))
                }
                Text(m.text).font(.monoMedium(12)).monospacedDigit()
            }
            .foregroundStyle(m.coral ? Hue.ink : Hue.inkSecondary)
            .lineLimit(1)
        }
    }
}

/// The small circular action beside a card title (invite / join / directions).
/// Coral outline by default; a filled coral disc for the "on" state.
@ViewBuilder
func exploreCircleIcon(_ system: String, filled: Bool = false) -> some View {
    Image(systemName: system)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(filled ? .white : Hue.ink)
        .frame(width: 40, height: 40)
        .background(filled ? Hue.ink : Hue.surface)
        .clipShape(Circle())
        .overlay(Circle().stroke(filled ? Color.clear : Hue.ink.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        .contentTransition(.symbolEffect(.replace))
}

// MARK: - Photo slot

/// The empty image area for a card with no photo yet: a neutral block mark that
/// inherits each real photo slot's exact frame and clipping from its caller.
struct ExploreBlankPhoto: View {
    var body: some View {
        ZStack {
            Hue.fill
            Image(systemName: "square.on.square")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Hue.inkSecondary)
        }
    }
}

// MARK: - Card shell

/// The AllTrails card: a rounded photo (with the bookmark floating on it), then
/// a title + trailing action, a location subtitle, and the coral metadata row —
/// all sitting on the white page, no border.
struct ExploreCard<Photo: View, Trailing: View>: View {
    let id: String
    let title: String
    let subtitle: String?
    let meta: [MetaItem]
    @ViewBuilder var photo: () -> Photo
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack(alignment: .topTrailing) {
                photo()
                    .frame(maxWidth: .infinity)
                    .frame(height: 172)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                SaveBookmarkButton(id: id).padding(11)
            }

            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.sansBold(18))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                trailing()
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineLimit(1)
            }

            if !meta.isEmpty { exploreMetaRow(meta) }
        }
    }
}
