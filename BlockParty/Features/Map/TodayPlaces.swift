//
//  TodayPlaces.swift
//  Block Party — where each of today's events sits on the map: the one answer its bubbles
//  and card read (BP app references/map-reset, 2026-10-30).
//
//  An event is at its real spot, `club_events.lat,lng`, which the morning job sets from the
//  source registry's hand-checked coordinates: the venue its location names, or its Place's
//  own spot. Events at one spot share one bubble; an event with no spot stays off the map.
//  Bubbles that touch on screen merge into one, whose card pages through all their events.
//

import CoreGraphics
import CoreLocation
import Foundation

struct TodayPlaces {
    /// Today's events, as the Town feed has them.
    let events: [FeedCardItem]
    /// Each event's real spot, by event id.
    let spots: [String: CLLocationCoordinate2D]

    static let none = TodayPlaces(events: [], spots: [:])

    /// One bubble per spot with an event not yet over, soonest first, numbered for the
    /// opening pop-in.
    func bubbles(now: Date) -> [TodayBubble] {
        var bySpot: [String: (CLLocationCoordinate2D, [FeedCardItem])] = [:]
        for event in events {
            guard let at = spots[event.id] else { continue }
            let key = "\(at.latitude),\(at.longitude)"
            bySpot[key, default: (at, [])].1.append(event)
        }
        var bubbles = bySpot.compactMap { key, spot -> TodayBubble? in
            let shown = TodayBubbleRules.order(spot.1, now: now)
            return shown.isEmpty ? nil : TodayBubble(id: key, coordinate: spot.0, events: shown)
        }
        bubbles.sort { (TodayBubbleRules.starts($0.event), $0.id) < (TodayBubbleRules.starts($1.event), $1.id) }
        for i in bubbles.indices { bubbles[i].order = i }
        return bubbles
    }

    /// Every one of today's events is over (or there were none): the map says so. Events with
    /// no spot count too, so a day whose bubbles are all missing spots never says it's done.
    func dayIsOver(now: Date) -> Bool {
        TodayBubbleRules.order(events, now: now).isEmpty
    }

    /// Bubbles whose centres sit closer than `within` points on screen become one, at the
    /// first one's spot (the earliest), its events ordered again. `points` are the bubbles'
    /// screen centres, in the same order.
    static func merge(_ bubbles: [TodayBubble], at points: [CGPoint], within: CGFloat, now: Date) -> [TodayBubble] {
        var merged: [(bubble: TodayBubble, point: CGPoint)] = []
        for (bubble, point) in zip(bubbles, points) {
            if let i = merged.firstIndex(where: { hypot($0.point.x - point.x, $0.point.y - point.y) < within }) {
                merged[i].bubble.events = TodayBubbleRules.order(merged[i].bubble.events + bubble.events, now: now)
            } else {
                merged.append((bubble, point))
            }
        }
        return merged.map(\.bubble)
    }
}
