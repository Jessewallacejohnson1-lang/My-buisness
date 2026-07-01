//
//  Place.swift
//  Hygge — "Around Town", real St. Joseph, MN places.
//
//  Single source of truth for the carousel and the full-screen showcase.
//  Copy is real and true; we never invent counts — any numbers in a showcase
//  come from real event data, never from here. Ported verbatim from the Expo
//  app's src/data/places.ts.
//

import Foundation

struct PlaceFact: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { label + value }
}

struct Place: Identifiable, Hashable {
    let slug: String            // url-safe id
    let name: String            // display name
    let tagline: String         // one-line card subtitle
    let image: String           // bundled hero photo (base name)
    let kw: [String]?           // keywords for matching events to this place
    let description: [String]   // 1–2 warm, true paragraphs
    let facts: [PlaceFact]      // a few honest facts
    let where_: String?         // address/landmark for "Open in Maps"
    var id: String { slug }
}

enum Places {
    static let all: [Place] = [
        Place(
            slug: "downtown",
            name: "Downtown",
            tagline: "Shops & cafés on Minnesota St",
            image: "downtown",
            kw: ["downtown", "minnesota st", "local blend", "krewe", "bo diddley", "middy", "college ave", "bad habit"],
            description: [
                "St. Joe's main street is a few walkable blocks of Minnesota Street — locally-owned coffee, a deli, a brewery taproom, and storefronts where the person behind the counter tends to know your order.",
                "It's the town's living room: slow mornings at the coffeehouse, a summer farmers market, and a steady drift of students and families on foot.",
            ],
            facts: [
                PlaceFact(label: "Where", value: "Minnesota Street"),
                PlaceFact(label: "Coffee", value: "The Local Blend"),
                PlaceFact(label: "Pint", value: "Bad Habit Brewing"),
            ],
            where_: "Minnesota Street, St. Joseph, MN"
        ),
        Place(
            slug: "saint-bens",
            name: "Saint Ben's",
            tagline: "College of Saint Benedict",
            image: "saint-bens",
            kw: ["saint ben", "st. ben", "st ben", "csb", "benedict", "gorecki", "campus"],
            description: [
                "The College of Saint Benedict — 'St. Ben's' — is a Benedictine women's liberal-arts college on the north edge of town, partnered with Saint John's across the river.",
                "Tree-lined paths, the Gorecki center, and a hospitality you can feel the moment you step onto campus. Concerts, lectures, and games here are open to neighbors.",
            ],
            facts: [
                PlaceFact(label: "Founded", value: "1887"),
                PlaceFact(label: "Type", value: "Women's liberal arts"),
                PlaceFact(label: "Partner", value: "Saint John's"),
            ],
            where_: "College of Saint Benedict, St. Joseph, MN"
        ),
        Place(
            slug: "sacred-heart-chapel",
            name: "Sacred Heart Chapel",
            tagline: "The monastery & its dome",
            image: "sacred-heart-chapel",
            kw: ["chapel", "sacred heart", "monastery", "mass", "sisters"],
            description: [
                "At the heart of Saint Benedict's Monastery stands the Sacred Heart Chapel, its copper dome a landmark you can spot from the highway.",
                "Home to the Benedictine sisters who founded both the monastery and the college, it's a quiet, candle-warmed space open for prayer and song.",
            ],
            facts: [
                PlaceFact(label: "Feature", value: "Copper dome"),
                PlaceFact(label: "Home to", value: "Benedictine sisters"),
                PlaceFact(label: "Open for", value: "Prayer & song"),
            ],
            where_: "Sacred Heart Chapel, St. Joseph, MN"
        ),
        Place(
            slug: "saint-johns",
            name: "Saint John's",
            tagline: "The Abbey in Collegeville",
            image: "saint-johns-abbey",
            kw: ["saint john", "st. john", "st john", "sju", "abbey", "collegeville"],
            description: [
                "Just west in Collegeville, Saint John's Abbey and University sit among thousands of acres of woods, prairie, and lake.",
                "The Abbey Church — Marcel Breuer's soaring concrete bell banner — draws architecture lovers, and the arboretum trails and Stella Maris chapel are open to wander.",
            ],
            facts: [
                PlaceFact(label: "Where", value: "Collegeville"),
                PlaceFact(label: "Architect", value: "Marcel Breuer"),
                PlaceFact(label: "Grounds", value: "2,700 acres"),
            ],
            where_: "Saint John's Abbey, Collegeville, MN"
        ),
        Place(
            slug: "wobegon-trail",
            name: "Wobegon Trail",
            tagline: "Bike, walk & run the trail",
            image: "wobegon-trail",
            kw: ["wobegon", "trail", "bike", "walk", "run", "ride", "river", "watab"],
            description: [
                "The Lake Wobegon Trail runs right through town — a flat, paved rail-trail named for Garrison Keillor's fictional hometown.",
                "Bike it, run it, walk the dog, or push a stroller; it links St. Joseph toward St. Cloud one way and rolls out past Avon and Albany the other.",
            ],
            facts: [
                PlaceFact(label: "Surface", value: "Paved rail-trail"),
                PlaceFact(label: "Named for", value: "Keillor's Lake Wobegon"),
                PlaceFact(label: "Good for", value: "Bikes, runs, strollers"),
            ],
            where_: "Lake Wobegon Trail, St. Joseph, MN"
        ),
    ]

    static func bySlug(_ slug: String) -> Place? { all.first { $0.slug == slug } }
}
