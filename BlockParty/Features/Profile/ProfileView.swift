//
//  ProfileView.swift
//  Block Party — the You tab: your Profile (five-tabs 03), the profile page (`ProfilePage`, BP app
//  references/profile-remake, profile-middle) with your full Calendar and Agenda under "Going"
//  (`YouPage`), where a neighbour's page has its Going rows; only you see them. On the cover, share
//  (Your code) in white glass and the gear in dark glass; your settings, Liked among them, push from
//  the gear on the shell's stack, over the tab bar, as an Event page does. Under your name, Edit
//  profile and Map.
//
//  Motion: the house SpringReveal cascade on Settings; press-scale on every control.
//

import SwiftUI

struct ProfileView: View {
    /// Your name, photo, cover and switches, kept in the shell (`AppSession`) so coming back to You
    /// shows them at once while they read again.
    let model: ProfileModel
    /// You's Liked list, kept in the shell so a second visit shows the last list at once.
    let likes: YouModel
    /// The town map, full screen, as the Town bar's yellow disc opens it (`RootView`).
    let openMap: () -> Void
    @EnvironmentObject private var auth: AuthStore
    /// Pushes a neighbour found by Your code's Scan a code onto the shell's stack.
    @Environment(\.hostOpener) private var opener
    @Environment(CalendarSync.self) private var calendarSync
    /// For Muted and Following: a page pushed on the shell's stack reads the stack's environment,
    /// not this page's, so each link hands these on (`RootView` gives them to the You tab).
    @Environment(TownFeed.self) private var townFeed
    @Environment(SearchModel.self) private var searchModel
    @Environment(FriendsBook.self) private var friendsBook
    @Environment(RealLifeActions.self) private var actions
    /// Your three weeks of Going and the Town's groups, the You tab's (`RootView`).
    @Environment(YouModel.self) private var you
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed = false
    @State private var editing = ProfileView.debugEdit()
    @State private var settings = ProfileView.debugSettings()
    @State private var showAbout = false
    @State private var showModeration = ProfileView.debugModeration()
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    /// The Phone and Code steps, changing your number or adding one (onboarding 17).
    @State private var changing: PhoneForm?
    @State private var showingCode = false
    @State private var pushedEvent: FeedCardItem?
    @State private var pushedGroup: TownGroup?
    /// Start a group's sheet, from the last row of your Groups (BP app start-a-group 02).
    @State private var startingGroup = false
    @State private var showingFollowing = false

    /// DEBUG-only: force the edit sheet open on launch so it can be screenshotted
    /// headlessly. No effect in release.
    private static func debugEdit() -> Bool {
        LaunchFlags.has(.profileEdit)
    }
    /// DEBUG-only: `-profile-moderation` opens the admin review queue on launch.
    private static func debugModeration() -> Bool {
        LaunchFlags.has(.profileModeration)
    }
    /// DEBUG-only: `-profile-settings` (and `-profile-bottom`, scrolled to Log out) opens Settings.
    private static func debugSettings() -> Bool {
        LaunchFlags.has(.profileSettings) || LaunchFlags.has(.profileBottom)
    }

    var body: some View {
        ProfilePage(face: face, calendar: YouPage(model: you, open: { pushedEvent = $0 }, openGroup: { pushedGroup = $0 })) {
            HStack(spacing: ProfileMetric.glassBoxGap) {
                Spacer(minLength: 0)
                // Your code: only a real account can be found, so the quiet one's would lead nowhere.
                if friendsBook.hasAccount() {
                    ProfileGlassButton(glyph: Image(systemName: "square.and.arrow.up"), label: "Share your profile") {
                        Haptics.selection()
                        showingCode = true
                    }
                }
                ProfileGlassButton(glyph: Image(systemName: "gearshape"), label: "Settings", dark: true) {
                    Haptics.selection()
                    settings = true
                }
            }
        } bar: {
            // Room for the tab bar under your Groups, as every tab leaves.
            Color.clear.frame(height: DailyMetric.tabBarClearance - EventPage.Metric.contentBottom)
        } edit: {
            Haptics.selection()
            editing = true
        } openMap: {
            openMap()
        } openEvent: { pushedEvent = $0 } openGroup: { pushedGroup = $0 }
        openFriends: { opener?.push(FriendsRoute.allFriends) } openFollowing: { showingFollowing = true }
        openFollowers: { opener?.push(FriendsRoute.followers) }
        startGroup: { startingGroup = true }
        // On every visit, and for another account while You is open (`AppSession` has cleared the last one's).
        .task(id: auth.accountKey) { await model.load() }
        .navigationDestination(isPresented: $settings) { settingsPage.timesOpen("settings") }
        #if DEBUG
        .onChange(of: OpenCycle.shared.settings) { _, on in settings = on }
        #endif
        .navigationDestination(item: $pushedEvent) { EventPage(item: $0) }
        .navigationDestination(item: $pushedGroup) { GroupPage(group: $0).environment(searchModel) }
        // The counts open their lists, as Instagram's do: Settings' Following here; friends and followers on the
        // shell's stack, so a name in them opens its page (a list pushed from here held that push under it).
        .navigationDestination(isPresented: $showingFollowing) { FollowingPage().environment(searchModel) }
        .sheet(isPresented: $editing) { EditProfileView(model: model) }
        .sheet(isPresented: $startingGroup) {
            StartGroupSheet(groups: you.groups ?? []) { pushedGroup = $0 }
        }
        // As the Friends tab's Your code opens it (`FriendsWaysCard`).
        .sheet(isPresented: $showingCode) { YourCodeSheet { opener?.push($0) } }
    }

    /// Your page: your counts, the groups you're in (this session's joins laid over the read), your
    /// bio or "+ Add bio".
    private var face: ProfileFace {
        let bio = model.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProfileFace(
            name: model.displayName.isEmpty ? "Add your name" : model.displayName,
            avatarUrl: model.avatarUrl,
            coverUrl: model.coverUrl,
            bio: bio.isEmpty ? nil : bio,
            friends: model.extras?.friends,
            following: model.extras?.following,
            followers: model.extras?.followers,
            countsLoading: model.countsLoading,
            groups: (you.groups ?? []).filter { actions.member($0).isMember },
            addsBio: bio.isEmpty && model.canDescribe,
            coverKnown: model.loaded)
    }

    // MARK: - Settings

    /// Today's rows, pushed from the gear under Liked's top (`LikedPage`), on the shell's stack.
    private var settingsPage: some View {
        ScrollViewReader { proxy in
            // The rows a moment after the push starts: making them first held the tap 87 ms (tab-lag 02).
            MadeAfterOpen {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        if model.isAdmin { organizerBadge.springReveal(0, revealed: revealed) }
                        rows.springReveal(1, revealed: revealed)
                        // Hidden when there is no session to end. The quiet anonymous account every
                        // install gets counts as not signed in: signing out would only throw away
                        // its Going.
                        if AuthStore.shared.hasAccount {
                            VStack(spacing: 2) {
                                signOutButton
                                deleteAccountButton
                                if model.deleteFailed {
                                    Text(ProfileModel.deleteFailedLine)
                                        .font(.sans(13))
                                        .foregroundStyle(Hue.inkSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 6)
                                }
                            }
                            .springReveal(2, revealed: revealed)
                            .id("bottom")
                        }
                        // Pushed over the tab bar, so it only needs breathing room.
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .onAppear {
                    revealed = true
                    debugScrollBottom(proxy)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: "Settings") { settings = false } }
        }
        // While a delete runs nothing here takes a tap, so its answer can't go unseen.
        .disabled(model.deletingAccount)
        .onDisappear { model.deleteFailed = false }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAbout) {
            AboutBlockPartySheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showModeration) { ModerationView() }
        .fullScreenCover(item: $changing) { form in
            PhoneSignInScreen(form: form, close: { changing = nil }, done: {
                changing = nil
                return nil
            })
        }
        .confirmationDialog("Log out of Block Party?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            // Back to You, which starts over for the account that follows (`AppSession`).
            Button("Log out", role: .destructive) { Task { await model.signOut(); settings = false } }
            Button("Cancel", role: .cancel) {}
        }
        // Superlist's words (BP app references/delete-account): one question, no second screen (Jesse,
        // 2026-11-06). An alert, not Log out's confirmationDialog: on iOS 26.5 that shows no Cancel, and the
        // only button in sight is the one that can't be undone.
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete account", role: .destructive) {
                Task { if await model.deleteAccount() { settings = false } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, posts, messages and photos will be erased. This can't be undone.")
        }
    }

    /// DEBUG-only: `-profile-bottom` scrolls to the sign-out row on appear so the
    /// bottom of Settings can be screenshotted headlessly. No effect in release.
    private func debugScrollBottom(_ proxy: ScrollViewProxy) {
        #if DEBUG
        guard LaunchFlags.has(.profileBottom) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        #endif
    }

    private var organizerBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill").font(.sansBold(11))
            Text("Town organizer").font(.sansSemibold(12))
        }
        .foregroundStyle(Hue.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Hue.fill.opacity(0.92), in: Capsule())
    }

    // MARK: - Rows

    /// One group of rows, as in the mock, Liked at the top (ticket 04, inside-cards 16).
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassGroup {
                // Apple's push, as Instagram's and Facebook's Saved open (Mobbin, BP app
                // references/saved-in-profile). Instagram's word and the app's own heart, in ink as
                // every row's icon is (BP app inside-cards 16).
                NavigationLink { LikedPage(model: likes) } label: {
                    ProfileRow(icon: FeedActionGlyphView(glyph: .heart, size: 20), title: "Liked")
                }
                .buttonStyle(.press(.squish))
                ProfileRowDivider()
                ProfileRow(icon: "person.badge.plus", title: "Invite a neighbor",
                           action: { ShareCenter.shared.present(.appInvite()) })
                ProfileRowDivider()
                calendarRow
                ProfileRowDivider()
                // `plans-to-friends` (town-feed 28), beside the Calendar switch: only a real
                // account can have friends.
                if friendsBook.hasAccount() {
                    plansRow
                    ProfileRowDivider()
                    neighborsRow
                    ProfileRowDivider()
                    // `suggest-me-switch` (daily-tab 22).
                    suggestRow
                    ProfileRowDivider()
                }
                if model.isAdmin {
                    ProfileRow(icon: "checkmark.shield", title: "Review queue",
                               action: { Haptics.selection(); showModeration = true })
                    ProfileRowDivider()
                }
                ProfileRow(icon: "bell", title: "Notifications",
                           action: { openSystemSettings() })
                ProfileRowDivider()
                // `blocked-row` (BP app docs/plans/friends, ticket 04): only a real account can
                // have blocked anyone.
                if friendsBook.hasAccount() {
                    // `following-row` (follows 02), beside Blocked.
                    NavigationLink { FollowingPage().environment(searchModel) } label: {
                        ProfileRow(icon: "person.2", title: "Following")
                    }
                    .buttonStyle(.press(.squish))
                    ProfileRowDivider()
                    NavigationLink { BlockedPage() } label: {
                        ProfileRow(icon: "hand.raised", title: "Blocked")
                    }
                    .buttonStyle(.press(.squish))
                    ProfileRowDivider()
                    // `muted-row` (town-feed 21): the hosts you muted from a Town card.
                    NavigationLink { MutedPage().environment(townFeed) } label: {
                        ProfileRow(icon: "speaker.slash", title: "Muted")
                    }
                    .buttonStyle(.press(.squish))
                    ProfileRowDivider()
                }
                ProfileRow(icon: "info.circle", title: "About Block Party",
                           action: { showAbout = true })
                // Only a real account has a number to change; only you see it (onboarding 17).
                if PhoneSignIn.isOn, friendsBook.hasAccount() {
                    ProfileRowDivider()
                    ProfileRow(icon: "phone", title: "Phone number",
                               subtitle: auth.phone.map { PhoneNumber.spaced(PhoneNumber.digits($0)) },
                               action: { changing = .change() })
                }
                if let email = model.email, !email.isEmpty {
                    ProfileRowDivider()
                    ProfileRow(icon: "envelope", title: "Account", subtitle: email, accessory: .none)
                }
            }
            if calendarSync.refused {
                // Words picked from popular apps' calendar sync screens (Jesse, 2026-10-12:
                // "just use recommended words"). A tap opens the app's Settings, as
                // Notifications does.
                Button { openSystemSettings() } label: {
                    Text("Calendar access is off. Turn it on in Settings.")
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(minHeight: 44)
                        .padding(.leading, 6)
                }
                .buttonStyle(.press(.squish))
            }
        }
    }

    /// Your Going in your iPhone Calendar (ticket 05): Apple's switch, on while iOS is
    /// asked; a refusal flips it back, then shakes it.
    private var calendarRow: some View {
        HStack(spacing: 13) {
            Image(systemName: "calendar")
                .font(.sansSemibold(16))
                .foregroundStyle(Hue.ink)
                .frame(width: 26)
            // Todoist's and Grab's word for it (Mobbin, 2026-10-12).
            Text("Sync to Calendar")
                .font(.sansMedium(16))
                .foregroundStyle(Hue.ink)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle("Sync to Calendar", isOn: Binding(
                get: { calendarSync.isOn || calendarSync.asking },
                set: { on in
                    if on { Task { await calendarSync.turnOn() } } else { calendarSync.turnOff() }
                }))
                .labelsHidden()
                .disabled(calendarSync.asking)
                .turnBackShake(failures: calendarSync.refusals, shakes: !reduceMotion)
        }
        .frame(minHeight: 52)                   // the rows' height (`ProfileRow`)
    }

    /// Whether friends see your Going on the Events themselves (town-feed 28), on by default.
    private var plansRow: some View {
        switchRow("Show my plans to friends", icon: "person.2", value: model.plansToFriends,
                  failures: model.plansFailures) { on in await model.setPlansToFriends(on) }
    }

    /// Whether neighbours who aren't friends see you among who's going (inside-cards 36), on by default.
    private var neighborsRow: some View {
        switchRow("Show me to neighbors going", icon: "person.3", value: model.plansToNeighbors,
                  failures: model.neighborsFailures) { on in await model.setPlansToNeighbors(on) }
    }

    /// Whether you show on others' People you may know (daily-tab 22), on by default.
    private var suggestRow: some View {
        switchRow("Suggest me to people I may know", icon: "person.line.dotted.person", value: model.suggestMe,
                  failures: model.suggestFailures) { on in await model.setSuggestMe(on) }
    }

    /// Apple's switch, laid out as the Calendar row; it waits for the server's answer.
    private func switchRow(_ title: String, icon: String, value: Bool?, failures: Int,
                           set: @escaping (Bool) async -> Void) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.sansSemibold(16))
                .foregroundStyle(Hue.ink)
                .frame(width: 26)
            Text(title)
                .font(.sansMedium(16))
                .foregroundStyle(Hue.ink)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(title, isOn: Binding(
                get: { value ?? true },
                set: { on in Task { await set(on) } }))
                .labelsHidden()
                .disabled(value == nil)
                .turnBackShake(failures: failures, shakes: !reduceMotion)
        }
        .frame(minHeight: 52)                   // the rows' height (`ProfileRow`)
    }

    private var signOutButton: some View {
        Button { Haptics.light(); confirmSignOut = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.sansSemibold(15))
                Text("Log out").font(.displaySemi(16))
            }
            .foregroundStyle(Hue.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .glassPanel(Radius.card)
        }
        .buttonStyle(.press(.squish))
        .opacity(model.deletingAccount ? 0.45 : 1)
    }

    /// Under Log out, as Uxcel Go's (Jesse, 2026-11-06): quiet red words at Log out's height.
    private var deleteAccountButton: some View {
        Button { Haptics.light(); confirmDelete = true } label: {
            Text(model.deletingAccount ? "Deleting…" : "Delete account")
                .font(.displaySemi(15))
                .foregroundStyle(model.deletingAccount ? Hue.inkSecondary : Hue.canceled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
        .turnBackShake(failures: model.deleteFailures, shakes: !reduceMotion)
    }

    // MARK: - Helpers

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - About sheet

struct AboutBlockPartySheet: View {
    @Environment(\.dismiss) private var dismiss

    private var versionLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("About Block Party").font(.display(26)).foregroundStyle(Hue.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.sansSemibold(14)).foregroundStyle(Hue.ink)
                        .frame(width: 34, height: 34).background(Hue.fill, in: Circle())
                        .contentShape(TapArea())
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("Close About Block Party")
            }
            Text("Block Party puts today's events, the town calendar, and a live map of \(Town.everyday) in one place. Neighbors can share events, groups, and trails.")
                .font(.sans(16)).foregroundStyle(Hue.inkSecondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(versionLine).font(.monoMedium(13)).monospacedDigit().foregroundStyle(Hue.inkSecondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Hue.paper.ignoresSafeArea())
    }
}

#if DEBUG
/// `-open-cycle`'s hand on Settings (`RootView.cycleOpens`), which is this tab's own push.
@MainActor @Observable
final class OpenCycle {
    static let shared = OpenCycle()
    var settings = false
}
#endif
