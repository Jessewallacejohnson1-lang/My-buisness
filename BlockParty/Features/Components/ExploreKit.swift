//
//  ExploreKit.swift
//  Block Party — the bookmark glyph and button, and the
//  phone's old saved list (only read once, to move it up to the server).
//

import SwiftUI
import Combine

// MARK: - Saved (bookmark) state

/// The saves this phone kept in UserDefaults before saves lived on the server
/// (`RealLifeActions`). They move up once (`RealLifeActions.moveUp`) and leave this list;
/// nothing adds to it now.
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
        .buttonStyle(.press(.squish))
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .accessibilityLabel(saved ? "Remove from saved" : "Save for later")
        .signInSheet(isPresented: $signInShown)
        // On screen: a save that fails may shake here.
        .onAppear { actions.bookmarkOpened(item.id) }
        .onDisappear { actions.bookmarkClosed(item.id) }
    }
}
