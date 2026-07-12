//
//  ShareRevealView.swift
//  Hygge — the share reveal UI (scrim + preview card + target sheet).
//

import SwiftUI

struct ShareRevealView: View {
    @ObservedObject private var center = ShareCenter.shared

    var body: some View {
        ZStack {
            Color.black
                .opacity(center.revealed ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { center.dismiss() }
        }
        .animation(.easeOut(duration: 0.28), value: center.revealed)
    }
}
