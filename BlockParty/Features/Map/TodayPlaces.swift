//
//  TodayPlaces.swift
//  Block Party — which place each of today's events is at, on the map: the one answer its
//  pins, bubbles, Today and Places lists, pin card and search all read (codebase-health 12
//  in the BP app folder).
//
//  An event is at ONE curated spot, the first whose keywords its title or location hits
//  (MapSpots order). An event that names both Saint Ben's and its chapel lights one pin, and
//  its bubble, row and pin card all go to that one.
//

import CoreLocation
import Foundation

struct TodayPlaces {
    let events: [TimelineEvent]
    private let spotByEvent: [String: Spot]

    init(events: [TimelineEvent], spots: [Spot] = MapSpots.all) {
        self.events = events
        var spotByEvent: [String: Spot] = [:]
        for event in events {
            let haystack = [event.title, event.location].compactMap { $0 }.joined(separator: " ").lowercased()
            spotByEvent[event.id] = spots.first { $0.keywords.contains { haystack.contains($0) } }
        }
        self.spotByEvent = spotByEvent
    }

    /// The pin an event is at; nil for a venue with no curated pin.
    func spot(for event: TimelineEvent) -> Spot? { spotByEvent[event.id] }

    /// Today's events at this pin.
    func events(at spot: Spot) -> [TimelineEvent] {
        events.filter { spotByEvent[$0.id]?.id == spot.id }
    }

    /// One of its events is on right now.
    func isLive(_ spot: Spot, now: Date = TodayBubbleClock.now()) -> Bool {
        events(at: spot).contains { $0.isOn(now) }
    }

    /// One bubble per place: the place's lead event (on now, else next to start), at its pin,
    /// else at its known venue. Events with no known place, and ended ones, stay off the map.
    /// Soonest first, numbered for the opening pop-in.
    func bubbles(now: Date, picture: (TimelineEvent) -> (url: URL, isLogo: Bool)?) -> [TodayBubble] {
        var byPlace: [String: (CLLocationCoordinate2D, Spot?, [TimelineEvent])] = [:]
        var order: [String] = []
        for event in events {
            let place: (String, CLLocationCoordinate2D, Spot?)
            if let s = spot(for: event) {
                place = (s.id, s.coordinate, s)
            } else if let c = KnownVenues.coordinate(for: [event.location, event.title].compactMap { $0 }.joined(separator: " ")) {
                place = (String(format: "%.4f,%.4f", c.latitude, c.longitude), c, nil)
            } else { continue }
            if byPlace[place.0] == nil { order.append(place.0); byPlace[place.0] = (place.1, place.2, []) }
            byPlace[place.0]?.2.append(event)
        }
        var bubbles: [TodayBubble] = []
        for id in order {
            guard let place = byPlace[id], let lead = TodayBubbleRules.lead(place.2, now: now) else { continue }
            let pic = picture(lead)
            bubbles.append(TodayBubble(id: id, coordinate: place.0, spot: place.1, event: lead,
                                       picture: pic?.url, isLogo: pic?.isLogo ?? false))
        }
        bubbles.sort { TodayBubbleRules.starts($0.event) < TodayBubbleRules.starts($1.event) }
        for i in bubbles.indices { bubbles[i].order = i }
        return bubbles
    }
}
