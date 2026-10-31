//
//  ProfileView.swift
//  Block Party — Profile, in Apple's standard sheet from your photo at the top left of the You
//  tab (BP app docs/plans/you-tab): your own profile page (`ProfilePage`, BP app
//  references/profile-remake), with Edit profile and Settings in white circles on the cover. Your
//  settings, Saved among them, push from ☰ inside the sheet's own stack (`RootView`), as Saved
//  did, so nothing stacks a sheet on the sheet.
//
//  Motion: the house SpringReveal cascade on Settings; press-scale on every control.
//

import SwiftUI

struct ProfileView: View {
    /// Profile's Saved list, kept in the shell so a second visit shows the last list at once.
    let saves: YouModel
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarSync.self) private var calendarSync
    @Environment(FriendsBook.self) private var friendsBook
    @Environment(RealLifeActions.self) private var actions
    /// Your three weeks of Going and the Town's groups, the You tab's (`RootView`).
    @Environment(YouModel.self) private var you
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = ProfileModel()

    @State private var revealed = false
    @State private var editing = ProfileView.debugEdit()
    @State private var settings = ProfileView.debugSettings()
    @State private var showAbout = false
    @State private var showModeration = ProfileView.debugModeration()
    @State private var confirmSignOut = false
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
    /// DEBUG-only: `-profile-settings` (and `-profile-bottom`, scrolled to Sign out) opens Settings.
    private static func debugSettings() -> Bool {
        LaunchFlags.has(.profileSettings) || LaunchFlags.has(.profileBottom)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            ProfilePage(face: face(now: context.date)) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    FeedEventDetailDestination.circleButton(glyph: Image(systemName: "pencil"), label: "Edit profile",
                                                            reduceMotion: reduceMotion) {
                        Haptics.selection()
                        editing = true
                    }
                    FeedEventDetailDestination.circleButton(glyph: Image(systemName: "line.3.horizontal"),
                                                            label: "Settings", reduceMotion: reduceMotion) {
                        Haptics.selection()
                        settings = true
                    }
                }
            } bar: {
                EmptyView()
            } addBio: {
                Haptics.selection()
                editing = true
            } openEvent: { pushedEvent = $0 } openGroup: { pushedGroup = $0 }
        }
        .onAppear { debugAutoClose() }
        .task { await model.load() }
        .task {
            if you.going == nil { await you.refresh() }
            if you.groups == nil { await you.refreshGroups() }
        }
        .navigationDestination(isPresented: $settings) { settingsPage }
        .navigationDestination(item: $pushedEvent) { FeedEventDetailDestination(item: $0) }
        .navigationDestination(item: $pushedGroup) { GroupPage(group: $0) }
        .sheet(isPresented: $editing) { EditProfileView(model: model) }
    }

    /// Your page: your next three plans and how many in the three weeks, the groups you're in
    /// (this session's joins laid over the read, as You's row), your bio or "+ Add bio".
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
            going: plans?.rows,
            goingCount: plans?.count,
            addsBio: bio.isEmpty && model.canDescribe,
            coverKnown: model.loaded,
            now: now)
    }

    /// DEBUG-only: `-profile-autoclose` dismisses the sheet ~1.6s after open so the
    /// close motion can be recorded headlessly (no tap driving).
    private func debugAutoClose() {
        #if DEBUG
        guard LaunchFlags.has(.profileAutoclose) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { dismiss() }
        #endif
    }

    private var subLine: String {
        var parts = [Town.everyday]
        if let s = model.sinceLabel { parts.append("Neighbor since \(s)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Settings

    /// Today's rows, pushed from ☰ under Saved's top (`SavedPage`): the sheet's own stack.
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
                        signOutButton.springReveal(2, revealed: revealed).id("bottom")
                    }
                    // A sheet has no tab bar under it and only needs breathing room.
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
        .confirmationDialog("Sign out of Block Party?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut(); dismiss() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// DEBUG-only: `-profile-bottom` scrolls to the sign-out row on appear so the
    /// bottom of the sheet can be screenshotted headlessly. No effect in release.
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
                .buttonStyle(PressableStyle())
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
                    NavigationLink { FollowingPage() } label: {
                        ProfileRow(icon: "person.2", title: "Following")
                    }
                    .buttonStyle(PressableStyle())
                    ProfileRowDivider()
                    NavigationLink { BlockedPage() } label: {
                        ProfileRow(icon: "hand.raised", title: "Blocked")
                    }
                    .buttonStyle(PressableStyle())
                    ProfileRowDivider()
                    // `muted-row` (town-feed 21): the hosts you muted from a Town card.
                    NavigationLink { MutedPage() } label: {
                        ProfileRow(icon: "speaker.slash", title: "Muted")
                    }
                    .buttonStyle(PressableStyle())
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
                .buttonStyle(PressableStyle())
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
                Text("Sign out").font(.sansSemibold(16))
            }
            .foregroundStyle(Hue.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .glassPanel(Radius.card)
        }
        .buttonStyle(PressableStyle())
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
