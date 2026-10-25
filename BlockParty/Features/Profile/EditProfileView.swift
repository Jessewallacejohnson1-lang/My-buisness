//
//  EditProfileView.swift
//  Block Party — edit your community profile: cover · photo · name · bio · interests (the
//  cover and bio for a real account only, BP app references/profile-remake). Mirrors the
//  onboarding steps (same avatar well, the shared interest grid) and saves through
//  ProfileModel.save (upload avatar → town_profiles upsert). A clean opaque form —
//  glass is for the profile display, input reads calmer on paper.
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @ObservedObject var model: ProfileModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var image: UIImage?
    @State private var interests: Set<String> = []
    @State private var pick: PhotosPickerItem?
    @State private var bio = ""
    @State private var cover: UIImage?
    @State private var coverPick: PhotosPickerItem?
    @State private var showInterests = EditProfileView.debugOpenInterests()
    @State private var saving = false
    @State private var saveFailed = false

    /// DEBUG-only: `-profile-edit-interests` auto-opens the interest picker so its
    /// (non-onboarding) chrome can be screenshotted headlessly. No effect in release.
    private static func debugOpenInterests() -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-profile-edit-interests")
        #else
        return false
        #endif
    }

    private var interestLabels: [String] { Interests.labels(for: interests) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    if model.canDescribe {
                        PhotosPicker(selection: $coverPick, matching: .images, photoLibrary: .shared()) { coverWell }
                            .buttonStyle(PressableStyle())
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
            if interests.isEmpty { interests = Set(model.interestIds) }
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
            InterestPickerView(selected: $interests, name: name,
                               onBack: { showInterests = false },
                               onContinue: { showInterests = false })
        }
    }

    // MARK: - Chrome

    private var header: some View {
        ZStack {
            Text("Edit profile").font(.sansSemibold(17)).foregroundStyle(Hue.ink)
            HStack {
                Button { Haptics.light(); dismiss() } label: {
                    Text("Cancel").font(.sans(16)).foregroundStyle(Hue.inkSecondary)
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
            if saveFailed {
                Text("Couldn't save your profile. Check your connection and try again.")
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
                saveFailed = false
                saving = true
                Task {
                    let ok = await model.save(name: name, image: image, interests: Array(interests),
                                              bio: model.canDescribe ? bio : nil, cover: cover)
                    saving = false
                    if ok {
                        Haptics.success()
                        dismiss()
                    } else {
                        Haptics.error()
                        withAnimation(.easeOut(duration: 0.2)) { saveFailed = true }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.white) }
                    Text(saving ? "Saving changes…" : "Save changes")
                        .font(.sansSemibold(17)).foregroundStyle(.white)
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
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = model.avatarUrl, let u = URL(string: url) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Hue.surface }
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
                    .font(.sansSemibold(15))
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
            if interests.isEmpty {
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
                    Text(interests.isEmpty ? "Choose interests" : "Edit interests · \(interests.count)")
                        .font(.sansSemibold(15))
                }
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Hue.fill.opacity(0.9), in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }
}
