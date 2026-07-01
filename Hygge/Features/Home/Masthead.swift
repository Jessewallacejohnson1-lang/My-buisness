//
//  Masthead.swift
//  Hygge — Home header: wordmark, today's date, glass action circles.
//

import SwiftUI

struct Masthead: View {
    var name: String?

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
                glassCircle("magnifyingglass")
                glassCircle("person")
            }
            .padding(.top, 4)
        }
    }

    private func glassCircle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Hue.ink)
            .frame(width: 38, height: 38)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
    }
}
