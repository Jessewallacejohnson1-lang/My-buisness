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
    /// (one with no time is oldest); `kept` on a tie, since a change that only adds a scoring play
    /// leaves the live score's time where it was.
    nonisolated static func newer(_ kept: Game?, _ other: Game?) -> Game? {
        guard let kept else { return other }
        guard let other else { return kept }
        if (kept.final == nil) != (other.final == nil) { return kept.final != nil ? kept : other }
        return (other.live?.at ?? .distantPast) > (kept.live?.at ?? .distantPast) ? other : kept
    }

    /// On while a held game with no final is being played, or the map follows; never while away.
    private func check(at now: Date) {
        let playing = held.values.joined().contains { card in
            guard let game = game(card), game.final == nil else { return false }
            return game.live != nil || card.isNow(at: now)
        }
        let on = !away && (playing || follower != nil)
        guard on != listening else { return }
        listening = on
        listen(on)
    }

    #if DEBUG
    @ObservationIgnored private var replaying = false

    /// `-town-live` (with `-town-samples -town-games`): SJU vs Gustavus is on today, and its score,
    /// scoring plays and down and distance (game-card 08) change every 4 seconds as realtime changes, through
    /// the same path a real one takes, to its final. The plays' names are made up. With `-town-volleyball`, CSB vs
    /// Carleton plays from late in its third set to a 3-2 final instead, its sets kept past it; with `-town-soccer`,
    /// SJU vs Augsburg from the 38th minute through halftime and three goals to a 2-1 final; with `-town-basketball`,
    /// CSB vs Loras from late in the 2nd quarter, through both teams' bonus and overtime, to a 52-48 final (game-card 09).
    private func replayLiveGame() {
        guard !replaying else { return }
        replaying = true
        let volleyball = LaunchFlags.has(.townVolleyball), soccer = LaunchFlags.has(.townSoccer)
        let basketball = LaunchFlags.has(.townBasketball)
        let id = volleyball ? "v1" : soccer ? "s1" : basketball ? "b1" : "g1"
        // Each step: the score, period and clock, and the scoring play that made it (none at kickoff).
        let football: [(String, String?)] = [
            (#"[0,0],"period":"Q1","clock":"15:00","drive":{"down":1,"togo":"10","spot":"SJU25","side":0,"ball":25}"#, nil),
            (#"[7,0],"period":"Q1","clock":"9:18","drive":{"down":1,"togo":"10","spot":"GAC25","side":1,"ball":75}"#, #"{"id":"1","text":"C. Kern 1 yd TD run (M. Olson kick)","period":"Q1","clock":"9:18","side":0,"score":[7,0]}"#),
            (#"[7,3],"period":"Q2","clock":"0:03","drive":{"down":1,"togo":"10","spot":"SJU25","side":0,"ball":25}"#, #"{"id":"2","text":"T. Lund 34 yd field goal","period":"Q2","clock":"0:03","side":1,"score":[7,3]}"#),
            (#"[14,3],"period":"Q3","clock":"4:12","drive":{"down":2,"togo":"7","spot":"GAC34","side":0,"ball":66}"#, #"{"id":"3","text":"J. Jeffrey 52 yd TD run (M. Olson kick)","period":"Q3","clock":"4:12","side":0,"score":[14,3]}"#),
            (#"[14,10],"period":"Q4","clock":"6:05","drive":{"down":3,"togo":"4","spot":"SJU41","side":0,"ball":41}"#, #"{"id":"4","text":"A. Moen 7 yd TD run (T. Lund kick)","period":"Q4","clock":"6:05","side":1,"score":[14,10]}"#),
            (#"[21,10],"period":"Q4","clock":"0:45","drive":{"down":1,"togo":"10","spot":"GAC25","side":1,"ball":75}"#, #"{"id":"5","text":"S. Berg 18 yd TD pass from C. Kern (M. Olson kick)","period":"Q4","clock":"0:45","side":0,"score":[21,10]}"#),
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
            (#"[1,0],"period":"1st half","clock":"41'","clock_s":2410"#, #"{"id":"1","text":"Goal by SJU Hanson,Ben, top left","period":"1st half","clock":"41'","side":0,"score":[1,0]}"#),
            (#"[1,0],"period":"1st half","clock":"46'","clock_s":2700"#, nil),
            (#"[1,0],"period":"2nd half","clock":"46'","clock_s":2700"#, nil),
            (#"[1,1],"period":"2nd half","clock":"58'","clock_s":3430"#, #"{"id":"2","text":"Goal by AUG Larkin,Sam","period":"2nd half","clock":"58'","side":1,"score":[1,1]}"#),
            (#"[2,1],"period":"2nd half","clock":"71'","clock_s":4210"#, #"{"id":"3","text":"Goal by SJU Hanson,Ben, low right","period":"2nd half","clock":"71'","side":0,"score":[2,1]}"#),
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
        let steps = volleyball ? sets : soccer ? halves : basketball ? quarters : football
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
            } else {
                send(soccer ? [2, 1] : basketball ? [52, 48] : [21, 10], nil, nil)
            }
        }
    }
    #endif
}
