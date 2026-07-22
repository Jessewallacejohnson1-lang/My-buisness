//
//  ActivityImageFilter.swift
//  Block Party — hides Activities cards that can't resolve a photo, so Explore stays
//  photo-forward (a product choice). "Has a photo" mirrors each card's own 3-tier
//  cascade exactly: an organizer-uploaded `imageUrl`, a bundled `KnownLocalPhoto`,
//  else a confidence-gated Google Places lookup (`VenuePhoto` / `GooglePlacesService`).
//  Both sides derive the venue through `ActivityVenue`, so the filter and the card can
//  never disagree about which place is being looked up.
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
    /// Event: organizer photo → bundled → venue lookup.
    static func has(event e: UpcomingEvent) async -> Bool {
        if e.imageUrl.flatMap(URL.init(string:)) != nil { return true }
        if KnownLocalPhoto.name(forTitle: e.title) != nil { return true }
        return await resolves(ActivityVenue.event(e))
    }

    /// Club: no photo field at all — only a venue lookup can supply one.
    /// NOTE: `clubs` is EMPTY in production (0 rows), so this path is dead weight
    /// today. Kept because the composer can create clubs; not worth optimising.
    static func has(club c: ClubView) async -> Bool {
        await resolves(ActivityVenue.club(c))
    }

    /// Trail: imageUrl → bundled → lookup. (`WobegonExploreCard` is a hardcoded view,
    /// not a fetched row, so it never passes through this filter.)
    static func has(trail t: Trail) async -> Bool {
        if t.imageUrl.flatMap(URL.init(string:)) != nil { return true }
        if KnownLocalPhoto.name(forTitle: t.title) != nil { return true }
        return await resolves(ActivityVenue.trail(t))
    }

    /// Park: bundled → coordinate-anchored lookup (curated pin, so it usually resolves).
    static func has(park p: Park) async -> Bool {
        if KnownLocalPhoto.name(forTitle: p.title) != nil { return true }
        return await resolves(ActivityVenue.park(p))
    }

    /// Does this venue clear Rule A and carry a photo? No curated anchor means no
    /// photo can ever clear the gate, so skip the round-trip entirely.
    private static func resolves(_ venue: ActivityVenue) async -> Bool {
        guard let anchor = venue.anchor else { return false }
        return await GooglePlacesService.shared.confidentPhoto(name: venue.name, coordinate: anchor) != nil
    }
}

// MARK: - Tuning (measured, not guessed)

/// Stateless, so `nonisolated` — a MainActor-isolated constant can't be read from a
/// default argument without tripping the 0-warning bar.
private nonisolated enum PhotoFilterTuning {

    /// How long the whole filter may take before it gives up and shows everything.
    ///
    /// MEASURED 2026-07-21 against the live Places API with today's real content. The
    /// long pole is the city-park lane: 6 of the 9 parks have no bundled photo, so each
    /// needs one `searchText` plus (when a candidate clears Rule A) one `details`.
    ///   • Run SERIALLY, as this filter used to: 12 sequential requests, **3.07 s** on
    ///     a fast desktop connection — so a 3.0 s deadline fired on EVERY cold load and
    ///     the photo-forward filter was silently inert on first paint.
    ///   • Run in `maxConcurrentLookups`-wide windows: **1.42 s** for the same work
    ///     (2.2x), because the critical path collapses to one venue's search → details
    ///     pair rather than twelve requests end to end.
    /// 3.0 s therefore stays, but it is now a genuine safety valve with ~2x headroom
    /// instead of a budget the normal path blows through. It is not raised further
    /// because `ActivitiesModel.loaded` gates the tab reveal: every extra second spent
    /// here is an extra second of skeleton.
    static let deadlineSeconds = 3.0

    /// Photo lookups in flight at once, per collection. Each is one Places `searchText`
    /// (plus at most one `details`), so this is the burst we're willing to send Google
    /// for a single screen. Six covers the whole city-park set in one wave and keeps a
    /// future 50-event town from firing 50 requests simultaneously.
    static let maxConcurrentLookups = 6
}

// MARK: - Filter

/// Filtered copies of the four Activities collections, keeping only items with a
/// resolvable photo. Runs the four types concurrently (and, within each type, up to
/// `maxConcurrentLookups` at a time) and returns the originals unchanged if it can't
/// finish within the deadline (fail-open).
@MainActor
func imagedActivities(
    events: [UpcomingEvent], clubs: [ClubView], trails: [Trail], parks: [Park],
    deadline: Double = PhotoFilterTuning.deadlineSeconds
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

/// Keep the items for which `has` is true, preserving order. Items are evaluated in
/// windows of `maxConcurrentLookups` so their network round-trips overlap; verdicts
/// are collected by index, so concurrency can never reorder a shelf.
@MainActor
private func keepImaged<T>(_ items: [T], _ has: @escaping @MainActor (T) async -> Bool) async -> [T] {
    guard !items.isEmpty else { return [] }
    var verdicts: [Bool] = []
    verdicts.reserveCapacity(items.count)
    for start in stride(from: 0, to: items.count, by: PhotoFilterTuning.maxConcurrentLookups) {
        // The deadline fired while an earlier window was resolving: stop opening new
        // Places round-trips and fail open (keep everything) rather than block on the
        // rest. `withDeadline` cancels this task the moment it gives up.
        if Task.isCancelled { return items }
        let end = min(start + PhotoFilterTuning.maxConcurrentLookups, items.count)
        verdicts += await concurrentVerdicts(Array(items[start..<end]), has)
    }
    if Task.isCancelled { return items }   // deadline fired → don't hide anything
    return items.indices.compactMap { verdicts[$0] ? items[$0] : nil }
}

/// `has` applied to every item at once, returned in input order.
@MainActor
private func concurrentVerdicts<T>(_ items: [T], _ has: @escaping @MainActor (T) async -> Bool) async -> [Bool] {
    await withTaskGroup(of: (Int, Bool).self) { group -> [Bool] in
        for (i, item) in items.enumerated() {
            group.addTask { @MainActor in (i, await has(item)) }
        }
        var verdicts = [Bool](repeating: false, count: items.count)
        for await (i, ok) in group { verdicts[i] = ok }
        return verdicts
    }
}

/// Run `op`, or return nil if it doesn't finish within `seconds` — and RETURN AT the
/// deadline, not after `op` eventually finishes.
///
/// This cannot be a `withTaskGroup`: a group awaits (drains) every child before it
/// returns, so a `group.addTask { await op() }` child that ignores cancellation holds
/// the whole call open for the full duration of `op` — which is exactly why the old
/// 3 s deadline never fired and the Activities tab hung 20-45 s on a cold load. Instead
/// `op` runs as an UNSTRUCTURED task and races a sleep on a one-shot continuation:
/// whichever finishes first settles it, the loser is ignored, and a slow `op` is
/// cancelled and left to unwind on its own (its structured children — `keepImaged`'s
/// windows — see the cancellation and stop opening new Places calls).
@MainActor
private func withDeadline<T: Sendable>(_ seconds: Double, _ op: @escaping @MainActor () async -> T) async -> T? {
    let work = Task { @MainActor in await op() }

    let result: T? = await withCheckedContinuation { continuation in
        let gate = DeadlineGate<T>(continuation)
        Task { await gate.settle(with: await work.value) }
        Task { try? await Task.sleep(for: .seconds(seconds)); await gate.settle(with: nil) }
    }

    work.cancel()   // deadline won → stop the abandoned work from billing further windows
    return result
}

/// One-shot resume guard for `withDeadline`'s race. An actor (so it's `Sendable` and
/// safe to capture in the two racing tasks) that resumes the continuation exactly once
/// — the second `settle` is a no-op, so neither racer can double-resume.
private actor DeadlineGate<T: Sendable> {
    private var continuation: CheckedContinuation<T?, Never>?
    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }
    func settle(with value: T?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
