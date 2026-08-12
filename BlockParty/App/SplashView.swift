//
//  SplashView.swift
//  Block Party — the launch splash.
//
//  A full-bleed ink field with the exact app mark and product name. Shown while the
//  app boots (RootView) and mirrored by the app's other brand surfaces.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Hue.ink
            GeometryReader { geo in
                VStack(spacing: 18) {
                    BlockPartyMark(side: 160)
                    Text("Block Party")
                        .font(.logo(34))
                        .foregroundStyle(.white)
                }
                    .fixedSize()
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
