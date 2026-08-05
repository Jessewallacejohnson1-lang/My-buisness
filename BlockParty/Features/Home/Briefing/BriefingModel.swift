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
    func vote(_ api: BriefingAPI, optionIndex: Int) async {
        guard let current = payload, let touch = current.touch, !touch.hasVoted else { return }
        let previous = current
        payload = current.applying(touch: touch.applyingVote(optionIndex))

        do {
            try await api.vote(touchId: touch.id, optionIndex: optionIndex)
        } catch {
            Log.network("touch vote failed: \(error.localizedDescription)")
            payload = previous
        }
    }

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

nonisolated extension BriefingPayload {
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
