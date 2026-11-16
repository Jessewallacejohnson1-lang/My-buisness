//
//  NeedWords.swift
//  Block Party — the plain words people type for what they need, joined to the kinds of places (Google types)
//  and the words in their names that mean it (BP app search-helpful 04): "gas" finds a fuel station, "plumber" a
//  plumbing company, "breakfast" the cafés. Google's kinds, not a town's names, so it works in every town.
//

import Foundation

enum NeedWords {
    struct Need {
        /// What people type, every way they say it.
        let words: [String]
        /// Google types that mean it; "restaurant" also covers "pizza_restaurant" and every other "_restaurant".
        let types: Set<String>
        /// Words or phrases in a name that mean it ("plumbing" for "plumber").
        var names: [String] = []
    }

    static let all: [Need] = [
        // Food and drink
        Need(words: ["food", "dinner", "eat", "restaurant"],
             types: ["restaurant", "bar_and_grill", "fast_food", "meal_takeaway", "diner"]),
        Need(words: ["lunch"], types: ["restaurant", "bar_and_grill", "fast_food", "meal_takeaway", "cafe", "deli",
                                       "sandwich_shop", "diner"]),
        Need(words: ["breakfast", "brunch"], types: ["cafe", "coffee_shop", "bakery", "breakfast_restaurant",
                                                     "brunch_restaurant", "diner"]),
        Need(words: ["chinese food", "chinese"], types: ["chinese_restaurant"]),
        Need(words: ["mexican food", "mexican"], types: ["mexican_restaurant"]),
        Need(words: ["italian food", "italian"], types: ["italian_restaurant"]),
        Need(words: ["wings"], types: ["bar_and_grill", "bar", "pub", "sports_bar", "pizza_restaurant",
                                       "chicken_wings_restaurant"],
             names: ["grill", "tap", "pub", "tavern"]),
        Need(words: ["beer", "drinks", "pub"], types: ["bar", "pub", "brewery", "bar_and_grill", "liquor_store",
                                                       "beer_store"],
             names: ["tap", "tavern", "pub", "brewing", "brewery", "liquor"]),
        Need(words: ["wine"], types: ["liquor_store", "wine_bar", "winery", "wine_store"], names: ["liquor", "wine"]),
        Need(words: ["cocktails", "cocktail"], types: ["bar", "cocktail_bar", "distillery", "pub", "bar_and_grill"],
             names: ["distilling", "distillery", "tavern"]),
        Need(words: ["coffee"], types: ["coffee_shop", "cafe"]),
        Need(words: ["ice cream"], types: ["ice_cream_shop"]),
        Need(words: ["groceries", "grocery"], types: ["grocery_store", "supermarket"]),
        // Errands
        Need(words: ["gas", "gas station", "fuel"], types: ["gas_station", "fuel", "convenience", "convenience_store"]),
        Need(words: ["pharmacy", "drugstore"], types: ["pharmacy", "drugstore"]),
        Need(words: ["bank", "atm"], types: ["bank", "atm"]),
        Need(words: ["post office", "mail"], types: ["post_office"]),
        Need(words: ["library"], types: ["library"]),
        Need(words: ["hardware", "hardware store"], types: ["hardware_store"]),
        Need(words: ["flowers", "florist"], types: ["florist"]),
        Need(words: ["gifts", "gift shop"], types: ["gift_shop"]),
        Need(words: ["clothes", "clothing"], types: ["clothing_store", "boutique"], names: ["boutique"]),
        Need(words: ["thrift store", "thrift", "secondhand"], types: ["second_hand_store", "thrift_store"],
             names: ["thrift"]),
        // Care
        Need(words: ["haircut", "hair", "salon"], types: ["hair_salon", "barber_shop", "beauty_salon", "hair_care"],
             names: ["salon", "cuts", "cutters", "hair", "barber", "barbers", "styles"]),
        Need(words: ["barber"], types: ["barber_shop"], names: ["barber", "barbers"]),
        Need(words: ["nails"], types: ["nail_salon"], names: ["nails"]),
        Need(words: ["massage", "spa"], types: ["massage", "spa"], names: ["massage", "spa"]),
        Need(words: ["dentist", "dental"], types: ["dentist", "dental_clinic"], names: ["dental", "dentistry"]),
        Need(words: ["doctor", "clinic"], types: ["doctor", "medical_clinic", "hospital"], names: ["clinic"]),
        Need(words: ["vet", "veterinarian"], types: ["veterinary_care"], names: ["veterinary", "animal hospital"]),
        Need(words: ["daycare", "childcare", "child care", "preschool"],
             types: ["day_care_center", "child_care_agency", "preschool"],
             names: ["childcare", "daycare", "preschool"]),
        Need(words: ["gym", "workout", "fitness"], types: ["gym", "fitness_center", "yoga_studio"],
             names: ["fitness", "gym"]),
        Need(words: ["yoga"], types: ["yoga_studio"], names: ["yoga"]),
        Need(words: ["church", "worship"], types: ["church", "place_of_worship", "christian_place_of_worship"],
             names: ["church", "parish", "abbey", "monastery", "chapel"]),
        Need(words: ["catholic church", "catholic"], types: ["catholic_church"], names: ["parish", "abbey", "monastery"]),
        // Home and car
        Need(words: ["mechanic", "car repair", "auto repair", "oil change", "tires"],
             types: ["car_repair", "automotive_service", "auto_repair", "oil_change", "tire_shop"],
             names: ["auto", "autobody", "tire", "tires", "radiator", "diesel"]),
        Need(words: ["plumber", "plumbing"], types: ["plumber"], names: ["plumbing"]),
        Need(words: ["electrician"], types: ["electrician"], names: ["electric", "electrical"]),
        Need(words: ["lawyer", "attorney", "legal"], types: ["attorney_or_law_firm", "lawyer", "legal_service"],
             names: ["law", "attorney", "attorneys", "legal"]),
        Need(words: ["realtor", "real estate", "homes for sale"], types: ["real_estate_agency", "real_estate_service"],
             names: ["realty", "realtor", "realtors", "real estate"]),
        Need(words: ["hotel", "motel", "lodging", "place to stay"],
             types: ["lodging", "hotel", "motel", "bed_and_breakfast", "inn", "extended_stay_hotel"],
             names: ["inn", "hotel", "motel"]),
        // Out and about
        Need(words: ["hiking", "hike", "trails"], types: ["hiking_area"], names: ["trail"]),
        Need(words: ["ice skating", "skating"], types: ["ice_skating_rink"], names: ["rink", "skate", "skating"]),
        Need(words: ["art", "gallery", "museum"], types: ["art_gallery", "museum"], names: ["gallery", "arts"]),
        Need(words: ["family"], types: ["playground", "zoo", "amusement_park", "indoor_playground",
                                                "day_care_center"],
             names: ["playground", "zoo", "kids"]),
        Need(words: ["playground"], types: ["playground", "indoor_playground"], names: ["playground"]),
    ]

    /// The words a place answers to by its Google types, as strongly as its own kind ("gas" for a fuel station).
    static func typed(_ types: [String]) -> [String] {
        all.filter { need in
            types.contains { t in need.types.contains { t == $0 || ($0 == "restaurant" && t.hasSuffix("_restaurant")) } }
        }.flatMap(\.words)
    }

    /// The words a row answers to by the words in its name, more weakly ("plumber" for a name with "Plumbing").
    static func named(_ name: String) -> [String] {
        let spaced = " " + name.folding(options: [.diacriticInsensitive], locale: nil).lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }.split(separator: " ").joined(separator: " ") + " "
        return all.filter { need in need.names.contains { spaced.contains(" " + $0 + " ") } }.flatMap(\.words)
    }
}
