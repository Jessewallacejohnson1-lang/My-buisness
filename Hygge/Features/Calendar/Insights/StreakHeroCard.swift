//
//  StreakHeroCard.swift
//  Hygge — the "Current Streak" hero for the Upcoming "Insights" face.
//
//  Pixel-faithful FIRST pass: fixed placeholder content ("4 Days"), matched to
//  the reference recording. Real streak data is wired in a follow-up. The dark
//  indigo→plum ground with soft translucent 3D blobs mirrors the reference's
//  abstract, glossy backdrop.
//

import SwiftUI

struct StreakHeroCard: View {
    private let cardHeight: CGFloat = 218

    var body: some View {
        ZStack {
            background
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: InsightsPalette.cardRadius, style: .continuous))
        .insightsCardShadow()
    }

    // MARK: - Foreground content

    private var content: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            Text("4")
                .font(.system(size: 112, weight: .bold))
                .foregroundStyle(InsightsPalette.onDark)

            Text("Days")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(InsightsPalette.onDark)
                .padding(.top, -8)

            Spacer(minLength: 0)

            Text("Your journaling streak started on Sunday.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(InsightsPalette.onDarkMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var header: some View {
        ZStack {
            Text("Current Streak")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(InsightsPalette.onDark)

            HStack {
                Spacer()
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(InsightsPalette.onDark)
                    )
            }
        }
    }

    // MARK: - 3D abstract blob background

    private var background: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Predominantly VERTICAL dark-indigo → plum ground (three stops
                // so the top stays near-black indigo like the reference).
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x241F39), location: 0.0),
                        .init(color: Color(hex: 0x462C50), location: 0.55),
                        .init(color: InsightsPalette.streakBottom, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Periwinkle-blue folded shape, center-left — the reference's most
                // visible blob; everything else stays muted so the dark plum
                // ground reads through (the reference is NOT a pink card).
                blob(InsightsPalette.blobBlue, size: 262, opacity: 0.80)
                    .position(x: w * 0.28, y: h * 0.60)

                // Muted coral ribbon, lower-right (kept low so it doesn't glow pink).
                blob(InsightsPalette.blobCoral, size: 172, opacity: 0.34)
                    .position(x: w * 0.83, y: h * 0.82)

                // Faint coral accent, upper area.
                blob(InsightsPalette.blobCoral, size: 120, opacity: 0.28)
                    .position(x: w * 0.24, y: h * 0.20)
            }
            .frame(width: w, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: InsightsPalette.cardRadius, style: .continuous))
    }

    private func blob(_ color: Color, size: CGFloat, opacity: Double) -> some View {
        Ellipse()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: 42)
    }
}

#Preview {
    StreakHeroCard()
        .padding()
        .background(InsightsPalette.canvas)
}
