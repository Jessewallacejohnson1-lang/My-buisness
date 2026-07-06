//
//  ExploreKit.swift
//  Hygge — the AllTrails-style "Explore" building blocks: a photo-card shell,
//  a coral metadata row, a saved-bookmark toggle, and shared press/appear motion.
//
//  White surface, coral (Hue.accent) as the one accent. Reused by ActivitiesView.
//

import SwiftUI
import Combine

// MARK: - Motion primitives

/// Card / control press feedback: a subtle spring scale-down while held.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
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
                .foregroundStyle(saved ? Hue.accent : Hue.mapInk)
                .symbolEffect(.bounce, value: saved)
                .frame(width: 38, height: 38)
                .background(Hue.surface)
                .clipShape(Circle())
                .mapFloatShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "Saved" : "Save")
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
                Text("·").font(.mono(12)).foregroundStyle(Hue.grayLight)
            }
            HStack(spacing: 4) {
                if let ic = m.icon {
                    Image(systemName: ic).font(.system(size: 11, weight: .semibold))
                }
                Text(m.text).font(.monoMedium(12)).monospacedDigit()
            }
            .foregroundStyle(m.coral ? Hue.accent : Hue.gray)
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
        .foregroundStyle(filled ? .white : Hue.accent)
        .frame(width: 40, height: 40)
        .background(filled ? Hue.accent : Hue.surface)
        .clipShape(Circle())
        .overlay(Circle().stroke(filled ? Color.clear : Hue.accent.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        .contentTransition(.symbolEffect(.replace))
}

// MARK: - Photo slot

/// The empty image area for a card with no photo yet: a clean, faintly-coral
/// placeholder the user can drop a real photo into later.
struct ExploreBlankPhoto: View {
    var body: some View {
        ZStack {
            Hue.bgSubtle
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Hue.accent.opacity(0.3))
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
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                SaveBookmarkButton(id: id).padding(11)
            }

            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.sansBold(18))
                    .foregroundStyle(Hue.mapInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                trailing()
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.sans(14))
                    .foregroundStyle(Hue.gray)
                    .lineLimit(1)
            }

            if !meta.isEmpty { exploreMetaRow(meta) }
        }
    }
}
