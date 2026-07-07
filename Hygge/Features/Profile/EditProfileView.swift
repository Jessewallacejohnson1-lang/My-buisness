//
//  EditProfileView.swift
//  Hygge — edit your community profile: photo · name · interests. Mirrors the
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
                    PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) { avatarWell }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    nameField
                    interestsSection
                }
                .padding(24)
            }
            footer
        }
        .background(Hue.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear {
            if name.isEmpty { name = model.displayName }
            if interests.isEmpty { interests = Set(model.interestIds) }
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
                               onContinue: { showInterests = false },
                               showsProgress: false)
        }
    }

    // MARK: - Chrome

    private var header: some View {
        ZStack {
            Text("Edit profile").font(.sansSemibold(17)).foregroundStyle(Hue.ink)
            HStack {
                Button { Haptics.light(); dismiss() } label: {
                    Text("Cancel").font(.sans(16)).foregroundStyle(Hue.ink2)
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
                Text("Couldn't save — check your connection and try again.")
                    .font(.sans(13))
                    .foregroundStyle(Hue.clay700)
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
                    let ok = await model.save(name: name, image: image, interests: Array(interests))
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
                    Text(saving ? "Saving…" : "Save")
                        .font(.sansSemibold(17)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Hue.accent, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Hue.canvas)
    }

    // MARK: - Fields

    private var avatarWell: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = model.avatarUrl, let u = URL(string: url) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Hue.paper }
            } else {
                ZStack {
                    Hue.paper
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill").font(.system(size: 24)).foregroundStyle(Hue.accent)
                        Text("Add photo").font(.sansMedium(13)).foregroundStyle(Hue.ink3)
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
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Hue.accent, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
        .accessibilityLabel(image == nil ? "Add a profile picture" : "Change profile picture")
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME").font(.mono(11)).tracking(1.5).foregroundStyle(Hue.ink3)
            TextField("Your name", text: $name)
                .font(.sans(17)).foregroundStyle(Hue.ink)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Hue.paper, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
                .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
        }
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INTERESTS").font(.mono(11)).tracking(1.5).foregroundStyle(Hue.ink3)
            if interests.isEmpty {
                Text("Pick a few so we can quietly surface what fits around town.")
                    .font(.sans(14)).foregroundStyle(Hue.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(interestLabels, id: \.self) { interestChip($0) }
                }
            }
            Button { Haptics.selection(); showInterests = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .semibold))
                    Text(interests.isEmpty ? "Choose interests" : "Edit interests · \(interests.count)")
                        .font(.sansSemibold(15))
                }
                .foregroundStyle(Hue.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Hue.accentSoft.opacity(0.9), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }
}
