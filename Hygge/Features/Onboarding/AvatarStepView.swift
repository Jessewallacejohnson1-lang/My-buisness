//
//  AvatarStepView.swift
//  Hygge — "Add a profile picture." Tap the circular well to pick from the
//  library; Skip is always allowed. Upload happens after this step (OnboardingView).
//

import SwiftUI
import PhotosUI

struct AvatarStepView: View {
    @Binding var image: UIImage?
    let name: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var pick: PhotosPickerItem?

    private var firstName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init) ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(index: 2, total: 3, onBack: onBack).padding(.top, 8)

            VStack(spacing: 8) {
                Text("Add a profile picture")
                    .font(.display(30))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(firstName.isEmpty ? "So neighbors know it's you." : "So neighbors know it's you, \(firstName).")
                    .font(.sans(16))
                    .foregroundStyle(Hue.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 36)

            Spacer()

            PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                well
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()

            ContinueButton(title: "Continue") {
                Haptics.selection(); onContinue()
            }
            // The photo is optional; a subtle skip reads calmer than a second
            // heavy button, and only shows until a photo is chosen.
            Button(action: { Haptics.selection(); onContinue() }) {
                Text(image == nil ? "I'll add one later" : " ")
                    .font(.sans(14)).foregroundStyle(Hue.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .opacity(image == nil ? 1 : 0)
            .allowsHitTesting(image == nil)
        }
        .padding(24)
        .background(Hue.canvas.ignoresSafeArea())
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { image = ui }
                }
            }
        }
    }

    private var well: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 176, height: 176)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .fill(Hue.paper)
                    .frame(width: 176, height: 176)
                    .overlay(Circle().stroke(Hue.hairline, style: StrokeStyle(lineWidth: 2, dash: [7, 6])))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 26)).foregroundStyle(Hue.accent)
                            Text("Add photo").font(.sansMedium(14)).foregroundStyle(Hue.ink3)
                        }
                    )
            }
        }
        .accessibilityLabel(image == nil ? "Add a profile picture" : "Change profile picture")
    }
}
