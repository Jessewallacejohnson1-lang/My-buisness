//
//  ActivityVenue.swift
//  Block Party — the ONE place that decides which strings an Activities card hands
//  to the Google Places photo lookup: the venue NAME Rule A matches Google's result
//  against, and the curated ANCHOR it measures the distance from.
//
//  It exists because two callers must never disagree: `ActivityImage` (which decides
//  whether a card is kept) and the card's own `VenuePhoto` (which renders the photo).
//  If they derive the venue differently, Explore keeps a card that then draws blank,
//  or hides one that would have resolved.
//
//  Why the anchor is resolved HERE rather than left to
//  `GooglePlacesService.confidentPhoto(forFreeText:hint:)`: that helper concatenates
//  `title + hint` into ONE string and hands it to `KnownVenues.coordinate(for:)`,
//  which returns the FIRST venue in its table whose keyword appears anywhere in that
//  string. Table order — not relevance — then decides the anchor, so an event's own
//  title can outrank its location. Measured 2026-07-21: "Millstream Arts Festival"
//  at "Downtown St. Joseph" anchored on Millstream Park (the `millstream` keyword
//  sits above `downtown` in the table), putting the correct Google match 1,024.9 m
//  away and blanking the card — where the location alone anchors it to 26.2 m and
//  resolves. Location first, title only as a rescue, fixes that class of bug.
//

import CoreLocation

/// The venue identity behind one Activities card.
struct ActivityVenue {
    /// The real-world PLACE name — what `search()` queries and what Rule A checks
    /// Google's returned name against. An event or club uses its `location`, never
    /// its own title (a title says what is happening, not where).
    let name: String
    /// The human-verified coordinate Rule A measures Google's match against. nil
    /// means KnownVenues has never heard of this place, so no photo can clear the
    /// gate and the card stays blank — by design, not by accident.
    let anchor: CLLocationCoordinate2D?

    /// An event: its location is the venue; its title only rescues a location
    /// KnownVenues doesn't recognise.
    static func event(_ e: UpcomingEvent) -> ActivityVenue {
        hosted(at: e.location, named: e.title)
    }

    /// A club: same shape as an event — the meeting location is the venue.
    static func club(_ c: ClubView) -> ActivityVenue {
        hosted(at: c.location, named: c.name)
    }

    /// A trail: its TITLE is the venue name ("Millstream Park Trail" is a place),
    /// while its `location` is an address that only anchors it.
    static func trail(_ t: Trail) -> ActivityVenue {
        ActivityVenue(name: t.title, anchor: anchor(at: t.location, named: t.title))
    }

    /// A city park carries its own curated pin, so it skips KnownVenues entirely.
    static func park(_ p: Park) -> ActivityVenue {
        ActivityVenue(name: p.title, anchor: p.coordinate)
    }

    /// Something that happens AT a venue (an event, a club meeting): the location
    /// names the place, the item's own name is the fallback.
    private static func hosted(at location: String?, named ownName: String) -> ActivityVenue {
        ActivityVenue(name: location ?? ownName, anchor: anchor(at: location, named: ownName))
    }

    /// Location FIRST — see `KnownVenues.anchor(location:named:)`, the shared rule the
    /// Feed path (`FeedCardVenuePhoto` → `confidentPhoto(forFreeText:)`) uses too, so
    /// Activities and the feed can never disagree about how a venue anchors.
    private static func anchor(at location: String?, named ownName: String) -> CLLocationCoordinate2D? {
        KnownVenues.anchor(location: location, named: ownName)
    }
}
