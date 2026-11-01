//
//  GameMatchup.swift
//  Block Party — a game's Event page: the two teams' colors across the whole screen, the score, the logos
//  and each sport's own touch; its scoring plays; and its white Town card (`WhiteGameCard`).
//
//  The page (BP app docs/plans/game-card, ticket 08; Jesse, 2026-10-31: "like Apple, how the whole entire
//  screen is those two colors blended together... really simple and smooth UI", then "I love that" to the
//  Figma drafts beside Apple Sports' live game screen, `references/game-page-blend/`): each team's color
//  deepened to Apple's depth, the left one's to 36% of the width and the right one's from 66%, fading to
//  near-black from halfway down; the big score on the outside over each logo on its white disc, Live and
//  the clock between them; for a live football game the down, distance and spot over a field bar; for
//  volleyball its sets in chips over a faint net, for soccer the minute in a ring over a faint center circle and
//  its scorers under the teams (ticket 09). The Town card went white on 2026-10-29 (ticket 06).
//

import SwiftUI

/// A game's scoreboard at the top of its Event page (ticket 08's Football draft, 402 pt phone).
struct GameMatchup: View {
    let game: Game
    /// The day and time before it starts ("Sat · 1 PM"), in the chip between the logos.
    let when: String?
    /// Called off: VoiceOver says so with the score, which is the page's heading.
    var cancelled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Metric {
        static let number: CGFloat = 64
        /// The number's line, and the logo 12 pt under it.
        static let numberLine: CGFloat = 76
        static let numberGap: CGFloat = 12
        static let disc: CGFloat = 60
        static let logo: CGFloat = 44
        static let nameGap: CGFloat = 10
        static let middle: CGFloat = 112
        /// The chip and the clock line 4 pt into the number's line, 10 pt apart.
        static let middleTop: CGFloat = 4
        static let middleGap: CGFloat = 10
        /// The loser's side once the final is in, and the trailing number while it's on.
        static let faded: Double = 0.55
        /// Football's line, volleyball's sets and soccer's scorers 28 pt under the names, football's bar 12 pt
        /// under its line.
        static let driveTop: CGFloat = 28
        static let barTop: CGFloat = 12
    }

    var body: some View {
        // Each second while it's on, so a stale clock goes and a quiet game stops saying Live.
        TimelineView(.periodic(from: .now, by: game.live == nil ? 60 : 1)) { context in
            // The score stays through a quiet spell (halftime: the server writes only a change); Live, the
            // clock and the field bar wait for a fresh one, so a feed gone quiet never leaves a frozen ball.
            let fresh = game.live?.isLive(at: context.date) == true
            let live = game.live
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    side(0, live: live, fresh: fresh)
                    middle(live: live, fresh: fresh, at: context.date).frame(width: Metric.middle)
                    side(1, live: live, fresh: fresh)
                }
                // The page's heading, in the title's place: "Live, Football, Saint John's 14, Gustavus 3, Q3, 4:12".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel((fresh ? "Live, " : "") + game.spoken + (fresh ? live?.clock.map { ", \($0)" } ?? "" : ""))
                .accessibilityValue(cancelled ? "Canceled" : "")
                .accessibilityAddTraits(.isHeader)
                if fresh, let drive = live?.drive {
                    FieldBar(game: game, drive: drive)
                        .padding(.top, Metric.driveTop)
                        .transition(.opacity)
                }
                if !game.sets.isEmpty {
                    SetChips(game: game)
                        .padding(.top, Metric.driveTop)
                        .transition(.opacity)
                }
                if game.scorers.contains(where: { !$0.isEmpty }) {
                    Scorers(game: game)
                        .padding(.top, Metric.driveTop)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Motion.smooth, value: fresh ? live?.drive : nil)
            // The first set's chip fades in, even when the live score came before any set.
            .animation(reduceMotion ? nil : Motion.smooth, value: game.sets.isEmpty)
            // A goal's scorer fades in under its team; a player's second goal cross-fades into their line.
            .animation(reduceMotion ? nil : Motion.smooth, value: game.scorers)
        }
        // A refresh that brings the live score or the final cross-fades into it.
        .animation(Motion.smooth, value: game.final)
        .animation(Motion.smooth, value: game.live == nil)
        // A scoring play while it's on screen: the clock line says it, that logo pops (ticket 07).
        .playsMoments(of: game)
    }

    /// Behind while it's on (the final fades the loser's whole side instead).
    private func trailing(_ side: Int, live: Game.Live?) -> Bool {
        guard game.final == nil, let score = live?.score, score[0] != score[1] else { return false }
        return score[side] < score[1 - side]
    }

    /// One team: its number (live and final), its logo on a white disc, its short name, and a yellow dot
    /// after the name while it has the ball.
    private func side(_ side: Int, live: Game.Live?, fresh: Bool) -> some View {
        let team = game.teams[side]
        let score = game.final ?? live?.score
        return VStack(spacing: 0) {
            if let score {
                Text("\(score[side])")
                    .font(.eventDisplay(Metric.number))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    // "102" still fits beside the clock on a 375 pt phone.
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(reduceMotion ? nil : Motion.smooth, value: score[side])
                    .frame(height: Metric.numberLine)
                    .opacity(trailing(side, live: live) ? Metric.faded : 1)
                    .padding(.bottom, Metric.numberGap)
                    .transition(.opacity)
            }
            LogoDisc(logo: team.logo, initial: team.initial, logoSide: Metric.logo, letter: .eventDisplay(28))
                .frame(width: Metric.disc, height: Metric.disc)
                .shadow(color: .black.opacity(0.28), radius: 9, y: 6)
                .momentPop(side)
            HStack(spacing: 6) {
                Text(team.short)
                    .font(.sansMedium(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if fresh, live?.drive?.side == side {
                    Circle().fill(Hue.brandDisc).frame(width: 7, height: 7).transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, Metric.nameGap)
        }
        .frame(maxWidth: .infinity)
        .opacity(game.winner == 1 - side ? Metric.faded : 1)
    }

    /// Between the teams: Live and the clock while it's on (the period alone through a quiet spell), Final
    /// after, the day and VS before.
    @ViewBuilder
    private func middle(live: Game.Live?, fresh: Bool, at now: Date) -> some View {
        VStack(spacing: Metric.middleGap) {
            if game.final != nil {
                NightChip(text: "Final")
            } else if let live, game.isSoccer, let minute = live.minute(at: now) {
                // The chip keeps its place through a quiet spell, so the ring stays on the center circle.
                NightChip(text: "Live", dot: Hue.live)
                    .opacity(fresh ? 1 : 0)
                    .animation(Motion.smooth, value: fresh)
                MinuteRing(minute: minute, halftime: live.isHalftime)
            } else if let live {
                if fresh { NightChip(text: "Live", dot: Hue.live) }
                MomentLine(style: .onNight) { Text(live.line(at: now)).monospacedDigit() }
            } else {
                if let when { NightChip(text: when) }
                Text("VS")
                    .font(.eventDisplay(26))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, game.final != nil || live != nil ? Metric.middleTop : 0)
    }

    // MARK: The page's colors

    /// The whole page behind everything: the two teams' colors, deepened, left into right, under a wash
    /// that takes them to near-black by halfway down (Apple Sports' live game, measured). Volleyball's
    /// faint net and soccer's center circle sit under the wash.
    static func backdrop(_ game: Game) -> some View {
        ZStack {
            LinearGradient(stops: [.init(color: shade(game.teams[0]), location: 0),
                                   .init(color: shade(game.teams[0]), location: 0.36),
                                   .init(color: shade(game.teams[1]), location: 0.66),
                                   .init(color: shade(game.teams[1]), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            if game.isVolleyball {
                VolleyballNet()
            }
            if game.isSoccer {
                SoccerPitch()
            }
            LinearGradient(stops: [.init(color: Hue.gameNight.opacity(0), location: 0),
                                   .init(color: Hue.gameNight.opacity(0.18), location: 0.22),
                                   .init(color: Hue.gameNight.opacity(0.72), location: 0.42),
                                   .init(color: Hue.gameNight.opacity(0.93), location: 0.58),
                                   .init(color: Hue.gameNight.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// A team's color at the page's depth (Burnley's claret and Chelsea's blue sit near 21% lightness in
    /// Apple's); none known is the poster's dark.
    static func shade(_ team: Game.Team) -> Color {
        vivid(team).map { Color(hex: tone($0, lightness: 0.21, saturationCap: 0.82)) } ?? Hue.poster
    }

    /// The same hue bright enough for thin marks on the dark (an end zone, a scoring play's bar); none
    /// known is a faint white.
    static func mark(_ team: Game.Team) -> Color {
        vivid(team).map { Color(hex: tone($0, lightness: 0.58, saturationFloor: 0.7)) } ?? .white.opacity(0.3)
    }

    /// The team's color, or for a black or grey one (Gustavus, St. Olaf) its logo's first real color; nil
    /// when none is known.
    static func vivid(_ team: Game.Team) -> UInt32? {
        ([team.rgb].compactMap { $0 } + team.colors).first { rgb in
            let (_, lightness, saturation) = hls(rgb)
            return saturation > 0.15 && (0.08...0.92).contains(lightness)
        }
    }

    /// The color at that lightness, its hue kept, its saturation held between the floor and the cap (a
    /// grey stays grey).
    static func tone(_ rgb: UInt32, lightness: Double, saturationFloor: Double = 0.6, saturationCap: Double = 1) -> UInt32 {
        let (hue, _, saturation) = hls(rgb)
        let s = saturation > 0.08 ? min(max(saturation, saturationFloor), saturationCap) : saturation
        let q = lightness < 0.5 ? lightness * (1 + s) : lightness + s - lightness * s, p = 2 * lightness - q
        func channel(_ t: Double) -> UInt32 {
            let t = t < 0 ? t + 1 : t > 1 ? t - 1 : t
            let v = t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p
            return UInt32((v * 255).rounded())
        }
        return channel(hue + 1 / 3) << 16 | channel(hue) << 8 | channel(hue - 1 / 3)
    }

    /// Hue (0 to 1), lightness and saturation.
    private static func hls(_ rgb: UInt32) -> (Double, Double, Double) {
        let r = Double(rgb >> 16 & 0xFF) / 255, g = Double(rgb >> 8 & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), l = (high + low) / 2, d = high - low
        guard d > 0 else { return (0, l, 0) }
        let s = l > 0.5 ? d / (2 - high - low) : d / (high + low)
        let h = high == r ? (g - b) / d + (g < b ? 6 : 0) : high == g ? (b - r) / d + 2 : (r - g) / d + 4
        return (h / 6, l, s)
    }
}

/// A chip between the logos on the page's dark: "Live" behind Apple's red dot, "Final", or the day.
private struct NightChip: View {
    let text: String
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(text).font(.sansBold(13)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.white.opacity(0.14), in: Capsule())
    }
}

/// Football's down and distance over the field (ticket 08's Football draft): the host's end zone on the
/// left in its color as the score sits, yard lines every ten, the ball on its spot and BP's yellow at the
/// first down. The ball and the line spring to each new spot.
private struct FieldBar: View {
    let game: Game
    let drive: Game.Live.Drive

    static let height: CGFloat = 30
    static let endZone: CGFloat = 8
    static let corner: CGFloat = 9

    var body: some View {
        VStack(spacing: GameMatchup.Metric.barTop) {
            Text(drive.line)
                .font(.sansMedium(15))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
                .contentTransition(.numericText())
            GeometryReader { proxy in
                let field = proxy.size.width - 2 * Self.endZone
                let x = { (yards: Int) in Self.endZone + field * CGFloat(yards) / 100 }
                ZStack(alignment: .leading) {
                    Color.white.opacity(0.08)
                    ForEach(1..<10) { ten in
                        Color.white.opacity(0.16).frame(width: 1).offset(x: x(ten * 10))
                    }
                    GameMatchup.mark(game.teams[0]).frame(width: Self.endZone)
                    GameMatchup.mark(game.teams[1]).frame(width: Self.endZone).offset(x: proxy.size.width - Self.endZone)
                    if let first = drive.firstDown {
                        Hue.brandDisc.frame(width: 2).offset(x: x(first) - 1)
                    }
                    if let ball = drive.ball {
                        Color.white.opacity(0.9).frame(width: 2).offset(x: x(ball) - 1)
                        Ellipse().fill(.white).frame(width: 14, height: 10).offset(x: x(ball) - 7)
                    }
                }
            }
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(drive.spoken(teams: game.teams))
    }
}

/// Volleyball's sets under the logos (game-card 09; Jesse, 2026-11-01: "i agree" to the mock beside the
/// Figma draft, `references/volleyball-sets/`): each played set's points in a chip, the winner's white and
/// a thin bar of its color under them; the set being played bigger and brighter, its points rolling in.
/// A set that ends shrinks into the row as the next one grows in.
private struct SetChips: View {
    let game: Game

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The draft's chips, measured in its CSS.
    enum Metric {
        static let gap: CGFloat = 8
        static let size = CGSize(width: 62, height: 52)
        static let playingSize = CGSize(width: 96, height: 64)
        static let corner: CGFloat = 14
        static let pointsGap: CGFloat = 6
        /// The set's name under the points being played, lifting them 12 pt.
        static let playingLift: CGFloat = 12
        static let bar = CGSize(width: 22, height: 3)
        static let bottom: CGFloat = 7
        static let fill: Double = 0.08
        static let playingFill: Double = 0.16
        /// The losing side's points, and the trailing side's in the set being played.
        static let behind: Double = 0.45
        static let label: Double = 0.6
        /// The set's name leaving, in seconds (picked).
        static let labelOut: Double = 0.1
    }

    var body: some View {
        let sets = game.sets, playing = game.setPlaying
        HStack(alignment: .bottom, spacing: Metric.gap) {
            ForEach(sets.indices, id: \.self) { set in
                chip(sets[set], set: set, playing: set == playing)
                    // The one being played gets its full width first; the played ones narrow for a fifth set.
                    .layoutPriority(set == playing ? 1 : 0)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : Motion.smooth, value: sets)
        .animation(reduceMotion ? nil : Motion.smooth, value: playing)
        // "Set 1, Saint Ben's 25, Carleton 21. Set 2, … Set 4, being played, Saint Ben's 18, Carleton 14".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sets.indices.map { set in
            (["Set \(set + 1)", set == playing ? "being played" : nil] + game.teams.indices.map { "\(game.teams[$0].short) \(sets[set][$0])" })
                .compactMap { $0 }.joined(separator: ", ")
        }.joined(separator: ". "))
    }

    private func chip(_ points: [Int], set: Int, playing: Bool) -> some View {
        let ahead: Int? = points[0] == points[1] ? nil : (points[0] > points[1] ? 0 : 1)
        let size = playing ? Metric.playingSize : Metric.size
        return ZStack(alignment: .bottom) {
            HStack(spacing: Metric.pointsGap) {
                ForEach(0..<2, id: \.self) { side in
                    Text("\(points[side])")
                        .foregroundStyle(.white.opacity(ahead == 1 - side ? Metric.behind : 1))
                        .contentTransition(.numericText(countsDown: false))
                }
            }
            .font(playing ? .sansBold(22) : .sansMedium(15))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxHeight: .infinity)
            .padding(.bottom, playing ? Metric.playingLift : 0)
            // A set that ends cross-fades its points into the small chip's, rather than rolling them while
            // they change size.
            .id(playing)
            if playing {
                Text("Set \(set + 1)")
                    .font(.sansMedium(11))
                    .foregroundStyle(.white.opacity(Metric.label))
                    .padding(.bottom, Metric.bottom)
                    // Gone before the chip has shrunk, so it never crosses the winner's bar coming in.
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: Metric.labelOut))))
            } else if let ahead, game.teams.indices.contains(ahead) {
                Capsule()
                    .fill(GameMatchup.mark(game.teams[ahead]))
                    .frame(width: Metric.bar.width, height: Metric.bar.height)
                    .padding(.bottom, Metric.bottom)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: size.width)
        .frame(height: size.height)
        .background(.white.opacity(playing ? Metric.playingFill : Metric.fill))
        // Nothing hangs out of a chip while it shrinks.
        .clipShape(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
    }
}

/// Volleyball's faint net behind the score (game-card 09's draft): thin white lines crossing every 18 pt
/// over the top of the page, which the wash darkens with everything else.
private struct VolleyballNet: View {
    static let mesh: CGFloat = 18
    static let depth: CGFloat = 430
    static let line: Double = 0.045

    var body: some View {
        Canvas { context, size in
            var net = Path()
            for x in stride(from: -Self.depth, to: size.width, by: Self.mesh) {
                net.move(to: CGPoint(x: x, y: 0))
                net.addLine(to: CGPoint(x: x + Self.depth, y: Self.depth))
                net.move(to: CGPoint(x: x + Self.depth, y: 0))
                net.addLine(to: CGPoint(x: x, y: Self.depth))
            }
            context.stroke(net, with: .color(.white.opacity(Self.line)), lineWidth: 1)
        }
        .frame(height: Self.depth)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// Soccer's minute in a ring that fills to 90 (game-card 09; Jesse, 2026-11-01: "yes to all" to the mock beside
/// the Figma draft, `references/soccer-ring/`): the minute, HT through halftime, white on a faint track. It runs
/// on between pushes and holds at each period's end (`Game.Live.minute(at:)`); full past 90, in overtime. A goal
/// grows its moment over the ring, as the clock line does for the other sports.
private struct MinuteRing: View {
    let minute: Int
    let halftime: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The draft's ring, measured in its SVG: 72 pt across, its line on a 30 pt radius, 3 pt wide.
    enum Metric {
        static let size: CGFloat = 72
        static let diameter: CGFloat = 60
        static let line: CGFloat = 3
        static let track: Double = 0.16
        static let full = 90
    }

    var body: some View {
        let filled = CGFloat(min(minute, Metric.full)) / CGFloat(Metric.full)
        ZStack {
            Circle().stroke(.white.opacity(Metric.track), lineWidth: Metric.line)
            Circle()
                .trim(from: 0, to: filled)
                .stroke(.white, style: StrokeStyle(lineWidth: Metric.line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : Motion.smooth, value: filled)
        }
        .frame(width: Metric.diameter, height: Metric.diameter)
        .frame(width: Metric.size, height: Metric.size)
        .overlay {
            // The ring never changes size, so the minute rolls in place.
            MomentLine(style: .inRing) {
                Text(halftime ? "HT" : "\(minute)'")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : Motion.smooth, value: halftime ? 0 : minute)
            }
        }
    }
}

/// Soccer's scorers under each team (game-card 09's draft): one line per player ("Hanson 23', 71'"), 13 pt at
/// 70% white, under its team's name.
private struct Scorers: View {
    let game: Game

    static let words: Double = 0.7
    static let lineGap: CGFloat = 4

    var body: some View {
        let scorers = game.scorers
        HStack(alignment: .top, spacing: 0) {
            column(scorers[0])
            Color.clear.frame(width: GameMatchup.Metric.middle, height: 0)
            column(scorers[1])
        }
        // "Saint John's goals: Hanson 23, 71. Augsburg goals: Larkin 58".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.teams.indices.filter { !scorers[$0].isEmpty }.map { side in
            "\(game.teams[side].short) goals: " + scorers[side].joined(separator: "; ").replacingOccurrences(of: "'", with: "")
        }.joined(separator: ". "))
    }

    /// A line keeps its place when it changes, so a player's second goal cross-fades into it.
    private func column(_ lines: [String]) -> some View {
        VStack(spacing: Self.lineGap) {
            ForEach(lines.indices, id: \.self) { line in
                Text(lines[line]).transition(.opacity)
            }
        }
        .font(.sans(13))
        .foregroundStyle(.white.opacity(Self.words))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }
}

/// Soccer's faint center circle and halfway line behind the score (game-card 09's draft): white at 9%, which the
/// wash darkens with everything else, and the center spot.
private struct SoccerPitch: View {
    static let line: Double = 0.09
    static let width: CGFloat = 2
    static let radius: CGFloat = 78
    static let spot: CGFloat = 4
    static let spotFill: Double = 0.12
    /// How far down the halfway line runs, as the net does.
    static let depth: CGFloat = 430
    /// The circle's center below the safe area's top: 18 pt above the minute ring's center, as in the draft (the
    /// matchup starts 57.5 pt down, the ring's center 74 pt into it).
    static let center: CGFloat = 113.5

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            Canvas { context, size in
                let mid = CGPoint(x: size.width / 2, y: top + Self.center)
                var lines = Path()
                lines.move(to: CGPoint(x: mid.x, y: 0))
                lines.addLine(to: CGPoint(x: mid.x, y: Self.depth))
                lines.addEllipse(in: CGRect(x: mid.x - Self.radius, y: mid.y - Self.radius, width: 2 * Self.radius, height: 2 * Self.radius))
                context.stroke(lines, with: .color(.white.opacity(Self.line)), lineWidth: Self.width)
                context.fill(Path(ellipseIn: CGRect(x: mid.x - Self.spot, y: mid.y - Self.spot, width: 2 * Self.spot, height: 2 * Self.spot)),
                             with: .color(.white.opacity(Self.spotFill)))
            }
        }
        .accessibilityHidden(true)
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

/// A game's scoring plays on its Event page, newest first (BP app game-card 05; Jesse, 2026-10-25: "copy
/// sidearm"): SIDEARM's own words, the time under each, the score after it with the scoring side in ink,
/// and a thin bar of the scoring school's color on its side, as Apple Sports' Key Plays draw them
/// (`references/live-plays/`). Volleyball has none: every point would be a play, and its sets are the
/// chips under its logos (game-card 09).
struct GameScoring: View {
    let game: Game
    /// Above its heading, when it has anything to show.
    var top: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let rowGap: CGFloat = 8
    static let bar: CGFloat = 3

    var body: some View {
        if !game.plays.isEmpty {
            section("Scoring plays") {
                ForEach(game.plays.reversed()) { play in
                    row(play)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : Motion.smooth, value: game.plays.count)
            .padding(.top, top)
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

    private func row(_ play: Game.Play) -> some View {
        let score = play.score, side = play.side
        let home = Text("\(score[0])"), away = Text("\(score[1])")
        return VStack(alignment: .leading, spacing: 6) {
            Text(play.text)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(play.when).monospacedDigit()
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
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        // The scoring school's color, on its side of the row.
        .overlay(alignment: side == 1 ? .trailing : .leading) {
            if game.teams.indices.contains(side) {
                Capsule()
                    .fill(GameMatchup.mark(game.teams[side]))
                    .frame(width: Self.bar)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([play.text, play.when, "\(game.teams[0].short) \(score[0]), \(game.teams[1].short) \(score[1])"]
            .joined(separator: ", "))
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
    /// Behind the letter alone, while the logo loads or when it can't: the Town's white card shows a
    /// place with no logo as a letter on the light fill (no-photo-cards), so one still loading matches.
    var blank: Color? = nil

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
                if let blank {
                    Circle().fill(blank).transition(.opacity)
                }
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
