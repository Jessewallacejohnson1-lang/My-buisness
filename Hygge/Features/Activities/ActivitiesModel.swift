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
    /// from the backend (see CityParks.swift). A `var` so the imageless-card filter
    /// can prune it alongside the fetched collections.
    @Published private(set) var parks: [Park] = CityParks.all
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
        // Fetch into locals (seeded from the current values so a failed refresh keeps
        // what's on screen), filter, then publish all four collections ONCE at the end.
        // Publishing the unfiltered fetch first would flash the imageless cards on a
        // `.refreshable` (where `loaded` is already true), breaking the no-pop invariant.
        var newClubs = clubs, newTrails = trails, newEvents = events
        do {
            newClubs = try await api.getApprovedClubs()
            newTrails = try await api.getTrails()
            newEvents = try await api.getUpcomingEvents()
            failed = false
        } catch {
            // Only flag failed when we have nothing to show, so a refresh error
            // doesn't blank data the user is already looking at.
            if newClubs.isEmpty && newTrails.isEmpty && newEvents.isEmpty { failed = true }
            Log.network("ActivitiesModel.load: \(error)")
        }
        // Hide imageless cards (a photo-forward Explore) before publishing, so nothing
        // pops out after the fact. Bounded + fail-open (see imagedActivities). The FULL
        // civic park set is fed in so every park is re-evaluated each load.
        let imaged = await imagedActivities(events: newEvents, clubs: newClubs, trails: newTrails, parks: CityParks.all)
        events = imaged.events; clubs = imaged.clubs; trails = imaged.trails; parks = imaged.parks
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
