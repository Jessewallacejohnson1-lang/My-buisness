//
//  HomeModel.swift
//  Hygge — Home data: today's events + the daily quest, with optimistic writes.
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

    func load(_ api: CommunityAPI) async {
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

    func completeQuest(_ api: CommunityAPI) async {
        guard let quest, !questDone else { return }
        questDone = true
        questCount += 1
        do { try await api.completeQuest(quest.id) }
        catch { questDone = false; questCount -= 1 }
    }
}
