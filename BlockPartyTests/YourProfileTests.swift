//
//  YourProfileTests.swift
//  BlockPartyTests — Your profile (BP app codebase-health-2 09): one model, one read, every save
//  shows at once, and only it writes the phone's copy. Reads go through the app's one client to
//  the fake server, so nothing leaves the phone, and the phone's copy is a store of the test's own.
//

import XCTest
@testable import BlockParty

@MainActor
final class YourProfileTests: XCTestCase {
    private lazy var auth = FakeTokenProvider(userId: "a")
    private lazy var server = FakeServer()
    private lazy var phone: UserDefaults = {
        let name = "YourProfileTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }()
    /// Holds each read of your row until the test lets it land.
    private let gate = Gate()
    /// Holds each save of your row (not the photo's upload) until the test lets it land.
    private let saves = Gate()

    private func row(_ who: String, photo: String) -> FakeServer.Answer {
        FakeServer.Answer(body: """
            [{"user_id":"\(who)","display_name":"Avery Lund","avatar_url":"\(photo)","interests":["coffee"],
              "onboarded_at":"2026-10-01T12:00:00Z","created_at":"2026-09-01T12:00:00Z"}]
            """)
    }

    /// The model on the fake server; `held` keeps every read of your row waiting on `gate`, and
    /// `savesHeld` every save of it on `saves`.
    private func model(held: Bool = false, savesHeld: Bool = false) -> ProfileModel {
        let server = server, gate = gate, saves = saves
        let send = Supabase.Send { @MainActor request in
            if request.url!.path.hasSuffix("town_profiles") {
                if held, request.httpMethod == "GET" { await gate.wait() }
                if savesHeld, request.httpMethod == "POST" { await saves.wait() }
            }
            return try await server.send.run(request)
        }
        return ProfileModel(supabase: Supabase(auth: auth, send: send), phone: phone, signOut: {})
    }

    private var reads: Int {
        server.requests.filter { $0.httpMethod == "GET" && $0.url!.path.hasSuffix("town_profiles") }.count
    }

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in
            UIColor.gray.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    /// A photo saved on You is the tab bar's at once: only the upload and the save go, no read.
    /// Another account's change takes it away in the same turn.
    func testASavedPhotoShowsWithNoNewRead() async {
        let profile = model()
        let problem = await profile.save(name: "Avery Lund", image: photo(), interests: ["coffee"])

        XCTAssertNil(problem)
        XCTAssertEqual(server.requests.map(\.httpMethod), ["POST", "POST"], "the upload and the save")
        XCTAssertEqual(reads, 0, "no read")
        XCTAssertTrue(profile.avatarUrl?.contains("/avatars/a/avatar-") == true, "\(profile.avatarUrl ?? "nil")")

        auth.userId = "b"
        profile.accountChanged()
        XCTAssertNil(profile.avatarUrl, "a's photo")
    }

    /// The launch's read and You's visit, asked together, send one request.
    func testTwoReadsAskedTogetherSendOne() async {
        server.answers["town_profiles"] = row("a", photo: "photo-a")
        let profile = model(held: true)
        async let launch = profile.read()
        async let visit = profile.read()
        while gate.held == 0 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        gate.open()
        let landed = await (launch, visit)

        XCTAssertTrue(landed.0 && landed.1)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(profile.avatarUrl, "photo-a")
    }

    /// A read sent before a save never lands after it: the new photo stays.
    func testAReadASaveOvertookNeverLands() async {
        server.answers["town_profiles"] = row("a", photo: "photo-old")
        let profile = model(held: true)
        let read = Task { await profile.read() }
        while gate.held == 0 { await Task.yield() }

        _ = await profile.save(name: "Avery Lund", image: photo(), interests: ["coffee"])
        let saved = profile.avatarUrl
        gate.open()

        let landed = await read.value
        XCTAssertFalse(landed)
        XCTAssertEqual(profile.avatarUrl, saved)
        XCTAssertNotEqual(profile.avatarUrl, "photo-old")
    }

    /// A read sent while a save is out, answering after it with the row from before, never lands.
    func testAReadSentWhileASaveIsOutNeverLands() async {
        server.answers["town_profiles"] = row("a", photo: "photo-old")
        let profile = model(held: true, savesHeld: true)
        let save = Task { await profile.save(name: "Avery Lund", image: photo(), interests: ["coffee"]) }
        while saves.held == 0 { await Task.yield() }
        let read = Task { await profile.read() }
        while gate.held == 0 { await Task.yield() }

        saves.open()
        _ = await save.value
        let saved = profile.avatarUrl
        gate.open()

        let landed = await read.value
        XCTAssertFalse(landed)
        XCTAssertEqual(profile.avatarUrl, saved)
        XCTAssertNotEqual(profile.avatarUrl, "photo-old")
    }

    /// The root view's read for a new account can go out before the shell hears of the change: the
    /// shell's word then changes nothing, and the read still lands.
    func testTheShellsAccountChangeAfterTheReadKeepsIt() async {
        server.answers["town_profiles"] = row("b", photo: "photo-b")
        let profile = model(held: true)
        profile.avatarUrl = "photo-a"
        auth.userId = "b"
        let read = Task { await profile.read() }
        while gate.held == 0 { await Task.yield() }
        XCTAssertNil(profile.avatarUrl, "a's photo went with the read")

        profile.accountChanged()
        gate.open()

        let landed = await read.value
        XCTAssertTrue(landed)
        XCTAssertEqual(profile.avatarUrl, "photo-b")
    }

    /// A read the account changed under never lands (codebase-health 22): the last account's photo
    /// stays gone, and the next account's sheets wait for its own read.
    func testAReadTheAccountChangeOvertookNeverLands() async {
        server.answers["town_profiles"] = row("a", photo: "photo-a")
        let profile = model(held: true)
        let read = Task { await profile.read() }
        while gate.held == 0 { await Task.yield() }

        auth.userId = "b"
        profile.accountChanged()
        gate.open()

        let landed = await read.value
        XCTAssertFalse(landed)
        XCTAssertNil(profile.avatarUrl)
        XCTAssertFalse(profile.loaded, "b's row is still to read")
    }

    /// Another account read with nothing having said so (onboarding up, the shell not there yet):
    /// the last one's photo goes before the new one's answer, here an account with no row yet.
    func testAReadForAnotherAccountDropsTheLastFirst() async {
        server.answers["town_profiles"] = row("a", photo: "photo-a")
        let profile = model()
        await profile.read()
        XCTAssertEqual(profile.avatarUrl, "photo-a")

        auth.userId = "b"
        server.answers["town_profiles"] = FakeServer.Answer(body: "[]")
        let landed = await profile.read()

        XCTAssertTrue(landed, "no row yet is an answer")
        XCTAssertNil(profile.avatarUrl, "a's photo")
        XCTAssertNil(profile.onboardedAt)
    }

    /// No signal: the read fails, and a sheet waiting on it opens anyway, on the phone's Interests,
    /// so its Save can't send none.
    func testAFailedReadStillOpensTheSheets() async {
        phone.set(["coffee"], forKey: Interests.interestsKey)
        server.failure = URLError(.notConnectedToInternet)
        let profile = model()
        profile.accountChanged()

        let landed = await profile.read()

        XCTAssertFalse(landed)
        XCTAssertTrue(profile.loaded)
        XCTAssertEqual(profile.interestIds, ["coffee"])
    }

    /// The read keeps your name and Interests on the phone, so the next launch opens on them; signing
    /// out forgets them.
    func testThePhoneKeepsNameAndInterestsUntilSignOut() async {
        server.answers["town_profiles"] = row("a", photo: "photo-a")
        await model().read()

        let next = model()
        XCTAssertEqual(next.displayName, "Avery Lund")
        XCTAssertEqual(next.interestIds, ["coffee"])
        XCTAssertEqual(Interests.get(phone), ["coffee"])

        phone.set(["faith"], forKey: OnboardingStore.interestsKey)   // picks from a flow finished here
        ProfileModel.forget(phone)
        XCTAssertNil(Interests.displayName(phone))
        XCTAssertEqual(Interests.get(phone), [])
        XCTAssertEqual(OnboardingStore(defaults: phone).interests, [], "the next account's flow starts empty")
    }

    /// Onboarding's finish hands its name and picks over before any save, and the stamp shows the
    /// date it landed.
    func testOnboardingAnswersAreYoursAtOnce() async {
        let onboarding = OnboardingStore(defaults: phone)
        onboarding.firstName = "Avery"
        onboarding.interests = ["faith", "coffee"]
        onboarding.finish()
        let profile = model()

        let finishing = profile.finished(onboarding)
        XCTAssertEqual(profile.displayName, "Avery", "at once, before anything lands")
        XCTAssertEqual(Interests.get(phone), ["faith", "coffee"])
        XCTAssertEqual(Interests.displayName(phone), "Avery")

        await finishing.value
        XCTAssertNotNil(profile.onboardedAt)
        XCTAssertEqual(reads, 0)
    }

    // MARK: - Onboarding's hand-off (codebase-health-2 10)

    private var stamps: [[String: Any]] {
        server.requests.filter { $0.httpMethod == "POST" && $0.url!.path.hasSuffix("town_profiles") }
            .compactMap { $0.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
            .filter { $0["onboarded_at"] != nil }
    }

    /// Onboarding finished before the quiet account existed (or offline): nothing goes, the tabs come
    /// up, and the account's arrival stamps it with the picks and takes the birthday off the phone.
    /// Landing after the tabs came up, it reads the Town feed again once, and the tabs stay up.
    func testAFinishMadeOfflineIsStampedWhenAnAccountArrives() async throws {
        auth.userId = nil
        let onboarding = OnboardingStore(defaults: phone)
        onboarding.interests = ["coffee", "faith"]
        onboarding.birthday = try OnboardingAge.day.parse("2001-10-24")
        onboarding.finish()
        let profile = model()

        await profile.finished(onboarding).value
        XCTAssertTrue(server.requests.isEmpty, "no account: nothing goes")
        XCTAssertTrue(profile.answersLanded, "the tabs come up")
        XCTAssertEqual(profile.lateLandings, 0)

        auth.userId = "a"
        profile.accountChanged()
        await profile.arrived(onboarding)

        XCTAssertEqual(stamps.count, 1)
        XCTAssertEqual(stamps.first?["interests"] as? [String], ["coffee", "faith"])
        XCTAssertEqual(stamps.first?["birthday"] as? String, "2001-10-24")
        XCTAssertNil(onboarding.birthday, "on the account, off the phone")
        XCTAssertEqual(profile.lateLandings, 1, "the Town feed reads again, sorted by them")
        XCTAssertTrue(profile.answersLanded, "the tabs stay up")

        await profile.arrived(onboarding)
        XCTAssertEqual(stamps.count, 1, "stamped once")
        XCTAssertEqual(profile.lateLandings, 1, "read again once")
    }

    /// Finished here with an account: the tabs wait for the stamp, which lands in time and isn't late.
    func testAFinishHereWaitsForTheStamp() async {
        let onboarding = OnboardingStore(defaults: phone)
        onboarding.interests = ["coffee"]
        onboarding.finish()
        XCTAssertTrue(onboarding.welcoming, "the Done island")
        let profile = model(savesHeld: true)

        let finishing = profile.finished(onboarding)
        while saves.held == 0 { await Task.yield() }
        XCTAssertFalse(profile.answersLanded, "the last screen stays up under the island")
        saves.open()
        await finishing.value

        XCTAssertTrue(profile.answersLanded)
        XCTAssertEqual(stamps.count, 1)
        XCTAssertEqual(profile.lateLandings, 0, "in time for the Town feed's first read")
    }

    /// A first launch, before the quiet account exists: nothing is read or stamped, so the launch's
    /// one read is the account's.
    func testNothingGoesBeforeAnAccountExists() async {
        auth.userId = nil
        let onboarding = OnboardingStore(defaults: phone)
        onboarding.finish()
        await model().arrived(onboarding)
        XCTAssertTrue(server.requests.isEmpty)
    }

    /// A reinstall: the account was stamped on another install, so onboarding finishes from the
    /// server's word on the Welcome and nothing is stamped again.
    func testAnAccountStampedElsewhereSkipsOnboarding() async {
        server.answers["town_profiles"] = row("a", photo: "photo-a")
        let onboarding = OnboardingStore(defaults: phone)
        let profile = model()

        await profile.arrived(onboarding)

        XCTAssertTrue(onboarding.finished)
        XCTAssertFalse(onboarding.finishedHere, "no Done island, no wait")
        XCTAssertEqual(stamps.count, 0)
        XCTAssertEqual(profile.lateLandings, 0)
    }
}

/// Holds each request that waits on it until `open`.
@MainActor
private final class Gate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var held: Int { waiting.count }

    func wait() async { await withCheckedContinuation { waiting.append($0) } }

    func open() {
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
