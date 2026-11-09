//
//  EditProfileView.swift
//  Block Party — edit your community profile: cover · photo · name · bio · interests (the
//  cover and bio for a real account only, BP app references/profile-remake). Mirrors the
//  onboarding steps (same avatar well, the shared interest chips) and saves through
//  ProfileModel.save (upload avatar → town_profiles upsert). A clean opaque form —
//  glass is for the profile display, input reads calmer on paper.
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    let model: ProfileModel
    @Environment(\.dismiss) private var dismiss
    @Environment(RealLifeActions.self) private var actions

    @State private var name = ""
    @State private var image: UIImage?
    @State private var interests: [String] = []
    /// Interests' Schools: nil while reading, empty when the read failed.
    @State private var schools: [FollowSuggestion]?
    /// Follows tapped in Interests, sent with Save as the picks are, so Cancel leaves both as they were.
    @State private var heldFollows: [FollowTarget: Bool] = [:]
    @State private var pick: PhotosPickerItem?
    @State private var bio = ""
    @State private var cover: UIImage?
    @State private var coverPick: PhotosPickerItem?
    @State private var showInterests = EditProfileView.debugOpenInterests()
    @State private var saving = false
    @State private var saveProblem: ProfileModel.SaveProblem?

    /// DEBUG-only: `-profile-edit-interests` auto-opens the interest picker so its
    /// (non-onboarding) chrome can be screenshotted headlessly. No effect in release.
    private static func debugOpenInterests() -> Bool {
        LaunchFlags.has(.profileEditInterests)
    }

    private var interestLabels: [String] { Interests.names(interests) }
    /// What the summary counts: what the sheet counts, schools followed included.
    private var chosen: Int {
        interestLabels.count + FollowSuggestions.schoolTargets(in: schools ?? []).filter { isFollowing($0) }.count
    }

    private func isFollowing(_ target: FollowTarget) -> Bool {
        heldFollows[target] ?? actions.follow(target).isFollowing
    }

    private func toggleFollow(_ target: FollowTarget) {
        heldFollows[target] = !isFollowing(target)
        let college = FollowSuggestions.collegeTargets(in: schools ?? [])
        guard college.contains(target) else { return }
        interests = Interests.withCollege(interests, following: college.contains(where: isFollowing))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Over the scroll, so Cancel's 44 pt tap reaches its 2 pt past the header.
            header.zIndex(1)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    if model.canDescribe {
                        PhotosPicker(selection: $coverPick, matching: .images, photoLibrary: .shared()) { coverWell }
                            .buttonStyle(.press(.squish))
                    }
                    PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) { avatarWell }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    nameField
                    if model.canDescribe { bioField }
                    interestsSection
                }
                .padding(24)
            }
            footer
        }
        .background(Hue.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear {
            if name.isEmpty { name = model.displayName }
            if interests.isEmpty { interests = model.interestIds }
            if bio.isEmpty { bio = model.bio }
        }
        // Opened before Profile's read landed: its bio comes in then, unless you've typed one.
        .onChange(of: model.bio) { old, new in if bio == old { bio = new } }
        .onChange(of: coverPick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { cover = ui }
                }
            }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { image = ui }
                }
            }
        }
        .sheet(isPresented: $showInterests) {
            InterestsSheet(picked: $interests, schools: schools,
                           isFollowing: { isFollowing($0) }, toggleFollow: { toggleFollow($0) },
                           schoolsOpened: { readSchools() })
                .task { if schools == nil { await loadSchools() } }
        }
    }

    /// Which schools you follow, then their tiles, so a tile never says Follow on one you do. Read
    /// when the sheet opens, not to change a name. Without the follows it's a failed read: nothing
    /// could say which you follow.
    private func loadSchools() async {
        guard let follows = try? await CommunityAPI(auth: AuthStore.shared).myFollows() else {
            schools = []
            return
        }
        actions.read(following: follows.map(\.target))
        schools = (try? await FollowSuggestions.loadSchools()) ?? []
    }

    /// Schools opened with nothing read (no signal back then): read again.
    private func readSchools() {
        guard schools?.isEmpty == true else { return }
        schools = nil
        Task { await loadSchools() }
    }

    // MARK: - Chrome

    private var header: some View {
        ZStack {
            Text("Edit profile").font(.displaySemi(17)).foregroundStyle(Hue.ink)
            HStack {
                Button { Haptics.light(); dismiss() } label: {
                    Text("Cancel").font(.sans(16)).foregroundStyle(Hue.inkSecondary)
                        .contentShape(TapArea())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Hue.hairline).frame(height: 1)
            if let saveProblem {
                Text(saveProblem.line)
                    .font(.sansBold(13))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
            Button {
                guard !saving else { return }
                saveProblem = nil
                saving = true
                Task {
                    let problem = await model.save(name: name, image: image, interests: interests,
                                                   bio: model.canDescribe ? bio : nil, cover: cover)
                    saving = false
                    if let problem {
                        Haptics.error()
                        withAnimation(.easeOut(duration: 0.2)) { saveProblem = problem }
                        // The line fades in silently; this reads it to VoiceOver as it appears.
                        AccessibilityNotification.Announcement(problem.line).post()
                    } else {
                        Haptics.success()
                        for (target, follow) in heldFollows where actions.follow(target).isFollowing != follow {
                            actions.toggleFollow(target)
                        }
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.white) }
                    Text(saving ? "Saving changes…" : "Save changes")
                        .font(.displaySemi(17)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Hue.ink, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Hue.paper)
    }

    // MARK: - Fields

    private var avatarWell: some View {
        ZStack {
            if image != nil || model.avatarUrl != nil {
                Avatar(avatarUrl: model.avatarUrl, size: 132, picked: image)
            } else {
                ZStack {
                    Hue.surface
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill").font(.sans(24)).foregroundStyle(Hue.ink)
                        Text("Add photo").font(.sansMedium(13)).foregroundStyle(Hue.inkSecondary)
                    }
                }
            }
        }
        .frame(width: 132, height: 132)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 4))
        .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.sansBold(12)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Hue.ink, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
        .accessibilityLabel(image == nil ? "Add a profile picture" : "Change profile picture")
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name").font(.mono(11)).tracking(1.5).foregroundStyle(Hue.inkSecondary)
            TextField("Your name", text: $name)
                .font(.sans(17)).foregroundStyle(Hue.ink)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Hue.surface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
                .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
        }
    }

    /// The cover, as wide as the field, at the profile's own shape; a tap picks a new one.
    private var coverWell: some View {
        Hue.fill
            .aspectRatio(GroupPage.Metric.heroAspect, contentMode: .fit)
            .overlay {
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else if let url = model.coverUrl.flatMap(URL.init(string:)) {
                    FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
                } else if let town = ProfileFace.town {
                    Image(uiImage: town).resizable().scaledToFill()
                }
            }
            .overlay {
                Label("Change cover", systemImage: "photo")
                    .font(.displaySemi(15))
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Hue.surface, in: Capsule())
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityLabel("Change cover photo")
    }

    /// Nextdoor's bio: their words for the empty box, 150 letters, the count under it.
    private var bioField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bio").font(.mono(11)).tracking(1.5).foregroundStyle(Hue.inkSecondary)
            TextField("Tell your neighbors a little about yourself", text: $bio, axis: .vertical)
                .font(.sans(17)).foregroundStyle(Hue.ink)
                .lineLimit(3...5)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Hue.surface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
                .onChange(of: bio) { _, v in
                    if ProfileModel.bioLength(v) > ProfileModel.bioLimit { bio = ProfileModel.clampBio(v) }
                }
            Text("\(ProfileModel.bioLength(bio))/\(ProfileModel.bioLimit)")
                .font(.sans(12)).foregroundStyle(Hue.inkSecondary).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interests").font(.mono(11)).tracking(1.5).foregroundStyle(Hue.inkSecondary)
            if interestLabels.isEmpty {
                Text("Choose a few to see events, groups, and trails that match.")
                    .font(.sans(14)).foregroundStyle(Hue.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(interestLabels, id: \.self) { interestChip($0) }
                }
            }
            Button { Haptics.selection(); showInterests = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").font(.sansSemibold(14))
                    Text(chosen == 0 ? "Choose interests" : "Edit interests · \(chosen)")
                        .font(.displaySemi(15))
                }
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Hue.fill.opacity(0.9), in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(.press(.squish))
        }
    }
}

/// Edit Profile's interests: onboarding's rows, keeping at least one thing picked or followed.
private struct InterestsSheet: View {
    @Binding var picked: [String]
    let schools: [FollowSuggestion]?
    let isFollowing: (FollowTarget) -> Bool
    let toggleFollow: (FollowTarget) -> Void
    let schoolsOpened: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var count: Int {
        Interests.count(picked) + FollowSuggestions.schoolTargets(in: schools ?? []).filter(isFollowing).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Interests")
                .font(.apple(17, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
            // Onboarding's white card on its grey canvas, one look for both (Jesse, 2026-11-09).
            InterestRows(picked: $picked, schools: schools, isFollowing: isFollowing, toggleFollow: toggleFollow,
                         schoolsOpened: schoolsOpened, bottomInset: 120) {
                EmptyView()
            }
        }
        // Watch sports and the rest no longer on the rows go when you come to change them.
        .onAppear { picked = Interests.onRows(picked) }
        // An old Campus pick stays only with something under the college followed, once that's read.
        .onChange(of: schools, initial: true) { _, new in
            let college = FollowSuggestions.collegeTargets(in: new ?? [])
            if !college.isEmpty {
                picked = Interests.withCollege(picked, following: college.contains(where: isFollowing))
            }
        }
        .overlay(alignment: .bottom) {
            // Onboarding's Next pill: grey and shaking until one thing is picked or followed.
            OnboardingNextBar(title: count == 0 ? "Pick 1" : "Done", allowed: count > 0) {
                Haptics.selection(); dismiss()
            }
            .padding(.horizontal, FollowGridMetric.gutter)
            .padding(.top, 32)
            .padding(.bottom, 8)
            // The rows scroll away under the canvas, as onboarding's do under its Next pill.
            .background(LinearGradient(colors: [Hue.onboardingCanvas.opacity(0), Hue.onboardingCanvas], startPoint: .top, endPoint: .center)
                .ignoresSafeArea())
        }
        .background(Hue.onboardingCanvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(count == 0)
    }
}
