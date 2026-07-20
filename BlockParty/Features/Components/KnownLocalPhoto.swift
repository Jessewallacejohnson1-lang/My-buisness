//
//  KnownLocalPhoto.swift
//  Block Party — bundled photos for specific real St. Joe / Collegeville trails and
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
        // Parks — human-verified real photos, bundled to OVERRIDE Google's fickle
        // auto-pick where it looked poor to a human (portrait phone shots that crop
        // to an ugly middle band, or dreary off-season snaps). Every one below was
        // eyeballed for "does this actually look good" before bundling — see
        // scripts/review_park_photos.py + the photo-quality-pass note in CLAUDE.md.
        //   • Centennial & Memorial — City of St. Joseph facility photos (landscape,
        //     sunny), used with the owner's city-photo sign-off.
        //   • Rivers Bend — a brand-new park absent from Google; its restored native
        //     prairie, from WJON / Townsquare Media (a commercial news org) with the
        //     owner's sign-off — get Townsquare's permission before shipping.
        "Centennial Park": "centennial-park",
        "Memorial Park": "memorial-park",
        "Rivers Bend Park": "rivers-bend-park",
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
