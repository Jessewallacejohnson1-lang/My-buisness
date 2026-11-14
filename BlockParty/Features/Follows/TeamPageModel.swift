//
//  TeamPageModel.swift
//  Block Party — what a school's page (`TeamPage`) reads: `team_page`, the school with its activities and its events
//  from yesterday on for its events card, in one read (BP app school-search 05 and 06). Every read goes through the
//  injected client, the app's one (`Supabase.app`) unless a test hands it a fake (the run's review).
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
    /// The school's events from yesterday on, nil while they load: they come with the page.
    private(set) var events: [SchoolEvent]?

    init(team: Game.Team, supabase: Supabase? = nil) {
        self.team = team
        api = CommunityAPI(supabase ?? .app)
    }

    /// Reads the page, its events with it. A failed read keeps what the page showed.
    func load(_ actions: RealLifeActions) async {
        guard let id = team.id else { return }
        if let read = try? await api.teamPage(id) {
            profile = read
            events = Self.events(read)
            actions.read(activities: read.activities)
        }
        failed = profile == nil
    }

    /// The page's events, each with its activity's icon and no middle-school tag, soonest first.
    static func events(_ page: TeamProfile) -> [SchoolEvent] {
        let symbols = Dictionary(page.activities.map { ($0.id, TeamPage.symbol($0)) }, uniquingKeysWith: { a, _ in a })
        return SchoolEvents.sorted(page.events.compactMap { event in
            Town.midnight(event.date).map {
                SchoolEvent(id: event.id, title: SchoolEvents.title(event.title), day: $0, time: event.time,
                            location: event.location, symbol: event.activity.flatMap { symbols[$0] } ?? "calendar")
            }
        })
    }
}
