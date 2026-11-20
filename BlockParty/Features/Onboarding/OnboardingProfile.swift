//
//  OnboardingProfile.swift
//  Block Party — onboarding's Profile step (BP app onboarding 35) in the Big art look (onboarding 43,
//  mock v2 "Profile"): on its sand colour, the 124 pt photo with its glass badge is the step's art,
//  "Your Profile" and its line centred under it, then the Name and Bio boxes, white with a soft edge.
//  With the keyboard up the column rides up 120 pt and the photo fades (onboarding 46).
//  It took the place of the Name and Photo steps. The answers live in `OnboardingStore`;
//  `OnboardingFlow` owns the backdrop, the back arrow, the dashes and Save Profile.
//

import SwiftUI
import PhotosUI

struct OnboardingProfile: View {
    @Bindable var store: OnboardingStore
    @AccessibilityFocusState.Binding var headingFocused: Bool
    /// What the column keeps clear at the bottom: Save Profile and its slot, or Save Profile over the keyboard.
    let bottomClear: CGFloat
    /// The keyboard is up: the column rides up `lift` and the photo fades (mock v2 `.lifts.up`).
    let keyboardUp: Bool

    /// How far the column rides up over the keyboard: the photo's row leaves under the top row, and the
    /// question sits just under the dashes with both boxes clear of Save Profile.
    static let lift: CGFloat = 120

    private enum Field: Hashable { case name, bio }
    @FocusState private var focus: Field?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The photo, the question and its line sit centred; the boxes stay full width.
                    OnboardingBigArt(question: OnboardingStep.profile.question,
                                     line: "So your neighbors know it's you.",
                                     focused: $headingFocused) {
                        OnboardingProfilePhoto(store: store, hidden: keyboardUp)
                    }
                    label("Name")
                    nameBox.id(Field.name)
                    label("Bio")
                    bioBox.id(Field.bio)
                }
                .padding(.horizontal, FollowGridMetric.gutter)
                // Less room at the top than the photo's row takes: the column sits that much higher, and
                // the scroll measures what is left, so a box still scrolls clear on a small phone.
                .padding(.top, BigArt.top - FollowGridMetric.scrollTop - (keyboardUp ? Self.lift : 0))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, bottomClear, for: .scrollContent)
            // Under the top row it goes, as every step's column does, into the step's colour.
            .padding(.top, FollowGridMetric.scrollTop)
            .overlay(alignment: .top) { OnboardingScrollEdge(color: Hue.bigArtProfile) }
            .ignoresSafeArea(.container, edges: .top)
            // The box being typed in clears Save Profile over the keyboard: once the keyboard is up
            // (the bottom it keeps clear changes then), and on a move from Name to Bio.
            .onChange(of: bottomClear) { reveal(proxy) }
            .onChange(of: focus) { reveal(proxy) }
        }
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        guard let focus else { return }
        withAnimation(Motion.sheet) { proxy.scrollTo(focus, anchor: .bottom) }
    }

    /// The small grey word over a box (mock v2 `.flabel`), 24 pt under what's above it and 6 pt above the
    /// box. VoiceOver hears it as the box's name.
    private func label(_ words: String) -> some View {
        OnboardingFieldLabel(words, color: Hue.bigArtWords)
            .padding(.top, 24)
            .accessibilityHidden(true)
    }

    private var nameBox: some View {
        TextField("Name", text: $store.name, prompt: Text("What Mom calls you").foregroundStyle(Hue.bigArtHint))
            .textContentType(.name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focus = .bio }
            .focused($focus, equals: .name)
            .profileBox(size: 17, minHeight: OnboardingFieldBox.height, top: 12)
            .onTapGesture { focus = .name }
            .accessibilityLabel("Name")
    }

    /// Grows with what's typed; Return closes the keyboard rather than starting a new line. Nextdoor's
    /// 150 letters, as Edit profile's bio, which this is.
    private static let bioHint = "A little about you. Optional."

    private var bioBox: some View {
        // The hint drawn as words of its own, so it wraps at any text size (a prompt stops at the
        // box's least lines) and holds the box's height while typing starts.
        ZStack(alignment: .topLeading) {
            Text(Self.bioHint)
                .foregroundStyle(Hue.bigArtHint)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(store.bio.isEmpty ? 1 : 0)
                .accessibilityHidden(true)
            // No title of its own: the words above stand in for the prompt.
            TextField("", text: $store.bio, axis: .vertical)
                .lineLimit(1...8)
                .submitLabel(.done)
                .focused($focus, equals: .bio)
                .accessibilityLabel("Bio")
                .accessibilityHint(Self.bioHint)
        }
        .profileBox(size: 15, minHeight: 58, top: 9)
        .onTapGesture { focus = .bio }
        .onChange(of: store.bio) { _, typed in
            if typed.contains("\n") {
                store.bio = typed.replacingOccurrences(of: "\n", with: "")
                focus = nil
            } else if ProfileModel.bioLength(typed) > ProfileModel.bioLimit {
                store.bio = ProfileModel.clampBio(typed)
            }
        }
    }
}

private extension View {
    /// The Big art look's box (mock v2 `.field`, `.field.tall`): white with a soft edge, the words 16 pt
    /// in, Name's at 17 pt and Bio's at 15. No line round it while typing. Grows with Dynamic Type.
    func profileBox(size: CGFloat, minHeight: CGFloat, top: CGFloat) -> some View {
        font(.apple(size))
            .foregroundStyle(Hue.ink)
            .tint(Hue.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, top)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .bigArtBox()
            // The whole box takes the tap.
            .contentShape(Rectangle())
    }
}

/// The 124 pt photo, the step's art (mock v2 `.pic .avatar`): empty, Instagram's blank picture (onboarding
/// 46); picked, the photo. The 38 pt Liquid Glass badge (Luma's photo-plus icon) sits on its bottom right. A
/// tap opens Apple's photo picker, or asks library or camera when the phone has one.
struct OnboardingProfilePhoto: View {
    @Bindable var store: OnboardingStore
    /// Faded out, its badge gone, while the keyboard is up (onboarding 46).
    var hidden = false

    @State private var asking = false
    @State private var library = false
    @State private var camera = false
    @State private var pick: PhotosPickerItem?
    /// A photo just picked or taken, in Adjust's circle before it lands (backlog 32).
    @State private var adjusting: UIImage?
    /// The camera's photo, held until the camera has gone so Adjust can come up.
    @State private var taken: UIImage?

    static let side: CGFloat = BigArt.art
    private static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Button {
            Haptics.light()
            if Self.hasCamera { asking = true } else { library = true }
        } label: { circle }
        .buttonStyle(.press(.squish))
        .allowsHitTesting(!hidden)
        .accessibilityHidden(hidden)
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
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    adjusting = await PhotoCrop.shrunk(image)
                }
                pick = nil
            }
        }
    }

    private func use(_ image: UIImage) {
        guard let jpeg = ProfileModel.avatarJPEG(image) else { return }
        Haptics.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.photo = jpeg }
    }

    private var circle: some View {
        // `Avatar` draws both: the picked photo, or the blank picture until there is one.
        Avatar(nil, size: Self.side, picked: store.photo.flatMap(UIImage.init(data:)))
            .shadow(color: Hue.ink.opacity(0.16), radius: 12, y: 10)
            .opacity(hidden ? 0 : 1)
            .overlay(alignment: .bottomTrailing) {
                // Glass can't be dimmed (docs/rules/swift-traps.md), so the badge leaves with the photo.
                if !hidden { badge.transition(.opacity) }
            }
            // The mock's 0.2 s fade, whatever moves the column.
            .animation(.easeOut(duration: 0.2), value: hidden)
            .contentShape(Circle())
    }

    /// Apple's Liquid Glass, as the tab bar's (Jesse, 2026-11-10). Light scheme so it doesn't follow dark
    /// mode; over a dark photo the glass still takes the photo's tone.
    private var badge: some View {
        Image(systemName: "photo.badge.plus")
            .font(.glyph(19, weight: .regular))
            .foregroundStyle(Hue.ink)
            .frame(width: 38, height: 38)
            .glassEffect(.regular.interactive(), in: Circle())
            .environment(\.colorScheme, .light)
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
