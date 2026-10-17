//
//  ProfileView.swift
//  Block Party — Profile: your photo, name, Edit profile, your saved Events and settings, in
//  Apple's standard sheet from your photo at the top left of the You tab (BP app
//  docs/plans/you-tab). What you're Going to lives on the You page; your interests are edited
//  in Edit profile. Saved pushes inside the sheet's own stack (`RootView`).
//
//  Motion: the house SpringReveal cascade on appear; press-scale on every control.
//

import SwiftUI

struct ProfileView: View {
    /// Profile's Saved list, kept in the shell so a second visit shows the last list at once.
    let saves: YouModel
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarSync.self) private var calendarSync
    @Environment(FriendsBook.self) private var friendsBook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = ProfileModel()

    @State private var revealed = false
    @State private var editing = ProfileView.debugEdit()
    @State private var showAbout = false
    @State private var showModeration = ProfileView.debugModeration()
    @State private var confirmSignOut = false

    /// DEBUG-only: force the edit sheet open on launch so it can be screenshotted
    /// headlessly. No effect in release.
    private static func debugEdit() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-profile-edit")
        #else
        return false
        #endif
    }
    /// DEBUG-only: `-profile-moderation` opens the admin review queue on launch.
    private static func debugModeration() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-profile-moderation")
        #else
        return false
        #endif
    }
    var body: some View {
        ScrollViewReader { proxy in
            content.onAppear {
                revealed = true
                debugScrollBottom(proxy)
                debugAutoClose()
            }
        }
    }

    /// DEBUG-only: `-profile-autoclose` dismisses the sheet ~1.6s after open so the
    /// close motion can be recorded headlessly (no tap driving).
    private func debugAutoClose() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-profile-autoclose") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { dismiss() }
        #endif
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                header.springReveal(0, revealed: revealed)
                rows.springReveal(1, revealed: revealed)
                // Hidden when there is no session to end. Sign-in is switched off
                // (`RootView.requiresSignIn`), so for most people this screen is now
                // reached without ever having signed in, and a "Sign out" button that
                // can only clear something that was never set reads as a broken
                // control. It comes back with the gate. The quiet anonymous account
                // every install gets counts as not signed in: signing out would only
                // throw away its Going.
                if AuthStore.shared.isSignedIn && !AuthStore.shared.isAnonymous {
                    signOutButton.springReveal(2, revealed: revealed).id("bottom")
                }
                // A sheet has no tab bar under it and only needs breathing room.
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, 39)                         // the mock's sheet edge to photo, under the grabber
        }
        // The sheet's stack draws its own ground under a page; the paper sheet shows through none.
        .background(Hue.paper.ignoresSafeArea())
        .task { await model.load() }
        .sheet(isPresented: $editing) { EditProfileView(model: model) }
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
        guard ProcessInfo.processInfo.arguments.contains("-profile-bottom") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        #endif
    }

    // MARK: - Header

    /// The mock's head: photo, name, town line, then Edit profile, the one way into
    /// Edit profile (BP app docs/plans/you-tab/issues/08).
    private var header: some View {
        VStack(spacing: 0) {
            ProfileHead(url: model.avatarUrl,
                        name: model.displayName.isEmpty ? "Add your name" : model.displayName,
                        nameInk: model.displayName.isEmpty ? Hue.inkSecondary : Hue.ink,
                        line: subLine)

            if model.isAdmin { organizerBadge }

            Button { Haptics.selection(); editing = true } label: {
                Text("Edit profile")
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(Hue.ink.opacity(0.12), lineWidth: 1))
            }
            .contentShape(Rectangle().inset(by: -4))   // 44pt tap target around the mock's 36pt button
            .buttonStyle(PressableStyle())
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
    }

    private var subLine: String {
        var parts = ["Saint Joseph, MN"]
        if let s = model.sinceLabel { parts.append("Neighbor since \(s)") }
        return parts.joined(separator: "  ·  ")
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
        .padding(.top, 8)
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
                    NavigationLink { BlockedPage() } label: {
                        ProfileRow(icon: "hand.raised", title: "Blocked")
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
    /// Apple's switch, laid out as the Calendar row; it waits for the server's answer.
    private var plansRow: some View {
        HStack(spacing: 13) {
            Image(systemName: "person.2")
                .font(.sansSemibold(16))
                .foregroundStyle(Hue.ink)
                .frame(width: 26)
            Text("Show my plans to friends")
                .font(.sansMedium(16))
                .foregroundStyle(Hue.ink)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle("Show my plans to friends", isOn: Binding(
                get: { model.plansToFriends ?? true },
                set: { on in Task { await model.setPlansToFriends(on) } }))
                .labelsHidden()
                .disabled(model.plansToFriends == nil)
                .turnBackShake(failures: model.plansFailures, shakes: !reduceMotion)
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close About Block Party")
            }
            Text("Block Party puts today's events, the town calendar, and a live map of St. Joseph in one place. Neighbors can share events, groups, and trails.")
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
