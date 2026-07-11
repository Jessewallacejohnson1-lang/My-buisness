//
//  HomeModel.swift
//  Hygge — Today data: the almanac's quest, today's agenda, and the interest feed,
//  with optimistic like/follow/RSVP writes.
//

import Foundation
import Combine

@MainActor
final class HomeModel: ObservableObject {
    @Published var today: [TimelineEvent] = []   // Zone 2 — today's agenda
    @Published var feed: [FeedPosting] = []       // Zone 3 — the interest feed
    @Published var quest: DailyQuest?             // Zone 1 — the quest momentum ring
    @Published var questCount = 0
    @Published var questDone = false
    @Published var name: String?
    @Published var loading = true
    @Published var loaded = false

    func load(_ api: CommunityAPI, _ social: SocialAPI) async {
        if !loaded { loading = true }
        // Prefer the canonical community name (what the profile shows/edits);
        // fall back to the email-derived first name only when none is set.
        let emailName = firstNameFromEmail(await api.currentEmail())
        name = Interests.displayName ?? emailName

        // Agenda + quest — one do/catch; calm empty states cover a failure.
        do {
            today = try await api.getTodayEvents()
            if let q = try await api.getTodayQuest() {
                quest = q
                questCount = (try? await api.getQuestCompletionCount(q.id)) ?? 0
                if let uid = await api.currentUserId() {
                    questDone = (try? await api.hasUserCompletedQuest(q.id, userId: uid)) ?? false
                }
            } else {
                quest = nil
            }
        } catch {
            Log.network("HomeModel.load today/quest: \(error)")
        }

        // The feed — its own do/catch so a feed hiccup never disturbs the agenda
        // above, and vice versa. Hydrate per-user liked/following state after.
        do {
            let raw = try await social.getFeedPostings(limit: 30)
            feed = (try? await social.hydrateUserState(raw)) ?? raw
        } catch {
            Log.network("HomeModel.load feed: \(error)")
        }

        #if DEBUG
        // Screenshot fixture: `-mock-feed` fills the feed with sample postings (real
        // bundled photos via KnownLocalPhoto titles) so the komoot card can be verified
        // headlessly before the social migration reaches prod. Never runs in release.
        if ProcessInfo.processInfo.arguments.contains("-mock-feed") { feed = HomeModel.mockFeed() }
        #endif

        loading = false
        loaded = true
    }

    func completeQuest(_ api: CommunityAPI) async {
        guard let quest, !questDone else { return }
        questDone = true
        questCount += 1
        do { try await api.completeQuest(quest.id) }
        catch { questDone = false; questCount -= 1 }
    }

    func toggleRsvp(_ api: CommunityAPI, _ ev: TimelineEvent) async {
        guard let i = today.firstIndex(where: { $0.id == ev.id }) else { return }
        let wasGoing = today[i].rsvpd
        today[i].rsvpd.toggle()
        today[i].goingCount += wasGoing ? -1 : 1
        do {
            if wasGoing { try await api.unRsvpEvent(ev.id) } else { try await api.rsvpEvent(ev.id) }
            // A concurrent load() may have replaced `today` with a pre-write snapshot
            // while the request was in flight; re-assert the intended state by id.
            if let j = today.firstIndex(where: { $0.id == ev.id }), today[j].rsvpd == wasGoing {
                today[j].rsvpd = !wasGoing
                today[j].goingCount += wasGoing ? -1 : 1
            }
        } catch {
            guard let j = today.firstIndex(where: { $0.id == ev.id }) else { return }
            today[j].rsvpd = wasGoing
            today[j].goingCount += wasGoing ? 1 : -1
        }
    }

    /// Optimistic like toggle on a feed posting, reconciled by id with rollback.
    func toggleLike(_ social: SocialAPI, _ posting: FeedPosting) async {
        guard let i = feed.firstIndex(where: { $0.id == posting.id }) else { return }
        let wasLiked = feed[i].liked
        feed[i].liked = !wasLiked
        feed[i].likeCount += wasLiked ? -1 : 1
        do {
            if wasLiked { try await social.unlikeEvent(posting.id) } else { try await social.likeEvent(posting.id) }
        } catch {
            guard let j = feed.firstIndex(where: { $0.id == posting.id }) else { return }
            feed[j].liked = wasLiked
            feed[j].likeCount += wasLiked ? 1 : -1
        }
    }

    /// Optimistic follow toggle. A follow targets a club/profile, so it applies to
    /// every posting from that same poster — flip them all, reconcile on failure.
    func toggleFollow(_ social: SocialAPI, _ posting: FeedPosting) async {
        let target = posting.posterTarget
        let wasFollowing = posting.following
        for idx in feed.indices where feed[idx].posterTarget == target {
            feed[idx].following = !wasFollowing
            feed[idx].followerCount += wasFollowing ? -1 : 1
        }
        do {
            if wasFollowing { try await social.unfollow(target) } else { try await social.follow(target) }
        } catch {
            for idx in feed.indices where feed[idx].posterTarget == target {
                feed[idx].following = wasFollowing
                feed[idx].followerCount += wasFollowing ? 1 : -1
            }
        }
    }

    #if DEBUG
    /// Sample feed for the `-mock-feed` launch arg (screenshot verification only —
    /// never runs in release). Titles match `KnownLocalPhoto` keys so the hero shows
    /// real bundled photos; counts are obviously illustrative, not seeded prod data.
    static func mockFeed() -> [FeedPosting] {
        let now = Date()
        return [
            FeedPosting(id: "mock-1", title: "St. Joseph Farmers Market",
                        eventDate: "2026-07-11", startTime: "9am", location: "Resource Training Center",
                        imageUrl: nil, createdAt: now.addingTimeInterval(-7200),
                        posterName: "St. Joe Farmers Market", posterAvatar: nil,
                        posterTarget: FollowTarget(type: .club, id: "mock-club-1"),
                        followerCount: 312, likeCount: 24, commentCount: 3, goingCount: 24,
                        liked: false, following: false, rsvpd: false),
            FeedPosting(id: "mock-2", title: "Trivia Night at Bad Habit Brewing",
                        eventDate: "2026-07-11", startTime: "6:30pm", location: "Bad Habit Brewing Co.",
                        imageUrl: nil, createdAt: now.addingTimeInterval(-3600),
                        posterName: "Bad Habit Brewing Co.", posterAvatar: nil,
                        posterTarget: FollowTarget(type: .club, id: "mock-club-2"),
                        followerCount: 540, likeCount: 61, commentCount: 8, goingCount: 11,
                        liked: true, following: true, rsvpd: false),
            FeedPosting(id: "mock-3", title: "Millstream Arts Festival",
                        eventDate: "2026-07-18", startTime: "10am", location: "Millstream Park",
                        imageUrl: nil, createdAt: now.addingTimeInterval(-18000),
                        posterName: "Millstream Arts", posterAvatar: nil,
                        posterTarget: FollowTarget(type: .profile, id: "mock-user-3"),
                        followerCount: 1842, likeCount: 479, commentCount: 6, goingCount: 210,
                        liked: false, following: false, rsvpd: false),
        ]
    }
    #endif
}
