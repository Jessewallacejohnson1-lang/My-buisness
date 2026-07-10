//
//  KnownLocalPhoto.swift
//  Hygge — bundled photos for specific real St. Joe / Collegeville trails and
//  events that don't have a confident Google Places match (see VenuePhoto).
//  Dropped into Resources/Images via the same Higgsfield pipeline as
//  wobegon-trail.jpg; PhotoView resolves them by base name.
//

enum KnownLocalPhoto {
    private static let byTitle: [String: String] = [
        // Trails
        "Klinefelter Park Trail": "klinefelter-park-trail",
        "Saint John's Abbey Arboretum": "sju-arboretum-trail",
        "Boardwalk Loop Trail": "boardwalk-loop-trail",
        "Chapel Trail — Stella Maris": "chapel-trail-stella-maris",
        // Events — venue exteriors / official event imagery
        "Trivia Night at Bad Habit Brewing": "bad-habit-brewing",
        "Open Mic at The Local Blend": "the-local-blend",
        "St. Joseph Farmers Market": "farmers-market",
        "Millstream Arts Festival": "millstream-arts-festival",
        "RocktoberFest": "rocktoberfest",
        // "Kidtoberfest" has no bundled photo yet (first-year 2026 event; assets not
        // published as of July 2026) — omitted so its card shows the coral photo-glyph
        // placeholder rather than a blank linen box. Add the key + a Resources/Images
        // file once real imagery exists.
    ]

    static func name(forTitle title: String) -> String? { byTitle[title] }
}
