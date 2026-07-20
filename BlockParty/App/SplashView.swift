//
//  SplashView.swift
//  Block Party — the launch splash.
//
//  A full-bleed ink field with the white "Block Party" wordmark centered — the same
//  ink + Jost lockup as the app icon and the brand badge. Shown while the
//  app boots (RootView) and mirrored by the launch screen so the hand-off is
//  seamless.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Hue.ink
            GeometryReader { geo in
                Text("Block Party")
                    .font(.logo(88))              // Jost SemiBold — large
                    .foregroundStyle(.white)
                    // Sit a touch below the lowest side button (volume-down, the one
                    // nearest the charging port) — upper-third, not dead-center.
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.34)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel("Block Party")
            }
        }
        .ignoresSafeArea()
    }
}

#Preview { SplashView() }
