//
//  ProfileView.swift
//  Block Party — Profile: your photo, name, Edit profile and settings, in Apple's standard
//  sheet from your photo at the top left of the You tab (BP app docs/plans/you-tab). What
//  you're Going to lives on the You page; your interests are edited in Edit profile.
//
//  Motion: the house SpringReveal cascade on appear; press-scale on every control.
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
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
            VStack(spacing: 16) {
                Color.clear.frame(height: 44)          // clears the fixed top bar
                header.springReveal(0, revealed: revealed)
                inviteCard.springReveal(1, revealed: revealed)
                settingsGroup.springReveal(2, revealed: revealed)
                // Hidden when there is no session to end. Sign-in is switched off
                // (`RootView.requiresSignIn`), so for most people this screen is now
                // reached without ever having signed in, and a "Sign out" button that
                // can only clear something that was never set reads as a broken
                // control. It comes back with the gate. The quiet anonymous account
                // every install gets counts as not signed in: signing out would only
                // throw away its Going.
                if AuthStore.shared.isSignedIn && !AuthStore.shared.isAnonymous {
                    signOutButton.springReveal(3, revealed: revealed).id("bottom")
                }
                // A sheet has no tab bar under it and only needs breathing room.
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 18)
        }
        .overlay(alignment: .top) { topBar }
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button { Haptics.selection(); editing = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(.sansSemibold(13))
                    Text("Edit profile").font(.sansSemibold(15))
                }
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Hue.fill.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(Hue.ink.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Edit profile")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Button { Haptics.selection(); editing = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(url: model.avatarUrl, size: 104)
                    Image(systemName: "pencil")
                        .font(.sansBold(12))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Hue.ink, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Edit profile picture")

            VStack(spacing: 6) {
                Text(model.displayName.isEmpty ? "Add your name" : model.displayName)
                    .font(.display(26))
                    .foregroundStyle(model.displayName.isEmpty ? Hue.inkSecondary : Hue.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse").font(.sansSemibold(11))
                    Text(subLine).font(.sans(13))
                }
                .foregroundStyle(Hue.inkSecondary)

                if model.isAdmin { organizerBadge }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
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
        .padding(.top, 2)
    }

    // MARK: - Invite

    private var inviteCard: some View {
        Button {
            ShareCenter.shared.present(.appInvite())
        } label: {
            FeatureFace(icon: "person.badge.plus",
                        value: "Invite",
                        label: "a neighbor",
                        subtitle: "Share Block Party")
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Settings

    private var settingsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Settings")
            GlassGroup {
                if model.isAdmin {
                    ProfileRow(icon: "checkmark.shield", title: "Review queue",
                               subtitle: "Approve or reject neighbor submissions",
                               action: { Haptics.selection(); showModeration = true })
                    ProfileRowDivider()
                }
                ProfileRow(icon: "person.crop.circle", title: "Edit profile",
                           action: { Haptics.selection(); editing = true })
                ProfileRowDivider()
                ProfileRow(icon: "bell", title: "Notifications", subtitle: "Manage in iOS Settings",
                           action: { openSystemSettings() })
                ProfileRowDivider()
                ProfileRow(icon: "info.circle", title: "About Block Party",
                           action: { showAbout = true })
                if let email = model.email, !email.isEmpty {
                    ProfileRowDivider()
                    ProfileRow(icon: "envelope", title: "Account", subtitle: email, accessory: .none)
                }
            }
        }
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

    private func groupLabel(_ text: String) -> some View {
        Text(text).font(.mono(11)).tracking(1.5).foregroundStyle(Hue.inkSecondary).padding(.leading, 6)
    }

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
            Text("Block Party puts today's events, the town calendar, and a live map of St. Joseph in one place. Neighbors can share events, clubs, and trails.")
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
