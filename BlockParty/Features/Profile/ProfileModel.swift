//
//  ProfileModel.swift
//  Block Party — state for the community profile screen. Loads the town_profiles row
//  (name · avatar · interests) plus the viewer's REAL activity (upcoming RSVPs,
//  joined clubs, quests completed) and owns the edit/save + sign-out paths.
//
//  Real-data-only: every count comes from a query. Nothing is seeded; if a value
//  can't be made real it stays 0/empty and the row simply reads "none yet".
//

import SwiftUI
import Combine

@MainActor
final class ProfileModel: ObservableObject {
    // Identity
    @Published var displayName = ""
    @Published var avatarUrl: String?
    @Published var interestIds: [String] = []
    @Published var email: String?
    @Published var sinceLabel: String?
    @Published var isAdmin = false

    // Activity (real — see CommunityAPI "My activity")
    @Published var upcoming: [UpcomingEvent] = []
    @Published var clubs: [ClubView] = []
    @Published var questCount = 0

    // Lifecycle
    @Published var loading = false
    @Published var loaded = false

    private let auth: AuthStore
    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var profiles: ProfileAPI { ProfileAPI(auth: auth) }
    private var storage: Storage { Storage(auth: auth) }

    // Default arg is nil (not `.shared`) so the main-actor singleton is only
    // touched inside this @MainActor init body — no cross-isolation warning.
    init(auth: AuthStore? = nil) { self.auth = auth ?? .shared }

    // MARK: - Derived

    /// Stored interest ids → human labels (drops any unknown id).
    var interestLabels: [String] { Interests.labels(for: interestIds) }

    var goingCount: Int { upcoming.count }
    var clubCount: Int { clubs.count }

    /// The soonest upcoming plan, for the feature card's subtitle.
    var nextPlan: UpcomingEvent? { upcoming.first }

    // MARK: - Load

    func load() async {
        loading = true

        // Instant first paint from local mirrors + auth (offline-friendly), then
        // refine from the network below.
        email = auth.email
        isAdmin = Admin.isAdmin(auth.email)
        // Real name only — never the raw email (that lives in the Account row).
        // Empty → the header shows an "Add your name" prompt.
        if displayName.isEmpty { displayName = Interests.displayName ?? "" }
        if interestIds.isEmpty { interestIds = Interests.get() }

        let api = self.api
        let profiles = self.profiles
        async let profileCall = profiles.getMyProfile()
        async let upcomingCall = api.getMyUpcomingRsvps()
        async let clubsCall = api.getMyClubs()
        async let questCall = api.getMyQuestCount()

        let profile = (try? await profileCall) ?? nil
        if let p = profile {
            if let n = p.displayName, !n.isEmpty { displayName = n }
            avatarUrl = p.avatarUrl
            // The server row is authoritative — adopt its interests even when empty
            // (a deliberate clear elsewhere must sync, not get resurrected on Save),
            // and mirror locally so Home's matching agrees.
            interestIds = p.interests
            Interests.set(p.interests)
            sinceLabel = ProfileModel.since(from: p.onboardedAt)
        }
        upcoming   = (try? await upcomingCall) ?? []
        clubs      = (try? await clubsCall) ?? []
        questCount = (try? await questCall) ?? 0

        loading = false
        loaded = true
    }

    // MARK: - Edit / save

    /// Persist an edit (same shape as OnboardingView.finishData, minus the onboarded
    /// stamp). Writes to the server FIRST and returns whether it succeeded — the
    /// local mirror + published state are committed only on success, so the editor
    /// can surface a real failure instead of falsely reporting "saved" and then
    /// silently reverting on the next load.
    func save(name: String, image: UIImage?, interests: [String]) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // A newly picked photo must upload successfully; otherwise we'd save a
        // profile that silently dropped the avatar the user chose.
        var newUrl = avatarUrl
        if let image, let data = image.jpegData(compressionQuality: 0.85), let uid = auth.userId {
            guard let uploaded = await storage.uploadAvatar(data, userId: uid) else { return false }
            newUrl = uploaded
        }

        do {
            try await profiles.upsert(displayName: trimmed.isEmpty ? nil : trimmed,
                                      avatarUrl: newUrl, interests: interests, onboarded: false)
        } catch {
            return false
        }

        // Commit only after the server accepted the write.
        Interests.set(interests)
        Interests.displayName = trimmed.isEmpty ? nil : trimmed
        displayName = trimmed
        avatarUrl = newUrl
        interestIds = interests
        return true
    }

    func signOut() async { await auth.signOut() }

    // MARK: - Helpers

    /// "July 2026" from an ISO onboarded_at (with or without fractional seconds).
    static func since(from iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        let frac  = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = plain.date(from: iso) ?? frac.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US")
        out.dateFormat = "MMMM yyyy"
        return out.string(from: date)
    }
}
