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
        if var read = try? await api.teamPage(id) {
            #if DEBUG
            if LaunchFlags.has(.teamMeets) { read = Self.sartellMeets(read) }
            #endif
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

    #if DEBUG
    /// `-team-meets`: Sartell's 12 club meeting times as `20261113202211_club_meeting_times.sql` stores them, laid on
    /// the live read before that migration is live (nothing-scheduled 03). A read that carries a time keeps its own.
    static func sartellMeets(_ page: TeamProfile) -> TeamProfile {
        guard page.short == "Sartell" else { return page }
        let rules = (try? JSONDecoder().decode([String: [MeetingRule]].self, from: Data(#"""
        {"Bible Study": [{"days": ["fri"], "time": "08:00"}], "Birding Club": [{"days": ["tue"], "time": "08:00"}],
         "Crochet & Knitting Club": [{"days": ["thu"], "time": "07:45"}],
         "Fellowship of Christian Athletes": [{"days": ["thu"], "time": "07:15"}],
         "F.E.M. Club": [{"days": ["tue"], "time": "08:00"}], "Honor Society": [{"days": ["tue"], "weeks": [2]}],
         "Letters of Love": [{"days": ["fri"], "weeks": [2]}],
         "Path to Healthcare Club": [{"days": ["fri"], "every": 2, "time": "07:45"}],
         "Sartell K-Pop Dance Cover Club": [{"days": ["wed"], "time": "After school"}],
         "S.A.F.E. Club": [{"days": ["mon"], "weeks": [1, 3], "time": "08:00"}],
         "Student Council": [{"days": ["fri"], "time": "07:45"}], "Table Top Gaming Club": [{"days": ["wed"], "time": "08:00"}]}
        """#.utf8))) ?? [:]
        var page = page
        page.activities = page.activities.map { a in
            guard a.meets == nil, let meets = rules[a.name] else { return a }
            return TeamProfile.Activity(id: a.id, name: a.name, note: a.note, kind: a.kind, following: a.following,
                                        next: a.next, meets: meets)
        }
        return page
    }
    #endif
}
