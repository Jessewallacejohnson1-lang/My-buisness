//
//  ProfileModel.swift
//  Block Party — Your profile (BP app codebase-health-2 09): your name, photo, Interests and
//  onboarded date, read once and kept for every screen that shows or edits them: the You tab (your
//  Profile), the tab bar's photo, New post, Your code, Edit interests and the "add your name"
//  sheet. The root view makes it (it reads while onboarding is up) and hands it to the shell's
//  `AppSession`; screens find it in the environment. Every save goes through it, so it shows
//  everywhere at once, and only it writes the phone's copy of your name and Interests
//  (`Interests`). What you're Going to lives in `YouModel`, not here.
//

import SwiftUI

@MainActor @Observable
final class ProfileModel {
    // Identity
    var displayName = ""
    var avatarUrl: String?
    var interestIds: [String] = []
    var email: String?
    var sinceLabel: String?
    var isAdmin = false
    /// When this account finished onboarding, from its row (nil: not yet, or unread).
    private(set) var onboardedAt: String?
    /// Profile's bio and cover photo, and the counts and groups `get_profile` sends (BP app
    /// references/profile-remake). Nil until read; an anonymous account has none.
    var bio = ""
    var coverUrl: String?
    var extras: ProfileExtras?
    /// "Show my plans to friends" (town-feed 28): nil until the server row says. Till then the
    /// switch shows the default, On, greyed, and can't be changed.
    var plansToFriends: Bool?
    /// Counts writes that failed and flipped the switch back; each one shakes it.
    private(set) var plansFailures = 0
    /// "Suggest me to people I may know" (daily-tab 22), as `plansToFriends`.
    var suggestMe: Bool?
    private(set) var suggestFailures = 0
    /// Delete account: a call out, whether the last one failed, and a count of failures, each of which
    /// shakes the button.
    private(set) var deletingAccount = false
    private(set) var deleteFailed = false
    private(set) var deleteFailures = 0
    static let deleteFailedLine = "Couldn't delete your account. Check your connection and try again."

    /// This account's row has been read, landed or failed: a sheet waiting on it opens, offline too.
    var loaded = false
    /// After a finish here, the answers the Town feed sorts by are on the account, or `answersWait`
    /// has passed: till then the flow's last screen stays up under the Done island, so the feed's
    /// first read has them (BP app onboarding 24). An account change leaves it: tabs that came up stay.
    private(set) var answersLanded = false
    /// Onboarding's answers that reached the account after the tabs came up (a slow signal, or the
    /// account came later): the Town feed reads again on each, sorted by them.
    private(set) var lateLandings = 0
    /// ponytail: a fixed wait; a slower signal gets the feed's second read instead.
    nonisolated static let answersWait: Duration = .seconds(2.5)

    /// The one client every read and write goes through, and the account it goes as.
    @ObservationIgnored private var supabase: Supabase
    private var auth: any TokenProviding { supabase.auth }
    private var profiles: ProfileAPI { ProfileAPI(supabase) }
    /// Where the phone's copy lives: `.standard`, or a test's own.
    @ObservationIgnored private let phone: UserDefaults
    @ObservationIgnored private let endSession: () async -> Void
    @ObservationIgnored private var writePlans: ((Bool) async throws -> Void)?
    @ObservationIgnored private var writeSuggest: ((Bool) async throws -> Void)?
    /// The switches with a write out, so taps queue behind it.
    @ObservationIgnored private var writing: Set<PartialKeyPath<ProfileModel>> = []
    /// The account what's shown belongs to.
    @ObservationIgnored private var account: String?
    /// The read out now, which a second ask joins rather than sending its own.
    @ObservationIgnored private var reading: (account: String?, turn: Int, task: Task<TownProfile?, Error>)?
    /// Moves on with every account change, and as each write goes and lands, so a read sent before
    /// it, or while it was out, never lands.
    @ObservationIgnored private var turn = 0

    // Default args are nil (not `.app`, `.shared`) so the main-actor singletons are only
    // touched inside this @MainActor init body — no cross-isolation warning.
    // `supabase` is the app's one client unless a test hands a fake (BP app codebase-health 22);
    // `signOut` ends the session; `writePlans` stands in for the server in tests.
    init(supabase: Supabase? = nil, phone: UserDefaults = .standard, signOut: (() async -> Void)? = nil,
         writePlans: ((Bool) async throws -> Void)? = nil,
         writeSuggest: ((Bool) async throws -> Void)? = nil) {
        self.supabase = supabase ?? .app
        self.phone = phone
        endSession = signOut ?? { await AuthStore.shared.signOut() }
        self.writePlans = writePlans
        self.writeSuggest = writeSuggest
        account = self.supabase.auth.userId
        // From the phone's copy at once, so nothing opens on "Add your name" and fades to it.
        displayName = Interests.displayName(phone) ?? ""
        interestIds = Interests.get(phone)
        #if DEBUG
        // `-town-samples`: the switches show on and their taps write nowhere, as Join's do;
        // `-town-offline`: every tap fails, as with no network.
        // `-town-offline`: Save fails as with no signal too, and sends nothing.
        if LaunchFlags.backend == .offline { self.supabase.send = .offline }
        if writePlans == nil, LaunchFlags.backend != .live {
            let offline = LaunchFlags.backend == .offline
            plansToFriends = true
            self.writePlans = { _ in if offline { throw URLError(.notConnectedToInternet) } }
            suggestMe = true
            self.writeSuggest = { _ in if offline { throw URLError(.notConnectedToInternet) } }
        }
        #endif
    }

    // MARK: - Read

    /// Your row, for every screen: at launch and for each new account (`RootView`), and on each
    /// visit to You. Asks made together share one request. True when it landed, row or none; false
    /// when it failed, or an account change or a write overtook it (what that wrote stands).
    @discardableResult
    func read() async -> Bool {
        let account = auth.userId
        // Another account than the one shown, with nothing having said so (onboarding is up, so the
        // shell isn't): the last one's goes first.
        if account != self.account {
            if self.account != nil { accountChanged() } else { self.account = account }
        }
        email = auth.email
        isAdmin = Admin.isAdmin(auth.email)
        // The phone's copy until the row lands, so an edit opened offline never saves no Interests.
        if displayName.isEmpty { displayName = Interests.displayName(phone) ?? "" }
        if interestIds.isEmpty { interestIds = Interests.get(phone) }
        // Joined only while nothing has been written since it went: an older read never lands.
        let sent = turn
        let task: Task<TownProfile?, Error>
        if let out = reading, out.account == account, out.turn == sent {
            task = out.task
        } else {
            let profiles = profiles
            task = Task { try await profiles.getMyProfile() }
            reading = (account, sent, task)
        }
        let result = await task.result
        if reading?.task == task { reading = nil }
        guard auth.userId == account else { return false }
        loaded = true
        guard sent == turn, case .success(let found) = result else { return false }
        // No row yet (a new quiet account): nothing to show but what the phone has.
        guard let row = found else { return true }
        if let n = row.displayName, !n.isEmpty { displayName = n }
        avatarUrl = row.avatarUrl
        // The server row is authoritative — adopt its interests even when empty (a deliberate
        // clear elsewhere must sync, not get resurrected on Save). Old ids come back as the new
        // 21, so a Save never drops what someone picked before the list changed.
        interestIds = Interests.migrate(row.interests)
        onboardedAt = row.onboardedAt
        // Onboarding went away for a while; a row made then has only its own stamp.
        sinceLabel = ProfileModel.since(from: row.onboardedAt ?? row.createdAt)
        bio = row.bio ?? ""
        coverUrl = row.coverUrl
        plansToFriends = row.plansToFriends ?? true
        suggestMe = row.suggestMe ?? true
        keep()
        return true
    }

    /// You's visit: your row, then the counts and groups only a real account has.
    func load() async {
        await read()
        guard canDescribe, let uid = auth.userId, let read = try? await profiles.getProfile(uid),
              auth.userId == uid else { return }
        extras = read
    }

    /// Another account, or none (`AppSession`): nothing of the last one's stays on the page. The
    /// switches wait for the next one's row, unless a write of their own stands in for the server
    /// (the DEBUG samples, tests).
    func accountChanged() {
        // The root view's read for this account already let the last one go (it can go out first).
        guard auth.userId != account else { return }
        turn += 1
        account = auth.userId
        displayName = Interests.displayName(phone) ?? ""
        avatarUrl = nil
        interestIds = []
        email = nil
        sinceLabel = nil
        onboardedAt = nil
        isAdmin = false
        bio = ""
        coverUrl = nil
        extras = nil
        loaded = false
        if writePlans == nil { plansToFriends = nil }
        if writeSuggest == nil { suggestMe = nil }
    }

    // MARK: - Onboarding's answers

    /// Onboarding finished: its name and Interests are yours on this phone at once, before any
    /// save reaches the account.
    private func answered(name: String?, interests: [String]) {
        if let name { displayName = name }
        if !interests.isEmpty { interestIds = interests }
        keep()
    }

    /// Onboarding's name, photo and Interests on your row (BP app onboarding 18, 20): only the
    /// answers given travel. Throws, keeping nothing, when the photo or the row is refused.
    private func saveAnswers(name: String?, photo: Data?, interests: [String]) async throws {
        turn += 1
        var url: String?
        if let photo { url = try await profiles.uploadPhoto(photo) }
        try await profiles.setNameAndPhoto(displayName: name, avatarUrl: url, interests: interests)
        turn += 1   // and a read sent while it was out
        if let name { displayName = name }
        if let url { avatarUrl = url }
        if !interests.isEmpty { interestIds = interests }
        keep()
    }

    // MARK: - Onboarding's hand-off (BP app codebase-health-2 10)

    /// Onboarding finished here: its name and Interests are yours at once; then the stamp, which the
    /// tabs wait for (at most `answersWait`), then the name and photo, then Contacts' requests. A
    /// finish from the server's word needs nothing here: `arrived` saves what waits.
    @discardableResult
    func finished(_ onboarding: OnboardingStore) -> Task<Void, Never> {
        answered(name: onboarding.displayName, interests: onboarding.interests)
        return Task {
            if onboardedAt == nil {
                let wait = Task {
                    guard (try? await Task.sleep(for: Self.answersWait)) != nil else { return }
                    answersLanded = true
                }
                await stamp(onboarding)
                wait.cancel()
            }
            answersLanded = true
            await sendAnswers(onboarding)
        }
    }

    /// A launch's account, or a new one (`RootView`): your row, then what onboarding owes it: the
    /// stamp for a finish that never reached an account (offline, or before the quiet account), the
    /// server's word for a finish on another install (a reinstall skips onboarding), and the answers
    /// still waiting on the phone. Nothing before an account exists.
    func arrived(_ onboarding: OnboardingStore) async {
        guard auth.userId != nil, await read() else { return }
        // A quiet account kept from before onboarding 27 is on the Welcome, not in: its stamp
        // mustn't finish the flow for the account made next, nor that flow's stamp land on it.
        guard !auth.isAnonymous else { return }
        if onboardedAt == nil, onboarding.finished, !onboarding.arrivedBefore {
            await stamp(onboarding)
        } else if onboardedAt != nil {
            onboarding.serverSaysFinished()
        }
        // After the read, so a name typed in onboarding beats the one read before it saved.
        await sendAnswers(onboarding)
    }

    /// Signed out (`RootView`, with `OnboardingStore.reset()`): the next account's finish here waits
    /// for its own answers again.
    func forgetOnboarding() { answersLanded = false }

    /// The onboarded stamp with the birthday and the picks. On the account, the birthday leaves the
    /// phone, so another account signing in here later can't take it.
    private func stamp(_ onboarding: OnboardingStore) async {
        let interests = onboarding.interests
        turn += 1
        guard (try? await profiles.markOnboarded(birthday: onboarding.birthday, interests: interests)) != nil else { return }
        turn += 1   // and a read sent while it was out
        onboardedAt = DateHelpers.timestampString(Date())
        sinceLabel = ProfileModel.since(from: onboardedAt)
        if !interests.isEmpty {
            interestIds = interests
            keep()
        }
        onboarding.birthday = nil
        if !onboarding.finishedHere || answersLanded { lateLandings += 1 }
    }

    /// The name, photo and picks once the flow is done and an account exists; till then they wait
    /// on the phone (BP app onboarding 18, 20). Then Contacts' Add friend picks, after the name: the
    /// server refuses a request without one (onboarding 23). A quiet account can't send them; a real
    /// one later can.
    private func sendAnswers(_ onboarding: OnboardingStore) async {
        guard onboarding.finished else { return }
        await onboarding.saveAnswers { name, photo in
            try await saveAnswers(name: name, photo: photo, interests: onboarding.interests)
        }
        guard auth.isSignedIn, !auth.isAnonymous else { return }
        let community = CommunityAPI(supabase)
        await onboarding.sendRequests { _ = try await community.friendWrite(.add, $0) }
    }

    // MARK: - The phone's copy

    /// Your name and Interests on the phone, so screens have them at once and offline.
    private func keep() {
        phone.set(interestIds, forKey: Interests.interestsKey)
        phone.set(displayName.isEmpty ? nil : displayName, forKey: Interests.nameKey)
    }

    /// Signed out: the phone's copy goes, and the old un-scoped onboarded flag, so another account
    /// here never inherits this one's name or Interests.
    static func forget(_ phone: UserDefaults = .standard) {
        phone.removeObject(forKey: Interests.interestsKey)
        phone.removeObject(forKey: Interests.nameKey)
        phone.removeObject(forKey: Interests.legacyOnboardedKey)
        phone.removeObject(forKey: OnboardingStore.interestsKey)   // picks from a flow this account finished
    }

    /// Only a real account has a bio, a cover, friends and a `get_profile` to read.
    var canDescribe: Bool { auth.isSignedIn && !auth.isAnonymous }

    // MARK: - Edit / save

    /// Persist an edit. Writes to the server FIRST and returns whether it succeeded — the
    /// local mirror + published state are committed only on success, so the editor
    /// can surface a real failure instead of falsely reporting "saved" and then
    /// silently reverting on the next load.
    /// Why a save didn't go through, as the line Edit profile shows and VoiceOver reads.
    nonisolated enum SaveProblem: Equatable {
        /// No session, or the server refused the token (a 401): only logging in fixes it.
        case signedOut
        /// Anything else: no signal, the server down, or its no.
        case other

        /// The save's own error, sorted. A 401 is the session, whoever said it: the app's own
        /// "Your session ended" before anything is sent, or the server's.
        static func of(_ error: Error) -> SaveProblem {
            (error as? SupabaseError)?.status == 401 ? .signedOut : .other
        }

        var line: String {
            switch self {
            case .signedOut: "Couldn't save. Log in and try again."
            case .other: "Couldn't save your profile. Check your connection and try again."
            }
        }
    }

    /// Saves the edit; nil when the server took it, else why it didn't.
    func save(name: String, image: UIImage?, interests: [String],
              bio: String? = nil, cover: UIImage? = nil) async -> SaveProblem? {
        turn += 1
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newBio = bio.map { Self.clampBio($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var newUrl = avatarUrl
        var newCover: String?
        do {
            // A newly picked photo must upload successfully; otherwise we'd save a
            // profile that silently dropped the avatar the user chose.
            if let image, let data = Self.avatarJPEG(image) { newUrl = try await profiles.uploadPhoto(data) }
            // A cover, as wide as the phone at 3x (`coverJPEG`), into the same folder.
            if let cover, let data = Self.coverJPEG(cover) {
                newCover = try await profiles.uploadPhoto(data, name: "cover")
            }
            try await profiles.upsert(displayName: trimmed.isEmpty ? nil : trimmed,
                                      avatarUrl: newUrl, interests: interests, onboarded: false,
                                      bio: canDescribe ? newBio : nil, coverUrl: canDescribe ? newCover : nil)
        } catch {
            Log.network("Profile.save: \(error)")
            return SaveProblem.of(error)
        }

        // Commit only after the server accepted the write; a read sent while it was out never lands.
        turn += 1
        displayName = trimmed
        avatarUrl = newUrl
        interestIds = interests
        if canDescribe, let newBio { self.bio = newBio }
        if let newCover { coverUrl = newCover }
        keep()
        return nil
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

    func signOut() async { await endSession() }

    /// Settings' Delete account (BP app launch-ready 01; Apple 5.1.1(v)): the server takes the rows, the
    /// files and the account, and only then does the phone sign out. A failure stays signed in and says
    /// so, and another try finishes the job. True when the account is gone.
    func deleteAccount() async -> Bool {
        deletingAccount = true
        deleteFailed = false
        defer { deletingAccount = false }
        do {
            try await supabase.invoke("delete-account", [:])
        } catch {
            deleteFailed = true
            deleteFailures += 1
            Haptics.error()
            AccessibilityNotification.Announcement(Self.deleteFailedLine).post()
            return false
        }
        await endSession()
        return true
    }

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
        guard let date = DateHelpers.timestamp(iso) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US")
        out.dateFormat = "MMMM yyyy"
        return out.string(from: date)
    }
}
