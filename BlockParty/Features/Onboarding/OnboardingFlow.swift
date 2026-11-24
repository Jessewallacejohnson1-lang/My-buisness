//
//  OnboardingFlow.swift
//  Block Party — the first-launch onboarding (BP app docs/plans/onboarding, ticket 16): the
//  Welcome (Nextdoor's layout, ticket 25 mock), Log in or Create account (onboarding 27), then
//  six question steps on one fixed frame in Luma's look (onboarding 34, mock v8): the grey canvas,
//  back and the dashes on top, an icon circle over each question, and the one
//  Next pill 84 pt from the bottom with its slot under it. Only the question moves between
//  steps. Phone and its texted code are a screen of their own over it (`PhoneSignInScreen`, onboarding 17), behind
//  `PhoneSignIn`. Profile, Birthday and Find your friends wear the Big art look (onboarding 43, 51), and Interests its
//  photo circles on the deep Dusk backdrop with white chrome (48); the other steps take theirs in tickets of their own.
//

import Contacts
import SwiftUI

/// The flow's steps in order. Phone and its texted code (SPEC steps 2 and 3) are not among them: they make the
/// account, as Log in does, on a screen over the Welcome that a relaunch never reopens (onboarding 17). Profile is Clubhouse's two steps again, the name
/// (`profile`, which keeps its saved name) then the photo (onboarding 55; one step from 35 to 55).
enum OnboardingStep: Int, CaseIterable {
    case welcome, profile, photo, birthday, interests, follow, friends, contacts

    /// The dashes start at Birthday: the Name and Photo steps have none, as Clubhouse's (onboarding 55).
    static let firstDashed: OnboardingStep = .birthday
    static let barTotal = allCases.count - firstDashed.rawValue

    /// The dashes show on this step.
    var dashed: Bool { rawValue >= Self.firstDashed.rawValue }

    /// Clubhouse's narrow "Next →" pill in Clubhouse's spots, on the Name and Photo steps (onboarding 55).
    var clubhouse: Bool { self == .profile || self == .photo }

    var question: String {
        switch self {
        case .welcome:   "Love where\nyou live."
        case .profile:   "What Mom calls you"
        case .photo:     "Add a photo?"
        case .birthday:  "When's your birthday?"
        case .interests: "What do you love doing?"
        case .follow:    "Follow 3 or more places\nyou like."
        case .friends:   "Find your friends"
        case .contacts:  "Friends on Block Party"
        }
    }

    /// The SF Symbol in the grey circle over the question, nearest mock v8's icons (onboarding 34). The
    /// Welcome draws no circle, nor do the Name and Photo steps, Birthday (its art is the cake) or Follow 3.
    var symbol: String {
        switch self {
        case .welcome, .profile, .photo: "person"
        case .birthday:  "birthday.cake"
        case .interests: "heart"
        case .follow:    "mappin.and.ellipse"
        case .friends:   "person.2"
        case .contacts:  "person.2"
        }
    }

    /// A step in the Big art look's soft colour at the top (onboarding 43, mock v2 `ART`); nil while the
    /// step keeps Luma's grey.
    var tint: Color? {
        switch self {
        case .profile, .photo, .friends: Hue.bigArtFriends
        case .birthday: Hue.bigArtBirthday
        default:        nil
        }
    }

    /// Interests sits on the deep Dusk backdrop with white words and chrome (onboarding 48), Follow 3 on its night
    /// (onboarding 50); the others stay light.
    var deep: Bool { self == .interests || night }
    var night: Bool { self == .follow }

    /// The link in the slot under the Next bar, where the step has one.
    var slot: String? {
        self == .friends ? "Not now" : nil
    }
}

/// Where the neighbour is in onboarding, saved on every change so a relaunch resumes there,
/// and whether they have finished it (then it never shows again).
@Observable
final class OnboardingStore {
    private(set) var step: OnboardingStep
    private(set) var finished: Bool
    /// Finished through the flow in this launch, not from the server's stamp: the Done island and
    /// the wait for the answers are for this one (onboarding 24). Never saved.
    private(set) var finishedHere = false
    /// The Done island is up: from a finish here until it closes. Never saved.
    var welcoming = false
    /// Had the app before onboarding was switched on: in without it, so nothing to stamp (24).
    private(set) var arrivedBefore = false
    /// The way the last move went, so the next question slides in from the right side.
    private(set) var forward = true
    /// The birthday the wheel is on, nil until it turns (ticket 19). Kept on the device, and saved to
    /// the account with the onboarded stamp, so an under-13 who stops here leaves nothing behind.
    var birthday: Date? {
        didSet { defaults.set(birthday.map { OnboardingAge.day.format($0) }, forKey: Self.birthdayKey) }
    }
    /// The Birthday step's gender pick, "female" or "male", nil for none (onboarding 31). Optional,
    /// kept and saved as the birthday is: on the device, then to the account with the onboarded stamp.
    var gender: String? {
        didSet { defaults.set(gender, forKey: Self.genderKey) }
    }
    /// "Come back when you're 13" is up over the birthday step.
    private(set) var tooYoung = false
    /// Log in or Create account is up over the Welcome (onboarding 27). Never saved: a relaunch
    /// opens on the Welcome.
    private(set) var account: OnboardingAccount?

    /// Profile's answers (tickets 18 and 35), kept on the phone until they reach `town_profiles`
    /// (`saveAnswers`): the one Name box, which is the display name, and the bio.
    var name: String { didSet { keep(name, Self.nameKey) } }
    var bio: String { didSet { keep(bio, Self.bioKey) } }
    /// The picked photo as it uploads (`ProfileModel.avatarJPEG`), nil until one is picked.
    var photo: Data? { didSet { keep(photo, Self.photoKey) } }
    /// Interests' picks (ticket 20), in the order made. Kept on the phone until the flow is done,
    /// then handed to Your profile (`ProfileModel.answered`), and reach the server with the name
    /// and photo.
    var interests: [String] { didSet { keep(interests, Self.interestsKey) } }
    /// Picked the Schools circle on Interests, so schools lead Follow 3 (onboarding 48; opened the Schools row
    /// before it, onboarding 28, under the same key).
    var schoolsPicked: Bool { didSet { defaults.set(schoolsPicked, forKey: Self.schoolsPickedKey) } }
    /// Follow 3's picks (ticket 22), in the order made. Kept on the phone: following needs a signed-up
    /// account, so the shell sends them once there is one (`takeFollows`).
    private(set) var follows: [FollowTarget] {
        didSet { defaults.set(try? JSONEncoder().encode(follows), forKey: Self.followsKey) }
    }
    /// Contacts' Add friend picks (ticket 23), people's ids in the order made. Kept on the phone: the
    /// server refuses a request from an account with no name, and the name waits here until the flow
    /// is done, so they go up after it (`sendRequests`).
    private(set) var requests: [String] {
        didSet { defaults.set(requests, forKey: Self.requestsKey) }
    }
    /// An answer changed since the last save reached the server.
    private(set) var answersPending: Bool
    /// A save is out, so a second caller doesn't upload the photo again.
    private var saving = false

    private let defaults: UserDefaults
    private static let stepKey = "onboarding.step"
    private static let finishedKey = "onboarding.finished"
    private static let nameKey = "onboarding.name"
    private static let bioKey = "onboarding.bio"
    /// The first and last name boxes before Profile (onboarding 35): read once, to resume on them.
    private static let firstKey = "onboarding.firstName"
    private static let lastKey = "onboarding.lastName"
    private static let photoKey = "onboarding.photo"
    private static let pendingKey = "onboarding.answersPending"
    private static let birthdayKey = "onboarding.birthday"
    private static let genderKey = "onboarding.gender"
    private static let followsKey = "onboarding.follows"
    private static let requestsKey = "onboarding.requests"
    static let interestsKey = "onboarding.interests"
    private static let schoolsPickedKey = "onboarding.schoolsOpened"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Saved by name, so a step added or moved later still resumes on the right one. Someone
        // saved on the old Name step comes back to `profile`, the name step under its old key (onboarding 35, 55).
        let saved = defaults.string(forKey: Self.stepKey).map { $0 == "name" ? "profile" : $0 }
        step = OnboardingStep.allCases.first { "\($0)" == saved } ?? .welcome
        // An install that opened the tabs before onboarding was switched on (the hello pill's last
        // look) is already in: it never gets the flow (onboarding 24). DEBUG `-onboarding` shows it anyway.
        let before = !defaults.bool(forKey: Self.finishedKey)
            && defaults.double(forKey: HelloDrop.lastSeenKey) > 0 && !LaunchFlags.has(.onboarding)
        finished = defaults.bool(forKey: Self.finishedKey) || before
        name = defaults.string(forKey: Self.nameKey)
            ?? [Self.firstKey, Self.lastKey].compactMap { defaults.string(forKey: $0)?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        bio = defaults.string(forKey: Self.bioKey) ?? ""
        photo = defaults.data(forKey: Self.photoKey)
        answersPending = defaults.bool(forKey: Self.pendingKey)
        birthday = defaults.string(forKey: Self.birthdayKey).flatMap { try? OnboardingAge.day.parse($0) }
        gender = defaults.string(forKey: Self.genderKey)
        // A flow begun before the picks had a key of their own kept them in the phone's copy.
        interests = defaults.stringArray(forKey: Self.interestsKey) ?? Interests.get(defaults)
        schoolsPicked = defaults.bool(forKey: Self.schoolsPickedKey)
        follows = Self.savedFollows(defaults)
        requests = defaults.stringArray(forKey: Self.requestsKey) ?? []
        arrivedBefore = before
    }

    /// Follow or unfollow on Follow 3, on the phone only; `twin` goes with it, as a school that is a place too.
    func toggleFollow(_ target: FollowTarget, with twin: FollowTarget? = nil) {
        let both = [target, twin].compactMap { $0 }
        if follows.contains(target) { follows.removeAll { both.contains($0) } } else { follows += both.filter { !follows.contains($0) } }
    }

    /// Add friend, or take it back, on Contacts, on the phone only.
    func toggleRequest(_ id: String) {
        if let i = requests.firstIndex(of: id) { requests.remove(at: i) } else { requests.append(id) }
    }

    /// Contacts' one button (onboarding 37, mock v8): "Add 2 friends" as people are ticked, "Next" with none.
    var contactsButton: String {
        switch requests.count {
        case 0: "Next"
        case 1: "Add 1 friend"
        case let n: "Add \(n) friends"
        }
    }

    /// Hands Contacts' requests to `send` once the flow is done and the name has reached the account,
    /// forgetting each the server answered, sent or refused. No answer (no signal, the server down)
    /// keeps the rest for the next save, which every launch makes.
    func sendRequests(_ send: (String) async throws -> Void) async {
        guard finished, !answersPending, !saving else { return }
        for id in requests {
            do { try await send(id) } catch let error where SupabaseHTTP.noAnswer(error) { return } catch {}
            requests.removeAll { $0 == id }
        }
    }

    /// Hands over the finished flow's follows and forgets them, once a signed-up account can send
    /// them; none while onboarding is still going.
    static func takeFollows(_ defaults: UserDefaults = .standard) -> [FollowTarget] {
        guard defaults.bool(forKey: finishedKey) else { return [] }
        let picks = savedFollows(defaults)
        defaults.removeObject(forKey: followsKey)
        return picks
    }

    private static func savedFollows(_ defaults: UserDefaults) -> [FollowTarget] {
        defaults.data(forKey: followsKey).flatMap { try? JSONDecoder().decode([FollowTarget].self, from: $0) } ?? []
    }

    /// 1 to `barTotal` from Birthday on; 0 before it, where no dashes show.
    var barIndex: Int { max(0, step.rawValue - OnboardingStep.firstDashed.rawValue + 1) }

    /// The Name box as typed, trimmed; nil while it holds nothing but spaces.
    var displayName: String? { Self.trimmed(name) }

    /// The name step may go on: it needs a name. The photo is optional (Skip), and the bio is no longer
    /// asked (onboarding 55): one typed before then still saves.
    var profileDone: Bool { displayName != nil }

    private static func trimmed(_ text: String) -> String? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
    }

    /// Hands the name, bio and photo to `write` (the account's `town_profiles` row) when any
    /// changed since it last succeeded. A failure, or no account yet, keeps them waiting on
    /// the phone for the next try.
    func saveAnswers(_ write: (_ name: String?, _ bio: String?, _ photo: Data?) async throws -> Void) async {
        let bio = Self.trimmed(bio)
        guard answersPending, !saving, displayName != nil || bio != nil || photo != nil else { return }
        saving = true
        defer { saving = false }
        do { try await write(displayName, bio, photo) } catch { return }
        answersPending = false
        defaults.set(false, forKey: Self.pendingKey)
    }

    func next(now: Date = .now) {
        if step == .birthday, let birthday, OnboardingAge.years(from: birthday, to: now) < 13 {
            forward = true
            tooYoung = true
            return
        }
        guard let after = OnboardingStep(rawValue: step.rawValue + 1) else { return finish() }
        move(to: after, forward: true)
    }

    func back() {
        // The account is made before the first question: Back there would make a second one.
        guard step != .profile, let before = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: before, forward: false)
    }

    /// Back from "Come back when you're 13" to the wheel.
    func notTooYoung() {
        forward = false
        tooYoung = false
    }

    /// The Welcome's Log in or Create account, or back to the Welcome (nil).
    func open(_ way: OnboardingAccount?) {
        account = way
        forward = way != nil
    }

    /// Back from Log in or Create account to the Welcome, or a step back through Forgot password.
    func accountBack() {
        account = account?.back
        forward = false
    }

    /// The account is made: on to the first question.
    func created() {
        account = nil
        next()
    }

    /// Logged in: an account that finished onboarding (on any phone) goes straight in, any other
    /// picks up at the first question.
    func loggedIn(onboarded: Bool) {
        account = nil
        if onboarded { markFinished() } else { next() }
    }

    /// Back to a clean Welcome: Close on "Come back when you're 13", and whenever the phone has no
    /// account (signed out, or the server turned its token down), so the next account starts from
    /// the beginning. Every answer is dropped, then every `onboarding.` key the device kept, and the
    /// tabs' last look, so the next account isn't taken for an install from before onboarding.
    func reset() {
        name = ""
        bio = ""
        photo = nil
        birthday = nil
        gender = nil
        follows = []
        requests = []
        interests = []
        schoolsPicked = false
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("onboarding.") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: HelloDrop.lastSeenKey)
        answersPending = false
        tooYoung = false
        // Log in stays up: someone on it is there to log in, as after backing out of a new password.
        if account != .logIn { account = nil }
        welcoming = false
        finished = false
        finishedHere = false
        arrivedBefore = false
        forward = false
        step = .welcome
    }

    /// "Not now" on Find your friends skips Contacts too (SPEC step 9), and sends nobody ticked there
    /// before going back.
    func skipFriends() {
        requests = []
        finish()
    }

    /// Apple's contacts prompt answered on Find your friends: allowed goes on to Contacts, refused ends
    /// the flow as Not now does, with no nag. Only from Find your friends: a second tap's answer lands
    /// too, and would otherwise skip Contacts.
    func answeredContacts(allowed: Bool) {
        guard step == .friends else { return }
        allowed ? next() : skipFriends()
    }

    func finish() {
        finishedHere = true
        welcoming = true
        markFinished()
    }

    /// The server's `onboarded_at` says this account finished on another install. Taken only
    /// on the Welcome, so a slow read can't pull someone out halfway through.
    func serverSaysFinished() {
        // Forgot password's code signs the phone in before the new password is made: that screen
        // stays up, and its Log in goes in (`loggedIn`).
        guard step == .welcome, account?.resets != true else { return }
        markFinished()
    }

    private func markFinished() {
        finished = true
        defaults.set(true, forKey: Self.finishedKey)
    }

    private func keep(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
        answersPending = true
        defaults.set(true, forKey: Self.pendingKey)
    }

    private func move(to new: OnboardingStep, forward: Bool) {
        self.forward = forward
        step = new
        defaults.set("\(new)", forKey: Self.stepKey)
    }
}

struct OnboardingFlow: View {
    let store: OnboardingStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Your profile, read once Log in lands: its onboarded stamp says where the account goes.
    @Environment(ProfileModel.self) private var profile
    /// Log in's and Create account's boxes, kept while you go back to the Welcome and in again.
    @State private var form = AccountForm()
    /// Phone or its texted code is up, over the Welcome or Log in (onboarding 17). Never saved: a relaunch opens on
    /// the Welcome.
    @State private var phone: PhoneForm?
    @AccessibilityFocusState private var questionFocused: Bool
    /// The Name step's box has the keyboard. Every move drops it first, so the keyboard slides down and the
    /// pill rides it, rather than the keyboard vanishing under the step change.
    @FocusState private var naming: Bool
    @State private var keyboardUp = false
    @State private var screenHeight: CGFloat = 874
    @State private var screenWidth: CGFloat = 402
    @Environment(\.displayScale) private var displayScale
    /// Schools' tiles and Follow 3's Places, schools and pages: nil while reading, empty if it failed.
    @State private var suggestions: [FollowSuggestion]?
    /// Next on Interests: its circles burst, then the step moves on (onboarding 48).
    @State private var bursting = false
    /// Contacts' check, held here so back to Find your friends and on again spends no second one of
    /// the day's five. A quiet account can't ask (`match_contacts` wants a real one): it finds nobody.
    @State private var contacts = ContactsMatch { emails, phones in
        #if DEBUG
        if LaunchFlags.backend == .samples { return OnboardingFlow.sampleMatches(phones) }
        #endif
        guard AuthStore.shared.hasAccount else { return [] }
        return try await CommunityAPI(auth: AuthStore.shared).matchContacts(emails: emails, phones: phones)
    }

    #if DEBUG
    /// `-town-samples`: the sample neighbours you could add, found as the phone's first contacts, so
    /// Contacts shows people on Block Party with no account and nothing asked of the server.
    /// `-onboarding-first-here` finds nobody, as a town's first neighbours would.
    static func sampleMatches(_ phones: [String]) -> [(code: String, neighbor: Neighbor)] {
        guard !LaunchFlags.has(.onboardingFirstHere) else { return [] }
        var seen = Set<String>()
        let people = (Neighbor.samples + Neighbor.sampleSuggestions)
            .filter { $0.relation == .stranger && seen.insert($0.displayName).inserted }
        return zip(phones, people.prefix(3)).map { (code: $0, neighbor: $1) }
    }

    /// `-town-samples` answers Contacts' check, so its answer counts as a real one (`firstHere`).
    static var samplesCheck: Bool { LaunchFlags.backend == .samples }
    #else
    static let samplesCheck = false
    #endif

    /// The Next pill's lift over the birthday wheel, above the home indicator's 34: 12 pt over the
    /// wheel's top, as over a keyboard (mock v8).
    private static let overWheel: CGFloat = OnboardingBirthdayWheel.height + 12 - 34
    /// What the Birthday step's column keeps clear above the safe area: that lift, the pill, and 16.
    private static let birthdayClear: CGFloat = overWheel + OnboardingNextBar.height + 16
    /// What any other step keeps clear: the pill and its slot, or the pill over the keyboard, and 16.
    private static let slotClear: CGFloat = OnboardingNextBar.height + 6 + 44 + 16
    private static let keyboardClear: CGFloat = 12 + OnboardingNextBar.height + 16

    private var bottomClear: CGFloat {
        if onWheel { return Self.birthdayClear }
        return keyboardUp ? Self.keyboardClear : Self.slotClear
    }

    /// Out-quint over 0.34 s, the mock's question slide.
    private static let slide: Animation = Motion.outQuint(0.34)

    var body: some View {
        // The question frame sits under the Welcome the whole time, so the Welcome fades off
        // the chrome rather than off a blank screen, and only the question slides in.
        ZStack {
            questions
                .accessibilityHidden(onWelcome || phone != nil)
            if onWelcome {
                OnboardingWelcome(start: go { [store] in
                                      if PhoneSignIn.isOn { phone = .signIn() } else { store.open(.create) }
                                  },
                                  logIn: go { [store] in store.open(.logIn) })
                    .accessibilityHidden(phone != nil)
                    .zIndex(1)
                    .transition(.opacity)
            }
            if let phone {
                PhoneSignInScreen(form: phone, close: go { [store] in
                    self.phone = nil
                    store.open(nil)
                }, done: loggedIn)
                    .zIndex(2)
                    .transition(.opacity)
            }
        }
        // The whole screen's height, keyboard or not, for the iPhone SE's Birthday (onboarding 47).
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: {
            screenHeight = $0
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        // One read for Schools and for Follow 3, while the earlier steps are up.
        .task { await readSuggestions() }
        // Reached Follow 3 with nothing read (no signal back then): read again.
        .onChange(of: store.step) { _, step in
            if step == .follow { readAgain() }
            bursting = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(Motion.sheet) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Motion.sheet) { keyboardUp = false }
        }
    }

    private func readSuggestions() async {
        let events = try? await CommunityAPI(auth: AuthStore.shared).upcomingTags()
        suggestions = (try? await FollowSuggestions.load(events: events ?? [])) ?? []
        FollowSuggestions.readAhead(suggestions ?? [], width: screenWidth, scale: displayScale)
    }

    /// Nothing read (no signal back then): read again.
    private func readAgain() {
        guard suggestions?.isEmpty == true else { return }
        suggestions = nil
        Task { await readSuggestions() }
    }

    /// A follow on Follow 3. One under the college picks its interests (Campus life).
    private func toggleFollow(_ target: FollowTarget) {
        store.toggleFollow(target, with: suggestions?.first { $0.target == target }?.twin)
        let college = FollowSuggestions.collegeTargets(in: suggestions ?? [])
        guard college.contains(target), store.follows.contains(target) else { return }
        store.interests = Interests.withCollege(store.interests)
    }

    /// Every question step: the backdrop, the fixed top row and Next bar, and the one part
    /// that moves, the question.
    private var questions: some View {
        ZStack(alignment: .top) {
            // The step's colour glides to the next one's (mock v2); Reduce Motion changes it at once.
            OnboardingBackdrop(tint: tint, deep: deep, night: night, flat: clubhouse)
                .animation(reduceMotion ? nil : BigArt.glide, value: tint)
                .animation(reduceMotion ? nil : BigArt.glide, value: deep)
                .animation(reduceMotion ? nil : BigArt.glide, value: night)
                .animation(reduceMotion ? nil : BigArt.glide, value: clubhouse)

            if !onWelcome {
                question
                    .id(store.account.map { "\($0)" } ?? (store.tooYoung ? "tooYoung" : "\(store.step)"))
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: store.forward ? 36 : -36).combined(with: .opacity),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }

            HStack(spacing: 4) {
                // None on the first question: the account is made, there's no going back to make another.
                OnboardingBackChevron(color: deep ? .white : Hue.ink, action: go { [store] in
                    // The code signed the phone in for its new password: back out of it is a sign-out.
                    if store.account == .newPassword { Task { await AuthStore.shared.signOut() } }
                    if store.account != nil { store.accountBack() } else if store.tooYoung { store.notTooYoung() } else { store.back() }
                })
                    .opacity(noBack ? 0 : 1)
                    // Nor while Log in or Create account waits on the server: its answer moves on.
                    .disabled(noBack || form.busy)
                OnboardingProgressBar(index: store.barIndex, total: OnboardingStep.barTotal, deep: deep)
                    .opacity(dashes ? 1 : 0)
                    .accessibilityHidden(!dashes)
            }
            // Mock v8's top row: 44 pt tall from 54 pt down, the chevron at 6, the line 20 from the right.
            .frame(height: 44)
            .padding(.leading, 6)
            .padding(.trailing, FollowGridMetric.gutter)
            .padding(.top, 54)
            .ignoresSafeArea(.container)

            if store.step == .follow { foot(night: true).transition(.opacity) }
            if store.step == .contacts { foot(night: false).transition(.opacity) }

            // Clubhouse's Skip at the top right of the photo step (onboarding 55): on without a photo.
            if on(.photo) {
                OnboardingLink(title: "Skip", font: .apple(17), color: Hue.inkSecondary, action: go { [store] in store.next() })
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 5)
                    .padding(.top, 54)
                    .ignoresSafeArea(.container)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if onWheel {
                OnboardingBirthdayWheel(date: birthday, now: .now, canvas: Hue.bigArtCanvas, homeBar: short ? 0 : 34)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.move(edge: .bottom))
            }
        }
        .overlay(alignment: .bottom) { bottom }
    }

    /// The wheel's date: today until it turns, as Instagram's starts.
    private var birthday: Binding<Date> {
        Binding(get: { [store] in store.birthday ?? .now }, set: { [store] in store.birthday = $0 })
    }

    /// Interests' or Follow 3's deep backdrop is up; Log in and Create account have none.
    private var deep: Bool { store.account == nil && store.step.deep }
    private var night: Bool { store.account == nil && store.step.night }

    /// The colour at the top of the step that is up, on a Big art step; Log in and Create account have none.
    private var tint: Color? {
        guard store.account == nil else { return nil }
        return store.tooYoung ? Hue.bigArtTooYoung : store.step.tint
    }

    /// A phone under 700 pt tall (the iPhone SE): no home bar, a smaller cake.
    private var short: Bool { screenHeight < BigArt.shortScreen }

    /// The dashes show: from Birthday on, not on Under 13.
    private var dashes: Bool { store.account == nil && !store.tooYoung && store.step.dashed }

    /// Birthday's wheel is up: the step, with Under 13 not over it.
    private var onWheel: Bool { on(.birthday) && !store.tooYoung }

    /// Where a scrolling step meets the top row: what's behind it there fading out over 16 pt.
    private var scrollEdge: some View {
        OnboardingScrollEdge(color: tint ?? Hue.onboardingCanvas)
    }

    /// Over a list that scrolls under the Next bar, the backdrop comes back over the bottom
    /// 190 pt, clear at the top and solid from 38% down (the mock's foot). Follow 3's is Spotify's slower
    /// fade, clear 236 pt up and solid 80 pt up (onboarding 50).
    private func foot(night: Bool) -> some View {
        OnboardingBackdrop(night: night)
            .mask {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: night ? 156 / 236 : 0.38)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: night ? 236 : 190)
                        // Solid on down behind a keyboard, whose glass would show the circles.
                        .overlay(alignment: .bottom) { Color.black.frame(height: 400).offset(y: 400) }
                }
                // Follow 3's rises with the keyboard, as its search types over the grid.
                .ignoresSafeArea(night ? .container : .all)
            }
            .allowsHitTesting(false)
    }

    private var question: some View {
        Group {
            if store.tooYoung && store.account == nil {
                OnboardingTooYoung(focused: $questionFocused)
            } else if on(.profile) {
                // Clubhouse's name step (onboarding 55): it draws its own question.
                OnboardingNameStep(store: store, headingFocused: $questionFocused, typing: $naming,
                                   submit: go { [store] in if store.profileDone { store.next() } })
            } else if on(.photo) {
                OnboardingPhotoStep(store: store, headingFocused: $questionFocused, bottomClear: Self.clubhouseClear)
            } else if store.step == .follow {
                // Follow 3's question scrolls away with its grid (onboarding 26); Spotify's look (50).
                OnboardingFollowGrid(suggestions: suggestions, interests: store.interests,
                                     schoolsFirst: store.schoolsPicked, follows: store.follows,
                                     focused: $questionFocused, toggle: { toggleFollow($0) })
            } else if on(.interests) {
                // 12 photo circles on the deep backdrop (onboarding 48).
                InterestCircles(picked: Binding(get: { store.interests }, set: { store.interests = $0 }),
                                schools: Binding(get: { store.schoolsPicked }, set: { store.schoolsPicked = $0 }),
                                bursting: bursting,
                                done: go { [store] in if store.step == .interests { store.next() } },
                                bottomClear: bottomClear,
                                focused: $questionFocused)
            } else if on(.friends) {
                // Jesse's market drawing over the ask (onboarding 51), no icon circle.
                OnboardingFriendsAsk(focused: $questionFocused)
            } else if on(.contacts) {
                // Contacts' question scrolls away with its search and rows, as Interests' does (onboarding 37).
                OnboardingContactsList(model: contacts, requests: store.requests,
                                       toggle: { [store] in store.toggleRequest($0) }) {
                    VStack(alignment: .leading, spacing: 0) {
                        heading
                        // Only while there's someone to pick: nobody here leaves the Invite list alone.
                        if peopleHere { OnboardingSubline("Pick who to add. They get a friend request.") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // No fade at the top, as Follow 3: its search pins there (mock v8 `.pin`).
                .padding(.top, FollowGridMetric.scrollTop)
                .ignoresSafeArea(.container)
            } else {
                // A step that reaches past the Next pill on a small phone or at a large text size (the
                // Birthday's gender row, onboarding 31; any step at the largest sizes, 34) scrolls clear
                // of it; where it fits it holds still.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if on(.birthday) { cake } else { heading }
                        answer
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FollowGridMetric.gutter)
                    .padding(.top, (tint == nil ? FollowGridMetric.headingTop : BigArt.top) - FollowGridMetric.scrollTop)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, bottomClear, for: .scrollContent)
                // Under the top row it goes, as Interests' does; the bottom keeps the safe area, as the bar does.
                .padding(.top, FollowGridMetric.scrollTop)
                .overlay(alignment: .top) { scrollEdge }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .onAppear { questionFocused = true }
        .onChange(of: firstHere) { _, now in
            if now { AccessibilityNotification.Announcement("You're one of the first here").post() }
        }
    }

    /// Birthday's Big art (onboarding 43): Jesse's cake, 124 pt tall, over the question.
    private var cake: some View {
        let art = short ? BigArt.shortArt : BigArt.art
        return OnboardingBigArt(question: store.step.question, row: art + 4, focused: $questionFocused) {
            Image(decorative: OnboardingBirthdayField.cakeImage)
                .resizable()
                .scaledToFit()
                .frame(height: art)
        }
    }

    /// The icon circle and the question under it (Luma's, onboarding 34).
    private var heading: some View {
        OnboardingHeading(symbol: store.account?.symbol ?? store.step.symbol,
                          question: store.account?.title ?? (firstHere ? "You're one of the first here" : store.step.question),
                          focused: $questionFocused)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: firstHere)
    }

    /// Contacts' check found nobody on Block Party, so the question says so (Jesse at onboarding 23's
    /// Check-in 1). Only from a real check: a quiet account finds nobody because it can't ask, and a
    /// phone with no numbers or emails asks nobody.
    private var firstHere: Bool {
        guard store.step == .contacts, AuthStore.shared.hasAccount || Self.samplesCheck,
              case .ready(let onApp, let invite) = contacts.state else { return false }
        return onApp.isEmpty && !invite.isEmpty
    }

    /// Contacts' check found someone you could still add, so the line under the question says how.
    private var peopleHere: Bool {
        guard case .ready(let onApp, _) = contacts.state else { return false }
        return onApp.contains { $0.relation == .stranger }
    }

    /// No back chevron on the first question: the account is made, there's no going back to make
    /// another.
    private var noBack: Bool { store.account == nil && store.step == .profile }

    /// What the step asks for, under its question; nothing yet on the placeholder steps.
    @ViewBuilder private var answer: some View {
        if let way = store.account {
            AccountFields(form: form, way: way, submit: submitAccount,
                          forgot: go { [store] in store.open(.forgot) },
                          resend: { Task { await form.resend(auth: .shared) } })
        } else {
            stepAnswer
        }
    }

    @ViewBuilder private var stepAnswer: some View {
        switch store.step {
        case .birthday:
            OnboardingBirthdayField(date: store.birthday ?? .now, now: .now, bigArt: true)
                .padding(.top, 24)
            OnboardingGenderRow(pick: Binding(get: { store.gender }, set: { store.gender = $0 }))
        default:
            EmptyView()
        }
    }

    /// The Next pill, 84 pt from the bottom with a fixed 44 pt slot under it, or 12 pt above an
    /// open keyboard or the wheel (the slot hides then), 20 pt in from each side (mock v8). On the Name and
    /// Photo steps it is Clubhouse's: 199 pt wide and centred, "Next →", 55 pt from the bottom with no slot,
    /// or 30.5 pt above the keyboard (onboarding 55).
    private var bottom: some View {
        VStack(spacing: 6) {
            OnboardingNextBar(title: nextTitle, count: stillToPick, allowed: nextAllowed,
                              busy: form.busy, refused: form.refusals, deep: deep, night: night,
                              arrow: clubhouse, action: nextAction)
                .frame(maxWidth: clubhouse ? OnboardingNextBar.narrow : .infinity)
            if !keyboardUp && !onWheel && !clubhouse { slot.frame(height: 44) }
        }
        .padding(.horizontal, FollowGridMetric.gutter)
        // Over the birthday wheel as over a keyboard.
        .padding(.bottom, onWheel ? Self.overWheel : 0)
        // The home indicator's 34 pt safe area is the mock's 34 under the slot; the keyboard's
        // safe area carries the bar up with it.
        .padding(.bottom, keyboardUp ? (clubhouse ? Self.clubhouseOverKeyboard : 12) : (clubhouse ? Self.clubhouseLift : 0))
    }

    /// Clubhouse's pill is up: the Name or Photo step, with no Log in or Create account over it.
    private var clubhouse: Bool { store.account == nil && store.step.clubhouse }

    /// Clubhouse's pill spots (`references/profile-clubhouse/SPEC.md`): 55 pt over the screen's bottom (the
    /// home indicator's 34 under it), or 30.6 over the keyboard.
    private static let clubhouseLift: CGFloat = 55 - 34
    private static let clubhouseOverKeyboard: CGFloat = 30.5
    /// What the Photo step keeps clear over the safe area's bottom: the pill in its spot.
    private static let clubhouseClear: CGFloat = OnboardingNextBar.narrowHeight + clubhouseLift

    /// Not now on Find your friends (which skips Contacts too), else empty.
    @ViewBuilder private var slot: some View {
        if store.account == nil, let title = store.step.slot {
            OnboardingLink(title: title, action: go { [store] in
                store.skipFriends()
            })
        } else {
            Color.clear
        }
    }

    /// "Pick 2 more" until Interests has its 3, "Follow 2 more" until Follow 3 has.
    private var nextTitle: String {
        if let way = store.account { return way == .logIn && form.hasPhone ? "Next" : way.button }
        if store.tooYoung { return "Close" }
        if store.step == .interests, picksMade < 3 { return "Pick \(3 - picksMade) more" }
        if store.step == .follow, followsNeeded > 0 { return "Follow \(followsNeeded) more" }
        if store.step == .contacts { return store.contactsButton }
        return "Next"
    }

    /// Picks or follows the title still asks for, for its number's roll.
    private var stillToPick: Int {
        switch store.step {
        case .interests: max(0, 3 - picksMade)
        case .follow: followsNeeded
        case .contacts: store.requests.count
        default: 0
        }
    }

    /// What Pick 3 counts: the circles picked on Interests, each 1 (onboarding 48).
    private var picksMade: Int {
        Interests.circlesPicked(store.interests) + (store.schoolsPicked ? 1 : 0)
    }

    /// Follows still to make on Follow 3; none while the read is out, when it failed or when it found
    /// fewer than 3, so a neighbour on a weak signal is never stuck there (SPEC: never block on the network).
    private var followsNeeded: Int {
        guard let suggestions, suggestions.count >= 3 else { return 0 }
        return max(0, 3 - FollowSuggestions.followed(suggestions, store.follows))
    }

    /// Placeholders always allow Next; a step that asks something says when it may (17 to 24).
    /// The name step waits for a name; the photo step's Next for a photo, Skip going on without one (55).
    /// DEBUG `-onboarding-not-yet` holds it grey, to show the shake.
    private var nextAllowed: Bool {
        #if DEBUG
        if LaunchFlags.has(.onboardingNotYet) { return false }
        #endif
        if let way = store.account { return form.canSubmit(way) }
        switch store.step {
        case .profile: return store.profileDone
        case .photo: return store.photo != nil
        case .birthday: return store.birthday != nil
        case .interests: return picksMade >= 3
        case .follow: return followsNeeded == 0
        default:     return true
        }
    }

    /// The Welcome, alone: nothing past it is up yet.
    private var onWelcome: Bool { on(.welcome) }

    /// `step` is up, with no Log in or Create account over it.
    private func on(_ step: OnboardingStep) -> Bool { store.step == step && store.account == nil }

    private var nextAction: () -> Void {
        if store.account != nil { return submitAccount }
        if store.tooYoung {
            return go { [store] in
                store.reset()
                // The account made before this step goes too: nothing stays.
                if AuthStore.shared.hasAccount { Task { await AuthStore.shared.deleteAccount() } }
            }
        }
        if store.step == .friends { return askContacts }
        // Interests' circles burst first, and move on when it's done; Reduce Motion goes at once.
        if store.step == .interests, !reduceMotion { return { bursting = true } }
        return go { [store] in store.next() }
    }

    /// Log in or Create account's Next, or a Forgot password step's. A new account goes on to the
    /// first question; a logged-in one (Log in, or the new password) reads Your profile first, and
    /// its onboarded stamp sends it straight in or to the first question. No answer from the read
    /// keeps the screen up with a line, to try again. The email's code sent goes on to the code, and
    /// the code taken to the new password.
    private func submitAccount() {
        guard let way = store.account else { return }
        Task {
            await form.submit(way, auth: .shared) {
                switch way {
                case .logIn, .newPassword:
                    guard let texted = form.textedPhone else { return await loggedIn() }
                    go { phone = .signIn(texted: texted) }()
                case .create: go { [store] in store.created() }()
                case .forgot: go { [store] in store.open(.code) }()
                case .code: go { [store] in store.open(.newPassword) }()
                }
                return nil
            }
        }
    }

    /// Logged in (an email, a new password or a texted code): Your profile's onboarded stamp sends the account straight
    /// in or to the first question. A line when the read had no answer, to try again.
    private func loggedIn() async -> String? {
        guard await profile.read() else { return AuthStore.Words.offline }
        let onboarded = profile.onboardedAt != nil
        go { [store] in
            phone = nil
            store.loggedIn(onboarded: onboarded)
        }()
        return nil
    }

    /// Find your friends' Next: Apple's contacts prompt, which answers at once when it was settled
    /// before. Allowed, all of them or some, goes on to Contacts; refused ends the flow, with no nag.
    private func askContacts() {
        Task {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            let status = CNContactStore.authorizationStatus(for: .contacts)
            let allowed = status == .authorized || status == .limited
            go { [store] in store.answeredContacts(allowed: allowed) }()
        }
    }

    /// A move between steps, on the slide's timing.
    private func go(_ move: @escaping () -> Void) -> () -> Void {
        {
            naming = false
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.slide) { move() }
        }
    }
}

/// Step 1, Nextdoor's welcome in BP's words (ticket 25 mock, Jesse 2026-10-24): a St. Joseph
/// photo full bleed, the white wordmark and headline top left, the Terms line and Log in. One white
/// pill where Nextdoor's last sits: Continue with phone, or Continue with email until texts work
/// (`PhoneSignIn`, onboarding 17). Apple and Google come above it as each can make an account (tickets 25, 39).
struct OnboardingWelcome: View {
    let start: () -> Void
    let logIn: () -> Void

    /// Nextdoor's spacing, measured on its screen (BP app `references/welcome-dogs/SPEC.md`, onboarding 54):
    /// the wordmark's letters end 30 pt over the headline's caps, as Nextdoor's house does, and the
    /// headline is its size, 32 on a 37 pt line.
    static let markTop: CGFloat = 98
    static let headlineTop: CGFloat = 150
    static let headlineSize: CGFloat = 32
    static let headlineLine: CGFloat = 37
    /// Inter Tight's own line at 32 pt (its ascent and descent, 1.21 em), which `headlineLine` spaces from.
    static let headlineNatural: CGFloat = 38.72

    /// The patio dogs at Bad Habit Brewing or the Millstream street fair, one at random for each new
    /// person (Jesse, 2026-11-22, onboarding 54). Both © Rubinski Visual for joetown.org, used with
    /// their OK (Millstream 2026-10-25, the dogs 2026-11-22).
    static let photos = (dogs: "welcome-dogs.jpg", millstream: "welcome-millstream.jpg")

    /// `-welcome-photo dogs|millstream` picks one for a screenshot; otherwise the coin does.
    static func pickPhoto(flag: String?, coin: Bool) -> String {
        switch flag {
        case "dogs": photos.dogs
        case "millstream": photos.millstream
        default: coin ? photos.dogs : photos.millstream
        }
    }

    /// Picked once a launch: Back from Create account or Log in makes a new Welcome, and it keeps the photo.
    private static let photoName = pickPhoto(flag: LaunchFlags.value(.welcomePhoto), coin: .random())

    @State private var shown = false
    /// A first open's launch zooms through to here; the logo and headline rise once it's half done.
    private let launch = LaunchStage.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            photo
            header
            actions
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear { shown = true }
        // Large text grows the headline and pills, never into each other.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The white wordmark at 98 pt and the headline at 150 pt, 24 pt from the left.
    private var header: some View {
        let mark = 180 / BlockPartyWordmark.aspect
        let up = shown && launch.headerUp
        return VStack(alignment: .leading, spacing: 0) {
            BlockPartyWordmark(height: mark)
                .foregroundStyle(.white)
                .rise(up, delay: 0)
            headline
                .padding(.top, Self.headlineTop - Self.markTop - mark)
                .rise(up, delay: 0.06)
        }
        .padding(.horizontal, 24)
        .padding(.top, Self.markTop)
    }

    /// "Love where" / "you live." in Inter Tight Bold, the app's header face (Jesse, 2026-11-18,
    /// onboarding 38), -1% tracking. One `Text` a line, so the lines sit 37 pt apart: a negative
    /// `lineSpacing` does nothing, and the font's own line would stand.
    private var headline: some View {
        VStack(alignment: .leading, spacing: Self.headlineLine - Self.headlineNatural) {
            ForEach(Array(OnboardingStep.welcome.question.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                Text(line)
            }
        }
        .font(.display(Self.headlineSize))
        .tracking(-Self.headlineSize / 100)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var terms: Text {
        let terms = Text("Terms").fontWeight(.semibold).underline()
        let privacy = Text("Privacy Policy").fontWeight(.semibold).underline()
        return Text("By continuing, you agree to our \(terms) and \(privacy).")
    }

    /// The pill, the Terms line and Log in, from the bottom up.
    private var actions: some View {
        VStack(spacing: 0) {
            WelcomePill(title: PhoneSignIn.isOn ? "Continue with phone" : "Continue with email",
                        icon: Image(systemName: PhoneSignIn.isOn ? "phone" : "envelope"), action: start)
                .rise(shown, delay: 0.16)
                .padding(.horizontal, 24)
            terms
                .font(.apple(13))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 18)
                .rise(shown, delay: 0.22)
            Button(action: logIn) { logInLine }
                .buttonStyle(.press(.dim))
                .padding(.top, 10)
                .rise(shown, delay: 0.22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 61)
    }

    private var logInLine: some View {
        Text("Already have an account? \(Text("Log in").fontWeight(.semibold))")
            .font(.apple(15))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    /// This person's photo (`photos`), full bleed, under Nextdoor's fades: a light one at the top
    /// for the headline, and a dark one from mid-screen down for the pills and small print.
    private var photo: some View {
        ZStack {
            Hue.welcomeScrim
                .overlay {
                    if let image = UIImage(named: Self.photoName) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipped()
            LinearGradient(stops: [.init(color: Hue.welcomeScrim.opacity(0.45), location: 0),
                                   .init(color: Hue.welcomeScrim.opacity(0), location: 0.32)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: Hue.welcomeScrim.opacity(0), location: 0.45),
                                   .init(color: Hue.welcomeScrim.opacity(0.18), location: 0.58),
                                   .init(color: Hue.welcomeScrim.opacity(0.45), location: 0.70),
                                   .init(color: Hue.welcomeScrim.opacity(0.70), location: 0.84),
                                   .init(color: Hue.welcomeScrim.opacity(0.82), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// A white 48 pt pill on the Welcome: sinks to 97% and greys a touch under the finger.
private struct WelcomePill: View {
    let title: String
    /// An SF Symbol, or later Google's four-colour G (`GoogleG`).
    let icon: Image
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.scaledToFit().font(.glyph(19, weight: .medium)).frame(width: 19, height: 19)
                Text(title).font(.apple(17, weight: .semibold))
            }
            .foregroundStyle(Hue.onBrandDisc)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(WelcomePillPress())
    }
}

/// The squish, on a white pill that greys under the finger.
private struct WelcomePillPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(.easeOut(duration: Press.inSeconds)) {
                $0.background(configuration.isPressed ? Hue.welcomePillDown : Hue.welcomePill, in: Capsule())
            }
            .press(.squish, down: configuration.isPressed)
    }
}

extension View {
    /// The Welcome's entrance: up 14 pt and in over 0.55 s, out-quint, after `delay`. Contacts' rows
    /// rise 8 pt over 0.32 s, 30 ms apart (mock v8).
    func rise(_ shown: Bool, delay: Double, by distance: CGFloat = 14, duration: Double = 0.55) -> some View {
        modifier(Rise(shown: shown, delay: delay, distance: distance, duration: duration))
    }
}

private struct Rise: ViewModifier {
    let shown: Bool
    let delay: Double
    let distance: CGFloat
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .animation(Motion.outQuint(duration).delay(delay), value: shown)
    }
}
