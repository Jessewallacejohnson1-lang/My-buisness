//
//  BPCardQuestionScreens.swift
//  S17 / S18 — question 5, cards. S19 — question 6, cards.
//
//  Same scaffold as the row questions, with `BPCard` instead of `BPRow`.
//
//  S17/S18 is one screen in two states: on pick, the bubble reacts differently depending
//  on WHICH card was chosen ("Welcome to the founding class." vs "No pressure — the
//  party's not going anywhere."), which is why the reaction reads off the answer rather
//  than a plain "something is selected" flag.
//
//  Founding membership is a FREE badge tier. There is no payment anywhere in this flow
//  and no price copy — the reference's equivalent screen sells a subscription, and that
//  is one of the places this clone deliberately diverges.
//

import SwiftUI

// MARK: - S17 / S18 — founding member

struct BPFoundingScreen: View {
    @ObservedObject var answers: BPAnswers
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        BPQuestionScaffold(
            step: step,
            prompt: prompt,
            canContinue: answers.foundingMember != nil,
            onBack: onBack,
            onContinue: onContinue
        ) {
            BPCard(title: "Founding Member",
                   subtitle: "Founding badge on your profile, first to post, name on the founders wall",
                   recommended: true,
                   selected: answers.foundingMember == true) {
                pick(true)
            }
            BPCard(title: "Just looking around",
                   subtitle: "Browse everything, join anytime",
                   selected: answers.foundingMember == false) {
                pick(false)
            }
        }
    }

    private var prompt: AttributedString {
        switch answers.foundingMember {
        case .some(true):  return BPCopy.plain("Welcome to the founding class.")
        case .some(false): return BPCopy.plain("No pressure — the party's not going anywhere.")
        case nil:          return BPCopy.plain("How do you want to get started?")
        }
    }

    private func pick(_ founding: Bool) {
        withAnimation(BP.Motion.bubbleSwap) { answers.foundingMember = founding }
    }
}

// MARK: - S19 — where to start

struct BPLandingScreen: View {
    @ObservedObject var answers: BPAnswers
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    /// Ids persist as `profile.landing_choice` and drive the post-onboarding tab.
    ///
    /// GATE DECISION (Jesse, 2026-07-24): "This week in St. Joe" lands on the **Today**
    /// tab. There is no "This week" tab — the tab enum is home ("Today") / activities /
    /// calendar / map — and the Today feed is the app's front page and its
    /// what's-happening surface, which matches the card's subtitle.
    static let week = "this_week"
    static let map = "the_map"

    var body: some View {
        BPQuestionScaffold(
            step: step,
            prompt: BPCopy.plain("Where do you want to start?"),
            canContinue: answers.landingChoice != nil,
            onBack: onBack,
            onContinue: onContinue
        ) {
            BPCard(title: "This week in St. Joe",
                   subtitle: "Jump straight into what's happening",
                   icon: .calendar,
                   recommended: true,
                   selected: answers.landingChoice == Self.week) {
                answers.landingChoice = Self.week
            }
            BPCard(title: "The map",
                   subtitle: "Explore town first",
                   icon: .map,
                   selected: answers.landingChoice == Self.map) {
                answers.landingChoice = Self.map
            }
        }
    }
}
