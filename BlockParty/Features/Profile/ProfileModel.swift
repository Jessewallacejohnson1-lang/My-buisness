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
    /// "Suggest me to people I may know" (daily-tab 22), as `plansToFriends`.
    @Published var suggestMe: Bool?
    @Published private(set) var suggestFailures = 0

    // Lifecycle
    @Published var loading = false
    @Published var loaded = false

    private let auth: AuthStore
    private var profiles: ProfileAPI { ProfileAPI(auth: auth) }
    private var storage: Storage { Storage(auth: auth) }
    private var writePlans: ((Bool) async throws -> Void)?
    private var writeSuggest: ((Bool) async throws -> Void)?
    /// The switches with a write out, so taps queue behind it.
    private var writing: Set<PartialKeyPath<ProfileModel>> = []

    // Default arg is nil (not `.shared`) so the main-actor singleton is only
    // touched inside this @MainActor init body — no cross-isolation warning.
    // `writePlans` stands in for the server in tests.
    init(auth: AuthStore? = nil, writePlans: ((Bool) async throws -> Void)? = nil,
         writeSuggest: ((Bool) async throws -> Void)? = nil) {
        self.auth = auth ?? .shared
        self.writePlans = writePlans
        self.writeSuggest = writeSuggest
        #if DEBUG
        // `-town-samples`: the switch shows on and its taps write nowhere, as Join's do.
        if writePlans == nil, ProcessInfo.processInfo.arguments.contains("-town-samples") {
            plansToFriends = true
            self.writePlans = { _ in }
            suggestMe = true
            self.writeSuggest = { _ in }
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
            // and mirror locally so Home's matching agrees. Old ids come back as the new 21, so
            // a Save never drops what someone picked before the list changed.
            interestIds = Interests.migrate(p.interests)
            Interests.set(interestIds)
            sinceLabel = ProfileModel.since(from: p.onboardedAt)
            plansToFriends = p.plansToFriends ?? true
            suggestMe = p.suggestMe ?? true
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
        if let image, let data = Self.avatarJPEG(image), let uid = auth.userId {
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

    /// The photo as it uploads: its middle square, at most 400 px a side, as a JPEG. Every
    /// avatar is a circle filled from the middle, and the largest, Edit Profile's 132 pt well,
    /// is 396 px at 3x; the full camera image was 4.7 MB (BP app backlog 03). Drawn, not
    /// cropped as a bitmap, so a photo taken with the phone turned stays upright, and a small
    /// one is never enlarged.
    nonisolated static func avatarJPEG(_ image: UIImage) -> Data? {
        let short = min(image.size.width, image.size.height)
        guard short > 0 else { return nil }
        let side = min(400, (short * image.scale).rounded(.down))
        let k = side / short
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let w = image.size.width * k, h = image.size.height * k
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return square.jpegData(compressionQuality: 0.85)
    }

    func signOut() async { await auth.signOut() }

    /// The switch answers at once. One write at a time: taps made while one is out are sent
    /// as their latest value when it returns, so the server ends where the switch does. A
    /// write the server refuses flips the switch back, unless a newer tap moved it, then
    /// shakes it with an error buzz (taste.md, 2026-09-27), as the Calendar switch does.
    func setPlansToFriends(_ on: Bool) async {
        await flip(\.plansToFriends, to: on, failures: \.plansFailures) { [self] in
            if let writePlans { try await writePlans($0) } else { try await profiles.setSwitch("plans_to_friends", $0) }
        }
    }

    /// "Suggest me to people I may know": the same switch, its own column.
    func setSuggestMe(_ on: Bool) async {
        await flip(\.suggestMe, to: on, failures: \.suggestFailures) { [self] in
            if let writeSuggest { try await writeSuggest($0) } else { try await profiles.setSwitch("suggest_me", $0) }
        }
    }

    private func flip(_ value: ReferenceWritableKeyPath<ProfileModel, Bool?>, to on: Bool,
                      failures: ReferenceWritableKeyPath<ProfileModel, Int>,
                      write: (Bool) async throws -> Void) async {
        guard let shown = self[keyPath: value], shown != on else { return }
        self[keyPath: value] = on
        guard !writing.contains(value) else { return }
        writing.insert(value)
        defer { writing.remove(value) }
        var saved = shown
        while let want = self[keyPath: value], want != saved {
            do {
                try await write(want)
                saved = want
            } catch {
                guard self[keyPath: value] == want else { continue }
                withAnimation(.easeInOut(duration: RealLifeActions.flip)) { self[keyPath: value] = saved }
                try? await Task.sleep(for: .seconds(RealLifeActions.flip))
                self[keyPath: failures] += 1
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
