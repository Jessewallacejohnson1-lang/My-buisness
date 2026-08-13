//
//  MapSearch.swift
//  Block Party — the map's client-side place/event search (map polish Phase 2).
//
//  Pure matching over what the map already holds — the curated spots (MapSpots.all),
//  the loaded POIs (MapModel.pois) and today's events (MapModel.todayEvents). No
//  network: the matcher is a case/diacritic-insensitive substring scan, with
//  name-prefix matches ranked first. Events resolve to their spot's pin through the
//  same keyword match the Today rows use (SJMapView.spot(for:)), passed in as a
//  closure so the rule cannot fork.
//
//  `MapDistance` is the tab's one distance formatter — extracted from
//  `MapPlaceDetail.distanceLabel` (the detail morph's "350 ft" style) so search
//  rows and the detail badge cannot drift apart.
//

import SwiftUI
import CoreLocation

// MARK: - Distance formatter (shared with MapPlaceDetail)

/// "350 ft" under a tenth of a mile, "1.2 mi" under ten, "12 mi" beyond — and nil
/// under 30 m, where a distance reads as noise. `nonisolated`: a pure numeric
/// formatter, callable from any context and unit-testable.
nonisolated enum MapDistance {
    static func label(meters: Double) -> String? {
        guard meters >= 30 else { return nil }
        let miles = meters / 1_609.344
        if miles < 0.1 {
            let roundedFeet = Int((meters * 3.28084 / 50).rounded()) * 50
            return "\(max(50, roundedFeet)) ft"
        }
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return "\(Int(miles.rounded())) mi"
    }
}

// MARK: - Result model

/// One row of the search dropdown. `target` keeps the source model itself (the
/// MapPlaceDetail discipline — selection cannot drift across duplicated view
/// models); an event additionally carries the pin it resolved to, so the commit
/// path needs no second keyword match.
struct MapSearchResult: Identifiable {
    enum Target {
        case spot(Spot)
        case poi(POI)
        case event(TimelineEvent, pin: Spot?)
    }

    let target: Target
    let name: String
    /// Category glyph via the existing pipelines — `SpotCategory.filledSymbol`,
    /// `POI.glyph` (PlaceCategoryMap) and `EventCategory.glyph`.
    let glyph: String
    /// Where a tap flies. Nil only for an event at an unlisted venue (no pin).
    let coordinate: CLLocationCoordinate2D?

    var id: String {
        switch target {
        case .spot(let s):     return "spot:\(s.id)"
        case .poi(let p):      return "poi:\(p.id)"
        case .event(let e, _): return "event:\(e.id)"
        }
    }
}

// MARK: - Matcher

enum MapSearch {

    /// Case- and diacritic-insensitive normalization ("Café" matches "cafe").
    nonisolated static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }

    /// Match rank: 0 = the name starts with the query, 1 = the name contains it,
    /// 2 = a secondary field (category label, primary type, event location)
    /// contains it. Nil = no match. Lower ranks list first.
    nonisolated static func rank(_ query: String, name: String, secondary: [String] = []) -> Int? {
        let q = normalized(query)
        guard !q.isEmpty else { return nil }
        let n = normalized(name)
        if n.hasPrefix(q) { return 0 }
        if n.contains(q) { return 1 }
        if secondary.contains(where: { normalized($0).contains(q) }) { return 2 }
        return nil
    }

    /// The empty state — one plain sentence, named for the town in view.
    nonisolated static func emptySentence(town: String) -> String {
        "Nothing in \(town) matches that yet."
    }

    /// Everything the map holds that matches `query` — prefix matches first, then
    /// catalogue order (spots · POIs · events) as the stable tiebreak.
    static func results(query: String,
                        spots: [Spot],
                        pois: [POI],
                        events: [TimelineEvent],
                        spotFor: (TimelineEvent) -> Spot?) -> [MapSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var ranked: [(rank: Int, order: Int, result: MapSearchResult)] = []
        var order = 0

        for spot in spots {
            let category = MapPlaceDetail.spot(spot).categoryLabel
            guard let r = rank(q, name: spot.name, secondary: [category]) else { continue }
            ranked.append((r, order, MapSearchResult(
                target: .spot(spot), name: spot.name,
                glyph: spot.category.filledSymbol, coordinate: spot.coordinate)))
            order += 1
        }
        for poi in pois {
            let type = (poi.primaryType ?? "").replacingOccurrences(of: "_", with: " ")
            guard let r = rank(q, name: poi.name, secondary: [poi.family.label, type]) else { continue }
            ranked.append((r, order, MapSearchResult(
                target: .poi(poi), name: poi.name,
                glyph: poi.glyph, coordinate: poi.coordinate)))
            order += 1
        }
        for event in events {
            let secondary = [event.location ?? "", event.category.label]
            guard let r = rank(q, name: event.title, secondary: secondary) else { continue }
            let pin = spotFor(event)
            ranked.append((r, order, MapSearchResult(
                target: .event(event, pin: pin), name: event.title,
                glyph: event.category.glyph, coordinate: pin?.coordinate)))
            order += 1
        }

        // Explicit tiebreak — Swift's sort is not guaranteed stable.
        return ranked
            .sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .map(\.result)
    }
}

// MARK: - Results panel

/// The dropdown under the expanded field — result rows on the same chrome
/// material. Rows are Buttons (never a bare onTapGesture inside a ScrollView —
/// the repo's pan-competition rule), and the panel hugs its content up to a cap
/// that keeps it clear of the keyboard.
struct MapSearchResultsPanel: View {
    let results: [MapSearchResult]
    let emptyText: String
    let distanceFor: (MapSearchResult) -> String?
    let onPick: (MapSearchResult) -> Void

    @State private var contentHeight: CGFloat = 0
    /// Chrome top + field ≈ 160pt and the keyboard tops out ≈ 340pt from the
    /// screen bottom, so 340 keeps the whole panel visible above the keyboard.
    private static let maxHeight: CGFloat = 340

    var body: some View {
        Group {
            if results.isEmpty {
                Text(emptyText)
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(results) { result in
                            Button { onPick(result) } label: { row(result) }
                                .buttonStyle(.plain)
                            if result.id != results.last?.id {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .onAppear { contentHeight = g.size.height }
                                .onChange(of: g.size.height) { _, h in contentHeight = h }
                        }
                    )
                }
                .frame(height: min(max(contentHeight, 44), Self.maxHeight))
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func row(_ result: MapSearchResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Hue.ink)
                Image(systemName: result.glyph)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Hue.surface)
            }
            .frame(width: 28, height: 28)
            Text(result.name)
                .font(.sansMedium(15))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let distance = distanceFor(result) {
                Text(distance)
                    .font(.sans(13).monospacedDigit())
                    .foregroundStyle(Hue.inkSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
