//
//  ProfileView.swift
//  Block Party — the community profile. A warm frosted-glass sheet: the town knows your
//  name, photo, interests, and your real activity (plans you've RSVP'd to, clubs
//  you've joined, quests done). Layout echoes a Revolut-style profile — avatar →
//  name → two feature cards → grouped rows — rendered on iOS translucency over the
//  light canvas, coral accent. Opened from Home's top-right person button.
//
//  Motion: the house SpringReveal cascade on appear; press-scale on every control;
//  spring disclosure for the activity lists. Real-data-only — no seeded counts.
//

import SwiftUI

struct ProfileView: View {
    /// Injected by the genie overlay so the top-bar ✕ and sign-out play the
    /// corner-collapse. Falls back to `dismiss()` if presented some other way.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ProfileModel()

    @State private var revealed = false
    @State private var editing = ProfileView.debugEdit()
    @State private var showAbout = false
    @State private var showModeration = ProfileView.debugModeration()
    @State private var confirmSignOut = false
    @State private var expanded: Expandable? = ProfileView.debugExpand()

    private enum Expandable { case events, clubs }

    /// DEBUG-only: force the edit sheet / an expanded activity list open on launch
    /// so those states can be screenshotted headlessly. No effect in release.
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
    private static func debugExpand() -> Expandable? {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-profile-expand") ? .events : nil
        #else
        return nil
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

    /// DEBUG-only: `-profile-autoclose` fires the genie collapse ~1.6s after open
    /// so the close motion can be recorded headlessly (no tap driving). Routes
    /// through the real `close()`, so it exercises the exact dismissal path.
    private func debugAutoClose() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-profile-autoclose") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { close() }
        #endif
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                Color.clear.frame(height: 44)          // clears the fixed top bar
                header.springReveal(0, revealed: revealed)
                featureCards.springReveal(1, revealed: revealed)
                aroundTown.springReveal(2, revealed: revealed)
                settingsGroup.springReveal(3, revealed: revealed)
                signOutButton.springReveal(4, revealed: revealed).id("bottom")
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
            Button("Sign out", role: .destructive) { Task { await model.signOut(); close() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Dismiss through the genie collapse when presented that way; otherwise the
    /// environment dismiss.
    private func close() {
        if let onClose { onClose() } else { dismiss() }
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
            circleButton("xmark") { close() }
            Spacer()
            Button { Haptics.selection(); editing = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold))
                    Text("Edit").font(.sansSemibold(15))
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Button { Haptics.selection(); editing = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(url: model.avatarUrl, size: 104)
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Hue.ink, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            }
            .buttonStyle(PressableStyle())

            VStack(spacing: 6) {
                Text(model.displayName.isEmpty ? "Add your name" : model.displayName)
                    .font(.display(26))
                    .foregroundStyle(model.displayName.isEmpty ? Hue.inkSecondary : Hue.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 11, weight: .semibold))
                    Text(subLine).font(.sans(13))
                }
                .foregroundStyle(Hue.inkSecondary)

                if model.isAdmin { organizerBadge }
            }

            if !model.interestLabels.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(model.interestLabels, id: \.self) { interestChip($0) }
                }
                .padding(.top, 2)
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
            Image(systemName: "checkmark.seal.fill").font(.system(size: 11, weight: .bold))
            Text("Town organizer").font(.sansSemibold(12))
        }
        .foregroundStyle(Hue.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Hue.fill.opacity(0.92), in: Capsule())
        .padding(.top, 2)
    }

    // MARK: - Feature cards

    private var featureCards: some View {
        HStack(spacing: 12) {
            plansCard
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
    }

    /// Coral + tappable only when there are plans to expand; otherwise a calm,
    /// non-interactive "0 plans · Nothing yet" tile (no dead coral affordance).
    @ViewBuilder private var plansCard: some View {
        let hasPlans = !model.upcoming.isEmpty
        let face = FeatureFace(icon: "calendar",
                               value: "\(model.goingCount)",
                               label: model.goingCount == 1 ? "plan" : "plans",
                               subtitle: hasPlans ? nextPlanLabel : "Nothing yet",
                               coral: hasPlans)
        if hasPlans {
            Button { Haptics.light(); toggle(.events) } label: { face }
                .buttonStyle(PressableStyle())
        } else {
            face
        }
    }

    private var nextPlanLabel: String? {
        guard let e = model.nextPlan else { return nil }
        return "Next · \(DateHelpers.prettyDate(e.eventDate))"
    }

    // MARK: - Around town (real activity)

    private var aroundTown: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("AROUND TOWN")
            GlassGroup {
                ProfileRow(icon: "calendar",
                           title: "Events you're going to",
                           trailing: "\(model.goingCount)",
                           accessory: model.upcoming.isEmpty ? .none : .expand(expanded == .events),
                           action: model.upcoming.isEmpty ? nil : { toggle(.events) })
                if expanded == .events, !model.upcoming.isEmpty {
                    disclosure { ForEach(model.upcoming) { eventItem($0) } }
                }

                ProfileRowDivider()
                ProfileRow(icon: "person.2",
                           title: "Clubs you've joined",
                           trailing: "\(model.clubCount)",
                           accessory: model.clubs.isEmpty ? .none : .expand(expanded == .clubs),
                           action: model.clubs.isEmpty ? nil : { toggle(.clubs) })
                if expanded == .clubs, !model.clubs.isEmpty {
                    disclosure { ForEach(model.clubs) { clubItem($0) } }
                }

                ProfileRowDivider()
                ProfileRow(icon: "checkmark.seal",
                           title: "Quests completed",
                           trailing: "\(model.questCount)",
                           accessory: .none)
            }
        }
    }

    private func toggle(_ e: Expandable) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            expanded = expanded == e ? nil : e
        }
    }

    private func disclosure<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) {
            ProfileRowDivider()
            VStack(spacing: 13) { content() }
                .padding(.vertical, 13)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func eventItem(_ e: UpcomingEvent) -> some View {
        HStack(spacing: 11) {
            Circle().fill(Hue.ink).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.sansMedium(14)).foregroundStyle(Hue.ink).lineLimit(1)
                Text(eventWhen(e)).font(.sans(12)).foregroundStyle(Hue.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if e.goingCount > 0 {
                Text("\(e.goingCount) going")
                    .font(.monoMedium(12)).monospacedDigit().foregroundStyle(Hue.inkSecondary)
            }
        }
        .padding(.leading, 4)
    }

    private func eventWhen(_ e: UpcomingEvent) -> String {
        var s = DateHelpers.prettyDate(e.eventDate)
        if let t = e.startTime, !t.isEmpty { s += " · \(t)" }
        return s
    }

    private func clubItem(_ c: ClubView) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "person.2.fill").font(.system(size: 12)).foregroundStyle(Hue.ink).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.sansMedium(14)).foregroundStyle(Hue.ink).lineLimit(1)
                if let sched = c.schedule, !sched.isEmpty {
                    Text(sched).font(.sans(12)).foregroundStyle(Hue.inkSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text("\(c.memberCount)").font(.monoMedium(12)).monospacedDigit().foregroundStyle(Hue.inkSecondary)
        }
        .padding(.leading, 4)
    }

    // MARK: - Settings

    private var settingsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("SETTINGS")
            GlassGroup {
                if model.isAdmin {
                    ProfileRow(icon: "checkmark.shield", title: "Review queue",
                               subtitle: "Approve what neighbors submit",
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
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 15, weight: .semibold))
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
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Hue.ink)
                        .frame(width: 34, height: 34).background(Hue.fill, in: Circle())
                }
                .buttonStyle(.plain)
            }
            Text("One calm place for everything happening in St. Joseph, Minnesota — a daily look at town, a shared calendar anyone can add to, a live town map, and small nudges to get out and meet your neighbors.")
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
