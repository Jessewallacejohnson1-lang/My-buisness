//
//  ShareRevealView.swift
//  Hygge — the share reveal UI (scrim + preview card + target sheet).
//

import SwiftUI

struct ShareRevealView: View {
    @ObservedObject private var center = ShareCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardScale: CGFloat {
        if reduceMotion { return center.revealed ? 1 : 1 }   // no scale under Reduce Motion
        return center.revealed ? 1.0 : 0.32
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(center.revealed ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { center.dismiss() }
                .animation(.easeOut(duration: 0.28), value: center.revealed)

            if let payload = center.payload {
                VStack {
                    Spacer(minLength: 0)
                    payload.preview
                        .scaleEffect(cardScale, anchor: .center)
                        .opacity(center.revealed ? 1 : 0)
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)   // taps fall through to the scrim (dismiss)
            }
        }
    }
}
