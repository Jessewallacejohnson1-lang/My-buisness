//
//  Game.swift
//  Block Party — a game between two teams: its sport, schools, live score, scoring plays and final
//  (BP app docs/plans/game-card). Moved out of Models.swift unchanged (BP app codebase-health 29).
//

import Foundation

/// A game between two teams, as `get_town_feed` sends it (`private.event_game`): the sport
/// ("Girls Soccer"), its special night ("Homecoming") and both schools, the host's first, its live
/// score while it's on, and its final once it's in.
nonisolated struct Game: Decodable, Hashable, Sendable {
    let sport: String
    let occasion: String?
    let teams: [Team]
    /// The final score in `teams` order (BP app docs/plans/game-card, ticket 02); nil before it's in,
    /// and for one that doesn't read, so the card stays VS. Only the server makes a final: a live
    /// score that says complete once can take it back (volleyball did, 2026-10-24).
    private(set) var final: [Int]?
    /// The score while it's being played (ticket 03); nil before, after, and for a high school game.
    private(set) var live: Live?
    /// Each period's score in `teams` order, as SIDEARM last sent them: volleyball's sets (ticket 05).
    /// Kept after the final, which the live score is not.
    private(set) var periods: [[Int]] = []
    /// A tied final settled on penalty kicks (game-card 15); nil for every other game. Kept after the final, which
    /// the live score is not.
    private(set) var shootout: Shootout?
    /// Hockey's shots on goal in `teams` order (game-card 09); nil for any other sport. Kept after the final, which the
    /// live score is not.
    private(set) var shots: [Int]?
    /// SIDEARM's scoring plays, oldest first (ticket 05): every play that changed the score, in its words.
    private(set) var plays: [Play] = []

    /// How penalty kicks settled a tie, as `live_score.shootout` keeps it (`private.sidearm_shootout`).
    nonisolated struct Shootout: Decodable, Hashable, Sendable {
        /// Kicks made, in `teams` order; never level.
        let score: [Int]
        /// The winner's letters as SIDEARM has them ("CSB"): the line has room for these, not "Saint Ben's".
        let who: String

        private enum CodingKeys: String, CodingKey { case score, who }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            score = try c.decode([Int].self, forKey: .score)
            who = try c.decode(String.self, forKey: .who)
            guard score.count == 2, score.allSatisfy({ $0 >= 0 }), score[0] != score[1], !who.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .score, in: c, debugDescription: "two unequal counts and a name")
            }
        }

        /// The side that won them, 0 or 1.
        var winner: Int { score[0] > score[1] ? 0 : 1 }
        /// "CSB wins 5–4", the winner's count first.
        var wins: String { "\(who) wins \(score[winner])–\(score[1 - winner])" }
    }

    /// One scoring play as `club_events.scoring_plays` keeps it (`private.sidearm_scoring`).
    nonisolated struct Play: Decodable, Hashable, Sendable, Identifiable {
        let id: String
        let text: String
        let period: String
        let clock: String?
        /// 0 for the first team (the host), 1 for the other.
        let side: Int
        let score: [Int]

        /// "Q3 · 4:12", or the period alone.
        var when: String { clock.map { "\(period) · \($0)" } ?? period }

        /// A list of them as JSON, one that doesn't read left out; nil when it isn't a list.
        static func list(from data: Data) -> [Play]? {
            (try? JSONDecoder().decode([LenientItem<Play>].self, from: data))?.compactMap(\.value)
        }
    }

    /// SIDEARM's score as `club_events.live_score` keeps it (`private.sidearm_live`): `teams` order,
    /// the period as the sport says it ("Q3", "2nd half", "Set 3"), and the clock ("4:12", "67'").
    nonisolated struct Live: Decodable, Hashable, Sendable {
        let score: [Int]
        let period: String
        let clock: String?
        /// The clock in seconds as last pushed: soccer's counts up and runs between pushes.
        let seconds: Int?
        let complete: Bool
        /// Each period's score in `teams` order (volleyball's sets); empty for an old read.
        let periods: [[Int]]
        /// When the server last wrote it: a clock older than `staleAfter` is hidden, not frozen, and a
        /// score older than `quietAfter` no longer says Live (a weather delay, a feed gone quiet).
        let at: Date?
        /// Football's down, distance and spot (game-card 08); nil for every other sport and between plays
        /// SIDEARM doesn't give one (a kickoff, an extra point).
        let drive: Drive?
        /// Basketball's quarters, or halves, as one bar (game-card 09); nil for any other sport and an old read.
        let bar: Bar?
        /// Basketball's fouls this quarter, or half, in `teams` order (game-card 09): the Bonus. Nil for any other
        /// sport, an old read, and a count from a period that is over.
        let fouls: [Int]?
        /// Penalty kicks that settled a tie (game-card 15); nil for any other read, and for one that doesn't read.
        let shootout: Shootout?
        /// The period being played, from 1: basketball's bar and hockey's power play count from it. Nil for any other sport.
        let periodNumber: Int?
        /// Hockey's saves and power plays (game-card 09); nil for any other sport and an old read.
        let ice: Ice?
        /// SIDEARM's own shots on goal in `teams` order, which come with the final; nil before it.
        let finalShots: [Int]?

        /// Hockey's plays the page counts, as `live_score.ice` keeps them (`private.sidearm_ice`), in SIDEARM's order.
        nonisolated struct Ice: Decodable, Hashable, Sendable {
            /// Each side's saves by play, in `teams` order.
            let saves: [[String]]
            /// Each power play's Start and End.
            let power: [Line]

            nonisolated struct Line: Decodable, Hashable, Sendable {
                /// The team with the extra skater: 0 for the first team (the host), 1 for the other.
                let side: Int
                let start: Bool
                /// The game's second, counting up over the three periods; nil in overtime, whose plays can say no clock.
                let at: Int?
            }
        }

        /// The power play on now (`Live.powerPlay`).
        nonisolated struct PowerPlay: Hashable, Sendable {
            /// The team with the extra skater, in `teams` order.
            let side: Int
            /// Seconds left of a minor's 2:00 by the clock as last sent, 0 past it (a major, which SIDEARM's words don't
            /// tell from a minor); nil when the clock can't say (overtime).
            let left: Int?
        }

        /// Shots on goal in `teams` order: SIDEARM's own with the final, else each side's saves and goals, which matched
        /// its totals on 18 of 20 sides of 10 real games and was 1 off on the other 2. Nil for any other sport.
        var shots: [Int]? {
            if let finalShots { return finalShots }
            guard let saves = ice?.saves, saves.count == 2 else { return nil }
            return [saves[0].count + score[0], saves[1].count + score[1]]
        }

        /// The game's second by the clock as last sent, which counts down from 20:00 in each of the three periods. Nil in
        /// overtime, whose length a push doesn't say.
        private var gameSecond: Int? {
            guard let periodNumber, (1...3).contains(periodNumber), let seconds else { return nil }
            return periodNumber * Self.hockeyPeriod - seconds
        }

        /// The power play on now, from SIDEARM's Start and End plays, the one running out first; nil at even strength.
        /// An End on a Start's own clock closes that Start: its penalty was matched by one on the other team, and the older
        /// one runs on (Bethel v UW-Superior, 2026-10-31). Any other End closes the oldest of that team's, the penalty
        /// that runs out first. A Start with no End in 5:00, the longest there is, was missed and is over.
        var powerPlay: PowerPlay? {
            guard let lines = ice?.power else { return nil }
            var open: [Ice.Line] = []
            for line in lines {
                if line.start { open.append(line); continue }
                let mine = open.indices.filter { open[$0].side == line.side }
                guard let oldest = mine.first, let newest = mine.last else { continue }
                open.remove(at: line.at != nil && open[newest].at == line.at ? newest : oldest)
            }
            let now = gameSecond
            guard let line = open.first(where: { line in
                guard let at = line.at, let now else { return true }
                return now - at < Self.longestPenalty
            }) else { return nil }
            guard let at = line.at, let now else { return PowerPlay(side: line.side, left: nil) }
            return PowerPlay(side: line.side, left: min(Self.minorPenalty, max(0, Self.minorPenalty - (now - at))))
        }

        /// A hockey period, a minor and a major, in seconds.
        private static let hockeyPeriod = 1200, minorPenalty = 120, longestPenalty = 300

        /// Basketball's periods as SIDEARM sends them (`private.sidearm_live`).
        nonisolated struct Bar: Hashable, Sendable {
            /// 1 for the first quarter or half; past `regulation` in overtime.
            let period: Int
            /// How many make the game: 4 quarters (CSB's women), 2 halves (SJU's men).
            let regulation: Int
            /// The period's length in seconds: 600 a quarter, 1200 a half, 300 an overtime.
            let length: Int

            /// One part per quarter or half, and one for overtime once it's on (a second refills it).
            var parts: Int { regulation + (period > regulation ? 1 : 0) }
            /// The part being played, from 0.
            var playing: Int { min(period, regulation + 1) - 1 }
            /// The quarter or half its fouls count in: overtime's count with the last one (the NCAA's rule).
            var foulPeriod: Int { min(period, regulation) }
        }

        /// How full each part of basketball's bar is, 0 to 1: the ones played full, the one being played as far as
        /// its clock has run as last sent (it stops on every whistle), the rest empty. None for any other sport.
        var barFill: [Double] {
            guard let bar else { return [] }
            let run = 1 - Double(seconds ?? bar.length) / Double(bar.length)
            return (0..<bar.parts).map { $0 < bar.playing ? 1 : $0 > bar.playing ? 0 : min(1, max(0, run)) }
        }

        /// That side is in the bonus: the other team's 5th foul of a quarter, or 7th of a half (the NCAA's rule).
        func inBonus(_ side: Int) -> Bool {
            guard let bar, let fouls, (0...1).contains(side) else { return false }
            return fouls[1 - side] >= (bar.regulation == 2 ? 7 : 5)
        }

        /// A live football game's situation as SIDEARM's newest play gives it (`private.sidearm_drive`): the
        /// down and distance, where the ball is, and who has it. Like SIDEARM's own scoreboard, it is the
        /// spot the newest play started from.
        nonisolated struct Drive: Decodable, Hashable, Sendable {
            let down: Int
            /// "7", or "Goal" inside the 10.
            let togo: String
            /// "GAC34": the side's letters and the yard line; "50" at midfield.
            let spot: String
            /// Who has the ball: 0 for the first team (the host), 1 for the other.
            let side: Int
            /// Yards from the host's goal line, 0 to 100; nil when the spot names neither team.
            let ball: Int?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                down = try c.decode(Int.self, forKey: .down)
                togo = try c.decode(String.self, forKey: .togo)
                spot = try c.decode(String.self, forKey: .spot)
                side = try c.decode(Int.self, forKey: .side)
                guard (1...4).contains(down), (0...1).contains(side), !togo.isEmpty, !spot.isEmpty else {
                    throw DecodingError.dataCorruptedError(forKey: .down, in: c, debugDescription: "a down")
                }
                ball = ((try? c.decodeIfPresent(Int.self, forKey: .ball)) ?? nil).flatMap { (0...100).contains($0) ? $0 : nil }
            }

            private enum CodingKeys: String, CodingKey { case down, togo, spot, side, ball }

            /// "2nd & 7 · GAC 34", "1st & Goal · SJU 3", "4th & 1 · 50".
            var line: String {
                let nth = ["1st", "2nd", "3rd", "4th"][down - 1]
                let letters = spot.prefix { $0.isLetter }, yard = spot.drop { $0.isLetter }
                return "\(nth) & \(togo) · \(letters.isEmpty ? String(yard) : "\(letters) \(yard)")"
            }

            /// Where the first down is, in yards from the host's goal line: the ball plus the distance toward
            /// the goal its team is going for. None at "& Goal", or without a ball.
            var firstDown: Int? {
                guard let ball, let yards = Int(togo) else { return nil }
                return min(100, max(0, side == 0 ? ball + yards : ball - yards))
            }

            /// "2nd and 7 on the GAC 34, Saint John's ball".
            func spoken(teams: [Team]) -> String {
                let words = line.replacingOccurrences(of: " & ", with: " and ").replacingOccurrences(of: " · ", with: " on the ")
                return teams.indices.contains(side) ? "\(words), \(teams[side].short) ball" : words
            }
        }

        static let staleAfter: TimeInterval = 120
        static let quietAfter: TimeInterval = 600

        func isLive(at now: Date) -> Bool { at.map { now.timeIntervalSince($0) < Self.quietAfter } ?? false }

        /// "Q3 · 4:12", or just the period once the clock is stale or the sport has none. Soccer's
        /// minute runs on from the last push ("2nd half · 67'", `minute(at:)`); football's and
        /// basketball's clocks stop on every whistle, so theirs shows as the scorer last sent it.
        func line(at now: Date) -> String {
            guard let clock, let at else { return period }
            if let minute = minute(at: now) { return "\(period) · \(minute)'" }
            return now.timeIntervalSince(at) < Self.staleAfter ? "\(period) · \(clock)" : period
        }

        /// Soccer's minute: it runs on from the last push, held at the end of the period that push was in
        /// through the break (45, 90, then each 10-minute overtime's end). Nil for a clock that isn't soccer's.
        func minute(at now: Date) -> Int? {
            guard clock?.hasSuffix("'") == true, let seconds, let at else { return nil }
            let minute = (seconds + Int(max(0, now.timeIntervalSince(at)))) / 60 + 1
            let end: Int? = switch period {
            case "1st half": 45
            case "2nd half": 90
            // SIDEARM's clock runs on from 90:00 through every overtime (guessed: no overtime seen yet).
            case "OT": 90 + 10 * max(1, (seconds - 5400 + 599) / 600)
            default: nil
            }
            return end.map { min(minute, $0) } ?? minute
        }

        /// The half is over: SIDEARM's clock stops at 45:00 and stays there until the second half starts
        /// (the NCAA's has no stoppage time: CSB's and SJU's files of 2026-10-24 ended halves at 45:00 and 90:00).
        var isHalftime: Bool { period == "1st half" && (seconds ?? 0) >= 2700 }

        private enum CodingKeys: String, CodingKey {
            case score, period, clock, seconds = "clock_s", complete, periods, at, drive, regulation, fouls, shootout, ice, shots
            case periodNumber = "period_n", length = "period_s"
        }

        /// The fouls as the server keeps them: the quarter or half, and each side's foul plays by id.
        private struct Fouls: Decodable { let period: Int; let ids: [[String]] }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            score = try c.decode([Int].self, forKey: .score)
            guard score.count == 2, score.allSatisfy({ $0 >= 0 }) else {
                throw DecodingError.dataCorruptedError(forKey: .score, in: c, debugDescription: "two scores")
            }
            period = try c.decode(String.self, forKey: .period)
            clock = (try? c.decodeIfPresent(String.self, forKey: .clock)) ?? nil
            seconds = (try? c.decodeIfPresent(Int.self, forKey: .seconds)) ?? nil
            complete = ((try? c.decodeIfPresent(Bool.self, forKey: .complete)) ?? nil) ?? false
            let periods = ((try? c.decodeIfPresent([[Int]].self, forKey: .periods)) ?? nil) ?? []
            self.periods = periods.count == 2 && periods[0].count == periods[1].count ? periods : []
            at = ((try? c.decodeIfPresent(String.self, forKey: .at)) ?? nil).flatMap { DateHelpers.timestamp($0) }
            // One that doesn't read is none: it never costs the score.
            drive = (try? c.decodeIfPresent(Drive.self, forKey: .drive)) ?? nil
            let int = { (key: CodingKeys) in ((try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil).flatMap { $0 > 0 ? $0 : nil } }
            if let period = int(.periodNumber), let regulation = int(.regulation), let length = int(.length) {
                bar = Bar(period: period, regulation: regulation, length: length)
            } else {
                bar = nil
            }
            // A count the server hasn't started over for this period yet is none, so no stale Bonus shows.
            let fouls = (try? c.decodeIfPresent(Fouls.self, forKey: .fouls)) ?? nil, period = bar?.foulPeriod
            self.fouls = fouls.flatMap { $0.ids.count == 2 && $0.period == period ? $0.ids.map(\.count) : nil }
            shootout = (try? c.decodeIfPresent(Shootout.self, forKey: .shootout)) ?? nil
            periodNumber = int(.periodNumber)
            ice = (try? c.decodeIfPresent(Ice.self, forKey: .ice)) ?? nil
            finalShots = ((try? c.decodeIfPresent([Int].self, forKey: .shots)) ?? nil).flatMap { $0.count == 2 ? $0 : nil }
        }
    }

    private enum CodingKeys: String, CodingKey { case sport, occasion, teams, final, live, plays }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sport = try c.decode(String.self, forKey: .sport)
        occasion = try c.decodeIfPresent(String.self, forKey: .occasion)
        teams = try c.decode([Team].self, forKey: .teams)
        let final = (try? c.decodeIfPresent([Int].self, forKey: .final)) ?? nil
        setScores(final: final, live: (try? c.decodeIfPresent(Live.self, forKey: .live)) ?? nil,
                  plays: ((try? c.decodeIfPresent([LenientItem<Play>].self, forKey: .plays)) ?? nil)?.compactMap(\.value) ?? [])
    }

    /// The same game with a realtime update's scores (`club_events.final_score`, `live_score`, `scoring_plays`).
    func with(final: [Int]?, live: Live?, plays: [Play]? = nil) -> Game {
        var game = self
        game.setScores(final: final, live: live, plays: plays ?? self.plays)
        return game
    }

    private mutating func setScores(final: [Int]?, live: Live?, plays: [Play]) {
        let final = final.flatMap { $0.count == 2 && $0.allSatisfy { $0 >= 0 } ? $0 : nil }
        self.final = final
        self.live = final == nil ? live : nil
        self.periods = live?.periods ?? []
        self.shootout = final.flatMap { $0[0] == $0[1] ? live?.shootout : nil }
        self.shots = live?.shots
        self.plays = plays.filter { $0.score.count == 2 && (0...1).contains($0.side) }
    }

    /// One element of a list that doesn't read is left out, not the whole list.
    nonisolated struct LenientItem<T: Decodable & Sendable>: Decodable, Sendable {
        let value: T?
        init(from decoder: Decoder) { value = try? T(from: decoder) }
    }

    /// The side with more, or on a tie the side that won on penalties, 0 or 1; nil before the final and on any other
    /// tie, which fades neither side.
    var winner: Int? {
        guard let final else { return nil }
        return final[0] == final[1] ? shootout?.winner : final[0] > final[1] ? 0 : 1
    }

    /// Volleyball keeps sets, not quarters or halves: its page draws them, and a set won is a moment.
    var isVolleyball: Bool { sport.localizedCaseInsensitiveContains("volleyball") }

    /// Soccer's page draws the minute in a ring and the scorers under the teams (game-card 09).
    var isSoccer: Bool { sport.localizedCaseInsensitiveContains("soccer") }

    /// Basketball's page draws its quarters as a bar, the Bonus and a faint court (game-card 09).
    var isBasketball: Bool { sport.localizedCaseInsensitiveContains("basketball") }

    /// Hockey's page draws a power-play bar, shots on goal and the rink's lines (game-card 09).
    var isHockey: Bool { sport.localizedCaseInsensitiveContains("hockey") }

    /// Our team, in `teams` order: the one around St. Joseph; when both are, or neither, the home team, first
    /// (Jesse, game-card 12). Its color is the page's Attend.
    var ours: Int { teams.count == 2 && !teams[0].local && teams[1].local ? 1 : 0 }

    /// Soccer's scorers under each team, in `teams` order (game-card 09): one line per player, in the order
    /// they first scored, their minutes after the name ("Hanson 23', 71'"); a goal SIDEARM names no one
    /// for is "Goal 23'". Kept after the final, as the plays are. None for any other sport.
    var scorers: [[String]] {
        guard isSoccer else { return [] }
        return [0, 1].map { side in
            var lines: [(name: String, minutes: [String])] = []
            for play in plays where play.side == side {
                let name = GameMoment.scorer(in: play.text) ?? "Goal"
                if let i = lines.firstIndex(where: { $0.name == name }) {
                    lines[i].minutes += [play.clock].compactMap { $0 }
                } else {
                    lines.append((name, [play.clock].compactMap { $0 }))
                }
            }
            return lines.map { ([$0.name] + [$0.minutes.joined(separator: ", ")].filter { !$0.isEmpty }).joined(separator: " ") }
        }
    }

    /// Volleyball's sets, each one's points in `teams` order (game-card 09): the chips under its logos.
    /// None for any other sport, whose periods are quarters and halves.
    var sets: [[Int]] {
        guard isVolleyball, periods.count == 2 else { return [] }
        return zip(periods[0], periods[1]).map { [$0, $1] }
    }

    /// The set being played, by its place in `sets`: the newest while the match is on; none before, once
    /// SIDEARM says it's complete, after the final, and between sets, when the sets won (volleyball's
    /// score) count every set listed.
    var setPlaying: Int? {
        guard let live, !live.complete, live.score.reduce(0, +) < sets.count else { return nil }
        return sets.count - 1
    }

    nonisolated struct Team: Decodable, Hashable, Sendable {
        let name: String
        /// As neighbours say it ("Gustavus", not "Gustavus Adolphus").
        let short: String
        /// The school's logo in Block Party's Storage; nil until one is found (BP app
        /// docs/plans/game-card): the card shows the first letter.
        let logo: URL?
        /// The school's color as 0xRRGGBB; nil until it's known, or misread.
        let rgb: UInt32?
        /// The team's uuid, what a follow keys it by (hello-drop 03); nil for an old read.
        var id: String? = nil
        /// A team around St. Joseph: only these have a page and a Follow.
        var local = false
        /// Up to three colours read from its logo, most used first.
        var colors: [UInt32] = []
        /// What neighbours call it ("Johnnies"); nil when it has none.
        var nickname: String? = nil

        /// The name the pill says: its nickname, else its short name.
        var called: String { nickname ?? short }

        private enum CodingKeys: String, CodingKey { case name, short, logo, color, id, local, colors, nickname }

        /// A logo or color that doesn't read is none: it never costs the card.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            short = (try? c.decodeIfPresent(String.self, forKey: .short)) ?? name
            logo = (try? c.decodeIfPresent(String.self, forKey: .logo)).flatMap(URL.init(string:))
            rgb = (try? c.decodeIfPresent(String.self, forKey: .color)).flatMap(Self.rgb(hex:))
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
            local = ((try? c.decodeIfPresent(Bool.self, forKey: .local)) ?? nil) ?? false
            colors = (((try? c.decodeIfPresent([String].self, forKey: .colors)) ?? nil) ?? []).compactMap(Self.rgb(hex:))
            nickname = (try? c.decodeIfPresent(String.self, forKey: .nickname)) ?? nil
        }

        /// The page and the Follow: a local team the server named.
        var hasPage: Bool { local && id != nil }

        /// "#C20430" as 0xC20430; nil for anything else.
        static func rgb(hex: String) -> UInt32? {
            guard hex.count == 7, hex.first == "#" else { return nil }
            return UInt32(hex.dropFirst(), radix: 16)
        }

        /// What the disc shows until the logo lands, or instead of one: the first letter.
        var initial: String { short.first(where: \.isLetter).map { String($0).uppercased() } ?? "" }
    }

    /// The card's title as VoiceOver says it, naming the teams the discs show: "Football,
    /// Saint John's versus Gustavus", and once it's over "Football, Saint John's 33, Concordia 23, final".
    /// While it's on: "Football, Saint John's 14, Concordia 7, Q3" (the chip before it says Live). Settled on
    /// penalties: "Soccer, Saint Ben's 1, Macalester 1, final, Saint Ben's wins 5 to 4 on penalties".
    var spoken: String {
        guard teams.count == 2 else { return sport }
        if let final {
            let score = "\(sport), \(teams[0].short) \(final[0]), \(teams[1].short) \(final[1]), final"
            guard let shootout else { return score }
            let won = shootout.winner
            return score + ", \(teams[won].short) wins \(shootout.score[won]) to \(shootout.score[1 - won]) on penalties"
        }
        if let live {
            return "\(sport), \(teams[0].short) \(live.score[0]), \(teams[1].short) \(live.score[1]), \(live.period)"
        }
        return "\(sport), \(teams.map(\.short).joined(separator: " versus "))"
    }

    /// Only a game with exactly two teams: anything else is no game, and the card stays a
    /// photo card.
    struct Lenient: Decodable, Hashable {
        let value: Game?
        init(from decoder: Decoder) {
            let game = try? Game(from: decoder)
            value = game?.teams.count == 2 ? game : nil
        }
    }
}

extension Game.Team {
    /// A team you follow, from its Following row, for its page (follows 05): the page reads the rest.
    init(followed row: FollowRow) {
        name = row.name
        short = row.name
        logo = row.picture.flatMap(URL.init(string:))
        rgb = nil
        id = row.targetId
        local = true
    }
}
