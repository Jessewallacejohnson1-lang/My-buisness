//
//  OnboardingView.swift
//  Hygge — first-run wizard: Welcome → Name → Interests → Avatar → Map finale.
//  Collects name + interests + avatar, mirrors them to Supabase (best-effort,
//  non-blocking) and to UserDefaults (synchronous matching). Mirrors the Expo
//  onboarding, extended for community-profile capture.
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    enum Step { case hello, name, interests, avatar, map }
    @State private var step: Step = OnboardingView.initialStep()

    @State private var name: String = OnboardingView.initialName()
    @State private var selected: Set<String> = OnboardingView.initialInterests()
    @State private var avatar: UIImage?

    private let profiles = ProfileAPI(auth: .shared)
    private let storage = Storage(auth: .shared)

    var body: some View {
        ZStack {
            Hue.canvas.ignoresSafeArea()
            switch step {
            case .hello:
                hello.transition(.opacity)
            case .name:
                NameStepView(name: $name, onBack: { go(.hello) }, onContinue: { go(.interests) })
                    .transition(stepTransition)
            case .interests:
                InterestPickerView(selected: $selected, name: name,
                                   onBack: { go(.name) }, onContinue: { go(.avatar) })
                    .transition(stepTransition)
            case .avatar:
                AvatarStepView(image: $avatar, name: name,
                               onBack: { go(.interests) },
                               onContinue: { finishData(); go(.map) })
                    .transition(stepTransition)
            case .map:
                MapIntroView { finish() }.transition(.opacity)
            }
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity)
    }

    private func go(_ next: Step) {
        withAnimation(.easeInOut(duration: 0.4)) { step = next }
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Welcome to Hygge")
                .font(.display(38)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("One calm place for everything happening in St. Joseph — a daily look at town, a shared calendar anyone can add to, and small nudges to get out and meet your neighbors.")
                .font(.sans(16)).foregroundStyle(Hue.ink2).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: { go(.name) }) {
                Text("Get started")
                    .font(.sansSemibold(16)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Hue.accent, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: { finishData(); finish() }) {
                Text("Skip for now").font(.sans(14)).foregroundStyle(Hue.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    /// Commit locally at once (matching needs it synchronously), then best-effort
    /// mirror to Supabase — including the avatar upload. Never blocks the UI. The
    /// Task inherits the main actor (module default), so no Sendable crossing.
    private func finishData() {
        let ids = Array(selected)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Interests.set(ids)
        Interests.displayName = trimmed.isEmpty ? nil : trimmed
        let img = avatar
        Task {
            var avatarUrl: String?
            if let img, let data = img.jpegData(compressionQuality: 0.85),
               let uid = AuthStore.shared.userId {
                avatarUrl = await storage.uploadAvatar(data, userId: uid)
            }
            try? await profiles.upsert(displayName: trimmed.isEmpty ? nil : trimmed,
                                       avatarUrl: avatarUrl, interests: ids, onboarded: true)
        }
    }

    private func finish() {
        if let uid = AuthStore.shared.userId { Interests.setOnboarded(uid: uid) }
        onDone()
    }
}

// MARK: - DEBUG launch state (headless screenshot verification)
extension OnboardingView {
    static func initialStep() -> Step {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-onboarding-step"), i + 1 < args.count {
            switch args[i + 1] {
            case "name":      return .name
            case "interests": return .interests
            case "avatar":    return .avatar
            default:          break
            }
        }
        #endif
        return .hello
    }

    static func initialName() -> String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding-filled") { return "Alex" }
        #endif
        return Interests.displayName ?? ""
    }

    static func initialInterests() -> Set<String> {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding-filled") {
            return ["trails_hiking", "coffee", "live_music", "farmers_market", "faith"]
        }
        #endif
        return Set(Interests.get())
    }
}
