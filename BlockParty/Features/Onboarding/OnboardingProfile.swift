//
//  OnboardingProfile.swift
//  Block Party — onboarding's Profile step (BP app onboarding 35), Luma's profile screen copied at
//  mock v8's measured points ("4 · Profile"): the plain grey band fading into the canvas with the
//  wordmark at its bottom right, the 80 pt photo with its camera badge, "Your Profile", and the Name
//  and Bio boxes. It took the place of the Name and Photo steps. The answers live in
//  `OnboardingStore`; `OnboardingFlow` owns the back arrow, the progress line and Save Profile.
//

import SwiftUI
import PhotosUI

struct OnboardingProfile: View {
    @Bindable var store: OnboardingStore
    @AccessibilityFocusState.Binding var headingFocused: Bool
    /// What the column keeps clear at the bottom: Save Profile and its slot, or Save Profile over the keyboard.
    let bottomClear: CGFloat

    private enum Field: Hashable { case name, bio }
    @FocusState private var focus: Field?

    /// The band's height and the photo's top, from the screen's top edge (mock v8 `.ffade`, `.screen.lp`).
    private static let band: CGFloat = 224
    private static let top: CGFloat = 155

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingProfilePhoto(store: store)
                    Text("Your Profile")
                        .appleFont(20, weight: .semibold)
                        .foregroundStyle(Hue.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                        .padding(.top, 19)
                    Text("Introduce yourself to others in your events.")
                        .font(.apple(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 11)
                    label("Name").padding(.top, 23)
                    nameBox.id(Field.name)
                    label("Bio").padding(.top, 25)
                    bioBox.id(Field.bio)
                }
                .padding(.horizontal, FollowGridMetric.gutter)
                .padding(.top, Self.top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .top) { band }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, bottomClear, for: .scrollContent)
            // The band runs under the back arrow and the progress line, to the screen's top edge.
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .top) { topCover }
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

    /// Luma's grey band, plain (no stars, Jesse 2026-11-09), fading into the canvas over 200 pt, with
    /// the BlockParty wordmark 24 pt tall at its bottom right.
    private var band: some View {
        LinearGradient(stops: [.init(color: Hue.profileBand, location: 0),
                               .init(color: Hue.onboardingCanvas, location: 200 / Self.band)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: Self.band)
            .overlay(alignment: .bottomTrailing) {
                BlockPartyWordmark(height: 24)
                    .foregroundStyle(Hue.ink)
                    .padding(.trailing, FollowGridMetric.gutter)
                    .padding(.bottom, 28)
            }
            .accessibilityHidden(true)
    }

    /// Where the column meets the top row once it scrolls (a large text size): the band's own top,
    /// pinned, fading out 16 pt under the progress line. At rest it lies exactly on the band.
    private var topCover: some View {
        band
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: FollowGridMetric.scrollTop / Self.band),
                                       .init(color: .clear, location: (FollowGridMetric.scrollTop + 16) / Self.band)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
    }

    /// The small grey word over a box (mock v8 `.ll`), 10 pt above it. VoiceOver hears it as the box's name.
    private func label(_ words: String) -> some View {
        Text(words)
            .font(.apple(12))
            .foregroundStyle(Hue.inkSecondary)
            .padding(.bottom, 10)
            .accessibilityHidden(true)
    }

    private var nameBox: some View {
        TextField("Name", text: $store.name, prompt: Text("Your Name").foregroundStyle(Hue.inkSecondary))
            .textContentType(.name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focus = .bio }
            .focused($focus, equals: .name)
            .profileBox(minHeight: 44, top: 11)
            .onTapGesture { focus = .name }
            .accessibilityLabel("Name")
    }

    /// Grows with what's typed; Return closes the keyboard rather than starting a new line. Nextdoor's
    /// 150 letters, as Edit profile's bio, which this is.
    private var bioBox: some View {
        // Luma's two-line prompt drawn as words of its own, so it wraps at any text size (a prompt
        // stops at the box's least lines) and holds the box's height while typing starts.
        ZStack(alignment: .topLeading) {
            Text("Share a little about your background and interests.")
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(store.bio.isEmpty ? 1 : 0)
                .accessibilityHidden(true)
            // No title of its own: the words above stand in for the prompt.
            TextField("", text: $store.bio, axis: .vertical)
                .lineLimit(1...8)
                .submitLabel(.done)
                .focused($focus, equals: .bio)
                .accessibilityLabel("Bio")
                .accessibilityHint("Share a little about your background and interests.")
        }
        .profileBox(minHeight: 58, top: 9)
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
    /// Luma's box (mock v8 `.lf`): a soft grey, 10 pt corners, the words at 17 pt, 16 pt in. No line
    /// round it while typing, as Luma's. Grows with Dynamic Type.
    func profileBox(minHeight: CGFloat, top: CGFloat) -> some View {
        font(.apple(17))
            .foregroundStyle(Hue.ink)
            .tint(Hue.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, top)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(Hue.profileField, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // The whole box takes the tap.
            .contentShape(Rectangle())
    }
}

/// The 80 pt photo (mock v8 `.avatar`): empty, a plain colour circle (Luma's face is their own
/// character); picked, the photo. The white camera badge sits on its bottom right. A tap opens Apple's
/// photo picker, or asks library or camera when the phone has one.
struct OnboardingProfilePhoto: View {
    @Bindable var store: OnboardingStore

    @State private var asking = false
    @State private var library = false
    @State private var camera = false
    @State private var pick: PhotosPickerItem?

    static let side: CGFloat = 80
    private static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Button {
            Haptics.light()
            if Self.hasCamera { asking = true } else { library = true }
        } label: { circle }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(store.photo == nil ? "Add a photo" : "Change photo")
        .confirmationDialog("Add a profile picture", isPresented: $asking, titleVisibility: .hidden) {
            Button("Choose from library") { library = true }
            Button("Take photo") { camera = true }
        }
        .photosPicker(isPresented: $library, selection: $pick, matching: .images, photoLibrary: .shared())
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { use($0) }.ignoresSafeArea()
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    use(image)
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
        ZStack {
            if let picked = store.photo.flatMap(UIImage.init(data:)) {
                Avatar(nil, size: Self.side, picked: picked)
            } else {
                blank
            }
        }
        .frame(width: Self.side, height: Self.side)
        .shadow(color: Hue.ink.opacity(0.16), radius: 12, y: 10)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.glyph(14, weight: .medium))
                .foregroundStyle(Hue.ink)
                .frame(width: 30, height: 30)
                .background(Hue.surface, in: Circle())
                .shadow(color: Hue.ink.opacity(0.14), radius: 4, y: 2)
        }
        .contentShape(Circle())
    }

    /// The mock's empty photo: mint to lilac, a green glow top right and a violet one bottom left.
    private var blank: some View {
        Circle()
            .fill(LinearGradient(colors: [Hue.profileBlankMint, Hue.profileBlankBlue, Hue.profileBlankLilac],
                                 startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)))
            .overlay(RadialGradient(colors: [Hue.profileBlankGreen, Hue.profileBlankGreen.opacity(0)],
                                    center: UnitPoint(x: 0.78, y: 0.18), startRadius: 0, endRadius: Self.side * 0.5))
            .overlay(RadialGradient(colors: [Hue.profileBlankViolet, Hue.profileBlankViolet.opacity(0)],
                                    center: UnitPoint(x: 0.22, y: 0.88), startRadius: 0, endRadius: Self.side * 0.55))
            .clipShape(Circle())
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
