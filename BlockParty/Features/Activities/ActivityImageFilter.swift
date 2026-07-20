//
//  ActivityImageFilter.swift
//  Block Party — hides Activities cards that can't resolve a photo, so Explore stays
//  photo-forward (a product choice). "Has a photo" mirrors each card's own 3-tier
//  cascade exactly: an organizer-uploaded `imageUrl`, a bundled `KnownLocalPhoto`,
//  else a confidence-gated Google Places lookup (`VenuePhoto` / `GooglePlacesService`).
//
//  The Google tier is async, so resolution runs before the tab reveals (gated by
//  `ActivitiesModel.loaded`) — cards never pop-then-vanish. It's bounded by a
//  deadline and fails OPEN: if the network is slow, items show this load and drop
//  on the next (the lookups are cached), rather than hanging or hiding everything.
//

import Foundation
import CoreLocation

@MainActor
enum ActivityImage {
    /// Event: organizer photo → bundled → venue lookup (name = its location, else title).
    static func has(event e: UpcomingEvent) async -> Bool {
        if e.imageUrl.flatMap(URL.init(string:)) != nil { return true }
        if KnownLocalPhoto.name(forTitle: e.title) != nil { return true }
        let name = e.location ?? e.title
        let hint = e.location != nil ? e.title : nil
        return await GooglePlacesService.shared.confidentPhoto(forFreeText: name, hint: hint) != nil
    }

    /// Club: no photo field at all — only a venue lookup can supply one.
    static func has(club c: ClubView) async -> Bool {
        let name = c.location ?? c.name
        let hint = c.location != nil ? c.name : nil
        return await GooglePlacesService.shared.confidentPhoto(forFreeText: name, hint: hint) != nil
    }

    /// Trail: the bundled Wobegon card always has one; else imageUrl → bundled → lookup.
    static func has(trail t: Trail) async -> Bool {
        if t.id == "wobegon-trail" { return true }
        if t.imageUrl.flatMap(URL.init(string:)) != nil { return true }
        if KnownLocalPhoto.name(forTitle: t.title) != nil { return true }
        return await GooglePlacesService.shared.confidentPhoto(forFreeText: t.title, hint: t.location) != nil
    }

    /// Park: bundled → coordinate-anchored lookup (curated pin, so it usually resolves).
    static func has(park p: Park) async -> Bool {
        if KnownLocalPhoto.name(forTitle: p.title) != nil { return true }
        return await GooglePlacesService.shared.confidentPhoto(name: p.title, coordinate: p.coordinate) != nil
    }
}

/// Filtered copies of the four Activities collections, keeping only items with a
/// resolvable photo. Runs the four types concurrently (each serial within, so the
/// Google lookups' network I/O overlaps) and returns the originals unchanged if it
/// can't finish within `deadline` (fail-open).
@MainActor
func imagedActivities(
    events: [UpcomingEvent], clubs: [ClubView], trails: [Trail], parks: [Park],
    deadline: Double = 3.0
) async -> (events: [UpcomingEvent], clubs: [ClubView], trails: [Trail], parks: [Park]) {

    let filtered = await withDeadline(deadline) {
        async let e = keepImaged(events) { await ActivityImage.has(event: $0) }
        async let c = keepImaged(clubs) { await ActivityImage.has(club: $0) }
        async let t = keepImaged(trails) { await ActivityImage.has(trail: $0) }
        async let p = keepImaged(parks) { await ActivityImage.has(park: $0) }
        return (await e, await c, await t, await p)
    }
    guard let f = filtered else { return (events, clubs, trails, parks) }   // timed out → keep all
    return (f.0, f.1, f.2, f.3)
}

/// Keep the items for which `has` is true, preserving order.
@MainActor
private func keepImaged<T>(_ items: [T], _ has: (T) async -> Bool) async -> [T] {
    var kept: [T] = []
    kept.reserveCapacity(items.count)
    for item in items {
        if Task.isCancelled { return items }   // deadline fired → don't hide anything
        if await has(item) { kept.append(item) }
    }
    return kept
}

/// Run `op`, or return nil if it doesn't finish within `seconds`.
@MainActor
private func withDeadline<T: Sendable>(_ seconds: Double, _ op: @escaping @MainActor () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { @MainActor in await op() }
        group.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
