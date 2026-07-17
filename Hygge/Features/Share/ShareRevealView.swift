//
//  ShareRevealView.swift
//  Hygge — the share reveal UI (scrim + preview card + target sheet).
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
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black
                    .opacity(center.revealed ? 0.55 : 0)
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
                    bottomSheet(payload, safeBottom: geo.safeAreaInsets.bottom)
                        .offset(y: center.revealed ? 0 : 360)
                        .opacity(center.revealed ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The reveal lives in its OWN UIWindow, where a safe-area modifier buried
        // inside `.background(…)` doesn't reliably bleed the paper to the physical
        // edge — it sealed on some devices but left a scrim strip under the buttons on
        // others. So the whole overlay ignores the safe area (the sheet bottom-anchors
        // to the physical edge — the seal is now guaranteed by geometry, not by a
        // fragile modifier), and the sheet re-insets its own content by the real
        // bottom inset (read above) so the buttons still clear the home indicator.
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func bottomSheet(_ payload: SharePayload, safeBottom: CGFloat) -> some View {
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
        // Content sits above the home indicator; the paper (this view's background)
        // then fills the whole frame down to the physical bottom edge, sealing it —
        // no scrim strip peeks through beneath the buttons. `safeBottom` is the real
        // inset read from the enclosing GeometryReader.
        .padding(.bottom, 12 + safeBottom)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Radius.xl,
                                   topTrailingRadius: Radius.xl,
                                   style: .continuous)
                .fill(Hue.paper)
        )
    }
}
