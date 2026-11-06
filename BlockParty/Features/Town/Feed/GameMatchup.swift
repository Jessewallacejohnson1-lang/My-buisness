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
        /// The line under Final, wider than the column: the room between the numbers on the smallest phone.
        static let penalties: CGFloat = 190
        /// The day and time before it starts ("Thu, Nov 12 · 4:15 PM"), also wider than the column: the room between
        /// the logos on the smallest phone.
        static let when: CGFloat = 148
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
            let scorers = game.scorers
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    side(0, live: live, fresh: fresh)
                    middle(live: live, fresh: fresh, at: context.date).frame(width: Metric.middle)
                    side(1, live: live, fresh: fresh)
                }
                // The page's heading, in the title's place: "Live, Football, Saint John's 14, Gustavus 3, Q3, 4:12".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel((fresh ? "Live, " : "") + game.spoken + (fresh ? clock(live, at: context.date).map { ", \($0)" } ?? "" : ""))
                .accessibilityValue(cancelled ? "Canceled" : "")
                .accessibilityAddTraits(.isHeader)
                // Basketball's court rides the score, so its circle stays round the clock on every phone.
                .background(alignment: .top) {
                    if game.isBasketball, live?.bar != nil { BasketballCourt().transition(.opacity) }
                }
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
                if scorers.contains(where: { !$0.isEmpty }) {
                    Scorers(teams: game.teams, scorers: scorers)
                        .padding(.top, Metric.driveTop)
                        .transition(.opacity)
                }
                if let live, live.bar != nil {
                    QuarterBar(game: game, live: live, fresh: fresh)
                        .padding(.top, Metric.driveTop)
                        .transition(.opacity)
                }
            }
            // The bar fades in with the first live score.
            .animation(reduceMotion ? nil : Motion.smooth, value: live?.bar == nil)
            .animation(reduceMotion ? nil : Motion.smooth, value: fresh ? live?.drive : nil)
            // The first set's chip fades in, even when the live score came before any set.
            .animation(reduceMotion ? nil : Motion.smooth, value: game.sets.isEmpty)
            // A goal's scorer fades in under its team; a player's second goal cross-fades into their line.
            .animation(reduceMotion ? nil : Motion.smooth, value: scorers)
        }
        // A refresh that brings the live score or the final cross-fades into it.
        .animation(Motion.smooth, value: game.final)
        .animation(Motion.smooth, value: game.live == nil)
        .animation(Motion.smooth, value: game.shootout)
        // A scoring play while it's on screen: the clock line says it, that logo pops (ticket 07).
        .playsMoments(of: game)
    }

    /// The clock as VoiceOver says it: soccer's running minute, or halftime, as its ring shows them; else the
    /// clock as last sent.
    private func clock(_ live: Game.Live?, at date: Date) -> String? {
        guard let live else { return nil }
        if game.isSoccer, let minute = live.minute(at: date) { return live.isHalftime ? "halftime" : "minute \(minute)" }
        return live.clock
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
                // Wider than this column, in the room between the numbers, as Apple Sports' "VAN wins 4-2 Pens";
                // in the scorers' look, which reads on the team colors (Jesse, game-card 15).
                if let shootout = game.shootout {
                    Text("\(shootout.wins) on penalties")
                        .font(.sans(13))
                        .foregroundStyle(.white.opacity(Scorers.words))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: Metric.penalties)
                        .transition(.opacity)
                }
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
                if let when { NightChip(text: when).frame(width: Metric.when) }
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
    /// faint net and soccer's halfway line sit under the wash (soccer's center circle rides its minute ring).
    static func backdrop(_ game: Game) -> some View {
        let sides = colors(game.teams)
        return ZStack {
            LinearGradient(stops: [.init(color: shade(sides[0]), location: 0),
                                   .init(color: shade(sides[0]), location: 0.36),
                                   .init(color: shade(sides[1]), location: 0.66),
                                   .init(color: shade(sides[1]), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            if game.isVolleyball {
                VolleyballNet()
            }
            if game.isSoccer || game.isBasketball {
                // The draft's halfway line: 2 pt of white at 9%, down the middle to where the net stops.
                Color.white.opacity(0.09)
                    .frame(width: 2, height: VolleyballNet.depth)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            LinearGradient(stops: [.init(color: Hue.gameNight.opacity(0), location: 0),
                                   .init(color: Hue.gameNight.opacity(0.18), location: 0.22),
                                   .init(color: Hue.gameNight.opacity(0.72), location: 0.42),
                                   .init(color: Hue.gameNight.opacity(0.93), location: 0.58),
                                   .init(color: Hue.gameNight.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// A side's color at the page's depth (Burnley's claret and Chelsea's blue sit near 21% lightness in
    /// Apple's); none known is the poster's dark.
    static func shade(_ rgb: UInt32?) -> Color {
        rgb.map { Color(hex: tone($0, lightness: 0.21, saturationCap: 0.82)) } ?? Hue.poster
    }

    /// A side's color bright enough for thin marks on the dark (an end zone, a scoring play's bar), so each
    /// mark matches its half of the page; none known is a faint white.
    static func mark(_ game: Game, _ side: Int) -> Color {
        colors(game.teams)[side].map { Color(hex: tone($0, lightness: 0.58, saturationFloor: 0.7)) } ?? .white.opacity(0.3)
    }

    /// The colors the page draws, home first (BP app game-card 10): each team's own, unless the two sit
    /// within `closeHue` of each other, which reads as one color at the page's depth (Saint John's cardinal
    /// and Augsburg's maroon, Tue 2026-11-03). Then the away team takes its next color that isn't close
    /// (Macalester's navy); with none, the home team takes its own (Saint John's blue); with neither, the
    /// away side goes charcoal.
    static func colors(_ teams: [Game.Team]) -> [UInt32?] {
        let own = teams.map { vivid($0) }
        guard own.count == 2, let home = own[0], let away = own[1], close(home, away) else { return own }
        if let second = palette(teams[1]).first(where: { isVivid($0) && !close(home, $0) }) { return [home, second] }
        if let second = palette(teams[0]).first(where: { isVivid($0) && !close($0, away) }) { return [second, away] }
        return [home, charcoal]
    }

    /// Hues closer than this read as one color once both are deepened (Saint Ben's red and Macalester's
    /// orange-red sit 24° apart).
    private static let closeHue = 30.0
    /// A grey, which `tone` keeps grey: charcoal on the page, a grey mark.
    static let charcoal: UInt32 = 0x808080

    /// The team's color, or for a black or grey one (Gustavus, St. Olaf) its logo's first real color; nil
    /// when none is known.
    static func vivid(_ team: Game.Team) -> UInt32? {
        palette(team).first { isVivid($0) }
    }

    /// The team's color, then the colors read from its logo.
    private static func palette(_ team: Game.Team) -> [UInt32] {
        [team.rgb].compactMap { $0 } + team.colors
    }

    /// Colorful enough to tell a team by: not a grey, a black or a white.
    private static func isVivid(_ rgb: UInt32) -> Bool {
        let (_, lightness, saturation) = hls(rgb)
        return saturation > 0.15 && (0.08...0.92).contains(lightness)
    }

    /// Two colors whose hues sit within `closeHue` degrees, around the wheel.
    private static func close(_ a: UInt32, _ b: UInt32) -> Bool {
        let gap = abs(hls(a).0 - hls(b).0) * 360
        return min(gap, 360 - gap) < closeHue
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

    /// The page's Attend: our team's own color (Jesse, game-card 12), bright enough to show on the dark, as the
    /// marks are; nil when it has none, and Attend stays BP yellow.
    static func attend(_ game: Game) -> UInt32? {
        game.teams.indices.contains(game.ours) ? vivid(game.teams[game.ours]).map { tone($0, lightness: 0.58, saturationFloor: 0.7) } : nil
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
                    GameMatchup.mark(game, 0).frame(width: Self.endZone)
                    GameMatchup.mark(game, 1).frame(width: Self.endZone).offset(x: proxy.size.width - Self.endZone)
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
                    .fill(GameMatchup.mark(game, ahead))
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
/// on between pushes and holds at each period's end (`Game.Live.minute(at:)`); full past 90, in overtime. It sits
/// on the draft's faint center circle, which scrolls with it. A goal grows its moment over the ring, as the clock
/// line does for the other sports.
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
        /// The center circle: 156 pt across, its center 18 pt above the ring's, a 2 pt line, and its 8 pt spot.
        static let circle: CGFloat = 156
        static let circleUp: CGFloat = 18
        static let circleLine: CGFloat = 2
        static let spot: CGFloat = 8
    }

    /// The draft draws the circle and spot white at 9% and 12% under the page's dark wash, which darkens down the
    /// page; over the wash here, so they take the wash's share: 8.2% at the circle's top, 7.5% at its middle and
    /// 5.7% at its foot on a 402 pt phone, the spot 10%.
    private static let circleStroke = LinearGradient(stops: [.init(color: .white.opacity(0.082), location: 0),
                                                           .init(color: .white.opacity(0.075), location: 0.5),
                                                           .init(color: .white.opacity(0.057), location: 1)],
                                                   startPoint: .top, endPoint: .bottom)
    private static let spotFill: Double = 0.1

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
        .background {
            ZStack {
                Circle().stroke(Self.circleStroke, lineWidth: Metric.circleLine)
                    .frame(width: Metric.circle, height: Metric.circle)
                Circle().fill(.white.opacity(Self.spotFill))
                    .frame(width: Metric.spot, height: Metric.spot)
            }
            .offset(y: -Metric.circleUp)
            .accessibilityHidden(true)
        }
        .overlay {
            // The ring never changes size, so the minute rolls in place; HT and the minute cross-fade instead,
            // their letters being no count.
            MomentLine(style: .inRing) {
                Text(halftime ? "HT" : "\(minute)'")
                    .monospacedDigit()
                    // "110'" at a large text size still fits inside the ring.
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .id(halftime)
                    .animation(reduceMotion ? nil : Motion.smooth, value: halftime ? 0 : minute)
            }
        }
    }
}

/// Soccer's scorers under each team (game-card 09's draft): one line per player ("Hanson 23', 71'"), 13 pt at
/// 70% white, under its team's name.
private struct Scorers: View {
    let teams: [Game.Team]
    /// `Game.scorers`, in `teams` order.
    let scorers: [[String]]

    static let words: Double = 0.7
    static let lineGap: CGFloat = 4

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column(scorers[0])
            Color.clear.frame(width: GameMatchup.Metric.middle, height: 0)
            column(scorers[1])
        }
        // "Saint John's goals: Hanson 23, 71. Augsburg goals: Larkin 58".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(teams.indices.filter { !scorers[$0].isEmpty }.map { side in
            "\(teams[side].short) goals: " + scorers[side].joined(separator: "; ").replacingOccurrences(of: "'", with: "")
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

/// Basketball's quarters, or a men's game's halves, as one bar under the logos (game-card 09; Jesse, 2026-11-01:
/// "Yeah, I agree" to the mock beside the Figma draft, `references/basketball-bar/`): the ones played white, the one
/// being played filling as its clock runs, an OT part once overtime starts, each part's number under it; and Bonus
/// under the team in the bonus, in a row that keeps its room so nothing moves when it comes and goes.
private struct QuarterBar: View {
    let game: Game
    let live: Game.Live
    /// The Bonus waits for a fresh score, so a feed gone quiet never leaves one standing.
    let fresh: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The draft's bar, measured in its CSS: parts 8 pt tall and 6 pt apart, their numbers 14 pt under their tops,
    /// the Bonus chip 84 x 24 at 38 pt.
    enum Metric {
        static let gap: CGFloat = 6
        static let height: CGFloat = 8
        static let track: Double = 0.14
        static let labelGap: CGFloat = 6
        static let label: Double = 0.55
        /// The number under the part being played (the mock's; the draft shows every number alike).
        static let playingLabel: Double = 0.9
        static let bonusTop: CGFloat = 38
        static let bonus = CGSize(width: 84, height: 24)
    }

    var body: some View {
        let fill = live.barFill
        let playing = live.bar?.playing
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: Metric.gap) {
                ForEach(fill.indices, id: \.self) { part in
                    VStack(spacing: Metric.labelGap) {
                        Capsule()
                            .fill(.white.opacity(Metric.track))
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule().fill(.white).frame(width: proxy.size.width * fill[part])
                                }
                            }
                            .frame(height: Metric.height)
                        Text(name(part))
                            .font(.sansMedium(12))
                            .foregroundStyle(.white.opacity(part == playing ? Metric.playingLabel : Metric.label))
                            .lineLimit(1)
                    }
                    .transition(.opacity)
                }
            }
            HStack(spacing: 0) {
                bonus(0)
                Color.clear.frame(width: GameMatchup.Metric.middle, height: 0)
                bonus(1)
            }
            .padding(.top, Metric.bonusTop)
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: fill)
        // "Quarter 2 of 4, Saint Ben's in the bonus".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "1" to "4" (or "1" and "2"), then "OT".
    private func name(_ part: Int) -> String {
        part < (live.bar?.regulation ?? 0) ? "\(part + 1)" : "OT"
    }

    private func bonus(_ side: Int) -> some View {
        let on = fresh && live.inBonus(side)
        return Text("Bonus")
            .font(.sansBold(12))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: Metric.bonus.width, height: Metric.bonus.height)
            .background(.white.opacity(Metric.track), in: Capsule())
            .scaleEffect(on || reduceMotion ? 1 : 0.8)
            .opacity(on ? 1 : 0)
            .animation(reduceMotion ? Motion.smooth : Motion.select, value: on)
            .frame(maxWidth: .infinity)
    }

    private var spoken: String {
        guard let bar = live.bar else { return "" }
        let period = bar.period > bar.regulation ? "Overtime"
            : bar.regulation == 2 ? "Half \(bar.period) of 2" : "Quarter \(bar.period) of \(bar.regulation)"
        let bonus = game.teams.indices.filter { fresh && live.inBonus($0) }.map { "\(game.teams[$0].short) in the bonus" }
        return ([period] + bonus).joined(separator: ", ")
    }
}

/// Basketball's faint court behind the score (game-card 09's draft): the center circle round Live and the clock, and
/// the two three-point arcs reaching in from the sides, white 2 pt lines. The draft draws them at 9% under the page's
/// dark wash; drawn over it here, as soccer's circle is, they take the wash's share down the page on a 402 pt phone.
private struct BasketballCourt: View {
    /// The draft's SVG: the circle r 56 and the arcs r 170 from 60 pt off each side, all 54 pt under the score's top.
    static let centerY: CGFloat = 54
    static let circle: CGFloat = 112
    static let arc: CGFloat = 340
    static let arcOut: CGFloat = 261
    static let line: CGFloat = 2

    private static func stroke(_ alphas: [Double]) -> LinearGradient {
        LinearGradient(colors: alphas.map { .white.opacity($0) }, startPoint: .top, endPoint: .bottom)
    }
    /// 9% times what the wash leaves at each height: the circle 117 to 229 pt down, the arcs 3 to 343.
    private static let circleStroke = stroke([0.080, 0.075, 0.063])
    private static let arcStroke = stroke([0.090, 0.083, 0.075, 0.055, 0.032])

    var body: some View {
        ZStack {
            Circle().stroke(Self.circleStroke, lineWidth: Self.line)
                .frame(width: Self.circle, height: Self.circle)
            ForEach([-1, 1], id: \.self) { side in
                Circle().stroke(Self.arcStroke, lineWidth: Self.line)
                    .frame(width: Self.arc, height: Self.arc)
                    .offset(x: CGFloat(side) * Self.arcOut)
            }
        }
        .frame(width: 0, height: 0)
        .offset(y: Self.centerY)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
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
    /// The small line under the matchup: "Homecoming · Clemens Stadium" if it fits.
    let place: [String]

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
        return [live ? "Live" : nil, game.spoken, before, place.first].compactMap { $0 }.filter { !$0.isEmpty }
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
            .animation(reduceMotion ? nil : Motion.smooth, value: game.shootout)
            SmallLine(tries: place, alignment: .center)
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
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
            if let shootout = game.shootout {
                // Two lines in Final's place, between the logos on every phone (Jesse, game-card 15). No moments
                // come after a final, so they skip MomentLine, which holds to one line.
                Text("\(shootout.wins)\non penalties")
                    .font(MomentLineStyle.onWhite.font)
                    .foregroundStyle(Hue.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
            } else if let status {
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
/// sidearm"): the clean words (`GameMoment.words`, game-card 14), the time or assists under each, the score after it with the scoring side in ink,
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
                // A basketball game scores about 80 times (CSB v Augsburg, 2026-02-21): its newest 5 (game-card 09;
                // Jesse, 2026-11-01: yes to the mock's pick).
                ForEach(game.isBasketball ? Array(game.plays.suffix(5).reversed()) : game.plays.reversed()) { play in
                    row(play)
                        // A rewrite's words fill in with the scorers' cross-fade (game-card 13).
                        .animation(reduceMotion ? nil : Motion.smooth, value: play.text)
                        // A new play slides in on top; basketball's oldest of the 5 fades where it is, not
                        // sliding up over the rest.
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(reduceMotion ? nil : Motion.smooth, value: game.plays.count)
            .padding(.top, top)
        }
    }

    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.displaySemi(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Self.rowGap) { rows() }
        }
    }

    private func row(_ play: Game.Play) -> some View {
        let score = play.score, side = play.side
        let words = GameMoment.words(of: play, sport: game.sport)
        let home = Text("\(score[0])"), away = Text("\(score[1])")
        return VStack(alignment: .leading, spacing: 6) {
            Text(words.title)
                .font(.sansMedium(16))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(words.detail).monospacedDigit()
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
                    .fill(GameMatchup.mark(game, side))
                    .frame(width: Self.bar)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([words.title.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: " yd", with: " yard").replacingOccurrences(of: "TD", with: "touchdown"), words.detail, "\(game.teams[0].short) \(score[0]), \(game.teams[1].short) \(score[1])"]
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
