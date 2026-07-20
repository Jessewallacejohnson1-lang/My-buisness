//
//  ShareRevealView.swift
//  Block Party — the share reveal UI (scrim + preview card + target sheet).
//

import SwiftUI

struct ShareRevealView: View {
    @ObservedObject private var center = ShareCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardScale: CGFloat {
        if reduceMotion { return 1 }   // no scale under Reduce Motion
        return center.revealed ? 1.0 : 0.32
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .opacity(center.revealed ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { center.dismiss() }
                .animation(.easeOut(duration: 0.40), value: center.revealed)

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

            if let payload = center.payload {
                bottomSheet(payload)
                    .offset(y: center.revealed ? 0 : 360)
                    .opacity(center.revealed ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private func bottomSheet(_ payload: SharePayload) -> some View {
        VStack(spacing: 16) {
            HStack {
                Button { center.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Hue.ink3)
                }
                .buttonStyle(PressableStyle(scale: 0.9, haptic: true))
                Spacer()
                Text(payload.title)
                    .font(.mono(11)).tracking(1.6)
                    .foregroundStyle(Hue.ink3)
                Spacer()
                Color.clear.frame(width: 15, height: 15)   // balances the X
            }

            ShareTargetRow(includesImage: payload.includesImage)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        // The paper is the BACKGROUND shape (not a clip on the whole view) with
        // ignoresSafeArea, so it bleeds flush to the physical bottom edge —
        // clip-then-ignore left a dim strip over the home indicator.
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Radius.xl,
                                   topTrailingRadius: Radius.xl,
                                   style: .continuous)
                .fill(Hue.paper)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
