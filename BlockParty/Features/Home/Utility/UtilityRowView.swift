//
//  UtilityRowView.swift
//  Block Party — the Today "Utility Row": a horizontal, full-bleed scroll of
//  glanceable box-tiles rendered PURELY from the registry + the user's prefs.
//  Sits below the almanac, above the feed. Tiles tap-EXPAND in place.
//

import SwiftUI
import Combine

@MainActor
final class UtilityRowModel: ObservableObject {
    @Published private(set) var states: [UtilityTileID: UtilityTileState] = [:]
    @Published var expanded: UtilityTileID?

    let registry: UtilityTileRegistry
    let prefs: UtilityPrefsStore

    private var subscriptions: [UtilityTileID: UtilitySubscription] = [:]
    private var started = false

    init(registry: UtilityTileRegistry? = nil) {
        let reg = registry ?? UtilityTileRegistry()
        self.registry = reg
        self.prefs = UtilityPrefsStore(knownIDs: reg.knownIDs)
    }

    /// Enabled tiles, in order (from the UserDefaults mirror instantly, then the
    /// server row after `hydrate`).
    var tiles: [UtilityTileID] { prefs.tiles }

    func start() async {
        guard !started else { return }
        started = true
        refreshEnabled()            // instant, on the mirrored/default set
        openSubscriptions()
        await prefs.hydrate()       // reconcile from Supabase (may reorder / re-enable)
        refreshEnabled()            // fetch any newly-enabled tiles
        openSubscriptions()         // subscribe any new live tiles (idempotent)

        #if DEBUG
        // Headless verification of the expanded state (see -utility-expand).
        if ProcessInfo.processInfo.arguments.contains("-utility-expand") {
            expanded = prefs.tiles.first
        }
        #endif
    }

    func teardown() {
        for sub in subscriptions.values { sub.cancel() }
        subscriptions.removeAll()
        started = false
    }

    func toggleExpand(_ id: UtilityTileID) {
        expanded = (expanded == id) ? nil : id
    }

    func staleAfter(_ id: UtilityTileID) -> TimeInterval? {
        registry.descriptor(id)?.provider.refreshPolicy.staleAfter
    }

    // MARK: - Private

    private func refreshEnabled() {
        for id in prefs.tiles where states[id] == nil { states[id] = .loading }
        for id in prefs.tiles { Task { await refresh(id) } }
    }

    private func refresh(_ id: UtilityTileID) async {
        guard let descriptor = registry.descriptor(id) else { return }
        let settings = prefs.settings[id] ?? TileSettings()
        do {
            states[id] = .loaded(try await descriptor.provider.fetch(settings: settings))
        } catch {
            // Keep the last good value if we have one (airplane mode); else fail cleanly.
            if case .loaded = states[id] ?? .loading { return }
            states[id] = .failed
        }
    }

    private func openSubscriptions() {
        for id in prefs.tiles {
            guard subscriptions[id] == nil, let descriptor = registry.descriptor(id) else { continue }
            let settings = prefs.settings[id] ?? TileSettings()
            if let sub = descriptor.provider.subscribe(settings: settings, onChange: { [weak self] in
                Task { await self?.refresh(id) }
            }) {
                subscriptions[id] = sub
            }
        }
    }
}

struct UtilityRowView: View {
    @StateObject private var model = UtilityRowModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: UtilityTileMetrics.gap) {
                ForEach(model.tiles, id: \.self) { id in
                    if let descriptor = model.registry.descriptor(id) {
                        UtilityTileView(
                            descriptor: descriptor,
                            state: model.states[id] ?? .loading,
                            isExpanded: model.expanded == id,
                            staleAfter: model.staleAfter(id),
                            onTap: { model.toggleExpand(id) }
                        )
                    }
                }
            }
            .padding(.horizontal, 18)   // standard tab gutter; last tile peeks past the edge
            .padding(.vertical, 10)      // room for the tile shadows inside the scroll content
        }
        // Same spring as the Calendar bento's expand/collapse.
        .animation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.82), value: model.expanded)
        .task { await model.start() }
        .onDisappear { model.teardown() }
    }
}

#if DEBUG
/// Full-screen headless preview of the Utility Row (RootView `-utility-row-preview`).
struct UtilityRowPreview: View {
    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Utility Row")
                    .font(.mono(11)).tracking(1.5)
                    .foregroundStyle(Hue.inkSecondary)
                UtilityRowView()
            }
        }
    }
}
#endif
