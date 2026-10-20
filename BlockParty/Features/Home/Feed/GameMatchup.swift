//
//  GameMatchup.swift
//  Block Party — a game's picture on its Town card: the two teams' colors, logos and VS.
//
//  Drawn instead of a photo for a game between two teams (BP app docs/plans/game-card,
//  ticket 01; Jesse, 2026-10-20: "I want idea E", "keep names"; taste.md). X's and Apple
//  Sports' game headers: the left team's color to 40% of the width, the right team's from
//  60%, each logo on a white disc with the school's short name under it, VS between them.
//  The title, place line and day chip stay the card's own, over this.
//

import SwiftUI

struct GameMatchup: View {
    let game: Game

    /// The mock's Picked row, on its 370 pt card (BP app references/game-card/mock.html).
    enum Metric {
        /// The card's shape, fixed: a game has no photo to take one from.
        static let aspect: CGFloat = 5.0 / 4.0
        static let rowTop: CGFloat = 62
        static let disc: CGFloat = 84
        static let logo: CGFloat = 58
        static let column: CGFloat = 112
        static let gap: CGFloat = 22
        static let vsWidth: CGFloat = 50
        static let nameGap: CGFloat = 8
    }

    var body: some View {
        // One page that still rubber-bands, as a one-photo card does, so a sideways swipe moves
        // it instead of reaching the link under it, which opens the Event page (event-card 02).
        ScrollView(.horizontal, showsIndicators: false) {
            art.containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.always, axes: .horizontal)
        // The card's title says the matchup ("Football, Saint John's versus Gustavus").
        .accessibilityHidden(true)
    }

    private var art: some View {
        LinearGradient(stops: [.init(color: fill(game.teams[0]), location: 0),
                               .init(color: fill(game.teams[0]), location: 0.4),
                               .init(color: fill(game.teams[1]), location: 0.6),
                               .init(color: fill(game.teams[1]), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: Metric.gap) {
                    TeamColumn(team: game.teams[0])
                    Text("VS")
                        .font(.eventDisplay(26))
                        .foregroundStyle(.white)
                        .frame(width: Metric.vsWidth, height: Metric.disc)
                    TeamColumn(team: game.teams[1])
                }
                .padding(.top, Metric.rowTop)
            }
    }

    /// The school's color; one not known yet is ink, so two of them make Apple Sports' dark
    /// header. Ink as it is on paper: the card is the same in dark mode.
    private func fill(_ team: Game.Team) -> Color {
        team.rgb.map { Color(hex: $0) } ?? Hue.ink.onLightCanvas
    }
}

/// One school: its logo on a white disc, its short name under it.
private struct TeamColumn: View {
    let team: Game.Team

    @ObservedObject private var logos = POILogoCache.shared

    var body: some View {
        let image = team.logo.flatMap(logos.image(for:))
        VStack(spacing: GameMatchup.Metric.nameGap) {
            ZStack {
                Circle().fill(.white)
                // The first letter until the logo lands, and for a school with none yet.
                if image == nil {
                    Text(team.initial)
                        .font(.eventDisplay(34))
                        .foregroundStyle(Hue.ink.onLightCanvas)
                        .transition(.opacity)
                }
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: GameMatchup.Metric.logo, height: GameMatchup.Metric.logo)
                        .transition(.opacity)
                }
            }
            .frame(width: GameMatchup.Metric.disc, height: GameMatchup.Metric.disc)
            // The mock's two shadows: a tight one where it sits, a soft one under it.
            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.22), radius: 11, y: 8)
            .animation(Motion.smooth, value: image != nil)

            Text(team.short)
                .font(.sansSemibold(13))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: GameMatchup.Metric.column)
        .task(id: team.logo) { if let url = team.logo { logos.prefetch([url]) } }
    }
}
