//
//  GameMatchup.swift
//  Block Party — a game's band on its Event page: the two teams' colors, logos and VS; and its
//  white Town card (`WhiteGameCard`).
//
//  Drawn instead of a photo for a game between two teams (BP app docs/plans/game-card,
//  ticket 01; Jesse, 2026-10-20: "I want idea E", "keep names"; taste.md). X's and Apple
//  Sports' game headers: the left team's color to 40% of the width, the right team's from
//  60%, each logo on a white disc with the school's short name under it, VS between them;
//  while it's being played, the live score in VS's place over the period and clock (ticket 03);
//  once the final is in, the score in VS's place and the loser's side faded (ticket 02).
//  The Town card went white on 2026-10-29 (ticket 06).
//

import SwiftUI

struct GameMatchup: View {
    let game: Game
    /// The row of logos this far below the art's top: the card's 62 pt, or the Event page band's (ticket 05).
    var rowTop: CGFloat = Metric.rowTop

    /// The mock's Picked row, on its 370 pt card (BP app references/game-card/mock.html).
    enum Metric {
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
        // The page's title says the matchup.
        art.accessibilityHidden(true)
    }

    /// The two schools' colors, the left one's to 40% of the width, the right one's from 60%.
    static func backdrop(_ game: Game) -> LinearGradient {
        LinearGradient(stops: [.init(color: fill(game.teams[0]), location: 0),
                               .init(color: fill(game.teams[0]), location: 0.4),
                               .init(color: fill(game.teams[1]), location: 0.6),
                               .init(color: fill(game.teams[1]), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    private var art: some View {
        Self.backdrop(game)
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: game.final == nil && game.live == nil ? Metric.gap : Metric.scoreGap) {
                    TeamColumn(team: game.teams[0], side: 0)
                        .opacity(game.winner == 1 ? Metric.faded : 1)
                    if let final = game.final {
                        FinalScore(final: final, winner: game.winner)
                            .transition(.opacity)
                    } else if let live = game.live {
                        LiveScore(live: live)
                            .transition(.opacity)
                    } else {
                        Text("VS")
                            .font(.eventDisplay(26))
                            .foregroundStyle(.white)
                            .frame(width: Metric.vsWidth, height: Metric.disc)
                            .transition(.opacity)
                    }
                    TeamColumn(team: game.teams[1], side: 1)
                        .opacity(game.winner == 0 ? Metric.faded : 1)
                }
                .padding(.top, rowTop)
                // A refresh that brings the live score or the final cross-fades VS into it.
                .animation(Motion.smooth, value: game.final)
                .animation(Motion.smooth, value: game.live == nil)
            }
            // A scoring play while it's on screen: the pill says it, that logo pops (ticket 07).
            .playsMoments(of: game)
    }

    /// The school's color; one not known yet is ink, so two of them make Apple Sports' dark
    /// header. Ink as it is on paper: the card is the same in dark mode.
    static func fill(_ team: Game.Team) -> Color {
        team.rgb.map { Color(hex: $0) } ?? Hue.ink.onLightCanvas
    }
}

/// A game's Town card (BP app game-card 06; Jesse, 2026-10-29: "remove the background entirely and
/// just have the two teams versus over the white background"): white, the sport above, the two logos
/// bare with their short names under them, VS between them over the time, the place below. While
/// it's on, the score and "Live" behind the red dot take VS's place; once the final is in, the score
/// over "Final" with the loser's side faded. A tap opens the Event page, as on any card
/// (`references/game-card/white/mock.html`, the After phone).
struct WhiteGameCard: View {
    let item: FeedCardItem
    let game: Game
    /// "Homecoming · Clemens Stadium", under the matchup.
    let place: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The mock's After phone, on its 370 x 196 pt card.
    enum Metric {
        static let aspect: CGFloat = 370.0 / 196.0
        static let sportTop: CGFloat = 18
        static let rowTop: CGFloat = 58
        static let logo: CGFloat = 64
        static let column: CGFloat = 112
        static let gap: CGFloat = 14
        static let middle: CGFloat = 92
        static let placeBottom: CGFloat = 16
        /// The place line keeps clear of the heart in the corner, on both sides so it stays centred.
        static let placeInset: CGFloat = 62
        static let dot: CGFloat = 7
        /// The loser's side once the final is in: ink on white, so lighter than on the team colors.
        static let faded: Double = 0.45
    }

    var body: some View {
        // On the minute, as the photo cards' chip turns to Now; each second while a score comes in.
        let minute = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        TimelineView(.periodic(from: minute, by: game.live == nil ? 60 : 1)) { context in
            // One page that rubber-bands sideways, as a one-photo card does, so a sideways swipe moves
            // it instead of reaching the link under it (event-card 02).
            ScrollView(.horizontal, showsIndicators: false) {
                card(at: context.date).containerRelativeFrame(.horizontal)
            }
            .scrollBounceBehavior(.always, axes: .horizontal)
            // One element, so the card's link reads it: a scroll view hides what's inside it from the link.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(at: context.date))
        }
        // A scoring play while it's on screen: the line under the score says it, that logo pops (ticket 07).
        .playsMoments(of: game)
        // White in dark mode too, as the team-color band it replaced was pinned light: it is the card's look.
        .environment(\.colorScheme, .light)
    }

    /// "Football, Saint John's versus Gustavus, Sat, Oct 31 · 1 PM, Clemens Stadium"; "Live, Football,
    /// Saint John's 14, Concordia 7, Q3, …"; the final's score and "final" are `Game.spoken`'s own.
    private func spoken(at date: Date) -> String {
        let live = game.live?.isLive(at: date) == true
        let before = game.final == nil && game.live == nil ? status(at: date)?.text : nil
        return [live ? "Live" : nil, game.spoken, before, place].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func card(at date: Date) -> some View {
        let status = status(at: date)
        return ZStack(alignment: .top) {
            Hue.surface
            Text(game.sport)
                .font(.eventDisplay(22))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .padding(.top, Metric.sportTop)
            HStack(alignment: .top, spacing: Metric.gap) {
                team(0)
                middle(status)
                team(1)
            }
            .padding(.top, Metric.rowTop)
            // A refresh that brings the live score or the final cross-fades VS into it.
            .animation(reduceMotion ? nil : Motion.smooth, value: game.final)
            .animation(reduceMotion ? nil : Motion.smooth, value: game.live == nil)
            Text(place)
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
                .padding(.horizontal, Metric.placeInset)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, Metric.placeBottom)
        }
    }

    /// Under VS or the score: "Final", "Live · Q3 4:12" (the red dot), "Now" (the green dot), else the
    /// day and time, which the photo cards' chip says.
    private func status(at date: Date) -> (dot: Color?, text: String)? {
        if game.final != nil { return (nil, "Final") }
        if let live = game.live, live.isLive(at: date) {
            let line = live.line(at: date)
            return (Hue.live, line.isEmpty ? "Live" : "Live · \(line)")
        }
        if item.isNow(at: date) { return (Hue.now, "Now") }
        return item.whenLine.map { (nil, $0.text) }
    }

    /// The score where VS was: the loser's number and its dash faded once the final is in (a tie
    /// fades neither), each new number rolling in while it's on.
    private var score: Text? {
        if let final = game.final {
            let faded = Hue.ink.opacity(Metric.faded)
            let home = String(final[0]), away = String(final[1])
            return switch game.winner {
            case 0: Text("\(home)\(Text(" – \(away)").foregroundStyle(faded))")
            case 1: Text("\(Text("\(home) – ").foregroundStyle(faded))\(away)")
            default: Text("\(home) – \(away)")
            }
        }
        return game.live.map { Text("\($0.score[0]) – \($0.score[1])") }
    }

    private func middle(_ status: (dot: Color?, text: String)?) -> some View {
        VStack(spacing: 4) {
            Group {
                if let score {
                    score.font(.eventDisplay(26))
                        .contentTransition(.numericText(countsDown: false))
                } else {
                    Text("VS").font(.eventDisplay(22))
                }
            }
            .foregroundStyle(Hue.ink)
            .lineLimit(1)
            // A basketball score ("102 – 98") still fits.
            .minimumScaleFactor(0.7)
            .animation(reduceMotion ? nil : Motion.smooth, value: game.live?.score)
            if let status {
                // A scoring play turns it into an ink capsule round the moment for 3 s (ticket 07).
                MomentLine(style: .onWhite) {
                    HStack(spacing: 5) {
                        if let dot = status.dot {
                            Circle().fill(dot).frame(width: Metric.dot, height: Metric.dot)
                        }
                        Text(status.text).monospacedDigit()
                    }
                    .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(minWidth: Metric.middle, minHeight: Metric.logo)
    }

    /// One school: its logo bare, its short name under it; faded once it has lost.
    private func team(_ side: Int) -> some View {
        let team = game.teams[side]
        return VStack(spacing: 8) {
            LogoDisc(logo: team.logo, initial: team.initial, logoSide: Metric.logo, letter: .eventDisplay(30), disc: false)
                .frame(width: Metric.logo, height: Metric.logo)
                .momentPop(side)
            Text(team.short)
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: Metric.column)
        .opacity(game.winner == 1 - side ? Metric.faded : 1)
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

/// The score while it's on, where VS was: FinalScore's look with neither side faded, each new
/// number rolling in as the scoreboard's do, over a pill with the period and clock ("Q3 · 4:12";
/// the mock's Picked row, Live phone). A clock that stops coming in is hidden, not left frozen.
/// A scoring play turns the pill white round its words for 3 s (`MomentLine`, ticket 07).
private struct LiveScore: View {
    let live: Game.Live

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Text("\(live.score[0]) – \(live.score[1])")
                .font(.eventDisplay(34))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(countsDown: false))
                .animation(reduceMotion ? nil : Motion.smooth, value: live.score)
            // Each second, so soccer's minute turns over on time and a stale clock goes.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                MomentLine(style: .onColor) {
                    Text(live.line(at: context.date)).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: GameMatchup.Metric.column, minHeight: GameMatchup.Metric.disc, maxHeight: GameMatchup.Metric.disc)
    }
}

/// A game's scoring plays on its Event page, newest first (BP app game-card 05; Jesse, 2026-10-25: "copy
/// sidearm"): SIDEARM's own words, the time under each, the score after it with the scoring side in ink,
/// and a thin bar of the scoring school's color on its side, as Apple Sports' Key Plays draw them
/// (`references/live-plays/`). Volleyball shows its sets instead: every point would be a play.
struct GameScoring: View {
    let game: Game

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let rowGap: CGFloat = 8
    static let bar: CGFloat = 3

    var body: some View {
        if !game.plays.isEmpty {
            section("Scoring plays") {
                ForEach(game.plays.reversed()) { play in
                    row(text: play.text, when: play.when, score: play.score, side: play.side)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : Motion.smooth, value: game.plays.count)
        } else if game.sport.localizedCaseInsensitiveContains("volleyball"), game.periods.count == 2 {
            section("Sets") {
                ForEach(game.periods[0].indices, id: \.self) { set in
                    let score = [game.periods[0][set], game.periods[1][set]]
                    row(text: "Set \(set + 1)", when: nil, score: score,
                        side: score[0] == score[1] ? nil : (score[0] > score[1] ? 0 : 1))
                }
            }
        }
    }

    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Self.rowGap) { rows() }
        }
    }

    private func row(text: String, when: String?, score: [Int], side: Int?) -> some View {
        let home = Text("\(score[0])"), away = Text("\(score[1])")
        return VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let when { Text(when).monospacedDigit() }
                Spacer(minLength: 8)
                Text("\(side == 0 ? home.foregroundStyle(Hue.ink).bold() : home) – \(side == 1 ? away.foregroundStyle(Hue.ink).bold() : away)")
                    .monospacedDigit()
            }
            .font(.sans(13))
            .foregroundStyle(Hue.inkSecondary)
        }
        .padding(.vertical, 12)
        .padding(.leading, side == 1 ? 16 : 20)
        .padding(.trailing, side == 1 ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Hue.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        // The scoring school's color, on its side of the row.
        .overlay(alignment: side == 1 ? .trailing : .leading) {
            if let side, game.teams.indices.contains(side) {
                Capsule()
                    .fill(GameMatchup.fill(game.teams[side]))
                    .frame(width: Self.bar)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text, when, "\(game.teams[0].short) \(score[0]), \(game.teams[1].short) \(score[1])"]
            .compactMap { $0 }.joined(separator: ", "))
    }
}

/// One school: its logo on a white disc, its short name under it.
private struct TeamColumn: View {
    let team: Game.Team
    /// 0 for the host, 1 for the other: a moment of its own pops its disc (ticket 07).
    let side: Int

    var body: some View {
        VStack(spacing: GameMatchup.Metric.nameGap) {
            LogoDisc(logo: team.logo, initial: team.initial, logoSide: GameMatchup.Metric.logo, letter: .eventDisplay(34))
                .frame(width: GameMatchup.Metric.disc, height: GameMatchup.Metric.disc)
                // The mock's two shadows: a tight one where it sits, a soft one under it.
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.22), radius: 11, y: 8)
                .momentPop(side)

            Text(team.short)
                .font(.sansSemibold(13))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: GameMatchup.Metric.column)
    }
}

/// A logo fitted on a white disc, or its first letter: while the logo loads, for a school or
/// place with none yet, and for one that fails. A game's schools, and town news's places.
struct LogoDisc: View {
    let logo: URL?
    let initial: String
    let logoSide: CGFloat
    let letter: Font
    /// A host's picture beside its name (Town cards, Town news): the logo's empty border trimmed,
    /// and a round badge filling the whole circle (`LogoFit`, Jesse 2026-10-24).
    var fits = false
    /// On the white game card the logo, or its letter, stands bare (game-card 06).
    var disc = true

    @ObservedObject private var logos = POILogoCache.shared

    var body: some View {
        let loaded = logo.flatMap(logos.image(for:))
        let fit = fits ? loaded.flatMap { image in logo.map { LogoFit.of(image, url: $0) } } : nil
        let image = fit?.image ?? loaded
        ZStack {
            if disc {
                Circle().fill(.white)
            }
            if let image, fit?.round == true {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .clipShape(Circle())
                    .transition(.opacity)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: logoSide, height: logoSide)
                    .transition(.opacity)
            } else {
                Text(initial)
                    .font(letter)
                    .foregroundStyle(Hue.ink.onLightCanvas)
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: image != nil)
        .task(id: logo) { if let logo { logos.prefetch([logo]) } }
    }
}
