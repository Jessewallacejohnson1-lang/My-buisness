//
//  OnboardingFlow.swift
//  Block Party — the first-launch onboarding (BP app docs/plans/onboarding, ticket 16): the
//  Welcome (Nextdoor's layout, ticket 25 mock), Log in or Create account (onboarding 27), then
//  six question steps on one fixed frame in Luma's look (onboarding 34, mock v8): the grey canvas,
//  back and the progress line on top, an icon circle over each question, and the one
//  Next pill 84 pt from the bottom with its slot under it. Only the question moves between
//  steps. The steps are placeholders, a question each, until tickets 17 to 24 fill them.
//

import Contacts
import SwiftUI

/// The flow's steps in order. The bar counts the six after the Welcome. Phone and its texted code
/// (SPEC steps 2 and 3) come back with phone sign-in (onboarding 17): empty, they stay out (Jesse, 24).
/// Name and Photo became the one Profile step (onboarding 35, mock v8).
enum OnboardingStep: Int, CaseIterable {
    case welcome, profile, birthday, interests, follow, friends, contacts

    static let barTotal = allCases.count - 1

    var question: String {
        switch self {
        case .welcome:   "Love where\nyou live."
        case .profile:   "Your Profile"
        case .birthday:  "When's your birthday?"
        case .interests: "What do you love doing?"
        case .follow:    "Follow 3 places"
        case .friends:   "Find your friends"
        case .contacts:  "Friends on Block Party"
        }
    }

    /// The SF Symbol in the grey circle over the question, nearest mock v8's icons (onboarding 34).
    var symbol: String {
        switch self {
        case .welcome:   "house"
        case .profile:   "person"
        case .birthday:  "birthday.cake"
        case .interests: "heart"
        case .follow:    "mappin.and.ellipse"
        case .friends:   "person.2"
        case .contacts:  "person.2"
        }
    }

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
    /// Opened Schools on Interests, so schools lead Follow 3 (onboarding 28).
    var schoolsOpened: Bool { didSet { defaults.set(schoolsOpened, forKey: Self.schoolsOpenedKey) } }
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
    private static let schoolsOpenedKey = "onboarding.schoolsOpened"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Saved by name, so a step added or moved later still resumes on the right one. Someone
        // saved on the old Name or Photo step comes back to Profile, which took both (onboarding 35).
        let saved = defaults.string(forKey: Self.stepKey).map { ["name", "photo"].contains($0) ? "profile" : $0 }
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
        schoolsOpened = defaults.bool(forKey: Self.schoolsOpenedKey)
        follows = Self.savedFollows(defaults)
        requests = defaults.stringArray(forKey: Self.requestsKey) ?? []
        arrivedBefore = before
    }

    /// Follow or unfollow on Follow 3, on the phone only.
    func toggleFollow(_ target: FollowTarget) {
        if let i = follows.firstIndex(of: target) { follows.remove(at: i) } else { follows.append(target) }
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

    /// 1 to 7 on the question steps, 0 on the Welcome.
    var barIndex: Int { step.rawValue }

    /// The Name box as typed, trimmed; nil while it holds nothing but spaces.
    var displayName: String? { Self.trimmed(name) }

    /// Profile may go on (Save Profile): it needs a name; the photo and bio are optional.
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
    func notTooYoung() { tooYoung = false }

    /// The Welcome's Log in or Create account, or back to the Welcome (nil).
    func open(_ way: OnboardingAccount?) {
        account = way
        forward = way != nil
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
        schoolsOpened = false
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("onboarding.") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: HelloDrop.lastSeenKey)
        answersPending = false
        tooYoung = false
        account = nil
        welcoming = false
        finished = false
        finishedHere = false
        arrivedBefore = false
        forward = false
        step = .welcome
    }

    /// "Not now" on Find your friends skips Contacts too (SPEC step 9).
    func skipFriends() { finish() }

    func finish() {
        finishedHere = true
        welcoming = true
        markFinished()
    }

    /// The server's `onboarded_at` says this account finished on another install. Taken only
    /// on the Welcome, so a slow read can't pull someone out halfway through.
    func serverSaysFinished() {
        guard step == .welcome else { return }
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
    @AccessibilityFocusState private var questionFocused: Bool
    @State private var keyboardUp = false
    /// Schools' tiles and Follow 3's Places, schools and pages: nil while reading, empty if it failed.
    @State private var suggestions: [FollowSuggestion]?
    /// Contacts' check, held here so back to Find your friends and on again spends no second one of
    /// the day's five. A quiet account can't ask (`match_contacts` wants a real one), so until phone
    /// sign-in makes one at step 2 (onboarding 17) it finds nobody.
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
        if store.step == .birthday && store.account == nil { return Self.birthdayClear }
        return keyboardUp ? Self.keyboardClear : Self.slotClear
    }

    /// Out-quint over 0.34 s, the mock's question slide.
    private static let slide: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.34)

    var body: some View {
        // The question frame sits under the Welcome the whole time, so the Welcome fades off
        // the chrome rather than off a blank screen, and only the question slides in.
        ZStack {
            questions
                .accessibilityHidden(onWelcome)
            if onWelcome {
                OnboardingWelcome(create: go { [store] in store.open(.create) },
                                  logIn: go { [store] in store.open(.logIn) })
                    .zIndex(1)
                    .transition(.opacity)
            }
            if store.tooYoung {
                OnboardingTooYoung(back: go { [store] in store.notTooYoung() },
                                   close: go { [store] in
                                       store.reset()
                                       // The account made before this step goes too: nothing stays.
                                       if AuthStore.shared.hasAccount { Task { await AuthStore.shared.deleteAccount() } }
                                   })
                    .zIndex(2)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            }
        }
        // One read for Schools and for Follow 3, while the earlier steps are up.
        .task { await readSuggestions() }
        // Reached Follow 3 with nothing read (no signal back then): read again.
        .onChange(of: store.step) { _, step in
            if step == .follow { readAgain() }
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
    }

    /// Nothing read (no signal back then): read again.
    private func readAgain() {
        guard suggestions?.isEmpty == true else { return }
        suggestions = nil
        Task { await readSuggestions() }
    }

    /// A follow on Schools or Follow 3. One under the college picks its interests, and taking the
    /// last one off takes them.
    private func toggleFollow(_ target: FollowTarget) {
        store.toggleFollow(target)
        let college = FollowSuggestions.collegeTargets(in: suggestions ?? [])
        guard college.contains(target) else { return }
        store.interests = Interests.withCollege(store.interests, following: store.follows.contains(where: college.contains))
    }

    /// Every question step: the backdrop, the fixed top row and Next bar, and the one part
    /// that moves, the question.
    private var questions: some View {
        ZStack(alignment: .top) {
            OnboardingBackdrop()

            if !onWelcome {
                question
                    .id(store.account.map { "\($0)" } ?? "\(store.step)")
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: store.forward ? 36 : -36).combined(with: .opacity),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }

            HStack(spacing: 4) {
                // None on the first question: the account is made, there's no going back to make another.
                OnboardingBackChevron(action: go { [store] in if store.account != nil { store.open(nil) } else { store.back() } })
                    .opacity(store.step == .profile ? 0 : 1)
                    // Nor while Log in or Create account waits on the server: its answer moves on.
                    .disabled(store.step == .profile || form.busy)
                OnboardingProgressBar(index: store.barIndex, total: OnboardingStep.barTotal)
                    .opacity(store.account == nil ? 1 : 0)
            }
            // Mock v8's top row: 44 pt tall from 54 pt down, the chevron at 6, the line 20 from the right.
            .frame(height: 44)
            .padding(.leading, 6)
            .padding(.trailing, FollowGridMetric.gutter)
            .padding(.top, 54)
            .ignoresSafeArea(.container)

            if [.interests, .follow, .contacts].contains(store.step) { foot.transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            if store.step == .birthday {
                OnboardingBirthdayWheel(date: birthday, now: .now)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.move(edge: .bottom))
            }
        }
        .overlay(alignment: .bottom) { bottom }
        .accessibilityHidden(store.tooYoung)
    }

    /// The wheel's date: today until it turns, as Instagram's starts.
    private var birthday: Binding<Date> {
        Binding(get: { [store] in store.birthday ?? .now }, set: { [store] in store.birthday = $0 })
    }

    /// Where a scrolling step meets the top row: the backdrop fading out over 16 pt.
    private var scrollEdge: some View {
        LinearGradient(colors: [Hue.onboardingCanvas, Hue.onboardingCanvas.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(height: 16)
            .padding(.top, FollowGridMetric.scrollTop)
            .allowsHitTesting(false)
    }

    /// Over a list that scrolls under the Next bar, the backdrop comes back over the bottom
    /// 190 pt, clear at the top and solid from 38% down (the mock's foot).
    private var foot: some View {
        OnboardingBackdrop()
            .mask {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.38)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 190)
                }
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)
    }

    private var question: some View {
        Group {
            if store.step == .profile && store.account == nil {
                // Luma's profile screen whole (onboarding 35): its own band, photo and title, no icon circle.
                OnboardingProfile(store: store, headingFocused: $questionFocused, bottomClear: bottomClear)
            } else if store.step == .follow {
                // Follow 3's question scrolls away with its grid (onboarding 26).
                OnboardingFollowGrid(suggestions: suggestions, interests: store.interests,
                                     schoolsFirst: store.schoolsOpened, follows: store.follows,
                                     toggle: { toggleFollow($0) }) {
                    VStack(alignment: .leading, spacing: 0) {
                        heading
                        // Mock v8's line under Follow 3 (onboarding 36).
                        OnboardingSubline("Picked from what you love. Their events show up first.")
                    }
                }
            } else if store.step == .interests {
                // Interests' question scrolls away with its rows, as Follow 3's does (onboarding 28).
                InterestRows(picked: Binding(get: { store.interests }, set: { store.interests = $0 }),
                             schools: suggestions,
                             isFollowing: { [store] in store.follows.contains($0) },
                             toggleFollow: { toggleFollow($0) },
                             schoolsOpened: { store.schoolsOpened = true; readAgain() },
                             topInset: FollowGridMetric.headingTop - FollowGridMetric.scrollTop) {
                    VStack(alignment: .leading, spacing: 0) {
                        heading
                        OnboardingSubline("We'll show events, groups and places that match.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, FollowGridMetric.scrollTop)
                .overlay(alignment: .top) { scrollEdge }
                .ignoresSafeArea(.container)
            } else if store.step == .friends && store.account == nil {
                // Luma's contacts ask whole (onboarding 37): its faces and white sheet, no icon circle.
                OnboardingFriendsAsk(focused: $questionFocused)
            } else if store.step == .contacts && store.account == nil {
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
                .padding(.top, FollowGridMetric.scrollTop)
                .overlay(alignment: .top) { scrollEdge }
                .ignoresSafeArea(.container)
            } else {
                // A step that reaches past the Next pill on a small phone or at a large text size (the
                // Birthday's gender row, onboarding 31; any step at the largest sizes, 34) scrolls clear
                // of it; where it fits it holds still.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heading
                        answer
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, FollowGridMetric.gutter)
                    .padding(.top, FollowGridMetric.headingTop - FollowGridMetric.scrollTop)
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

    /// The icon circle and the question under it (Luma's, onboarding 34).
    private var heading: some View {
        OnboardingHeading(symbol: store.account?.symbol ?? store.step.symbol,
                          question: store.account?.title ?? (firstHere ? "You're one of the first here" : store.step.question),
                          cake: store.account == nil && store.step == .birthday,
                          focused: $questionFocused)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: firstHere)
    }

    /// Contacts' check found nobody on Block Party, so the question says so (Jesse at onboarding 23's
    /// Check-in 1). Only from a real check: a quiet account finds nobody because it can't ask, and a
    /// phone with no numbers or emails asks nobody.
    private var firstHere: Bool {
        guard store.step == .contacts, AuthStore.shared.hasAccount || LaunchFlags.backend == .samples,
              case .ready(let onApp, let invite) = contacts.state else { return false }
        return onApp.isEmpty && !invite.isEmpty
    }

    /// Contacts' check found someone you could still add, so the line under the question says how.
    private var peopleHere: Bool {
        guard case .ready(let onApp, _) = contacts.state else { return false }
        return onApp.contains { $0.relation == .stranger }
    }

    /// What the step asks for, under its question; nothing yet on the placeholder steps.
    @ViewBuilder private var answer: some View {
        if let way = store.account {
            AccountFields(form: form, way: way, submit: submitAccount)
        } else {
            stepAnswer
        }
    }

    @ViewBuilder private var stepAnswer: some View {
        switch store.step {
        case .birthday:
            OnboardingBirthdayField(date: store.birthday ?? .now, now: .now)
                .padding(.top, 24)
            OnboardingGenderRow(pick: Binding(get: { store.gender }, set: { store.gender = $0 }))
        default:
            EmptyView()
        }
    }

    /// The Next pill, 84 pt from the bottom with a fixed 44 pt slot under it, or 12 pt above an
    /// open keyboard or the wheel (the slot hides then), 20 pt in from each side (mock v8).
    private var bottom: some View {
        VStack(spacing: 6) {
            OnboardingNextBar(title: nextTitle, count: stillToPick, allowed: nextAllowed,
                              busy: form.busy, refused: form.refusals, profile: onProfile,
                              white: store.step == .friends && store.account == nil, action: nextAction)
            if !keyboardUp && store.step != .birthday { slot.frame(height: 44) }
        }
        .padding(.horizontal, FollowGridMetric.gutter)
        // Over the birthday wheel as over a keyboard.
        .padding(.bottom, store.step == .birthday ? Self.overWheel : 0)
        // The home indicator's 34 pt safe area is the mock's 34 under the slot; the keyboard's
        // safe area carries the bar up with it.
        .padding(.bottom, keyboardUp ? 12 : 0)
    }

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

    /// "Pick 2 more" until step 7 has its 3, "Follow 2 more" until step 8 has.
    private var nextTitle: String {
        if let way = store.account { return way.button }
        if store.step == .profile { return "Save Profile" }
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

    /// What Pick 3 counts: everything picked or followed on Interests. Until the tiles are read, a
    /// relaunch's follows all count, so nobody is held back by a read still out or failed.
    private var picksMade: Int {
        guard let suggestions, !suggestions.isEmpty else { return Interests.count(store.interests) + store.follows.count }
        let schools = FollowSuggestions.schoolTargets(in: suggestions)
        return Interests.count(store.interests) + store.follows.filter(schools.contains).count
    }

    /// Follows still to make on step 8; none while the read is out, when it failed or when it found
    /// fewer than 3, so a neighbour on a weak signal is never stuck there (SPEC: never block on the network).
    private var followsNeeded: Int {
        guard let suggestions, suggestions.count >= 3 else { return 0 }
        return max(0, 3 - store.follows.count)
    }

    /// Placeholders always allow Next; a step that asks something says when it may (17 to 24).
    /// Profile waits for a name; its photo and bio are optional (onboarding 35).
    /// DEBUG `-onboarding-not-yet` holds it grey, to show the shake.
    private var nextAllowed: Bool {
        #if DEBUG
        if LaunchFlags.has(.onboardingNotYet) { return false }
        #endif
        if store.account != nil { return form.canSubmit }
        switch store.step {
        case .profile: return store.profileDone
        case .birthday: return store.birthday != nil
        case .interests: return picksMade >= 3
        case .follow: return followsNeeded == 0
        default:     return true
        }
    }

    /// Profile is up, so the pill is Luma's Save Profile (onboarding 35).
    private var onProfile: Bool { store.step == .profile && store.account == nil }

    /// The Welcome, alone: nothing past it is up yet.
    private var onWelcome: Bool { store.step == .welcome && store.account == nil }

    private var nextAction: () -> Void {
        if store.account != nil { return submitAccount }
        return store.step == .friends ? askContacts : go { [store] in store.next() }
    }

    /// Log in or Create account's Next. A new account goes on to the first question; a logged-in
    /// one reads Your profile first, and its onboarded stamp sends it straight in or to the first
    /// question. No answer from the read keeps the screen up with a line, to try again.
    private func submitAccount() {
        guard let way = store.account else { return }
        Task {
            await form.submit(way, auth: .shared) {
                if way == .logIn {
                    guard await profile.read() else { return AuthStore.Words.offline }
                    let onboarded = profile.onboardedAt != nil
                    go { [store] in store.loggedIn(onboarded: onboarded) }()
                } else {
                    go { [store] in store.created() }()
                }
                return nil
            }
        }
    }

    /// Find your friends' Next: Apple's contacts prompt, which answers at once when it was settled
    /// before. Allowed, all of them or some, goes on to Contacts; refused ends the flow, with no nag.
    private func askContacts() {
        Task {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            let status = CNContactStore.authorizationStatus(for: .contacts)
            let allowed = status == .authorized || status == .limited
            // A second tap's answer lands too: only the first moves on, or it would skip Contacts.
            go { [store] in
                guard store.step == .friends else { return }
                allowed ? store.next() : store.finish()
            }()
        }
    }

    /// A move between steps, on the slide's timing.
    private func go(_ move: @escaping () -> Void) -> () -> Void {
        { withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.slide) { move() } }
    }
}

/// Step 1, Nextdoor's welcome in BP's words (ticket 25 mock, Jesse 2026-10-24): the Millstream
/// street fair photo full bleed, the white wordmark and headline top left, the Terms line and Log
/// in. One white pill, Continue with email, where Nextdoor's last sits (onboarding 27): Apple,
/// Google and phone come back above it as each can make an account (tickets 25, 17).
struct OnboardingWelcome: View {
    let create: () -> Void
    let logIn: () -> Void

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

    /// The white wordmark at 88 pt and the headline at 150 pt, 24 pt from the left.
    private var header: some View {
        let mark = 180 / BlockPartyWordmark.aspect
        let up = shown && launch.headerUp
        return VStack(alignment: .leading, spacing: 0) {
            BlockPartyWordmark(height: mark)
                .foregroundStyle(.white)
                .rise(up, delay: 0)
            Text(OnboardingStep.welcome.question)
                .appleFont(36, weight: .bold)   // Apple's font, as every onboarding word (Jesse, 2026-11-09)
                .lineSpacing(-3)   // SF's 43 pt line to the mock's 40
                .foregroundStyle(.white)
                .padding(.top, 150 - 88 - mark)
                .accessibilityAddTraits(.isHeader)
                .rise(up, delay: 0.06)
        }
        .padding(.horizontal, 24)
        .padding(.top, 88)
    }

    private var terms: Text {
        let terms = Text("Terms").fontWeight(.semibold).underline()
        let privacy = Text("Privacy Policy").fontWeight(.semibold).underline()
        return Text("By continuing, you agree to our \(terms) and \(privacy).")
    }

    /// The pill, the Terms line and Log in, from the bottom up.
    private var actions: some View {
        VStack(spacing: 0) {
            WelcomePill(title: "Continue with email", icon: Image(systemName: "envelope"), action: create)
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

    /// The Millstream street fair, full bleed (Jesse, 2026-10-25; © Rubinski Visual, used with
    /// their OK), under Nextdoor's fades: a light one at the top for the headline, and a dark
    /// one from mid-screen down for the pills and small print.
    private var photo: some View {
        ZStack {
            Hue.welcomeScrim
                .overlay {
                    if let image = UIImage(named: "welcome-millstream.jpg") {
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
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay), value: shown)
    }
}
