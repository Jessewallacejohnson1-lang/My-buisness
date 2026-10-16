//
//  ProfileModel.swift
//  Block Party — state for Profile, the sheet behind the photo on the You tab. Loads the
//  town_profiles row (name · avatar · interests) and owns the edit/save + sign-out paths.
//  What the neighbour is Going to lives on the You page (`YouModel`), not here.
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
    /// "Show my plans to friends" (town-feed 28): nil until the server row says. Till then the
    /// switch shows the default, On, greyed, and can't be changed.
    @Published var plansToFriends: Bool?
    /// Counts writes that failed and flipped the switch back; each one shakes it.
    @Published private(set) var plansFailures = 0

    // Lifecycle
    @Published var loading = false
    @Published var loaded = false

    private let auth: AuthStore
    private var profiles: ProfileAPI { ProfileAPI(auth: auth) }
    private var storage: Storage { Storage(auth: auth) }
    private var writePlans: ((Bool) async throws -> Void)?
    private var plansWriting = false

    // Default arg is nil (not `.shared`) so the main-actor singleton is only
    // touched inside this @MainActor init body — no cross-isolation warning.
    // `writePlans` stands in for the server in tests.
    init(auth: AuthStore? = nil, writePlans: ((Bool) async throws -> Void)? = nil) {
        self.auth = auth ?? .shared
        self.writePlans = writePlans
        #if DEBUG
        // `-town-samples`: the switch shows on and its taps write nowhere, as Join's do.
        if writePlans == nil, ProcessInfo.processInfo.arguments.contains("-town-samples") {
            plansToFriends = true
            self.writePlans = { _ in }
        }
        #endif
    }

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

        let profile = (try? await profiles.getMyProfile()) ?? nil
        if let p = profile {
            if let n = p.displayName, !n.isEmpty { displayName = n }
            avatarUrl = p.avatarUrl
            // The server row is authoritative — adopt its interests even when empty
            // (a deliberate clear elsewhere must sync, not get resurrected on Save),
            // and mirror locally so Home's matching agrees.
            interestIds = p.interests
            Interests.set(p.interests)
            sinceLabel = ProfileModel.since(from: p.onboardedAt)
            plansToFriends = p.plansToFriends ?? true
        }

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

    /// The switch answers at once. One write at a time: taps made while one is out are sent
    /// as their latest value when it returns, so the server ends where the switch does. A
    /// write the server refuses flips the switch back, unless a newer tap moved it, then
    /// shakes it with an error buzz (taste.md, 2026-09-27), as the Calendar switch does.
    func setPlansToFriends(_ on: Bool) async {
        guard let shown = plansToFriends, shown != on else { return }
        plansToFriends = on
        guard !plansWriting else { return }
        plansWriting = true
        defer { plansWriting = false }
        var saved = shown
        while let want = plansToFriends, want != saved {
            do {
                if let writePlans { try await writePlans(want) } else { try await profiles.setPlansToFriends(want) }
                saved = want
            } catch {
                guard plansToFriends == want else { continue }
                withAnimation(.easeInOut(duration: RealLifeActions.flip)) { plansToFriends = saved }
                try? await Task.sleep(for: .seconds(RealLifeActions.flip))
                plansFailures += 1
                Haptics.error()
                // The shake and the buzz are silent to VoiceOver; this says it.
                AccessibilityNotification.Announcement("Couldn't change that. Try again.").post()
                return
            }
        }
    }

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
