//
//  StreakHeroCard.swift
//  Block Party — the "Current Streak" hero for the Upcoming "Insights" face.
//
//  Fixed placeholder content ("4 Days") on the monochrome ink hero ground.
//  Real streak data is wired in a follow-up.
//

import SwiftUI

struct StreakHeroCard: View {
    var title: String = "Current Streak"
    var value: String = "4"
    var unit: String = "Days"
    var subtitle: String = "Your journaling streak started on Sunday."

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

            Text(value)
                .font(.system(size: 112, weight: .bold))
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .foregroundStyle(InsightsPalette.onDark)

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(InsightsPalette.onDark)
                    .padding(.top, -8)
            }

            Spacer(minLength: 0)

            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(InsightsPalette.onDarkMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var header: some View {
        ZStack {
            Text(title)
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

    private var background: some View {
        Hue.ink
            .clipShape(RoundedRectangle(cornerRadius: InsightsPalette.cardRadius, style: .continuous))
    }
}

#Preview {
    StreakHeroCard()
        .padding()
        .background(InsightsPalette.canvas)
}
