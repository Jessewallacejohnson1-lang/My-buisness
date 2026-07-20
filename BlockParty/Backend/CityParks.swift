//
//  CityParks.swift
//  Block Party — the real, official City of St. Joseph park system. A fixed civic
//  dataset (not user-submitted, unlike clubs/events/trails), so it's bundled
//  here rather than round-tripped through Supabase. Sourced from the city's
//  own facilities pages (stjosephmn.gov/112/Parks and each park's detail page,
//  transcribed 2026-07-11). Lake Wobegon Trailhead is deliberately omitted —
//  it's already represented as a trail (see WobegonExploreCard).
//
//  Each park carries a building-accurate `coordinate` used to anchor Rule A's
//  Google-Places photo confidence check (VenuePhoto(coordinate:)). Five were
//  cross-validated against OSM leisure=park polygon centers to within ~2 m
//  (Centennial, Klinefelter, Memorial, Millstream, Northland — they also live
//  in KnownVenues); the other four are address-level geocodes (Cloverdale,
//  Hollow, Monument) or, for Rivers Bend, a triangulated estimate — a wrong
//  coordinate only makes the 75 m confidence gate skip a photo (fail-safe),
//  never shows a wrong one.
//

import Foundation
import CoreLocation

struct Park: Identifiable, Hashable {
    let id: String
    let title: String
    let address: String
    let acres: String?
    let description: String
    let features: [String]
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

enum CityParks {
    static let all: [Park] = [
        Park(id: "centennial-park",
             title: "Centennial Park",
             address: "205 Birch St W, St. Joseph, MN 56374",
             acres: "2.3",
             description: "A downtown-adjacent green space with updated ADA restroom facilities and new playground equipment, an easy walk from Minnesota Street's shops and restaurants. A lighted picnic shelter and full-size basketball court host neighborhood gatherings and pickup games.",
             features: ["Playground", "Full-size basketball court", "Lighted picnic shelter", "ADA restrooms"],
             lat: 45.56699, lon: -94.32363),

        Park(id: "cloverdale-park",
             title: "Cloverdale Park",
             address: "800 Able St E, St. Joseph, MN 56374",
             acres: "0.48",
             description: "A small residential tot lot with playground equipment, a play structure, and a shaded picnic shelter — a quiet corner park the city has eyed for a future meditative-garden redesign.",
             features: ["Playground", "Play structure", "Picnic shelter"],
             lat: 45.564391, lon: -94.30518),

        Park(id: "hollow-park",
             title: "Hollow Park",
             address: "207 5th Ave NW, St. Joseph, MN 56374",
             acres: nil,
             description: "A neighborhood play area tucked into a residential pocket on the northwest side of town.",
             features: ["Playground"],
             lat: 45.5660231, lon: -94.3266238),

        Park(id: "klinefelter-park",
             title: "Klinefelter Park",
             address: "1000 Dale St E, St. Joseph, MN 56374",
             acres: nil,
             description: "An excellent bituminous walking trail loops a central wetland, crossing two pedestrian bridges past benches set for wildlife-watching. A memorial monument, picnic shelter, and bathrooms sit trailside.",
             features: ["Wetland walking trail", "2 pedestrian bridges", "Memorial monument", "Restrooms"],
             // Google's verified "Klinefelter Park" pin (9 photos). The OSM polygon
             // centroid (45.5572) sits ~195 m south — outside the 75 m photo gate —
             // so anchor on Google's pin so the real park photos resolve.
             lat: 45.55884, lon: -94.30395),

        Park(id: "memorial-park",
             title: "Memorial Park",
             address: "28 3rd Ave NW, St. Joseph, MN 56374",
             acres: "4.89",
             description: "Home field for the St. Joseph Saints, between downtown and a residential neighborhood. The lighted hockey rink and skateboard court trade places every winter, turning into a skating rink and sledding hill.",
             features: ["Baseball field", "Concession stand", "Hockey rink / skate court", "Sledding hill"],
             lat: 45.56532, lon: -94.32355),

        Park(id: "millstream-park",
             title: "Millstream Park",
             address: "725 County Rd 75 W, St. Joseph, MN 56374",
             acres: "35",
             description: "On the city's northwest edge, a wooded walking trail follows the Watab River through the park's 35 acres — a playground, volleyball court, and rentable pavilion make it a go-to for all ages, year-round.",
             features: ["Wooded river trail", "Playground", "Volleyball court", "Pavilion (year-round rental)"],
             lat: 45.57007, lon: -94.32874),

        Park(id: "monument-park",
             title: "Monument Park",
             address: "202 Birch St W, St. Joseph, MN 56374",
             acres: "0.39",
             description: "A pocket park built around a 1940s historical marker commemorating the timber blockhouse raised here during the 1862 Dakota Conflict — a refuge for settlers along the Minnesota River Valley.",
             features: ["Historical monument", "Benches"],
             lat: 45.566421, lon: -94.3227439),

        Park(id: "northland-park",
             title: "Northland Park",
             address: "303 Gumtree St E, St. Joseph, MN 56374",
             acres: "9.25",
             description: "A roomy neighborhood park north of County Road 75, amid a large housing development — open 10 a.m. to 10 p.m. daily, with room to roam and a foot-golf course.",
             features: ["Foot golf", "Open green space"],
             lat: 45.57285, lon: -94.31153),

        Park(id: "rivers-bend-park",
             title: "Rivers Bend Park",
             address: "County Rd 121 / College Ave S, St. Joseph, MN 56374",
             acres: "95+",
             description: "The city's largest park, south of Kennedy Community School along the Sauk River — 95-plus acres including 30-plus acres of native prairie wildflowers and grasses, a paved trail over a mile long, and an ADA-accessible canoe/kayak launch.",
             features: ["Native prairie", "1.25+ mi paved trail", "Canoe/kayak launch (ADA dock)", "Paved parking"],
             // Triangulated estimate (not mapped by name in OSM); low confidence —
             // the 75 m gate simply skips the photo if it's off.
             lat: 45.5335, lon: -94.3055),
    ]
}
