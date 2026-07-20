//
//  PlaceCategoryMap.swift
//  Block Party — the single source of truth mapping a Google Places (New) `primaryType`
//  (with a `types[]` fallback) onto one of the two POI families this pass ships —
//  Food & Drink and Business / Retail / Services — plus the SF Symbol glyph and the
//  marker tint each place gets on the map.
//
//  Why primaryType-first with explicit inline group Sets (not a keyword scan):
//  Google returns exactly one `primaryType` per place and it is authoritative.
//  A pure keyword scan mis-files real venues — e.g. `health_food_store` contains
//  "food" but is a *retail* store (business), not a restaurant. So we classify by
//  primaryType against the group Sets first, and only scan `types[]` when
//  primaryType is missing/unrecognized (store-first there too, for the same reason).
//
//  Google adds new types over time, so the group Sets are inline and self-contained:
//  extend the two Sets below (and, optionally, `glyph(primaryType:family:)`) rather
//  than reaching for another file. Suffix rules (`_restaurant` → food, `_store` →
//  business) catch the long tail of cuisine/retail variants without enumerating them.
//
//  Families are differentiated by GLYPH, not colour; all place pins use ink.
//

import SwiftUI

// MARK: - Family

/// Which of the two POI families a place belongs to. The raw values match the
/// `places.family` text column, so a Supabase row decodes straight into this.
enum PlaceFamily: String, Codable, Hashable, CaseIterable {
    case food
    case business

    /// Marker tint — places differ by glyph, not colour.
    /// Named `tint` to match `SpotCategory.tint` / `EventCategory.tint`, so a shared
    /// pin renderer can read one accessor across civic and POI pins.
    var tint: Color {
        switch self {
        case .food:     return Hue.ink
        case .business: return Hue.ink
        }
    }

    /// Glyph used when a place's `primaryType` isn't specifically mapped below.
    nonisolated var defaultGlyph: String {
        switch self {
        case .food:     return "fork.knife"
        case .business: return "building.2.fill"
        }
    }

    /// Accessibility / label word for the family.
    var label: String {
        switch self {
        case .food:     return "Food & drink"
        case .business: return "Business"
        }
    }
}

// MARK: - Mapping

enum PlaceCategoryMap {

    /// Google `primaryType` values that belong to Food & Drink (dining + drink).
    /// Any `*_restaurant` cuisine variant is caught by the suffix rule in `isFood`,
    /// so this Set only lists the food types that are NOT `*_restaurant`.
    nonisolated static let foodPrimaryTypes: Set<String> = [
        "restaurant", "fine_dining_restaurant",
        "bar", "bar_and_grill", "pub", "wine_bar", "night_club",
        "cafe", "coffee_shop", "cafeteria", "tea_house",
        "bakery", "bagel_shop", "donut_shop", "dessert_shop",
        "sandwich_shop", "meal_takeaway", "meal_delivery", "fast_food_restaurant",
        "ice_cream_shop", "juice_shop", "brewery", "food_court", "deli", "diner",
    ]

    /// Google `primaryType` values that belong to Business / Retail / Services /
    /// Finance. Any `*_store` retail variant is caught by the suffix rule in
    /// `isBusiness`, so this Set lists the business types that are NOT `*_store`
    /// (services, finance, auto, salons, civic services, and a few `*_shop` retail
    /// types like `butcher_shop`/`tire_shop` that read as retail, not dining).
    nonisolated static let businessPrimaryTypes: Set<String> = [
        "store", "supermarket", "shopping_mall", "market", "gift_shop", "wholesaler", "supplier",
        "butcher_shop", "tire_shop",
        "bank", "atm", "finance", "accounting", "credit_union",
        "pharmacy", "drugstore",
        "gas_station", "car_repair", "car_wash", "car_dealer", "car_rental",
        "hair_care", "hair_salon", "barber_shop", "beauty_salon", "nail_salon", "spa",
        "gym", "fitness_center", "yoga_studio", "sports_activity_location",
        "post_office", "courier_service", "laundry", "dry_cleaner",
        "real_estate_agency", "insurance_agency", "lawyer", "travel_agency",
        "veterinary_care", "florist", "service", "professional_service",
        "general_contractor", "plumber", "electrician", "moving_company", "storage",
        // Hand-seeded local venues (see 20260716120000_places_seed_local.sql): keep
        // these in sync with the glyph cases below so family() and glyph() agree.
        "dentist", "doctor", "chiropractor", "physiotherapist",
        "lodging", "bed_and_breakfast", "guest_house", "farm", "garden_center",
        "art_gallery", "art_studio", "day_care_center", "child_care_agency", "preschool",
    ]

    nonisolated private static func isFood(_ t: String) -> Bool {
        foodPrimaryTypes.contains(t) || t.hasSuffix("_restaurant")
    }

    nonisolated private static func isBusiness(_ t: String) -> Bool {
        businessPrimaryTypes.contains(t) || t.hasSuffix("_store")
    }

    /// Classify a place into a family. Returns `nil` when it fits neither family
    /// (e.g. a school, a park, a place of worship) so callers can skip it — this
    /// pass only ships Food and Business, and civic landmarks stay curated pins.
    nonisolated static func family(primaryType: String?, types: [String] = []) -> PlaceFamily? {
        if let pt = primaryType, !pt.isEmpty {
            if isFood(pt) { return .food }
            if isBusiness(pt) { return .business }
        }
        // primaryType absent/unrecognized → scan types[]. Business/store first, so a
        // `health_food_store`'s generic "food" tag doesn't misfile it as a restaurant.
        if types.contains(where: isBusiness) { return .business }
        if types.contains(where: isFood) { return .food }
        // Last-resort: a bare "food" tag with no more specific type → food. Everything
        // else unrecognized returns nil (skipped). We deliberately do NOT map the
        // near-universal generic "establishment"/"point_of_interest" tags to business —
        // that would misfile schools, parks, and places of worship as retail.
        if types.contains("food") { return .food }
        return nil
    }

    /// SF Symbol glyph for a place, chosen by its `primaryType` subtype so venues in
    /// the same family are told apart by icon. Falls back to the family's default
    /// glyph for an unmapped subtype. (All symbols exist at the app's iOS 26.5
    /// deployment target, so no `#available` gating is needed — see note below.)
    nonisolated static func glyph(primaryType: String?, family: PlaceFamily) -> String {
        switch primaryType ?? "" {
        // — Food & Drink —
        case "cafe", "coffee_shop", "tea_house", "cafeteria":
            return "cup.and.saucer.fill"
        case "bakery", "bagel_shop", "donut_shop", "dessert_shop", "dessert_restaurant", "ice_cream_shop":
            return "birthday.cake.fill"
        case "bar", "pub", "wine_bar", "brewery", "night_club", "bar_and_grill":
            return "wineglass.fill"
        case "fast_food_restaurant", "meal_takeaway", "meal_delivery",
             "sandwich_shop", "hamburger_restaurant":
            return "takeoutbag.and.cup.and.straw.fill"

        // — Business / Retail / Services —
        case "grocery_store", "supermarket", "convenience_store",
             "health_food_store", "liquor_store", "butcher_shop", "market":
            return "cart.fill"
        case "bank", "atm", "finance", "accounting", "credit_union":
            return "building.columns.fill"
        case "pharmacy", "drugstore":
            return "cross.case.fill"
        case "hair_care", "hair_salon", "barber_shop", "beauty_salon", "nail_salon", "spa":
            return "scissors"
        case "gym", "fitness_center", "sports_activity_location":
            return "dumbbell.fill"
        case "yoga_studio":
            return "figure.yoga"
        case "gas_station":
            return "fuelpump.fill"
        case "car_repair", "car_wash", "tire_shop":
            return "wrench.and.screwdriver.fill"
        case "auto_parts_store", "car_dealer", "car_rental":
            return "car.fill"
        case "hardware_store", "building_materials_store", "home_improvement_store":
            return "hammer.fill"
        case "post_office", "courier_service":
            return "envelope.fill"
        case "laundry", "dry_cleaner":
            return "washer.fill"
        case "real_estate_agency":
            return "house.fill"
        case "insurance_agency", "lawyer", "travel_agency",
             "service", "supplier", "professional_service", "general_contractor":
            return "briefcase.fill"
        case "clothing_store", "shoe_store", "jewelry_store", "gift_shop",
             "department_store", "discount_store", "furniture_store", "home_goods_store",
             "electronics_store", "book_store", "pet_store", "sporting_goods_store",
             "store", "shopping_mall":
            return "bag.fill"

        // — Makers, growers, care & stays — the hyper-local venue subtypes hand-seeded
        //   in 20260716120000_places_seed_local.sql. These are also in businessPrimaryTypes
        //   above, so family() and glyph() agree (a live Places result classifies too, not
        //   only the SQL-seeded rows that carry their own family column). —
        case "florist", "garden_center", "farm":
            return "leaf.fill"
        case "art_gallery", "art_studio":
            return "paintpalette.fill"
        case "veterinary_care":
            return "pawprint.fill"
        case "dentist", "doctor", "chiropractor", "physiotherapist":
            return "cross.case.fill"
        case "lodging", "bed_and_breakfast", "guest_house":
            return "bed.double.fill"
        case "day_care_center", "child_care_agency", "preschool":
            return "figure.and.child.holdinghands"

        default:
            if (primaryType ?? "").hasSuffix("_restaurant") { return "fork.knife" }
            return family.defaultGlyph
        }
    }

    /// Convenience: classify + pick a glyph in one call. `nil` if unclassifiable.
    nonisolated static func classify(primaryType: String?, types: [String] = []) -> (family: PlaceFamily, glyph: String)? {
        guard let fam = family(primaryType: primaryType, types: types) else { return nil }
        return (fam, glyph(primaryType: primaryType, family: fam))
    }
}
