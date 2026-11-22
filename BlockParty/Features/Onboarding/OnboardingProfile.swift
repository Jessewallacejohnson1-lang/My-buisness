//
//  OnboardingProfile.swift
//  Block Party — onboarding's Profile as Clubhouse's two steps (BP app onboarding 55, Jesse 2026-11-22: "keep my
//  words remove the people use real names on bp and and slice the where you type pill by 20 percent i agree").
//  On white: "What Mom calls you" over one name box, then "Add a photo?" over a squircle to tap. Apple's font
//  at Clubhouse's sizes and spots, measured in BP app `references/profile-clubhouse/SPEC.md`. The answers
//  live in `OnboardingStore`; `OnboardingFlow` owns the backdrop, the back arrow, Skip and the Next pill.
//  Bio left onboarding (it stays in Edit profile); one typed before then still saves.
//

import SwiftUI
import PhotosUI

/// Clubhouse's spots, in points from the screen's top (its question's ink starts 140 pt down).
enum ClubhouseStep {
    static let questionTop: CGFloat = 134
    /// The name box: 20% narrower than the screen-wide box Clubhouse's two make (Jesse), Clubhouse's 40 pt tall.
    static let nameBoxTop: CGFloat = 214
    static let nameBoxWidth: CGFloat = 290
    static let nameBoxHeight: CGFloat = 40
}

/// The question on Clubhouse's steps: Apple's font, 22 pt regular, centred.
struct OnboardingClubhouseQuestion: View {
    let words: String
    @AccessibilityFocusState.Binding var focused: Bool

    var body: some View {
        Text(words)
            .font(.apple(22))
            .foregroundStyle(Hue.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, FollowGridMetric.gutter)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focused)
    }
}

/// "What Mom calls you" and one name box, the keyboard up as the step arrives (not under VoiceOver, so the
/// question is heard first). Return goes on once there is a name.
struct OnboardingNameStep: View {
    @Bindable var store: OnboardingStore
    @AccessibilityFocusState.Binding var headingFocused: Bool
    let submit: () -> Void

    @FocusState private var typing: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        VStack(spacing: 0) {
            OnboardingClubhouseQuestion(words: OnboardingStep.profile.question, focused: $headingFocused)
            nameBox
                .padding(.top, ClubhouseStep.nameBoxTop - ClubhouseStep.questionTop - Self.questionLine)
            Spacer(minLength: 0)
        }
        .padding(.top, ClubhouseStep.questionTop)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { if !voiceOver { typing = true } }
    }

    /// The question's one line at 22 pt (title2's 28).
    private static let questionLine: CGFloat = 28

    private var nameBox: some View {
        TextField("Name", text: $store.name, prompt: Text("Your name").foregroundStyle(Hue.bigArtHint))
            .textContentType(.name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit(submit)
            .focused($typing)
            .appleFont(24)
            .foregroundStyle(Hue.ink)
            .tint(Hue.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            // 40 pt, growing with large text so its words aren't cut.
            .frame(width: ClubhouseStep.nameBoxWidth)
            .frame(minHeight: ClubhouseStep.nameBoxHeight)
            .background(Hue.onboardingCream, in: RoundedRectangle(cornerRadius: Radius.nameBox, style: .continuous))
            // The whole box takes the tap.
            .contentShape(Rectangle())
            .onTapGesture { typing = true }
            .accessibilityLabel("Name")
    }
}

/// "Add a photo?" over the squircle, which sits midway between the question and the Next pill.
struct OnboardingPhotoStep: View {
    @Bindable var store: OnboardingStore
    @AccessibilityFocusState.Binding var headingFocused: Bool
    /// What it keeps clear over the safe area's bottom: the Next pill in its spot (`OnboardingFlow`).
    let bottomClear: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            OnboardingClubhouseQuestion(words: OnboardingStep.photo.question, focused: $headingFocused)
            Spacer(minLength: 16)
            OnboardingProfilePhoto(store: store)
            Spacer(minLength: 16)
        }
        .padding(.top, ClubhouseStep.questionTop)
        .padding(.bottom, bottomClear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// Clubhouse's 158 pt squircle (measured, `references/profile-clubhouse/SPEC.md`): cream with a 1 pt ring and
/// a photo glyph while empty, a spinner while a picked photo loads (an iCloud one can take a while), then the
/// photo filling it. A tap opens Apple's photo picker, or asks library or camera when the phone has one, and
/// the photo goes through Adjust's circle before it lands.
struct OnboardingProfilePhoto: View {
    @Bindable var store: OnboardingStore

    @State private var asking = false
    @State private var library = false
    @State private var camera = false
    @State private var pick: PhotosPickerItem?
    /// A picked photo is on its way in, from the library's pick to Adjust.
    @State private var loading = false
    /// A photo just picked or taken, in Adjust's circle before it lands (backlog 32).
    @State private var adjusting: UIImage?
    /// The camera's photo, held until the camera has gone so Adjust can come up.
    @State private var taken: UIImage?

    static let side: CGFloat = 158
    private static let shape = RoundedRectangle(cornerRadius: Radius.photoSquircle, style: .continuous)
    private static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Button {
            Haptics.light()
            if Self.hasCamera { asking = true } else { library = true }
        } label: { squircle }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(store.photo == nil ? "Add a photo" : "Change photo")
        .confirmationDialog("Add a profile picture", isPresented: $asking, titleVisibility: .hidden) {
            Button("Choose from library") { library = true }
            Button("Take photo") { camera = true }
        }
        .photosPicker(isPresented: $library, selection: $pick, matching: .images, photoLibrary: .shared())
        .fullScreenCover(isPresented: $camera, onDismiss: {
            guard let shot = taken else { return }
            taken = nil
            Task { adjusting = await PhotoCrop.shrunk(shot) }
        }) {
            CameraPicker { taken = $0 }.ignoresSafeArea()
        }
        .photoAdjust($adjusting, shape: .circle) { use($0) }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            loading = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    adjusting = await PhotoCrop.shrunk(image)
                }
                pick = nil
                loading = false
            }
        }
    }

    private func use(_ image: UIImage) {
        guard let jpeg = ProfileModel.avatarJPEG(image) else { return }
        Haptics.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.photo = jpeg }
    }

    private var squircle: some View {
        ZStack {
            Self.shape.fill(Hue.onboardingCream)
            Self.shape.strokeBorder(Hue.onboardingCreamRing, lineWidth: 1)
            if let picked = store.photo.flatMap(UIImage.init(data:)) {
                Image(uiImage: picked)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(Self.shape)
                    .transition(.opacity)
            } else if loading {
                ProgressView().tint(Hue.ink)
            } else {
                Image(systemName: "photo")
                    .font(.glyph(50, weight: .semibold))
                    .foregroundStyle(Hue.ink)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .contentShape(Self.shape)
    }
}

/// Apple's camera, front-facing for a profile picture, handing back the photo taken.
private struct CameraPicker: UIViewControllerRepresentable {
    let taken: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.taken(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
