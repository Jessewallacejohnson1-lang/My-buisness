//
//  ProfileView.swift
//  Block Party — the You tab: your Profile (five-tabs 03), the profile page (`ProfilePage`, BP app
//  references/profile-remake) with your full Calendar and Agenda under "Going" (`YouPage`), where a
//  neighbour's page has its Going rows; only you see them. Edit profile and Settings sit in white
//  circles on the cover; your settings, Saved among them, push from ☰ on the shell's stack, over
//  the tab bar, as an Event page does.
//
//  Motion: the house SpringReveal cascade on Settings; press-scale on every control.
//

import SwiftUI

struct ProfileView: View {
    /// Your name, photo, cover and switches, kept in the shell (`AppSession`) so coming back to You
    /// shows them at once while they read again.
    let model: ProfileModel
    /// Profile's Saved list, kept in the shell so a second visit shows the last list at once.
    let saves: YouModel
    @EnvironmentObject private var auth: AuthStore
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
    @State private var pushedEvent: FeedCardItem?
    @State private var pushedGroup: TownGroup?

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
        TimelineView(.everyMinute) { context in
            ProfilePage(face: face(now: context.date), calendar: YouPage(model: you, open: { pushedEvent = $0 })) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    EventPage.circleButton(glyph: Image(systemName: "pencil"), label: "Edit profile") {
                        Haptics.selection()
                        editing = true
                    }
                    EventPage.circleButton(glyph: Image(systemName: "line.3.horizontal"),
                                           label: "Settings") {
                        Haptics.selection()
                        settings = true
                    }
                }
            } bar: {
                // Room for the tab bar under your Groups, as every tab leaves.
                Color.clear.frame(height: DailyMetric.tabBarClearance - EventPage.Metric.contentBottom)
            } addBio: {
                Haptics.selection()
                editing = true
            } openEvent: { pushedEvent = $0 } openGroup: { pushedGroup = $0 }
        }
        // On every visit, and for another account while You is open (`AppSession` has cleared the last one's).
        .task(id: auth.accountKey) { await model.load() }
        .navigationDestination(isPresented: $settings) { settingsPage }
        .navigationDestination(item: $pushedEvent) { EventPage(item: $0) }
        .navigationDestination(item: $pushedGroup) { GroupPage(group: $0) }
        .sheet(isPresented: $editing) { EditProfileView(model: model) }
    }

    /// Your page: how many plans in the three weeks (the Calendar shows them, `YouPage`), the groups
    /// you're in (this session's joins laid over the read), your bio or "+ Add bio".
    private func face(now: Date) -> ProfileFace {
        let first = YouCalendar.firstDay(of: now)
        let going = you.going.map {
            YouCalendar.going(read: $0, tapped: Array(actions.goingTapped.values),
                              isGoing: { actions.going($0).isGoing }, first: first)
        }
        let plans = going.map { ProfileFace.nextPlans($0, now: now) }
        let bio = model.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProfileFace(
            name: model.displayName.isEmpty ? "Add your name" : model.displayName,
            avatarUrl: model.avatarUrl,
            coverUrl: model.coverUrl,
            bio: bio.isEmpty ? nil : bio,
            line: subLine,
            friends: model.extras?.friends,
            groups: (you.groups ?? []).filter { actions.member($0).isMember },
            goingCount: plans?.count,
            addsBio: bio.isEmpty && model.canDescribe,
            coverKnown: model.loaded,
            now: now)
    }

    private var subLine: String {
        var parts = [Town.everyday]
        if let s = model.sinceLabel { parts.append("Neighbor since \(s)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Settings

    /// Today's rows, pushed from ☰ under Saved's top (`SavedPage`), on the shell's stack.
    private var settingsPage: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    if model.isAdmin { organizerBadge.springReveal(0, revealed: revealed) }
                    rows.springReveal(1, revealed: revealed)
                    // Hidden when there is no session to end. The quiet anonymous account every
                    // install gets counts as not signed in: signing out would only throw away
                    // its Going.
                    if AuthStore.shared.isSignedIn && !AuthStore.shared.isAnonymous {
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
            .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: "Settings") { settings = false } }
            .onAppear {
                revealed = true
                debugScrollBottom(proxy)
            }
        }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAbout) {
            AboutBlockPartySheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showModeration) { ModerationView() }
        .confirmationDialog("Log out of Block Party?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            // Back to You, which starts over for the account that follows (`AppSession`).
            Button("Log out", role: .destructive) { Task { await model.signOut(); settings = false } }
            Button("Cancel", role: .cancel) {}
        }
        // Dot's dialog and Superlist's words (BP app references/delete-account): one question, no second
        // screen (Jesse, 2026-11-06).
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
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

    /// One group of rows, as in the mock, Saved at the top (ticket 04).
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassGroup {
                // Apple's push, as Instagram's and Facebook's Saved open (Mobbin, BP app
                // references/saved-in-profile). "Saved" from the words page.
                NavigationLink { SavedPage(model: saves) } label: {
                    ProfileRow(icon: BookmarkGlyph(saved: true), title: "Saved")
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
                if !friendsBook.isAnonymous() {
                    plansRow
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
                if !friendsBook.isAnonymous() {
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
        .disabled(model.deletingAccount)
        .opacity(model.deletingAccount ? 0.45 : 1)
    }

    /// Under Log out, as Uxcel Go's (Jesse, 2026-11-06): quiet red words at Log out's height.
    private var deleteAccountButton: some View {
        Button { Haptics.light(); confirmDelete = true } label: {
            HStack(spacing: 8) {
                if model.deletingAccount { ProgressView().controlSize(.small) }
                Text(model.deletingAccount ? "Deleting…" : "Delete account").font(.displaySemi(15))
            }
            .foregroundStyle(model.deletingAccount ? Hue.inkSecondary : Hue.canceled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
        .disabled(model.deletingAccount)
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
                .buttonStyle(.plain)
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
