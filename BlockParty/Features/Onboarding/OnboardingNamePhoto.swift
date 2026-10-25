//
//  OnboardingNamePhoto.swift
//  Block Party — onboarding steps 4 and 5 (BP app docs/plans/onboarding, ticket 18), drawn
//  under the question: Hinge's underlined name fields and Instagram's empty photo circle.
//  The answers live in `OnboardingStore`; `OnboardingFlow` owns the Next bar and Skip.
//

import SwiftUI
import PhotosUI

/// "What's your name?": first name, then "Last name", each on a 1.5 pt underline (ink once
/// typed in, control grey while empty), 48 pt under the question, the keyboard up from the
/// start. Return goes to the last name, then on when a first name is in.
struct OnboardingNameFields: View {
    @Bindable var store: OnboardingStore
    let done: () -> Void

    private enum Field { case first, last }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field("First name", text: $store.firstName, .first)
                .textContentType(.givenName)
                .submitLabel(.next)
                .padding(.top, 48)
            field("Last name", text: $store.lastName, .last)
                .textContentType(.familyName)
                .submitLabel(.done)
                .padding(.top, 24)
            Text("So friends and neighbors know it's you.")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, 12)
        }
        .onSubmit {
            if focus == .first { focus = .last } else if store.displayName != nil { done() }
        }
        .onAppear { focus = store.firstName.isEmpty || store.displayName == nil ? .first : .last }
    }

    private func field(_ placeholder: String, text: Binding<String>, _ which: Field) -> some View {
        let empty = text.wrappedValue.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: text,
                      prompt: Text(placeholder).foregroundStyle(Hue.inkSecondary))
                .font(empty ? .sans(28) : .sansMedium(28))
                .foregroundStyle(Hue.ink)
                .tint(Hue.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focus, equals: which)
            Rectangle()
                .fill(empty ? Hue.control : Hue.ink)
                .frame(height: 1.5)
        }
    }
}

/// "Add a profile picture": a 176 pt white circle with a dashed control-grey rim and a grey
/// figure, 48 pt under the line below the question. A tap opens Apple's photo picker, or
/// asks library or camera when the phone has one; the picked photo fills the circle.
struct OnboardingPhotoCircle: View {
    @Bindable var store: OnboardingStore

    @State private var asking = false
    @State private var library = false
    @State private var camera = false
    @State private var pick: PhotosPickerItem?

    private static let side: CGFloat = 176
    private static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Button {
            Haptics.light()
            if Self.hasCamera { asking = true } else { library = true }
        } label: { circle }
        .buttonStyle(OnboardingPress(scale: 0.95))
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
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
            if let data = store.photo, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            } else {
                Hue.surface
                OnboardingFigure()
                    .fill(Hue.edge)
                    .frame(width: 150, height: 150)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(Circle())
        .overlay {
            if store.photo == nil {
                Circle().strokeBorder(Hue.control, style: StrokeStyle(lineWidth: 1.5, dash: [4.5, 4.5]))
            }
        }
        .contentShape(Circle())
    }
}

/// The mock's grey figure in a 100-unit box: a head of radius 17 at (50, 38) over shoulders
/// that curve from (18, 86) to (82, 86).
private struct OnboardingFigure: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path(ellipseIn: CGRect(x: rect.minX + 33 * k, y: rect.minY + 21 * k, width: 34 * k, height: 34 * k))
        path.move(to: p(18, 86))
        path.addCurve(to: p(50, 59), control1: p(22, 68), control2: p(35, 59))
        path.addCurve(to: p(82, 86), control1: p(65, 59), control2: p(78, 68))
        path.closeSubpath()
        return path
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
