//
//  GameMatchup.swift
//  Block Party — a game's picture on its Town card: the two teams' colors, logos and VS.
//
//  Drawn instead of a photo for a game between two teams (BP app docs/plans/game-card,
//  ticket 01; Jesse, 2026-10-20: "I want idea E", "keep names"; taste.md). X's and Apple
//  Sports' game headers: the left team's color to 40% of the width, the right team's from
//  60%, each logo on a white disc with the school's short name under it, VS between them;
//  once the final is in, the score in VS's place and the loser's side faded (ticket 02).
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
        /// Once the final is in (ticket 02): the score takes a column of its own, 4 pt from the
        /// teams, and the loser's side is at 55%.
        static let scoreGap: CGFloat = 4
        static let faded: Double = 0.55
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
                HStack(alignment: .top, spacing: game.final == nil ? Metric.gap : Metric.scoreGap) {
                    TeamColumn(team: game.teams[0])
                        .opacity(game.winner == 1 ? Metric.faded : 1)
                    if let final = game.final {
                        FinalScore(final: final, winner: game.winner)
                            .transition(.opacity)
                    } else {
                        Text("VS")
                            .font(.eventDisplay(26))
                            .foregroundStyle(.white)
                            .frame(width: Metric.vsWidth, height: Metric.disc)
                            .transition(.opacity)
                    }
                    TeamColumn(team: game.teams[1])
                        .opacity(game.winner == 0 ? Metric.faded : 1)
                }
                .padding(.top, Metric.rowTop)
                // A refresh that brings the final cross-fades VS into it.
                .animation(Motion.smooth, value: game.final)
            }
    }

    /// The school's color; one not known yet is ink, so two of them make Apple Sports' dark
    /// header. Ink as it is on paper: the card is the same in dark mode.
    private func fill(_ team: Game.Team) -> Color {
        team.rgb.map { Color(hex: $0) } ?? Hue.ink.onLightCanvas
    }
}

/// The final where VS was: the score with the loser's number and its dash at 55% (a tie fades
/// neither), over the "Final" pill (FotMob's full time; the mock's Picked row).
private struct FinalScore: View {
    let final: [Int]
    let winner: Int?

    var body: some View {
        let faded = Color.white.opacity(GameMatchup.Metric.faded)
        let home = String(final[0]), away = String(final[1])
        let score: Text = switch winner {
        case 0: Text("\(home)\(Text(" – \(away)").foregroundStyle(faded))")
        case 1: Text("\(Text("\(home) – ").foregroundStyle(faded))\(away)")
        default: Text("\(home) – \(away)")
        }
        VStack(spacing: 6) {
            score
                .font(.eventDisplay(34))
                .foregroundStyle(.white)
                .lineLimit(1)
                // A basketball score ("102 – 98") still fits the column.
                .minimumScaleFactor(0.7)
            Text("Final")
                .font(.sansSemibold(12))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(.white.opacity(0.22), in: Capsule())
        }
        // Up to the mock's 112 pt, narrower on a 375 pt phone, where three columns would overrun the card.
        .frame(maxWidth: GameMatchup.Metric.column, minHeight: GameMatchup.Metric.disc, maxHeight: GameMatchup.Metric.disc)
    }
}

/// One school: its logo on a white disc, its short name under it.
private struct TeamColumn: View {
    let team: Game.Team

    var body: some View {
        VStack(spacing: GameMatchup.Metric.nameGap) {
            TeamDisc(team: team, logoSide: GameMatchup.Metric.logo, letter: .eventDisplay(34))
                .frame(width: GameMatchup.Metric.disc, height: GameMatchup.Metric.disc)
                // The mock's two shadows: a tight one where it sits, a soft one under it.
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.22), radius: 11, y: 8)

            Text(team.short)
                .font(.sansSemibold(13))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: GameMatchup.Metric.column)
    }
}

/// A game's host row: the host school's logo where a host's photo goes, as the Reference
/// draws it; its first letter until the logo lands.
struct GameHostMark: View {
    let team: Game.Team
    let side: CGFloat

    var body: some View {
        TeamDisc(team: team, logoSide: side * 0.75, letter: .sansSemibold(14))
            .frame(width: side, height: side)
            .overlay(Circle().strokeBorder(Hue.hairline.onLightCanvas, lineWidth: 0.5))
    }
}

/// A school's logo fitted on a white disc, or its first letter: while the logo loads, for a
/// school with none yet, and for one that fails.
private struct TeamDisc: View {
    let team: Game.Team
    let logoSide: CGFloat
    let letter: Font

    @ObservedObject private var logos = POILogoCache.shared

    var body: some View {
        let image = team.logo.flatMap(logos.image(for:))
        ZStack {
            Circle().fill(.white)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: logoSide, height: logoSide)
                    .transition(.opacity)
            } else {
                Text(team.initial)
                    .font(letter)
                    .foregroundStyle(Hue.ink.onLightCanvas)
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: image != nil)
        .task(id: team.logo) { if let url = team.logo { logos.prefetch([url]) } }
    }
}
