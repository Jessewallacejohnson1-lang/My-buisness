//
//  Masthead.swift
//  Hygge — Home header: wordmark, today's date, glass action circles.
//

import SwiftUI

struct Masthead: View {
    var name: String?
    var onAdd: (() -> Void)?       // "+" button — like Instagram top-right
    var onProfile: (() -> Void)?   // person button → the community profile sheet

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hygge")
                    .font(.display(34))
                    .foregroundStyle(Hue.ink)
                HStack(spacing: 6) {
                    if let name, !name.isEmpty {
                        Text("Hi \(name)")
                            .font(.sansMedium(13))
                            .foregroundStyle(Hue.ink2)
                        Text("·").foregroundStyle(Hue.ink3)
                    }
                    Text(dateLine)
                        .font(.mono(13))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink2)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                // "+" composer — Instagram-style top-right
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Hue.paper)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Hue.moss700))
                            .shadow(color: Hue.moss700.opacity(0.35), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                glassCircle("magnifyingglass")
                glassCircle("person", action: onProfile)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func glassCircle(_ symbol: String, action: (() -> Void)? = nil) -> some View {
        let face = Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Hue.ink)
            .frame(width: 38, height: 38)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
        if let action {
            Button { Haptics.light(); action() } label: { face }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Your profile")
        } else {
            face
        }
    }
}
