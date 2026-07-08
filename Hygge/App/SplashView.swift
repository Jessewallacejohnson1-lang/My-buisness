//
//  SplashView.swift
//  Hygge — the launch splash.
//
//  A full-bleed coral field with the white "Hygge" wordmark centered — the same
//  coral + Atkinson lockup as the app icon and the brand badge. Shown while the
//  app boots (RootView) and mirrored by the launch screen so the hand-off is
//  seamless.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Hue.accent                            // coral #FF6B57
            GeometryReader { geo in
                Text("Hygge")
                    .font(.logo(88))              // Atkinson Hyperlegible Bold — large
                    .foregroundStyle(.white)
                    // Sit a touch below the lowest side button (volume-down, the one
                    // nearest the charging port) — upper-third, not dead-center.
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.34)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel("Hygge")
            }
        }
        .ignoresSafeArea()
    }
}

#Preview { SplashView() }
