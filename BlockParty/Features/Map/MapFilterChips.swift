//
//  MapFilterChips.swift
//  Block Party — the map's filter chip row (map polish Phase 4).
//
//  Five always-visible chips under the town pill — All · Food · Parks · Events ·
//  Saved — replacing the retired top-left `SpotFilter` Menu, whose four buckets
//  only ever touched the six curated spots. The chips span BOTH catalogs: the
//  curated civic spots AND the Supabase `places` POIs, and the filtered sets feed
//  `recomputeClusters`, so the cluster bubbles recount to what's visible.
//
//  Shape: 12pt rounded squares (`Radius.button`) — NEVER capsules (the brand's
//  button rule; the town pill beside them is the deliberate pill exception).
//  Rest = the same Liquid Glass as the chrome circles; SELECTED = a solid ink
//  disc with a white label, matching the cluster bubbles (black ink per the
//  approved plan — this overrides the accent's "active filter" seam here).
//

import SwiftUI

// MARK: - Filter semantics (pure, tested in MapFilterChipsTests)

/// What the map is filtered to. Pure predicates (`nonisolated` — the module
/// defaults to MainActor) so the semantics unit-test without a view; the caller
/// resolves liveness/saves and passes plain facts in.
nonisolated enum MapFilter: String, CaseIterable, Hashable {
    case all, food, parks, events, saved

    var title: String {
        switch self {
        case .all:    return "All"
        case .food:   return "Food"
        case .parks:  return "Parks"
        case .events: return "Events"
        case .saved:  return "Saved"
        }
    }

    /// Membership for a curated civic spot. `hasEventToday` is the same
    /// resolution the pins use — a real happening resolved to the spot today,
    /// or a live (possibly DEBUG-forced) state right now.
    func includesSpot(category: SpotCategory, hasEventToday: Bool, isSaved: Bool) -> Bool {
        switch self {
        case .all:
            return true
        case .food:
            // Pattern-match, not `==`: SpotCategory is MainActor-isolated by the
            // module default, so its synthesized Equatable can't be called here.
            if case .coffee = category { return true }
            return false
        case .parks:
            switch category {
            case .park, .trail: return true
            default:            return false
            }
        case .events:
            return hasEventToday
        case .saved:
            return isSaved
        }
    }

    /// Membership for a `places` POI. Parks and Events never include POIs:
    /// the POI catalog ships only the food/business families, and events
    /// resolve to curated pins only (SJMapView.spot(for:)).
    func includesPOI(family: PlaceFamily, isSaved: Bool) -> Bool {
        switch self {
        case .all:
            return true
        case .food:
            if case .food = family { return true }
            return false
        case .parks, .events:
            return false
        case .saved:
            return isSaved
        }
    }

    /// DEBUG-only: `-map-filter all|food|parks|events|saved` starts the map on
    /// a chip (mirrors `-explore-filter`) so every filtered state can be
    /// screenshotted headlessly. No effect in release / without the flag.
    static func initial() -> MapFilter {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-filter"), i + 1 < a.count,
           let f = MapFilter(rawValue: a[i + 1]) { return f }
        #endif
        return .all
    }

    /// The chips are one-tap filters, so the label spells the outcome out.
    var a11yLabel: String {
        switch self {
        case .all:    return "Show everything on the map"
        case .food:   return "Show food and drink"
        case .parks:  return "Show parks and trails"
        case .events: return "Show places with events today"
        case .saved:  return "Show saved places"
        }
    }
}

// MARK: - Chip row

/// The horizontal, scrollable chip row. A plain `ScrollView` of `Button`s —
/// deliberately no row-level gestures, so it can never compete with the map pan
/// (the repo's pan-competition rule). Selection state lives in `SJMapView`
/// (`@State var filter`), which owns the haptic + cluster recount on change.
struct MapFilterChips: View {
    @Binding var selection: MapFilter

    /// The selected chip matches the cluster bubbles, which sit on the SAME
    /// light cartography in both appearances — so like them it pins to the
    /// light-canvas ramp instead of following the system (see MonoMarkerPalette).
    private static let selectedFill = Hue.ink.onLightCanvas
    private static let selectedLabel = Hue.surface.onLightCanvas

    private static let chipShape = RoundedRectangle(cornerRadius: Radius.button,
                                                    style: .continuous)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // The tab shell wraps everything in GlassEffectContainer(spacing: 22),
            // whose field blend BRIDGES glass shapes sitting 8pt apart — the chips
            // fused into one blob (caught by screenshot). A nested tight container
            // re-scopes the blend so each chip keeps its own silhouette.
            GlassEffectContainer(spacing: 1) {
                HStack(spacing: 8) {
                    ForEach(MapFilter.allCases, id: \.self) { filter in
                        chip(filter)
                    }
                }
            }
            // The row bleeds edge-to-edge so chips scroll under the screen
            // margin; this inset aligns the resting row with the chrome's 16pt.
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter the map")
    }

    @ViewBuilder
    private func chip(_ filter: MapFilter) -> some View {
        let isSelected = selection == filter
        let label = Text(filter.title)
            .font(.sansSemibold(14))
            .foregroundStyle(isSelected ? Self.selectedLabel : Hue.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        Button {
            guard selection != filter else { return }
            selection = filter   // SJMapView's onChange ticks the haptic + recount
        } label: {
            // Same branch pattern as SJMapView.chromeCircle: glass at rest,
            // a solid fill (glass can't carry a solid ink) when selected.
            if isSelected {
                label
                    .background(Self.chipShape.fill(Self.selectedFill))
                    .mapFloatShadow()
            } else {
                label
                    .glassEffect(.regular, in: Self.chipShape)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.a11yLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
