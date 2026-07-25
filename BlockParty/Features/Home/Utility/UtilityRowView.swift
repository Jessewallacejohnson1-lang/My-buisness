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
    @Published var showCustomize = false

    let registry: UtilityTileRegistry
    let prefs: UtilityPrefsStore

    private var subscriptions: [UtilityTileID: UtilitySubscription] = [:]
    private var prefsObserver: AnyCancellable?
    private var started = false
    #if DEBUG
    private var debugForceEmpty = false
    #endif

    init(registry: UtilityTileRegistry? = nil) {
        let reg = registry ?? UtilityTileRegistry()
        self.registry = reg
        self.prefs = UtilityPrefsStore(knownIDs: reg.knownIDs)
        // Re-publish when the nested prefs store changes so the row + its first-run
        // affordances update after hydrate / save.
        prefsObserver = prefs.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// Enabled tiles, in order (from the UserDefaults mirror instantly, then the
    /// server row after `hydrate`).
    var tiles: [UtilityTileID] {
        #if DEBUG
        if debugForceEmpty { return [] }
        #endif
        return prefs.tiles
    }

    /// First-run affordances: the trailing "Customize" tile shows on first run
    /// AND whenever zero tiles are enabled (the row never dead-ends). The caption
    /// shows only until the first save.
    var showCustomizeTile: Bool { !prefs.hasSavedOnce || tiles.isEmpty }
    var showCaption: Bool { !prefs.hasSavedOnce }

    /// Persist a customize-sheet draft, then reconcile fetches + subscriptions.
    func applyDraft(order: [UtilityTileID], enabled: Set<UtilityTileID>,
                    settings: [UtilityTileID: TileSettings]) async {
        let tiles = order.filter { enabled.contains($0) }
        await prefs.save(tiles: tiles, settings: settings)
        for id in Array(states.keys) where !enabled.contains(id) { states[id] = nil }
        reconcileSubscriptions()
        refreshEnabled()        // re-fetch enabled tiles (settings may have changed)
        openSubscriptions()
    }

    func start() async {
        guard !started else { return }
        started = true
        refreshEnabled()            // instant, on the mirrored/default set
        openSubscriptions()
        await prefs.hydrate()       // reconcile from Supabase (may reorder / re-enable)
        // teardown() (or a new start()) may have run during the hydrate network
        // round-trip; if the lifecycle moved on, bail so we don't resurrect a
        // subscription that teardown just cancelled (orphaned RealtimeClient leak).
        guard started, !Task.isCancelled else { return }
        reconcileSubscriptions()    // drop subs for tiles hydrate disabled
        refreshEnabled()            // fetch any newly-enabled tiles
        openSubscriptions()         // subscribe any new live tiles (idempotent)

        #if DEBUG
        // Headless verification hooks.
        if ProcessInfo.processInfo.arguments.contains("-utility-expand") {
            expanded = prefs.tiles.first
        }
        if ProcessInfo.processInfo.arguments.contains("-utility-customize") {
            showCustomize = true
        }
        if ProcessInfo.processInfo.arguments.contains("-utility-empty") {
            debugForceEmpty = true
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

    /// Cancel + drop subscriptions for tiles no longer enabled.
    private func reconcileSubscriptions() {
        let enabled = Set(prefs.tiles)
        for (id, sub) in subscriptions where !enabled.contains(id) {
            sub.cancel(); subscriptions[id] = nil
        }
    }
}

struct UtilityRowView: View {
    @StateObject private var model = UtilityRowModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                            .contextMenu {   // long-press → open the customize sheet
                                Button { model.showCustomize = true } label: {
                                    Label("Customize row…", systemImage: "slider.horizontal.3")
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                        }
                    }
                    // Trailing "Customize" tile — first run, and whenever zero tiles
                    // are enabled (the row never dead-ends).
                    if model.showCustomizeTile {
                        UtilityCustomizeTile { model.showCustomize = true }
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 18)   // standard tab gutter; last tile peeks past the edge
                .padding(.vertical, 10)      // room for the tile shadows inside the scroll content
            }
            // Same spring as the Calendar bento's expand/collapse.
            .animation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.82), value: model.expanded)
            // Row re-animates on a save: removed tiles fade+scale, added slide in.
            .animation(reduceMotion ? nil : Motion.sheet, value: model.tiles)

            // One-time caption; disappears permanently after the first save.
            if model.showCaption {
                Text("Tap to choose what shows here.")
                    .font(.sans(12))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, 18)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.sheet, value: model.showCustomizeTile)
        .animation(reduceMotion ? nil : Motion.sheet, value: model.showCaption)
        .sheet(isPresented: $model.showCustomize) {
            UtilityCustomizeSheet(model: model)
        }
        .task { await model.start() }
        .onDisappear { model.teardown() }
    }
}

/// The trailing neutral "Customize" tile (plus glyph + label).
struct UtilityCustomizeTile: View {
    let onTap: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("Customize")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: UtilityTileMetrics.width, height: UtilityTileMetrics.compactH)
        .background(
            LinearGradient(colors: UtilityTileGradient.customize.map { Color(hex: $0) },
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: UtilityTileMetrics.corner, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: UtilityTileMetrics.corner, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement()
        .accessibilityLabel("Customize your quick info")
        .accessibilityAddTraits(.isButton)
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
