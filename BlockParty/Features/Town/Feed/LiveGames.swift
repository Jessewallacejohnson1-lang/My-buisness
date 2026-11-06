//
//  LiveGames.swift
//  Block Party — every game's newest score while it's played (BP app codebase-health-2 08).
//
//  The app holds one (`AppSession`). A screen that shows games holds them: the Town feed its list
//  while it's on screen, an Event page its Event while it's open, from whatever tab opened it. It
//  listens on the one `club_events` connection while a held game with no final is being played (its
//  score already coming, or on by its hours: a high school game on by its hours listens for nothing
//  for three hours, cheaper than the server marking which games will score), or while the map
//  follows every change, and never in the background. Each game's newest version is kept by its
//  Event id, and the Town card, the Event page and the map ask it for "this game now", so a card and
//  its page never disagree (game-card 03 and 05).
//

import Foundation

@MainActor @Observable
final class LiveGames {
    /// Each game's newest version by its Event id: from what screens held, and the scores that came in.
    private(set) var games: [String: Game] = [:]
    /// Listening now, for tests.
    @ObservationIgnored private(set) var listening = false

    /// What each screen holds, by the screen's name.
    @ObservationIgnored private var held: [String: [FeedCardItem]] = [:]
    /// The map, while it's open: every change on the connection.
    @ObservationIgnored private var follower: ((RealtimeClient.Change) -> Void)?
    @ObservationIgnored private var away = false
    /// Checks again when a held game's hours start or end, with no one touching the screen.
    @ObservationIgnored private var recheck: Task<Void, Never>?
    /// Turns the change stream on and off: the realtime connection, or a test's fake.
    @ObservationIgnored private var listen: (Bool) -> Void

    init(listen: @escaping (Bool) -> Void) {
        self.listen = listen
    }

    /// The app's: one `club_events` connection, signed in as the session's account (else the public key).
    /// Under DEBUG `-town-live`, a replayed game instead.
    convenience init(token: @escaping () async -> String?) {
        self.init(listen: { _ in })
        #if DEBUG
        if LaunchFlags.has(.townLive) {
            listen = { [weak self] on in if on { self?.replayLiveGame() } }
            return
        }
        #endif
        let client = RealtimeClient(table: "club_events", tokenProvider: token)
        client.onChange = { [weak self] change in self?.changed(change) }
        listen = { on in on ? client.start() : client.stop() }
    }

    /// A screen shows these Event cards (the Town feed's list while it's on screen, an open Event
    /// page's Event); none lets go. Each game's newer version is kept, and listening checked again.
    func hold(_ holder: String, _ cards: [FeedCardItem], at now: Date = Date()) {
        for card in cards {
            guard let game = card.game else { continue }
            let newer = Self.newer(games[card.id], game)
            if newer != games[card.id] { games[card.id] = newer }
        }
        let shown = cards.filter { game($0) != nil }
        held[holder] = shown.isEmpty ? nil : shown
        check(at: now)
    }

    /// The card's game as it is now: the newest score that came in, else the game it came with.
    func game(_ card: FeedCardItem) -> Game? {
        Self.newer(games[card.id], card.game)
    }

    /// The map, while it's open (nil once it closes): every change, on the same connection.
    func follow(_ handler: ((RealtimeClient.Change) -> Void)?, at now: Date = Date()) {
        follower = handler
        check(at: now)
    }

    /// The app went to the background (`true`) or came back.
    func away(_ away: Bool, at now: Date = Date()) {
        self.away = away
        check(at: now)
    }

    /// A change on the connection: a game something showed takes its row's new scores, and the map
    /// hears every change. A final may have been the last game playing.
    func changed(_ change: RealtimeClient.Change, at now: Date = Date()) {
        if change.kind == .update, let row = change.new, let id = row.id, let game = games[id] {
            let live = row.liveScore.flatMap { try? JSONDecoder().decode(Game.Live.self, from: $0) }
            let plays = row.scoringPlays.flatMap(Game.Play.list(from:))
            let scored = game.with(final: row.finalScore, live: live, plays: plays)
            if scored != game {
                games[id] = scored
                if scored.final != nil { check(at: now) }
            }
        }
        follower?(change)
    }

    /// The newer of `kept` and `other`: the one with a final, else the one whose live score is later
    /// (one with no time is oldest). On a tie, `other`, the one that came in last (a corrected final, a
    /// logo found), unless `kept` has scoring plays it lacks: a change that only adds a play leaves the
    /// live score's time where it was.
    nonisolated static func newer(_ kept: Game?, _ other: Game?) -> Game? {
        guard let kept else { return other }
        guard let other else { return kept }
        if (kept.final == nil) != (other.final == nil) { return kept.final != nil ? kept : other }
        let (keptAt, otherAt) = (kept.live?.at ?? .distantPast, other.live?.at ?? .distantPast)
        if keptAt != otherAt { return otherAt > keptAt ? other : kept }
        return other.plays.count >= kept.plays.count ? other : kept
    }

    /// The held cards with their games as they are now, those without a final.
    private var unfinished: [FeedCardItem] {
        held.values.joined().compactMap { card in
            guard let game = game(card), game.final == nil else { return nil }
            var card = card
            card.game = game
            return card
        }
    }

    /// When listening may next change by the clock alone: the soonest start or end still to come of
    /// a held game's hours (a game runs three hours), for one whose score isn't coming yet.
    func nextCheck(at now: Date) -> Date? {
        unfinished.filter { $0.game?.live == nil }
            .compactMap { card in card.when.flatMap { when in [when.start, when.end].first { $0 > now } } }
            .min()
    }

    /// On while a held game with no final is being played, or the map follows; never while away. A
    /// page opened before kickoff checks again at kickoff, and once more when the game's hours end.
    private func check(at now: Date) {
        let playing = unfinished.contains { $0.game?.live != nil || (!$0.cancelled && $0.when?.isOn(now) == true) }
        let on = !away && (playing || follower != nil)
        if on != listening {
            listening = on
            listen(on)
        }
        recheck?.cancel()
        recheck = away ? nil : nextCheck(at: now).map { next in
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.check(at: Date())
            }
        }
    }

    #if DEBUG
    @ObservationIgnored private var replaying = false

    /// `-town-live` (with `-town-samples -town-games`): SJU vs Gustavus is on today, and its score,
    /// scoring plays and down and distance (game-card 08) change every 4 seconds as realtime changes, through
    /// the same path a real one takes, to its final. The plays' names are made up. With `-town-volleyball`, CSB vs
    /// Carleton plays from late in its third set to a 3-2 final instead, its sets kept past it; with `-town-soccer`,
    /// SJU vs Augsburg from the 38th minute through halftime and three goals to a 2-1 final; with `-town-basketball`,
    /// CSB vs Loras from late in the 2nd quarter, through both teams' bonus and overtime, to a 52-48 final; with
    /// `-town-hockey`, SJU vs St. Olaf through a power play each, a major and overtime, to a 3-2 final (game-card 09);
    /// with `-town-shootout`, Saint Ben's vs Macalester level through overtime to a 1-1 final won on penalties (game-card 15).
    private func replayLiveGame() {
        guard !replaying else { return }
        replaying = true
        let volleyball = LaunchFlags.has(.townVolleyball), soccer = LaunchFlags.has(.townSoccer)
        let basketball = LaunchFlags.has(.townBasketball), shootout = LaunchFlags.has(.townShootout)
        let hockey = LaunchFlags.has(.townHockey)
        let id = volleyball ? "v1" : soccer ? "s1" : basketball ? "b1" : hockey ? "h1" : shootout ? "p1" : "g1"
        // Each step: the score, period and clock, and the scoring play that made it (none at kickoff).
        let football: [(String, String?)] = [
            (#"[0,0],"period":"Q1","clock":"15:00","drive":{"down":1,"togo":"10","spot":"SJU25","side":0,"ball":25}"#, nil),
            (#"[7,0],"period":"Q1","clock":"9:18","drive":{"down":1,"togo":"10","spot":"GAC25","side":1,"ball":75}"#, #"{"id":"1","text":"Feeney,Trey left pass complete to Kern,Cole for 9 yards to the GAC00, TOUCHDOWN.","period":"Q1","clock":"9:18","side":0,"score":[7,0]}"#),
            (#"[7,3],"period":"Q2","clock":"0:03","drive":{"down":1,"togo":"10","spot":"SJU25","side":0,"ball":25}"#, #"{"id":"2","text":"Lund,Tate field goal attempt from 34 GOOD.","period":"Q2","clock":"0:03","side":1,"score":[7,3]}"#),
            (#"[14,3],"period":"Q3","clock":"4:12","drive":{"down":2,"togo":"7","spot":"GAC34","side":0,"ball":66}"#, #"{"id":"3","text":"Feeney,Trey middle pass complete to Jeffrey,Jack for 52 yards to the GAC00, TOUCHDOWN.","period":"Q3","clock":"4:12","side":0,"score":[14,3]}"#),
            (#"[14,10],"period":"Q4","clock":"6:05","drive":{"down":3,"togo":"4","spot":"SJU41","side":0,"ball":41}"#, #"{"id":"4","text":"Sieben,Jack left pass complete to Moen,Alex for 7 yards to the SJU00, TOUCHDOWN.","period":"Q4","clock":"6:05","side":1,"score":[14,10]}"#),
            (#"[21,10],"period":"Q4","clock":"0:45","drive":{"down":1,"togo":"10","spot":"GAC25","side":1,"ball":75}"#, #"{"id":"5","text":"Feeney,Trey right pass complete to Berg,Sam for 18 yards to the GAC00, TOUCHDOWN.","period":"Q4","clock":"0:45","side":0,"score":[21,10]}"#),
        ]
        // Sets won, the set, and each set's points; SIDEARM adds a set's column when it starts, so a set
        // won shows on its own before the next begins.
        let sets: [(String, String?)] = [
            (#"[1,1],"period":"Set 3","periods":[[25,23,18],[21,25,14]]"#, nil),
            (#"[1,1],"period":"Set 3","periods":[[25,23,24],[21,25,19]]"#, nil),
            (#"[2,1],"period":"Set 3","periods":[[25,23,25],[21,25,19]]"#, nil),
            (#"[2,1],"period":"Set 4","periods":[[25,23,25,0],[21,25,19,0]]"#, nil),
            (#"[2,1],"period":"Set 4","periods":[[25,23,25,16],[21,25,19,20]]"#, nil),
            (#"[2,2],"period":"Set 4","periods":[[25,23,25,22],[21,25,19,25]]"#, nil),
            (#"[2,2],"period":"Set 5","periods":[[25,23,25,22,0],[21,25,19,25,0]]"#, nil),
            (#"[2,2],"period":"Set 5","periods":[[25,23,25,22,9],[21,25,19,25,7]]"#, nil),
            (#"[2,2],"period":"Set 5","periods":[[25,23,25,22,14],[21,25,19,25,12]]"#, nil),
        ]
        // The minute as SIDEARM pushes it: the clock in seconds, stopped at 45:00 through halftime.
        let halves: [(String, String?)] = [
            (#"[0,0],"period":"1st half","clock":"38'","clock_s":2230"#, nil),
            (#"[1,0],"period":"1st half","clock":"41'","clock_s":2410"#, #"{"id":"1","text":"Shot by SJU Hanson,Ben, top left, GOAL","period":"1st half","clock":"41'","side":0,"score":[1,0]}"#),
            (#"[1,0],"period":"1st half","clock":"46'","clock_s":2700"#, nil),
            (#"[1,0],"period":"2nd half","clock":"46'","clock_s":2700"#, nil),
            (#"[1,1],"period":"2nd half","clock":"58'","clock_s":3430"#, #"{"id":"2","text":"Shot by AUG Larkin,Sam, GOAL","period":"2nd half","clock":"58'","side":1,"score":[1,1]}"#),
            (#"[2,1],"period":"2nd half","clock":"71'","clock_s":4210"#, #"{"id":"3","text":"Shot by SJU Hanson,Ben, low right, GOAL","period":"2nd half","clock":"71'","side":0,"score":[2,1]}"#),
            (#"[2,1],"period":"2nd half","clock":"90'","clock_s":5350"#, nil),
        ]
        // The clock as last sent, the period and its length, and each team's fouls this quarter by play id
        // (overtime's counting with the 4th); SIDEARM's words for the baskets, the names made up.
        func quarter(_ score: String, _ q: Int, _ clock: Int, fouls: (Int, Int, Int)) -> String {
            let ids = { (side: String, n: Int) in "[" + (0..<n).map { #""\#(side)\#(q)-\#($0)""# }.joined(separator: ",") + "]" }
            return #"\#(score),"period":"\#(q > 4 ? "OT" : "Q\(q)")","clock":"\#(clock / 60):\#(String(format: "%02d", clock % 60))","#
                + #""clock_s":\#(clock),"period_n":\#(q),"regulation":4,"period_s":\#(q > 4 ? 300 : 600),"#
                + #""fouls":{"period":\#(fouls.0),"ids":[\#(ids("c", fouls.1)),\#(ids("l", fouls.2))]}"#
        }
        let basket = { (id: Int, text: String, period: String, clock: String, side: Int, score: String) in
            #"{"id":"\#(id)","text":"\#(text)","period":"\#(period)","clock":"\#(clock)","side":\#(side),"score":\#(score)}"#
        }
        let quarters: [(String, String?)] = [
            (quarter("[30,27]", 2, 228, fouls: (2, 2, 4)), nil),
            (quarter("[33,27]", 2, 192, fouls: (2, 2, 5)), basket(1, "5 Jo Rohe 3PTR GOOD (11 Pt)", "Q2", "3:12", 0, "[33,27]")),
            (quarter("[33,29]", 2, 144, fouls: (2, 3, 5)), basket(2, "14 Ella Lindqvist LAYUP GOOD (8 Pt)", "Q2", "2:24", 1, "[33,29]")),
            (quarter("[35,29]", 2, 90, fouls: (2, 3, 6)), basket(3, "21 Anna Moore JUMPER GOOD (8 Pt)", "Q2", "1:30", 0, "[35,29]")),
            (quarter("[35,29]", 3, 600, fouls: (3, 0, 0)), nil),
            (quarter("[35,32]", 3, 401, fouls: (3, 5, 1)), basket(4, "3 Kate Hanna 3PTR GOOD (5 Pt)", "Q3", "6:41", 1, "[35,32]")),
            (quarter("[44,44]", 4, 0, fouls: (4, 2, 5)), nil),
            (quarter("[44,44]", 5, 300, fouls: (4, 2, 5)), nil),
            (quarter("[48,46]", 5, 151, fouls: (4, 3, 5)), basket(5, "5 Jo Rohe LAYUP GOOD (19 Pt)", "OT", "2:31", 0, "[48,46]")),
            // A sixth basket: the list keeps the newest 5.
            (quarter("[50,46]", 5, 64, fouls: (4, 3, 5)), basket(6, "21 Anna Moore LAYUP GOOD (10 Pt)", "OT", "1:04", 0, "[50,46]")),
        ]
        // Saint Ben's vs Macalester's real plays, then the clock running out on the second overtime.
        let overtime: [(String, String?)] = [
            (#"[1,1],"period":"OT","clock":"100'","clock_s":5990"#, #"{"id":"45","text":"Shot by MAC Arredondo,Ava, low right, GOAL","period":"1st half","clock":"19'","side":1,"score":[0,1]}"#),
            (#"[1,1],"period":"OT","clock":"105'","clock_s":6290"#, #"{"id":"73","text":"Shot by CSB Warren,Veronica, high right, GOAL","period":"1st half","clock":"29'","side":0,"score":[1,1]}"#),
            (#"[1,1],"period":"OT","clock":"107'","clock_s":6410"#, nil),
            (#"[1,1],"period":"OT","clock":"108'","clock_s":6470"#, nil),
            (#"[1,1],"period":"OT","clock":"109'","clock_s":6530"#, nil),
            (#"[1,1],"period":"OT","clock":"110'","clock_s":6590"#, nil),
        ]
        // The draft's game: the score, the rink's clock, each side's saves, and the power-play lines so far.
        let rink = { (score: String, period: Int, clock: Int, saves: (Int, Int), power: [(Int, Bool, Int?)]) -> String in
            let ids = { (n: Int) in "[" + (0..<n).map { #""\#($0)""# }.joined(separator: ",") + "]" }
            let lines = power.map { #"{"side":\#($0.0),"start":\#($0.1),"at":\#($0.2.map(String.init) ?? "null")}"# }.joined(separator: ",")
            return #"\#(score),"period":"\#(period > 3 ? "OT" : "P\(period)")","clock":"\#(clock / 60):\#(String(format: "%02d", clock % 60))","clock_s":\#(clock),"period_n":\#(period),"ice":{"saves":[\#(ids(saves.0)),\#(ids(saves.1))],"power":[\#(lines)]}"#
        }
        // SJU's power plays at 12:40 and 9:07 of the 2nd, St. Olaf's at 6:40, SJU's major from 15:00 of the 3rd.
        let first: [(Int, Bool, Int?)] = [(0, true, 1640), (0, false, 1735)]
        let second = first + [(0, true, 1853)]
        let third = second + [(0, false, 1973), (1, true, 2000)]
        let fourth = third + [(1, false, 2120), (0, true, 2700)]
        let periods: [(String, String?)] = [
            (rink("[0,0]", 1, 1200, (0, 0), []), nil),
            (rink("[1,0]", 1, 913, (4, 2), []), basket(1, "Goal by SJU Thoreson,Evan (EVEN STRENGTH); Assist by Burke,Sam.", "P1", "15:13", 0, "[1,0]")),
            (rink("[1,1]", 1, 478, (11, 7), []), basket(2, "Goal by OLF Lind,Carter (EVEN STRENGTH).", "P1", "7:58", 1, "[1,1]")),
            (rink("[1,1]", 2, 760, (16, 12), [(0, true, 1640)]), nil),
            (rink("[2,1]", 2, 665, (17, 13), first), basket(3, "Goal by SJU Burke,Sam (POWER-PLAY); Assist by Thoreson,Evan.", "P2", "11:05", 0, "[2,1]")),
            (rink("[2,1]", 2, 620, (18, 15), first), nil),
            (rink("[2,1]", 2, 547, (19, 16), second), nil),
            // The draft's moment: P2 · 8:31, 1:24 left, shots 24 and 19.
            (rink("[2,1]", 2, 511, (22, 18), second), nil),
            (rink("[2,1]", 2, 455, (23, 18), second), nil),
            (rink("[2,1]", 2, 400, (24, 19), third), nil),
            (rink("[2,1]", 2, 350, (24, 22), third), nil),
            (rink("[2,1]", 3, 900, (30, 24), fourth), nil),
            // Past 2:00 with no End: a major. The bar sits empty and the time goes.
            (rink("[2,1]", 3, 750, (33, 24), fourth), nil),
            (rink("[2,2]", 3, 400, (35, 24), fourth + [(0, false, 3000)]), basket(4, "Goal by OLF Lind,Carter (EVEN STRENGTH).", "P3", "6:40", 1, "[2,2]")),
            // Overtime: the clock can't say what's left.
            (rink("[2,2]", 4, 200, (37, 25), fourth + [(0, false, 3000), (1, true, nil)]), nil),
        ]
        let steps = volleyball ? sets : soccer ? halves : basketball ? quarters : hockey ? periods : shootout ? overtime : football
        // `club_events.live_score` as the realtime row carries it.
        let live = { (score: String, complete: Bool) in
            Data((#"{"score":"# + score + #","complete":\#(complete),"at":""# + DateHelpers.timestampString(.now) + #""}"#).utf8)
        }
        // The row's change: only its scores moved, so the map, following, reads nothing again for it.
        let send = { [weak self] (final: [Int]?, live: Data?, plays: [String]?) in
            let row = RealtimeClient.Change.Row(id: id, eventDate: nil, startTime: nil, status: nil, kind: nil,
                                                title: nil, location: nil, finalScore: final, liveScore: live,
                                                scoringPlays: plays.map { Data(("[" + $0.joined(separator: ",") + "]").utf8) })
            self?.changed(RealtimeClient.Change(kind: .update, new: row, old: row.withoutScores))
        }
        Task { @MainActor in
            var plays: [String] = []
            for (score, play) in steps {
                if let play { plays.append(play) }
                send(nil, live(score, false), plays)
                try? await Task.sleep(for: .seconds(4))
            }
            // The server keeps the last live score beside a final: volleyball's sets stay.
            if volleyball {
                send([3, 2], live(#"[3,2],"period":"Set 5","periods":[[25,23,25,22,15],[21,25,19,25,12]]"#, true), nil)
            } else if hockey {
                // SIDEARM's own shots come in the final's own write.
                send([3, 2], live(#"[3,2],"period":"OT","shots":[41,27]"#, true),
                     plays + [#"{"id":"5","text":"Goal by SJU Thoreson,Evan (EVEN STRENGTH, OVERTIME).","period":"OT","side":0,"score":[3,2]}"#])
            } else if shootout {
                // The kicks come in the final's own write.
                send([1, 1], live(#"[1,1],"period":"OT","shootout":{"score":[5,4],"who":"CSB"}"#, true), nil)
            } else {
                send(soccer ? [2, 1] : basketball ? [52, 48] : [21, 10], nil, nil)
            }
        }
    }
    #endif
}
