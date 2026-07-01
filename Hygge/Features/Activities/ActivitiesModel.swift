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
    @Published var loading = true
    @Published var loaded = false

    func load(_ api: CommunityAPI) async {
        if !loaded { loading = true }
        do {
            clubs = try await api.getApprovedClubs()
            trails = try await api.getTrails()
            events = try await api.getUpcomingEvents()
        } catch {
            // calm empty state on error
        }
        loading = false
        loaded = true
    }

    func toggleJoin(_ api: CommunityAPI, _ club: ClubView) async {
        guard let i = clubs.firstIndex(where: { $0.id == club.id }) else { return }
        let wasJoined = clubs[i].joined
        clubs[i].joined.toggle()
        clubs[i].memberCount += wasJoined ? -1 : 1
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
