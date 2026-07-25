//
//  OnboardingView.swift
//  Block Party — first-run wizard: Welcome → Name → Interests → Avatar → Map finale.
//  Collects name + interests + avatar, mirrors them to Supabase (best-effort,
//  non-blocking) and to UserDefaults (synchronous matching). Mirrors the Expo
//  onboarding, extended for community-profile capture.
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    /// TRIMMED to the two things the 20-screen pre-auth flow does NOT collect.
    ///
    /// Was `hello → name → interests → avatar → map`. The clone now owns the front door,
    /// so: `hello` is redundant (S03/S04 greet), `avatar` is dropped (Jesse, 2026-07-25 —
    /// `EditProfileView` still handles it later, and an empty avatar is a fine state), and
    /// `map` is redundant AND would fight S19, which now owns the landing-tab promise.
    ///
    /// Name and interests stay because they feed real features the clone never asks about:
    /// the greeting voice ("Evening on the block, Jesse") and interest matching. They keep
    /// the app's own visual language on purpose — the seam between the orange/teal clone
    /// and Block Party proper is sign-up, which is a natural narrative boundary.
    enum Step { case name, interests }
    @State private var step: Step = OnboardingView.initialStep()

    @State private var name: String = OnboardingView.initialName()
    @State private var selected: Set<String> = OnboardingView.initialInterests()
    private let profiles = ProfileAPI(auth: .shared)

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            switch step {
            case .name:
                // No back: nothing precedes this now. `onSkip` carries the escape hatch
                // that used to live on the removed `hello` step.
                NameStepView(name: $name,
                             onContinue: { go(.interests) },
                             onSkip: { finishData(); finish() })
                    .transition(stepTransition)
            case .interests:
                InterestPickerView(selected: $selected, name: name,
                                   onBack: { go(.name) },
                                   onContinue: { finishData(); finish() })
                    .transition(stepTransition)
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
            Text("Welcome to Block Party")
                .font(.display(38)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("See what's happening today, share events on the town calendar, and find your way around St. Joseph.")
                .font(.sans(16)).foregroundStyle(Hue.inkSecondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: { go(.name) }) {
                Text("Set up my profile")
                    .font(.sansSemibold(16)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Hue.ink, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: { finishData(); finish() }) {
                Text("Skip for now").font(.sans(14)).foregroundStyle(Hue.inkSecondary)
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
        Task {
            // avatarUrl stays nil: this step no longer collects one. `ProfileAPI.upsert`
            // is a full-row merge, so passing nil here CLEARS any existing avatar — which
            // is correct on first onboarding (there cannot be one yet) but would be wrong
            // if this were ever reused for an existing profile. Use `EditProfileView` for
            // that; it uploads before it upserts.
            try? await profiles.upsert(displayName: trimmed.isEmpty ? nil : trimmed,
                                       avatarUrl: nil, interests: ids, onboarded: true)
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
            default:          break
            }
        }
        #endif
        return .name
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
