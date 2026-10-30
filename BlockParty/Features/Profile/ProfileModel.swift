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
    /// Profile's bio and cover photo, and the counts and groups `get_profile` sends (BP app
    /// references/profile-remake). Nil until read; an anonymous account has none.
    @Published var bio = ""
    @Published var coverUrl: String?
    @Published var extras: ProfileExtras?
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
        // The name at once, so the sheet never opens on "Add your name" and fades to it.
        displayName = Interests.displayName ?? ""
        #if DEBUG
        // `-town-samples`: the switches show on and their taps write nowhere, as Join's do;
        // `-town-offline`: every tap fails, as with no network.
        if writePlans == nil, LaunchFlags.backend != .live {
            let offline = LaunchFlags.backend == .offline
            plansToFriends = true
            self.writePlans = { _ in if offline { throw URLError(.notConnectedToInternet) } }
            suggestMe = true
            self.writeSuggest = { _ in if offline { throw URLError(.notConnectedToInternet) } }
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
            // Onboarding went away for a while; a row made then has only its own stamp.
            sinceLabel = ProfileModel.since(from: p.onboardedAt ?? p.createdAt)
            bio = p.bio ?? ""
            coverUrl = p.coverUrl
            plansToFriends = p.plansToFriends ?? true
            suggestMe = p.suggestMe ?? true
        }

        if canDescribe, let uid = auth.userId, let read = try? await profiles.getProfile(uid) {
            extras = read
        }

        loading = false
        loaded = true
    }

    /// Only a real account has a bio, a cover, friends and a `get_profile` to read.
    var canDescribe: Bool { auth.isSignedIn && !auth.isAnonymous }

    // MARK: - Edit / save

    /// Persist an edit (same shape as OnboardingView.finishData, minus the onboarded
    /// stamp). Writes to the server FIRST and returns whether it succeeded — the
    /// local mirror + published state are committed only on success, so the editor
    /// can surface a real failure instead of falsely reporting "saved" and then
    /// silently reverting on the next load.
    func save(name: String, image: UIImage?, interests: [String],
              bio: String? = nil, cover: UIImage? = nil) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // A newly picked photo must upload successfully; otherwise we'd save a
        // profile that silently dropped the avatar the user chose.
        var newUrl = avatarUrl
        if let image, let data = Self.avatarJPEG(image), let uid = auth.userId {
            guard let uploaded = await storage.uploadAvatar(data, userId: uid) else { return false }
            newUrl = uploaded
        }
        // A cover, as wide as the phone at 3x (`coverJPEG`), into the same folder.
        var newCover: String?
        if let cover, let data = Self.coverJPEG(cover), let uid = auth.userId {
            guard let uploaded = await storage.uploadAvatar(data, userId: uid, name: "cover") else { return false }
            newCover = uploaded
        }
        let newBio = bio.map { Self.clampBio($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        do {
            try await profiles.upsert(displayName: trimmed.isEmpty ? nil : trimmed,
                                      avatarUrl: newUrl, interests: interests, onboarded: false,
                                      bio: canDescribe ? newBio : nil, coverUrl: canDescribe ? newCover : nil)
        } catch {
            return false
        }

        // Commit only after the server accepted the write.
        Interests.set(interests)
        Interests.displayName = trimmed.isEmpty ? nil : trimmed
        displayName = trimmed
        avatarUrl = newUrl
        interestIds = interests
        if canDescribe, let newBio { self.bio = newBio }
        if let newCover { coverUrl = newCover }
        return true
    }

    /// Nextdoor's 150 letters; the database holds the same line.
    nonisolated static let bioLimit = 150

    /// Letters as the database counts them (`char_length`, one per Unicode scalar): a family emoji
    /// is one to Swift but up to seven there, and a bio Swift let through was refused.
    nonisolated static func bioLength(_ text: String) -> Int { text.unicodeScalars.count }

    /// The bio cut to `bioLimit` the database's way, never mid-emoji.
    nonisolated static func clampBio(_ text: String) -> String {
        var out = "", used = 0
        for letter in text {
            used += letter.unicodeScalars.count
            guard used <= bioLimit else { break }
            out.append(letter)
        }
        return out
    }

    /// The cover as it uploads: at most 1290 px wide (a 430 pt phone at 3x), as a JPEG.
    nonisolated static func coverJPEG(_ image: UIImage) -> Data? {
        let wide = image.size.width
        guard wide > 0 else { return nil }
        let k = min(1, 1290 / (wide * image.scale)) * image.scale
        let size = CGSize(width: (wide * k).rounded(.down), height: (image.size.height * k).rounded(.down))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.8)
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
