//
//  PlaceSeeder.swift
//  Hygge — one-time seeder for the `places` table.
//
//  Sweeps Google Nearby Search (New) for St. Joseph's permanent food & business
//  venues, classifies each with PlaceCategoryMap, and upserts them into Supabase
//  `places` (admin-only writes; RLS `is_admin()` enforces it). The map then reads
//  categories from Supabase, so a map load never makes a live Places call.
//
//  This is NOT part of any normal flow: it runs once, only when the `-seed-places`
//  DEBUG launch argument is present and a signed-in admin session is available.
//  Re-running is safe — it upserts on `place_id` (merge-duplicates).
//

import Foundation
import CoreLocation

@MainActor
enum PlaceSeeder {

    /// `includedTypes` groups swept separately. Nearby Search (New) returns ≤20
    /// results per call and offers no pagination, so narrow, disjoint groups widen
    /// total coverage of a small town. Extend PlaceCategoryMap, not this list, to
    /// re-classify — these are only the discovery buckets.
    private static let groups: [[String]] = [
        ["restaurant", "cafe", "coffee_shop", "bakery", "bar", "meal_takeaway",
         "sandwich_shop", "ice_cream_shop", "fast_food_restaurant",
         "brewery", "pub", "wine_bar"],
        ["store", "grocery_store", "supermarket", "clothing_store", "hardware_store",
         "convenience_store", "liquor_store", "book_store", "florist", "furniture_store"],
        ["bank", "atm", "pharmacy", "gas_station", "hair_care", "beauty_salon", "gym",
         "car_repair", "laundry", "real_estate_agency", "insurance_agency", "post_office"],
    ]

    struct Summary: CustomStringConvertible {
        var discovered = 0, seeded = 0, skipped = 0, food = 0, business = 0
        var description: String {
            "discovered \(discovered), seeded \(seeded) (food \(food), business \(business)), skipped \(skipped)"
        }
    }

    /// DEBUG entry point (wired in HyggeApp). Runs once when `-seed-places` is passed
    /// and a signed-in admin session is available; a no-op otherwise.
    static func seedIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-seed-places") else { return }
        // Wait briefly for auth.restore() to land a session — the seed needs a token.
        for _ in 0..<10 {
            if Task.isCancelled { return }
            if (try? await AuthStore.shared.validAccessToken()) != nil { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let summary = await run(auth: .shared)
        print("[PlaceSeeder] \(summary)")
    }

    /// Sweep → classify → upsert. Requires a signed-in admin (server RLS enforces).
    @discardableResult
    static func run(auth: AuthStore) async -> Summary {
        var summary = Summary()
        let svc = GooglePlacesService.shared

        // 1. Sweep every group; dedupe by place_id.
        var byId: [String: NearbyPlace] = [:]
        for group in groups {
            for place in await svc.nearby(includedTypes: group) {
                byId[place.placeId] = place
            }
        }
        summary.discovered = byId.count

        // 2. Classify + build upsert rows (skip unclassifiable / permanently-closed).
        var rows: [[String: Any]] = []
        for place in byId.values {
            guard place.isOperational else { summary.skipped += 1; continue }
            guard !Self.isExcluded(place.name) else { summary.skipped += 1; continue }
            guard let family = PlaceCategoryMap.family(primaryType: place.primaryType, types: place.types) else {
                summary.skipped += 1; continue
            }
            // Prefer a curated building-accurate coordinate when we have one — the same
            // reason KnownVenues exists (device/Google coords miss small-town venues).
            let coord = KnownVenues.coordinate(for: place.name) ?? place.coordinate
            var row: [String: Any] = [
                "place_id": place.placeId,
                "name": place.name,
                "lat": coord.latitude,
                "lon": coord.longitude,
                "family": family.rawValue,
                "types": place.types,
                "source": "google_nearby",
                "updated_at": Self.iso.string(from: Date()),
            ]
            if let pt = place.primaryType { row["primary_type"] = pt }
            if let addr = place.address { row["address"] = addr }
            rows.append(row)
            if family == .food { summary.food += 1 } else { summary.business += 1 }
        }

        // 3. Upsert into Supabase (admin-only; RLS `is_admin()`).
        guard !rows.isEmpty else { return summary }
        do {
            let token = try await auth.validAccessToken()
            let body = try JSONSerialization.data(withJSONObject: rows)
            _ = try await SupabaseHTTP.rest("places", method: "POST",
                                            query: "on_conflict=place_id",
                                            accessToken: token, body: body,
                                            prefer: "resolution=merge-duplicates,return=minimal")
            summary.seeded = rows.count
        } catch {
            print("[PlaceSeeder] upsert failed: \(error.localizedDescription)")
        }
        return summary
    }

    /// Curated exclusions — specific venues the Google sweep surfaces that don't
    /// belong on a neighborly town map: a campus athletic facility that duplicates
    /// the Saint Ben's civic pin, and heavy-industrial businesses 1.5–2 km out
    /// (towing, materials / parts distributors). Matched by lowercased name
    /// fragment. Keep in sync with supabase/migrations/20260715120000_places_seed.sql.
    private static let excludedNameFragments: [String] = [
        "claire lynch", "mn heavy", "tamarack materials", "north central distributing",
        "bee line", "joe's auto parts", "precision motorsports",
    ]

    private static func isExcluded(_ name: String) -> Bool {
        let n = name.lowercased()
        return excludedNameFragments.contains { n.contains($0) }
    }

    private static let iso = ISO8601DateFormatter()
}
