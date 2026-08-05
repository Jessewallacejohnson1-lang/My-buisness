//
//  BriefingModel.swift
//  Block Party — state for the Today tab briefing.
//
//  House pattern: a `SomethingView` paired with a `SomethingModel` that owns state
//  and API calls.
//
//  Cache-first. On appear the cached payload renders immediately, then a refresh
//  runs in the background and swaps in quietly. A refresh failure leaves the
//  cached briefing on screen — an outage must not blank the tab.
//
//  Refresh-once-daily: the briefing changes at 6 AM, so re-fetching on every tab
//  switch is wasted. A fetch happens when the cached payload is for a different
//  town-date than today, or when the user pulls to refresh.
//

import Combine
import Foundation

@MainActor
final class BriefingModel: ObservableObject {
    @Published private(set) var payload: BriefingPayload?
    @Published private(set) var isRefreshing = false
    /// True only when a refresh failed AND there is nothing cached to show.
    @Published private(set) var loadFailed = false
    @Published private(set) var hasLoaded = false

    /// Guards against a stale in-flight response overwriting a newer one, the
    /// same generation-counter pattern HomeModel uses.
    private var generation = 0

    // MARK: - Loading

    /// Renders the cache, then refreshes if the cached briefing is not today's.
    func load(_ api: BriefingAPI) async {
        #if DEBUG
        // `-briefing-state <name>` renders Today from a canned payload with no
        // network at all — the Phase 3 gate, and the only way to reach the
        // 0-event / none / degraded states on demand.
        if let seeded = Self.debugSeed {
            payload = seeded
            hasLoaded = true
            return
        }
        #endif

        if payload == nil, let cached = BriefingCache.load() {
            payload = cached
            hasLoaded = true
        }
        guard needsRefresh else { hasLoaded = true; return }
        await refresh(api)
    }

    /// Unconditional re-fetch. Pull-to-refresh calls this.
    func refresh(_ api: BriefingAPI) async {
        generation += 1
        let mine = generation
        isRefreshing = true
        defer { if mine == generation { isRefreshing = false } }

        do {
            let result = try await api.today()
            guard mine == generation else { return }
            payload = result.payload
            loadFailed = false
            hasLoaded = true
            BriefingCache.save(result.raw)
        } catch {
            guard mine == generation else { return }
            Log.network("briefing refresh failed: \(error.localizedDescription)")
            // Only a failure with nothing to fall back on is user-visible.
            loadFailed = payload == nil
            hasLoaded = true
        }
    }

    /// True when there is no payload, or the one we have is for another day.
    var needsRefresh: Bool {
        guard let payload else { return true }
        return payload.briefingDate != Self.townToday()
    }

    // MARK: - Voting

    /// Applies the vote locally first so the poll answers the tap immediately,
    /// then writes it. On failure the optimistic change is rolled back by
    /// restoring the previous payload — the poll must never show a vote that did
    /// not land.
    /// Returns whether the vote actually persisted, so a caller only records an
    /// analytics event for a write that landed.
    @discardableResult
    func vote(_ api: BriefingAPI, optionIndex: Int) async -> Bool {
        guard let current = payload, let touch = current.touch, !touch.hasVoted else { return false }
        let previous = current
        payload = current.applying(touch: touch.applyingVote(optionIndex))

        do {
            try await api.vote(touchId: touch.id, optionIndex: optionIndex)
            return true
        } catch {
            Log.network("touch vote failed: \(error.localizedDescription)")
            payload = previous
            return false
        }
    }

    /// Same shape as voting: flip locally so the control answers the tap, write,
    /// and restore the previous payload if the write fails. The going count moves
    /// with it, so the number never disagrees with the button beside it.
    @discardableResult
    func setRsvp(_ api: CommunityAPI, event: BriefingEvent, going: Bool) async -> Bool {
        guard let current = payload else { return false }
        let previous = current
        payload = current.applyingRsvp(eventID: event.id, going: going)

        do {
            if going {
                try await api.rsvpEvent(event.id)
            } else {
                try await api.unRsvpEvent(event.id)
            }
            return true
        } catch {
            Log.network("briefing rsvp failed: \(error.localizedDescription)")
            payload = previous
            return false
        }
    }

    #if DEBUG
    /// The canned payload named by `-briefing-state <name>`, if any. Defaults to
    /// the three-event sample when the flag is passed with no name.
    static var debugSeed: BriefingPayload? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-briefing-state") else { return nil }
        let name = (i + 1 < args.count && !args[i + 1].hasPrefix("-")) ? args[i + 1] : "sample"
        return BriefingSample.payload(name)
    }
    #endif

    // MARK: - Helpers

    /// Today in the town's timezone as "YYYY-MM-DD". The briefing is anchored to
    /// the town, not the device — a user in another timezone still gets St. Joe's
    /// day.
    nonisolated static func townToday(_ now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Town.timeZone
        let c = cal.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Immutable transforms

nonisolated extension BriefingTouch {
    /// A copy with the caller's vote applied. Never mutates — the optimistic
    /// update replaces the value rather than editing it in place.
    func applyingVote(_ index: Int) -> BriefingTouch {
        guard !hasVoted, choices.indices.contains(index) else { return self }
        var counts = voteCounts
        if counts.indices.contains(index) { counts[index] += 1 }
        return BriefingTouch(
            id: id, kind: kind, prompt: prompt, options: options, body: body,
            voteCounts: counts, totalVotes: totalVotes + 1, myVote: index
        )
    }
}

nonisolated extension BriefingEvent {
    /// A copy with the caller's RSVP flipped and the going count moved to match.
    /// The count is floored at zero so a stale payload cannot render "-1 going".
    func applyingRsvp(_ going: Bool) -> BriefingEvent {
        guard going != rsvpd else { return self }
        return BriefingEvent(
            rank: rank, id: id, title: title, eventDate: eventDate, startTime: startTime,
            location: location, imageUrl: imageUrl, clubName: clubName, category: category,
            goingCount: max(0, goingCount + (going ? 1 : -1)), goingAvatars: goingAvatars,
            likeCount: likeCount, commentCount: commentCount,
            rsvpd: going, saved: saved, liked: liked
        )
    }
}

nonisolated extension BriefingPayload {
    /// A copy with one featured event's RSVP state changed.
    func applyingRsvp(eventID: String, going: Bool) -> BriefingPayload {
        applying(featured: featured.map { $0.id == eventID ? $0.applyingRsvp(going) : $0 })
    }

    private func applying(featured newFeatured: [BriefingEvent]) -> BriefingPayload {
        BriefingPayload(
            briefingDate: briefingDate, tz: tz, status: status, publishedAt: publishedAt,
            almanac: almanac, weather: weather, featured: newFeatured,
            featuredFallback: featuredFallback, touch: touch,
            spotlight: spotlight, caughtUp: caughtUp
        )
    }

    /// A copy carrying a different touch, leaving every other module untouched.
    func applying(touch newTouch: BriefingTouch) -> BriefingPayload {
        BriefingPayload(
            briefingDate: briefingDate, tz: tz, status: status, publishedAt: publishedAt,
            almanac: almanac, weather: weather, featured: featured,
            featuredFallback: featuredFallback, touch: newTouch,
            spotlight: spotlight, caughtUp: caughtUp
        )
    }
}
