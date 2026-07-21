//
//  ActivitiesModel.swift
//  Hygge — the unified browse surface: clubs, trails, and upcoming events.
//

import Foundation
import Combine

@MainActor
final class ActivitiesModel: ObservableObject {
    @Published var clubs: [ClubView] = []
    @Published var trails: [Trail] = []
    @Published var events: [UpcomingEvent] = []
    /// The city's official park system — a fixed civic dataset, not fetched
    /// from the backend (see CityParks.swift).
    let parks: [Park] = CityParks.all
    @Published var loading = true
    @Published var loaded = false
    /// A real fetch failure with nothing to show — so the view can say "couldn't
    /// reach the town" instead of the calm "nothing here yet" empty state (which
    /// would misrepresent an outage as an empty town). Mirrors CalendarModel.
    @Published var failed = false

    /// Clubs with a join/leave request outstanding — a second tap on the same club
    /// is ignored so an out-of-order POST/DELETE can't leave local state opposite
    /// the server.
    private var joinInFlight: Set<String> = []

    func load(_ api: CommunityAPI) async {
        if !loaded { loading = true }
        do {
            clubs = try await api.getApprovedClubs()
            trails = try await api.getTrails()
            events = try await api.getUpcomingEvents()
            failed = false
        } catch {
            // Only flag failed when we have nothing to show, so a refresh error
            // doesn't blank data the user is already looking at.
            if clubs.isEmpty && trails.isEmpty && events.isEmpty { failed = true }
            Log.network("ActivitiesModel.load: \(error)")
        }
        loading = false
        loaded = true
    }

    func toggleJoin(_ api: CommunityAPI, _ club: ClubView) async {
        guard !joinInFlight.contains(club.id) else { return }   // ignore taps while a request is outstanding
        guard let i = clubs.firstIndex(where: { $0.id == club.id }) else { return }
        let wasJoined = clubs[i].joined
        clubs[i].joined.toggle()
        clubs[i].memberCount += wasJoined ? -1 : 1
        joinInFlight.insert(club.id)
        defer { joinInFlight.remove(club.id) }
        do {
            if wasJoined { try await api.leaveClub(club.id) } else { try await api.joinClub(club.id) }
        } catch {
            // Re-resolve by id: a concurrent load() may have replaced `clubs`.
            guard let j = clubs.firstIndex(where: { $0.id == club.id }) else { return }
            clubs[j].joined = wasJoined
            clubs[j].memberCount += wasJoined ? 1 : -1
        }
    }
}
