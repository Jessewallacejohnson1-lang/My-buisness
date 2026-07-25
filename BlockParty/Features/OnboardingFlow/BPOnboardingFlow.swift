//
//  BPOnboardingFlow.swift
//  Block Party — the 20-screen onboarding container.
//
//  Owns the step machine, the horizontal push transitions, and the progress value.
//
//  The spec numbers 20 screens, but three of them are one screen in two states
//  (S05/S06 unselected→selected, S09/S10, S17/S18), so there are 17 navigable steps.
//  `BPStep.refID` maps each back to its reference frame(s) so the verification loop and
//  the debug flags can talk in the spec's numbering.
//
//  Progress bar runs from `.connection` (S05, where the spec says it debuts) through
//  `.finale`, linearly. It is deliberately NOT derived from `BPStep.allCases` — the
//  first four steps carry no bar, and including them would make it start part-filled.
//
//  Headless: `-bp-flow` enters the flow; `-bp-step <name>` jumps straight to a step
//  (names are the enum cases, e.g. `-bp-step connection`). `-bp-answered` prefills the
//  answers so selected states can be screenshotted without driving taps — this sim
//  setup has no gesture automation, so every state needs a flag to reach it.
//

import SwiftUI

enum BPStep: Int, CaseIterable {
    case splash, welcome, hello, sixQuestions
    case connection, buildingBlock, townLevel, motivations
    case keepInLoop, cadence, happenings, notifications, location
    case promises, founding, landing, finale

    /// The reference frame(s) this step is verified against.
    var refID: String {
        switch self {
        case .splash:        return "S01"
        case .welcome:       return "S02"
        case .hello:         return "S03"
        case .sixQuestions:  return "S04"
        case .connection:    return "S05/S06"
        case .buildingBlock: return "S07"
        case .townLevel:     return "S08"
        case .motivations:   return "S09/S10"
        case .keepInLoop:    return "S11"
        case .cadence:       return "S12"
        case .happenings:    return "S13"
        case .notifications: return "S14"
        case .location:      return "S15"
        case .promises:      return "S16"
        case .founding:      return "S17/S18"
        case .landing:       return "S19"
        case .finale:        return "S20"
        }
    }

    /// The progress bar debuts on S05 and runs to the end.
    static let firstWithProgress = BPStep.connection

    var showsProgress: Bool { rawValue >= Self.firstWithProgress.rawValue }

    /// A back arrow appears from S03 on; the splash and welcome have nowhere to go back to.
    var showsBack: Bool { rawValue >= BPStep.hello.rawValue }

    var progress: Double {
        guard showsProgress else { return 0 }
        let first = Self.firstWithProgress.rawValue
        let last = BPStep.finale.rawValue
        return Double(rawValue - first + 1) / Double(last - first + 1)
    }
}

struct BPOnboardingFlow: View {
    /// Called when the user finishes S20. Phase 3 wires this to sign-up + routing.
    var onFinish: (() -> Void)?

    @StateObject private var answers = BPAnswers()
    @State private var step: BPStep = BPOnboardingFlow.initialStep()
    /// Drives the push direction so back slides the opposite way to forward.
    @State private var goingBack = false

    var body: some View {
        ZStack {
            BP.paper.ignoresSafeArea()

            Group {
                switch step {
                case .splash:
                    BPSplashScreen { advance() }
                case .welcome:
                    BPWelcomeScreen(onStart: { advance() }, onSignIn: { /* Phase 3 */ })
                case .hello:
                    BPTalkingScreen(line: BPCopy.plain("Hey! Welcome to the party. \u{1F44B}"),
                                    step: step, onBack: back, onContinue: advance)
                case .sixQuestions:
                    BPTalkingScreen(line: BPCopy.emphasised("Just ", "6 quick questions", " and you're in."),
                                    step: step, onBack: back, onContinue: advance)
                case .connection:
                    BPConnectionScreen(answers: answers, step: step, onBack: back, onContinue: advance)
                case .buildingBlock:
                    BPBuildingBlockScreen(step: step, onBack: back, onContinue: advance)
                case .townLevel:
                    BPTownLevelScreen(answers: answers, step: step, onBack: back, onContinue: advance)
                default:
                    BPUnbuiltScreen(step: step, onBack: back, onContinue: advance)
                }
            }
            .transition(push)
            .id(step)
        }
        .environmentObject(answers)
    }

    // MARK: - Navigation

    private var push: AnyTransition {
        let inEdge: Edge = goingBack ? .leading : .trailing
        let outEdge: Edge = goingBack ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: inEdge), removal: .move(edge: outEdge))
    }

    private func advance() {
        guard let next = BPStep(rawValue: step.rawValue + 1) else { onFinish?(); return }
        goingBack = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { step = next }
        answers.resumeIndex = max(answers.resumeIndex, next.rawValue)
    }

    private func back() {
        guard let prev = BPStep(rawValue: step.rawValue - 1) else { return }
        goingBack = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { step = prev }
    }

    // MARK: - Debug entry

    private static func initialStep() -> BPStep {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-bp-step"), i + 1 < args.count {
            let name = args[i + 1]
            if let match = BPStep.allCases.first(where: { "\($0)" == name }) { return match }
        }
        #endif
        return .splash
    }
}

// MARK: - Shared screen chrome

/// The top bar every question/talking screen shares: back arrow, and the progress bar
/// once it has debuted. Keeping it here means the bar's position can never drift
/// between screens — the reference has it pinned identically on all of them.
struct BPScreenTop: View {
    let step: BPStep
    let onBack: () -> Void

    var body: some View {
        BPTopBar(progress: step.showsProgress ? step.progress : nil,
                 onBack: step.showsBack ? onBack : nil)
    }
}

/// Placeholder for the steps built in Phases 2–3, so the flow stays navigable and the
/// progress bar's advance can be verified end to end before those screens exist.
struct BPUnbuiltScreen: View {
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BPScreenTop(step: step, onBack: onBack)
            Spacer()
            VStack(spacing: 8) {
                Text(step.refID)
                    .font(.display(34))
                    .foregroundStyle(BP.ink)
                Text("not built yet")
                    .font(.mono(12))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(BP.gray)
            }
            Spacer()
            BPButton(title: "Continue", action: onContinue)
                .padding(.horizontal, BP.Metric.pageMargin)
                .padding(.bottom, 24)
        }
        .background(BP.paper.ignoresSafeArea())
    }
}
