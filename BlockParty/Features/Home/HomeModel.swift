//
//  HomeModel.swift
//  Block Party — Home data: today's events + the daily quest, with optimistic writes.
//

import Foundation
import Combine

@MainActor
final class HomeModel: ObservableObject {
    @Published var today: [TimelineEvent] = []
    @Published var board: TodayInStJoeContent = .loading  // curated town board (board_items)
    @Published var weekGoing = 0   // town-wide RSVPs, today → +7 days (the roll call)
    @Published var quest: DailyQuest?
    @Published var questCount = 0
    @Published var questDone = false
    @Published var name: String?
    @Published var loading = true
    @Published var loaded = false
    @Published var upcoming: [UpcomingEvent] = []
    @Published var communityFeedLoaded = false
    @Published var feedPostings: [FeedPosting] = []
    @Published var feedLoaded = false
    /// A real feed outage, distinct from an empty town. Only ever true when we have
    /// nothing to show — a refresh error over an already-loaded feed keeps the feed.
    @Published var feedFailed = false
    @Published private var feedGoingPreviews: [String: GoingPreview] = [:]
    @Published private var feedSavedIDs: Set<String> = []
    private var upcomingRsvpInFlight: Set<String> = []
    /// Desired RSVP states that have not yet been confirmed by an upcoming-feed
    /// read. This survives stale GET snapshots that race a successful POST.
    private var upcomingRsvpOverrides: [String: Bool] = [:]
    /// Only the most recently started lower-feed read may reconcile its response.
    private var upcomingLoadGeneration = 0
    private var feedLoadGeneration = 0

    var feedSections: [FeedCardSection] {
        FeedSectioning.sections(for: dedupeRecurring(feedPostings))
            .map {
                $0.mapped(
                    goingPreviews: feedGoingPreviews,
                    savedIDs: feedSavedIDs
                )
            }
    }

    func load(_ api: CommunityAPI, socialAPI: SocialAPI) async {
        if !loaded { loading = true }
        // Prefer the canonical community name (what the profile shows/edits);
        // fall back to the email-derived first name only when none is set.
        let emailName = firstNameFromEmail(await api.currentEmail())
        name = Interests.displayName ?? emailName
        do {
            today = try await api.getTodayEvents()
            // Roll call: today's RSVPs + the week ahead's, town-wide. getTodayEvents is
            // event_date == today and getWeekEvents is > today, so there's no overlap.
            let todayGoing = today.reduce(0) { $0 + $1.goingCount }
            let weekAhead = (try? await api.getWeekEvents()) ?? []
            weekGoing = todayGoing + weekAhead.reduce(0) { $0 + $1.goingCount }
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
            // Leave whatever we have; the UI shows calm empty states.
            Log.network("HomeModel.load today/quest: \(error)")
        }

        // The lower community feed is deliberately independent of the Today agenda:
        // a feed failure leaves both the existing feed and today's schedule intact.
        upcomingLoadGeneration += 1
        let loadGeneration = upcomingLoadGeneration
        do {
            let events = try await api.getUpcomingEvents()
            if loadGeneration == upcomingLoadGeneration {
                upcoming = events
                mergeUpcomingRsvpOverrides()
                communityFeedLoaded = true
            }
        } catch {
            if loadGeneration == upcomingLoadGeneration {
                Log.network("HomeModel.load upcoming: \(error)")
                communityFeedLoaded = true
            }
        }

        await loadFeed(socialAPI)

        // The curated town board — its own fetch so a board hiccup never disturbs
        // the timeline above, and vice versa.
        do {
            let items = try await api.getTodayInStJoe()
            if items.isEmpty {
                if let line = try await api.getEvergreenLine() {
                    board = .evergreen(line)
                } else {
                    board = .empty
                }
            } else {
                board = .items(items)
            }
        } catch {
            if case .loading = board { board = .empty }  // never stick on the spinner
            Log.network("HomeModel.load board: \(error)")
        }

        loading = false
        loaded = true
    }

    /// The social feed has its own failure boundary so agenda, roll-call, quest,
    /// and board loading remain intact if a social RPC is unavailable.
    func loadFeed(_ api: SocialAPI) async {
        feedLoadGeneration += 1
        let generation = feedLoadGeneration
        do {
            let postings = try await api.getFeedPostings()
            let hydrated = try await api.hydrateUserState(postings)
            let previews: [String: GoingPreview]
            do {
                previews = try await api.goingPreviews(eventIds: hydrated.map(\.id))
            } catch {
                previews = [:]
                Log.network("HomeModel.load going previews: \(error)")
            }
            let saved = (try? await api.savedEventIds(in: hydrated.map(\.id))) ?? []
            guard generation == feedLoadGeneration else { return }
            feedPostings = hydrated
            feedGoingPreviews = previews
            feedSavedIDs = saved
            feedLoaded = true
        } catch {
            guard generation == feedLoadGeneration else { return }
            feedLoaded = true
            Log.network("HomeModel.load feed: \(error)")
        }
    }

    #if DEBUG
    /// Loads a deterministic local state for the community-feed simulator preview.
    /// It deliberately bypasses every backend API so preview launches are reliable.
    func loadCommunityFeedPreview() {
        today = CommunityFeedPreview.today
        board = .empty
        weekGoing = 0
        quest = nil
        questCount = 0
        questDone = false
        name = "Neighbor"
        upcoming = CommunityFeedPreview.events
        communityFeedLoaded = true
        upcomingRsvpInFlight = []
        upcomingRsvpOverrides = [:]
        loading = false
        loaded = true
    }
    #endif

    func setFeedLike(
        _ api: SocialAPI,
        eventID: String,
        liked: Bool
    ) async {
        guard let index = feedPostings.firstIndex(where: { $0.id == eventID }) else { return }
        let previousLiked = feedPostings[index].liked
        let previousCount = feedPostings[index].likeCount
        guard previousLiked != liked else { return }

        feedPostings[index].liked = liked
        feedPostings[index].likeCount = max(0, previousCount + (liked ? 1 : -1))
        do {
            if liked {
                try await api.likeEvent(eventID)
            } else {
                try await api.unlikeEvent(eventID)
            }
        } catch {
            if let rollbackIndex = feedPostings.firstIndex(where: { $0.id == eventID }),
               feedPostings[rollbackIndex].liked == liked {
                feedPostings[rollbackIndex].liked = previousLiked
                feedPostings[rollbackIndex].likeCount = previousCount
            }
            Log.network("HomeModel.setFeedLike \(eventID): \(error)")
        }
    }

    func setFeedJoined(
        _ api: CommunityAPI,
        eventID: String,
        joined: Bool
    ) async {
        guard let index = feedPostings.firstIndex(where: { $0.id == eventID }) else { return }
        let previousJoined = feedPostings[index].rsvpd
        let previousCount = feedPostings[index].goingCount
        let event = feedPostings[index]
        guard previousJoined != joined else { return }

        feedPostings[index].rsvpd = joined
        feedPostings[index].goingCount = max(0, previousCount + (joined ? 1 : -1))
        do {
            if joined {
                try await api.rsvpEvent(eventID)
                if let date = event.eventDate, await Reminders.requestAuth() {
                    await Reminders.schedule(
                        eventId: eventID,
                        title: event.title,
                        date: date,
                        startTime: event.startTime
                    )
                }
            } else {
                try await api.unRsvpEvent(eventID)
                Reminders.cancel(eventId: eventID)
            }
        } catch {
            if let rollbackIndex = feedPostings.firstIndex(where: { $0.id == eventID }),
               feedPostings[rollbackIndex].rsvpd == joined {
                feedPostings[rollbackIndex].rsvpd = previousJoined
                feedPostings[rollbackIndex].goingCount = previousCount
            }
            Log.network("HomeModel.setFeedJoined \(eventID): \(error)")
        }
    }

    func setFeedSaved(
        _ api: SocialAPI,
        eventID: String,
        saved: Bool
    ) async {
        let wasSaved = feedSavedIDs.contains(eventID)
        guard wasSaved != saved else { return }
        if saved { feedSavedIDs.insert(eventID) } else { feedSavedIDs.remove(eventID) }
        do {
            if saved { try await api.saveEvent(eventID) } else { try await api.unsaveEvent(eventID) }
        } catch {
            // Roll back the optimistic toggle if the write failed.
            if saved { feedSavedIDs.remove(eventID) } else { feedSavedIDs.insert(eventID) }
            Log.network("HomeModel.setFeedSaved \(eventID): \(error)")
        }
    }

    func feedComments(_ api: SocialAPI, eventID: String) async throws -> [EventComment] {
        try await api.comments(eventId: eventID)
    }

    func addFeedComment(
        _ api: SocialAPI,
        eventID: String,
        body: String
    ) async throws -> EventComment {
        try await api.addComment(eventId: eventID, body: body)
    }

    func toggleRsvp(_ api: CommunityAPI, _ ev: TimelineEvent) async {
        guard let i = today.firstIndex(where: { $0.id == ev.id }) else { return }
        let wasGoing = today[i].rsvpd
        today[i].rsvpd.toggle()
        today[i].goingCount += wasGoing ? -1 : 1
        weekGoing += wasGoing ? -1 : 1
        do {
            if wasGoing { try await api.unRsvpEvent(ev.id) } else { try await api.rsvpEvent(ev.id) }
            // A concurrent load() may have replaced `today` with a pre-write snapshot
            // while the request was in flight; re-assert the intended state by id so a
            // successful RSVP isn't silently reverted to the server's stale value.
            if let j = today.firstIndex(where: { $0.id == ev.id }), today[j].rsvpd == wasGoing {
                today[j].rsvpd = !wasGoing
                today[j].goingCount += wasGoing ? -1 : 1
            }
        } catch {
            // Re-resolve by id: a concurrent load() may have replaced `today`.
            weekGoing += wasGoing ? 1 : -1
            guard let j = today.firstIndex(where: { $0.id == ev.id }) else { return }
            today[j].rsvpd = wasGoing
            today[j].goingCount += wasGoing ? 1 : -1
        }
    }

    /// RSVP from the lower community feed. This intentionally does not affect the
    /// Today agenda or roll-call because same-day events are excluded from that feed.
    func toggleUpcomingRsvp(_ api: CommunityAPI, _ event: UpcomingEvent) async {
        guard !upcomingRsvpInFlight.contains(event.id) else { return }
        guard let i = upcoming.firstIndex(where: { $0.id == event.id }) else { return }
        let wasGoing = upcoming[i].rsvpd
        let intendedState = !wasGoing
        upcomingRsvpOverrides[event.id] = intendedState
        upcoming[i].rsvpd = intendedState
        upcoming[i].goingCount += intendedState ? 1 : -1
        upcomingRsvpInFlight.insert(event.id)
        defer { upcomingRsvpInFlight.remove(event.id) }
        do {
            if wasGoing { try await api.unRsvpEvent(event.id) } else { try await api.rsvpEvent(event.id) }
        } catch {
            upcomingRsvpOverrides.removeValue(forKey: event.id)
            // Re-resolve by id in case a concurrent load() replaced the feed. Only
            // undo an active optimistic value; a newer snapshot may already have
            // restored the pre-toggle state, whose count must not be inverted again.
            guard let j = upcoming.firstIndex(where: { $0.id == event.id }) else { return }
            guard upcoming[j].rsvpd == intendedState else { return }
            upcoming[j].rsvpd = wasGoing
            upcoming[j].goingCount += wasGoing ? 1 : -1
        }
    }

    /// Reconcile a just-fetched snapshot with local RSVP writes. An override is
    /// cleared only once a server read agrees with it; otherwise the desired state
    /// is reapplied once to this snapshot, including its matching count delta.
    private func mergeUpcomingRsvpOverrides() {
        let overrides = upcomingRsvpOverrides
        for (eventId, desiredState) in overrides {
            guard let i = upcoming.firstIndex(where: { $0.id == eventId }) else {
                if !upcomingRsvpInFlight.contains(eventId) {
                    upcomingRsvpOverrides.removeValue(forKey: eventId)
                }
                continue
            }
            if upcoming[i].rsvpd == desiredState {
                if !upcomingRsvpInFlight.contains(eventId) {
                    upcomingRsvpOverrides.removeValue(forKey: eventId)
                }
            } else {
                upcoming[i].rsvpd = desiredState
                upcoming[i].goingCount += desiredState ? 1 : -1
            }
        }
    }

    func completeQuest(_ api: CommunityAPI) async {
        guard let quest, !questDone else { return }
        questDone = true
        questCount += 1
        do { try await api.completeQuest(quest.id) }
        catch { questDone = false; questCount -= 1 }
    }
}
