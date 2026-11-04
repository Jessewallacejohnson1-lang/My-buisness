//
//  GameMoment.swift
//  Block Party — a live game's moments: when a scoring play lands while its card or Event page is on
//  screen, the line under the score says what happened for 3 s, and that team's logo pops.
//
//  BP app docs/plans/game-card, ticket 07 (Jesse, 2026-10-29: "when teams score ... someone gets a
//  touchdown ... just kind of pop up ... super simple, clean, very Apple-like"; mock
//  `references/live-moments/mock.html`). The number rolling is the live score's own numericText.
//

import SwiftUI

/// One moment worth a beat: what happened, one detail, and whose it was.
nonisolated struct GameMoment: Equatable, Sendable {
    /// The play's id ("set-2" for a set), so a moment plays once.
    let id: String
    /// "Touchdown", "Field goal", "Safety", "Goal", "Set 2".
    let label: String
    /// The scorer's last name ("Jeffrey"), the kicker and yards ("Lund, 41 yd"), a set's winner; none
    /// when SIDEARM's words don't give one.
    let detail: String?
    /// 0 for the first team (the host), 1 for the other: its logo pops.
    let side: Int

    /// What a realtime update brought, or nil for a quiet one: an extra point, a basket, the clock, the
    /// final (which has its own look), and the first read of a game. Nor a read that comes after the
    /// app was away (its feed read again on return, or pulled): its last update is more than a stale
    /// clock's two minutes on from the one on screen, so a touchdown missed meanwhile isn't replayed.
    static func between(_ old: Game, _ new: Game) -> GameMoment? {
        guard new.final == nil, let live = new.live else { return nil }
        if let before = old.live?.at, let now = live.at, now.timeIntervalSince(before) > Game.Live.staleAfter { return nil }
        if let play = new.plays.last, !old.plays.contains(where: { $0.id == play.id }) {
            return of(play, sport: new.sport)
        }
        // SIDEARM keeps each period's score for every sport; only volleyball's are sets.
        guard new.isVolleyball else { return nil }
        return setWon(old.periods, new.periods, teams: new.teams)
    }

    /// A scoring play in SIDEARM's words: football's touchdown, field goal and safety, and a goal;
    /// anything else that scored (an extra point, a two-point try, a basket) stays quiet.
    static func of(_ play: Game.Play, sport: String) -> GameMoment? {
        let text = play.text, sport = sport.lowercased()
        let label: String
        var detail = scorer(in: text)
        if ["soccer", "hockey", "lacrosse"].contains(where: sport.contains) {
            label = "Goal"
        } else if sport.contains("football") {
            if text.range(of: #"\bTD\b|touchdown"#, options: [.regularExpression, .caseInsensitive]) != nil {
                label = "Touchdown"
            } else if text.range(of: "field goal", options: .caseInsensitive) != nil {
                label = "Field goal"
                // "Hansen,Matt field goal attempt from 39 GOOD." or "T. Lund 41 yd field goal": the kick's length beside the kicker.
                if let yards = capture(#"from (\d+) GOOD|(\d+) ?(?:yd|yards?)\b"#, in: text) {
                    detail = [detail, "\(yards) yd"].compactMap { $0 }.joined(separator: ", ")
                }
            } else if text.range(of: "safety", options: .caseInsensitive) != nil {
                label = "Safety"
            } else {
                return nil
            }
        } else {
            return nil
        }
        return GameMoment(id: play.id, label: label, detail: detail, side: play.side)
    }

    /// A play card's two lines (BP app game-card 14, the drafts' words): "Goal · Benson 39'" over "Assist: Holden",
    /// "Hansen 39 yd field goal" and "Driste 3-pointer" over the clock. Read from SIDEARM's live words, seen on real
    /// games; anything else stays as SIDEARM sent it, over the clock, since a wrong name is worse than its words.
    static func words(of play: Game.Play, sport: String) -> (title: String, detail: String) {
        let sport = sport.lowercased()
        if sport.contains("soccer"), let goal = goal(in: play) { return goal }
        let title = sport.contains("football") ? footballTitle(play.text) : sport.contains("basketball") ? basketballTitle(play.text) : nil
        return (title ?? play.text, play.when)
    }

    /// "Shot by SJU Benson,Soren, high left, GOAL; Assist by SJU Holden,Laird", "Penalty kick taken by Cornett,Billy,
    /// GOAL", and "Shot by CSB , GOAL" before SIDEARM has the name.
    private static func goal(in play: Game.Play) -> (title: String, detail: String)? {
        let text = play.text
        guard text.range(of: #"^(Shot by|Penalty kick taken by) .*\bGOAL\b"#, options: .regularExpression) != nil else { return nil }
        let assists = groups(#"Assist by \S+ \#(name),"#, in: text, all: true)
        let detail = text.hasPrefix("Penalty") ? "Penalty kick" : assists.isEmpty ? play.period : "Assist: " + assists.joined(separator: ", ")
        let who = (scorer(in: text).map { "Goal · \($0)" } ?? "Goal")
        return ([who, play.clock].compactMap { $0 }.joined(separator: " "), detail)
    }

    /// "Hansen,Matt field goal attempt from 39 GOOD.", "Hansen,Matt kick attempt good.", and a touchdown pass by its
    /// catcher: "Feeney,Trey middle pass complete to Melvin Jr.,Sedric for 3 yards to the GAC00, TOUCHDOWN."
    private static func footballTitle(_ text: String) -> String? {
        let kick = groups(#"^\#(name),[^,]* field goal attempt from (\d+) GOOD"#, in: text)
        if kick.count == 2 { return "\(kick[0]) \(kick[1]) yd field goal" }
        let point = groups(#"^\#(name),[^,]* kick attempt good"#, in: text)
        if let kicker = point.first { return "\(kicker) extra point" }
        let pass = groups(#"complete to \#(name),.* for (\d+) yards?\b.*TOUCHDOWN"#, in: text)
        return pass.count == 2 ? "\(pass[0]) \(pass[1]) yd TD pass" : nil
    }

    /// "5 Megan Driste 3PTR GOOD (3 Pt); 1 Lauren Arnold Assist (2 Asst)": the name, then the shot in capitals.
    private static func basketballTitle(_ text: String) -> String? {
        let read = groups(#"^\S+ (.+?) ([A-Z0-9][A-Z0-9 \-]*) GOOD \("#, in: text)
        guard read.count == 2, let last = read[0].split(separator: " ").last else { return nil }
        let shot = ["3PTR": "3-pointer", "FT": "free throw", "PULL UP": "pull-up"][read[1]] ?? read[1].lowercased()
        return "\(last) \(shot)"
    }

    /// A last name as SIDEARM writes it before the comma, "Jr." kept.
    private static let name = #"([A-Z][A-Za-z'’\-]+(?: (?:Jr|Sr)\.| (?:II|III|IV))?)"#

    /// The player a play is about, by last name: the catch's on a pass ("Kern,Cole pass complete to
    /// Berg,Sam"), else the first "Last,First" (SIDEARM's live words), else "J. Jeffrey" (its summary's).
    /// None beats a wrong name.
    static func scorer(in text: String) -> String? {
        capture("complete to \(name),", in: text)
            ?? capture(#"\#(name),\s?[A-Z]"#, in: text)
            ?? capture(#"^[A-Z]\.\s?\#(name)"#, in: text)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        groups(pattern, in: text).first
    }

    /// The captured words of the pattern's first match, or the first capture of every match.
    private static func groups(_ pattern: String, in text: String, all: Bool = false) -> [String] {
        guard let regex = try? Regex(pattern) else { return [] }
        if all { return text.matches(of: regex).compactMap { $0.output.count > 1 ? $0.output[1].substring.map { String($0) } : nil } }
        guard let match = text.firstMatch(of: regex) else { return [] }
        return (1..<match.output.count).compactMap { match.output[$0].substring.map { String($0) } }
    }

    /// Volleyball keeps no plays: a set is won when the next one starts (SIDEARM adds its column).
    private static func setWon(_ old: [[Int]], _ new: [[Int]], teams: [Game.Team]) -> GameMoment? {
        guard old.count == 2, new.count == 2, !old[0].isEmpty, new[0].count == old[0].count + 1 else { return nil }
        let set = old[0].count - 1
        let points = [new[0][set], new[1][set]]
        guard points[0] != points[1], teams.count == 2 else { return nil }
        let side = points[0] > points[1] ? 0 : 1
        return GameMoment(id: "set-\(set + 1)", label: "Set \(set + 1)", detail: teams[side].short, side: side)
    }
}

/// The moment playing on one game view, and how many each side has had (what sets off a logo's pop).
nonisolated struct MomentState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case line
        case moment(GameMoment)
        /// The clock's words back on the moment's fill, just before the fill clears.
        case settling
    }

    var phase: Phase = .line
    var beats = [0, 0]

    var moment: GameMoment? { if case .moment(let m) = phase { m } else { nil } }
    var beat: Int { beats[0] &+ beats[1] }
}

extension EnvironmentValues {
    /// The moment playing on the game this view sits in (`playsMoments(of:)`).
    @Entry var gameMoment = MomentState()
}

extension View {
    /// Plays the game's moments for everything under it: a new scoring play while it's on screen
    /// shows for 3 s, and a newer one takes over at once.
    func playsMoments(of game: Game) -> some View { modifier(MomentPlayer(game: game)) }

    /// The team's logo bumps to 112% and back when a moment is its own (`Motion.select`'s spring).
    func momentPop(_ side: Int) -> some View { modifier(MomentPop(side: side)) }
}

private struct MomentPlayer: ViewModifier {
    let game: Game

    /// How long a moment stays (the mock's 3 s), then how long its fill outlasts its words.
    static let hold: Duration = .seconds(3)
    static let settle: Duration = .milliseconds(300)

    @State private var state = MomentState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.gameMoment, state)
            .onChange(of: game) { old, new in
                guard let moment = GameMoment.between(old, new) else { return }
                // Reduce Motion: it appears and goes at once (DESIGN.md's Motion), nothing grows or pops.
                withAnimation(reduceMotion ? nil : Motion.bentoExpand) {
                    state.phase = .moment(moment)
                    state.beats[moment.side] &+= 1
                }
            }
            .task(id: state.beat) {
                guard state.beat > 0 else { return }
                try? await Task.sleep(for: Self.hold)
                guard !Task.isCancelled else { return }
                // The clock's words come back on the fill, then the fill clears: never an empty capsule.
                withAnimation(reduceMotion ? nil : Motion.bentoExpand) { state.phase = .settling }
                try? await Task.sleep(for: Self.settle)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : Motion.smooth) { state.phase = .line }
            }
            // A moment left mid-hold (the Event page opened over it, the card scrolled off) is over:
            // coming back shows the line, not the rest of it again.
            .onDisappear { state.phase = .line }
    }
}

private struct MomentPop: ViewModifier {
    let side: Int

    @Environment(\.gameMoment) private var moments
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat(1), trigger: reduceMotion ? 0 : moments.beats[side]) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(CGFloat(1.12), duration: 0.17, spring: Spring(response: 0.32, dampingRatio: 0.72))
                    SpringKeyframe(CGFloat(1), spring: Spring(response: 0.32, dampingRatio: 0.72))
                }
            }
    }
}

/// The line under a live game's score, which becomes the moment: a capsule that grows in place
/// round "Touchdown Jeffrey" (the Dynamic Island's way), holds, and melts back into the line.
/// The line keeps its own place in the layout; the capsule floats over it and never pushes the
/// logos aside.
struct MomentLine<Line: View>: View {
    let style: MomentLineStyle
    @ViewBuilder var line: Line

    @Environment(\.gameMoment) private var moments
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let filled = moments.phase != .line
        line
            .font(style.font)
            .lineLimit(1)
            .padding(.horizontal, style.plain.padding)
            .frame(height: style.plain.height)
            .hidden()
            .overlay {
                ZStack {
                    if let moment = moments.moment {
                        words(moment).transition(.blurReplace)
                    } else {
                        line.transition(.blurReplace)
                    }
                }
                .font(style.font)
                // The words take their color with the fill, so the clock's white words never vanish
                // into a white capsule as the moment arrives.
                .animation(fillAnimation(filled)) {
                    $0.foregroundStyle(filled ? style.filled.words : style.plain.words)
                }
                .lineLimit(1)
                // The line fits where it sits, as its hidden copy does; the moment's words (and the line
                // back on the fill) take the width they need, past the line's own.
                .fixedSize(horizontal: filled, vertical: false)
                .padding(.horizontal, filled ? style.filled.padding : style.plain.padding)
                .frame(height: filled ? style.filled.height : style.plain.height)
                .background {
                    // The moment's fill comes in at once, as the Island's black does (a fill fading in
                    // with the growth read as a grey blob in the frames), and melts away when it ends.
                    ZStack {
                        Capsule().fill(style.plain.fill)
                        Capsule().fill(style.filled.fill)
                            .animation(fillAnimation(filled)) { $0.opacity(filled ? 1 : 0) }
                    }
                }
                // A moment arriving nudges the capsule up 8% as it grows.
                .keyframeAnimator(initialValue: CGFloat(1), trigger: reduceMotion ? 0 : moments.beat) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(CGFloat(1.08), duration: 0.12, spring: Spring(response: 0.3, dampingRatio: 0.6))
                        SpringKeyframe(CGFloat(1), spring: Spring(response: 0.3, dampingRatio: 0.6))
                    }
                }
            }
    }

    /// The fill and its words' color: in at once, out on the smooth curve; none under Reduce Motion.
    private func fillAnimation(_ filled: Bool) -> Animation? {
        reduceMotion ? nil : filled ? .easeOut(duration: 0.08) : Motion.smooth
    }

    private func words(_ moment: GameMoment) -> Text {
        // A long name would reach the logos: the moment's name alone, then.
        // ponytail: a character count stands in for measuring the words; measure if names still collide.
        guard let detail = moment.detail, moment.label.count + 1 + detail.count <= style.longest
        else { return Text(moment.label) }
        return Text("\(moment.label) \(Text(detail).font(style.detailFont).foregroundStyle(style.filled.detail))")
    }
}

/// How the line and its capsule look on each surface (the mock's two phones).
struct MomentLineStyle {
    /// The line's own fill, side padding, height (none: its words' own) and words' color.
    let plain: (fill: Color, padding: CGFloat, height: CGFloat?, words: Color)
    /// The moment's, and its detail's color.
    let filled: (fill: Color, padding: CGFloat, height: CGFloat, words: Color, detail: Color)
    let font: Font
    let detailFont: Font
    /// The most characters the moment and its detail take between the two logos.
    let longest: Int

    /// The white game card (06): grey words under the score; a moment is an ink capsule.
    static let onWhite = MomentLineStyle(plain: (.clear, 0, nil, Hue.inkSecondary),
                                         filled: (Hue.ink, 10, 26, Hue.surface, Hue.surface.opacity(0.62)),
                                         font: .sansSemibold(13), detailFont: .sans(13), longest: 24)
    /// On a game's dark Event page (ticket 08): the clock in plain white words; a moment is a white capsule.
    static let onNight = MomentLineStyle(plain: (.clear, 0, nil, .white.opacity(0.9)),
                                         filled: (.white.opacity(0.97), 10, 28, Hue.ink.onLightCanvas,
                                                  Hue.inkSecondary.onLightCanvas),
                                         font: .sansMedium(16), detailFont: .sans(16), longest: 16)
    /// Inside soccer's minute ring (game-card 09): the minute in the draft's bold white; a goal is the same
    /// white capsule, over the ring.
    static let inRing = MomentLineStyle(plain: (.clear, 0, nil, .white), filled: onNight.filled,
                                        font: .sansBold(17), detailFont: .sans(17), longest: 16)
}
