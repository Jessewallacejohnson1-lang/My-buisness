//
//  BPWelcomeScreen.swift
//  S02 — welcome.
//
//  Mark centred upper-middle, lowercase wordmark under it, grey tagline, and a
//  bottom-pinned button pair.
//
//  GATE DECISION (Jesse, 2026-07-24): the flow runs PRE-AUTH, which fixes what these two
//  buttons do — the same thing they do in the reference. GET STARTED begins the
//  questions with no account; I ALREADY HAVE AN ACCOUNT jumps to sign-in. Answers buffer
//  locally and flush on first sign-in.
//
//  `onSignIn` is wired through but unbound until Phase 3, where the signed-out branch in
//  `RootView.gate` lands. It is deliberately NOT a no-op button in the meantime — Phase 3
//  connects it to `LoginView`.
//

import SwiftUI

struct BPWelcomeScreen: View {
    let onStart: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                BPMark(side: 116)

                VStack(spacing: 8) {
                    Text("block party")
                        .font(.logo(40))
                        .tracking(0.5)
                        .foregroundStyle(BP.ink)

                    Text("Join the neighborhood.")
                        .font(.sans(16))
                        .foregroundStyle(BP.gray)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                BPButton(title: "Get started", action: onStart)
                BPButton(title: "I already have an account", variant: .secondary, action: onSignIn)
            }
            .padding(.horizontal, BP.Metric.pageMargin)
            .padding(.bottom, BPLayout.buttonBottomGap)
        }
        .background(BP.paper.ignoresSafeArea())
    }
}
