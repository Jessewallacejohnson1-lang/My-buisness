//
//  AddModel.swift
//  Hygge — post an event / club / trail. Mirrors the Expo add.tsx pipeline:
//  validate → optional photo upload → Claude moderation → insert (approved, or
//  pending when moderation is unavailable). Events can repeat weekly.
//

import Foundation
import Combine

enum AddKind: String, Identifiable, CaseIterable {
    case event, club, trail
    var id: String { rawValue }
    var title: String {
        switch self { case .event: return "Event"; case .club: return "Club"; case .trail: return "Trail" }
    }
}

@MainActor
final class AddModel: ObservableObject {
    // Shared
    @Published var title = ""
    @Published var location = ""
    @Published var details = ""      // maps to `description` column
    @Published var photo: Data?

    // Event
    @Published var eventDate = Date()
    @Published var time = AddModel.defaultEveningTime()
    @Published var repeatWeeklyCount = 1

    // Club
    @Published var host = ""
    @Published var schedule = ""
    @Published var vibe = ""
    @Published var expectations = ""

    // Trail
    @Published var length = ""
    @Published var difficulty = ""

    // State
    @Published var submitting = false
    @Published var error: String?
    @Published var posted = false
    @Published var pendingNotice = false

    private static func defaultEveningTime() -> Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var startTimeString: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "h:mm a"
        return f.string(from: time)
    }

    func submit(kind: AddKind, api: CommunityAPI, storage: Storage, moderation: Moderation) async {
        error = nil
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = details.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !t.isEmpty else { error = "Please add a title."; return }
        switch kind {
        case .event: guard !loc.isEmpty else { error = "Where is it happening?"; return }
        case .trail: guard !loc.isEmpty else { error = "Where's the trailhead?"; return }
        case .club:  guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Who hosts it?"; return }
        }

        submitting = true
        defer { submitting = false }

        // 1) Optional photo → public URL (nil-safe).
        var imageUrl: String?
        if let photo { imageUrl = await storage.uploadEventImage(photo) }

        // 2) Moderation. Unavailable → queue; clear reject → show reason & stop.
        let (ok, reason) = await moderation.check(
            kind: kind.rawValue, title: t,
            location: loc.isEmpty ? nil : loc,
            length: (kind == .trail && !length.isEmpty) ? length : nil,
            description: desc.isEmpty ? nil : desc,
            imageUrl: imageUrl)
        let queued = reason == Moderation.queueSentinel
        if !ok && !queued {
            error = reason.isEmpty ? "That didn't pass review — try rewording it." : reason
            return
        }
        let status: ClubStatus = queued ? .pending : .approved

        // 3) Insert.
        do {
            var becamePending = (status == .pending)
            switch kind {
            case .event:
                let count = max(1, min(repeatWeeklyCount, 8))
                for i in 0..<count {
                    let date = Calendar.current.date(byAdding: .day, value: 7 * i, to: eventDate) ?? eventDate
                    let input = NewEventInput(title: t, eventDate: DateHelpers.localDate(date),
                                              startTime: startTimeString, location: loc,
                                              description: desc.isEmpty ? nil : desc, imageUrl: imageUrl)
                    try await api.addEvent(input, clubId: nil, status: status)
                }
            case .trail:
                let input = NewTrailInput(title: t, location: loc,
                                          length: length.isEmpty ? nil : length,
                                          difficulty: difficulty.isEmpty ? nil : difficulty,
                                          description: desc.isEmpty ? nil : desc, imageUrl: imageUrl)
                try await api.addTrail(input, status: status)
            case .club:
                // submitClub sets approved for admins, pending otherwise.
                let input = ClubInput(name: t, host: host.isEmpty ? nil : host,
                                      schedule: schedule.isEmpty ? nil : schedule,
                                      location: loc.isEmpty ? nil : loc,
                                      vibe: vibe.isEmpty ? nil : vibe,
                                      description: desc.isEmpty ? nil : desc,
                                      expectations: expectations.isEmpty ? nil : expectations)
                let row = try await api.submitClub(input)
                becamePending = row.status != .approved
            }
            if becamePending { pendingNotice = true } else { posted = true }
        } catch {
            self.error = (error as? SupabaseError)?.message ?? "Couldn't post — please try again."
        }
    }
}
