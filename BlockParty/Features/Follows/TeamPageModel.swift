//
//  TeamPageModel.swift
//  Block Party — what a school's page (`TeamPage`) reads: `team_page`, the school with its activities, and each
//  activity's coming events (`activity_events`) for its events card (BP app school-search 05). Every read goes
//  through the injected client, the app's one (`Supabase.app`) unless a test hands it a fake (the run's review).
//

import SwiftUI

@MainActor @Observable
final class TeamPageModel {
    let team: Game.Team
    let api: CommunityAPI
    /// The school and its activities; nil until read.
    private(set) var profile: TeamProfile?
    /// The page couldn't be read and there is none to show: the page says so once.
    private(set) var failed = false
    /// The school's coming events, nil while they load.
    private(set) var events: [SchoolEvent]?
    /// Every events read failed under a page that did load: the events card says so.
    private(set) var eventsFailed = false

    init(team: Game.Team, supabase: Supabase? = nil) {
        self.team = team
        api = CommunityAPI(supabase ?? .app)
    }

    /// Reads the page, then each activity's events. A refresh reads the events of the activities already on
    /// screen beside the page rather than after it (`team_page` takes about 3 s), and again only if the new page
    /// lists other activities with events. A failed read keeps what the page showed.
    func load(_ actions: RealLifeActions) async {
        guard let id = team.id else { return }
        let shown = profile.map { Self.withEvents($0.activities) } ?? []
        let early = shown.isEmpty ? nil : Task { await readEvents(shown) }
        do {
            if let read = try await api.teamPage(id) {
                profile = read
                actions.read(activities: read.activities)
            }
        } catch {}
        failed = profile == nil
        guard let profile else {
            early?.cancel()
            return
        }
        let wanted = Self.withEvents(profile.activities)
        let lists: [[SchoolEvent]]?
        if let early, wanted == shown {
            lists = await early.value
        } else {
            early?.cancel()
            lists = await readEvents(wanted)
        }
        if let lists {
            events = SchoolEvents.merged(lists)
            eventsFailed = false
        } else {
            eventsFailed = events == nil
        }
    }

    /// The activities with a coming event, each with its icon: only these have events to read.
    private static func withEvents(_ activities: [TeamProfile.Activity]) -> [Read] {
        activities.filter { $0.next != nil }.map { Read(id: $0.id, symbol: TeamPage.symbol($0)) }
    }

    private struct Read: Equatable {
        let id: String
        let symbol: String
    }

    /// Each activity's events, read together and handed back in the activities' order, whichever lands first, so
    /// an event two share always takes the first one's icon. A read that fails leaves its activity out; nil when
    /// every one failed.
    private func readEvents(_ reads: [Read]) async -> [[SchoolEvent]]? {
        guard !reads.isEmpty else { return [] }
        var lists = [[SchoolEvent]?](repeating: nil, count: reads.count)
        await withTaskGroup(of: (Int, [SchoolEvent]?).self) { group in
            for (index, read) in reads.enumerated() {
                group.addTask { @MainActor [api] in
                    guard let found = try? await api.activityEvents(read.id) else { return (index, nil) }
                    return (index, found.compactMap { event in
                        Town.midnight(event.date).map {
                            SchoolEvent(id: event.id, title: SchoolEvents.title(event.title), day: $0, time: event.time,
                                        location: event.location, symbol: read.symbol)
                        }
                    })
                }
            }
            for await (index, list) in group { lists[index] = list }
        }
        let read = lists.compactMap { $0 }
        return read.isEmpty ? nil : read
    }
}
