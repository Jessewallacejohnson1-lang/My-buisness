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
nonisolated struct GameMoment: Hashable, Sendable {
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
    /// final (which has its own look), and the first read of a game, so opening the app replays nothing.
    static func between(_ old: Game, _ new: Game) -> GameMoment? {
        guard new.final == nil, new.live != nil else { return nil }
        if let play = new.plays.last, !old.plays.contains(where: { $0.id == play.id }) {
            return of(play, sport: new.sport)
        }
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
                // "T. Lund 41 yd field goal": the kick's length beside the kicker.
                if let yards = capture(#"(\d+) ?(?:yd|yards?)\b"#, in: text) {
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

    /// The player a play is about, by last name: the catch's on a pass ("Kern,Cole pass complete to
    /// Berg,Sam"), else the first "Last,First" (SIDEARM's live words), else "J. Jeffrey" (its summary's).
    /// SIDEARM's football words are unseen until a real game (BP app game-card 07); none beats a wrong name.
    static func scorer(in text: String) -> String? {
        let name = #"([A-Z][A-Za-z'’\-]+)"#
        return capture("complete to \(name),", in: text)
            ?? capture(#"\#(name),\s?[A-Z]"#, in: text)
            ?? capture(#"^[A-Z]\.\s?\#(name)"#, in: text)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? Regex(pattern), let match = text.firstMatch(of: regex),
              match.output.count > 1, let found = match.output[1].substring else { return nil }
        return String(found)
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
                withAnimation(reduceMotion ? Motion.smooth : Motion.bentoExpand) {
                    state.phase = .moment(moment)
                    state.beats[moment.side] &+= 1
                }
            }
            .task(id: state.beat) {
                guard state.beat > 0 else { return }
                try? await Task.sleep(for: Self.hold)
                guard !Task.isCancelled else { return }
                // The clock's words come back on the fill, then the fill clears: never an empty capsule.
                withAnimation(reduceMotion ? Motion.smooth : Motion.bentoExpand) { state.phase = .settling }
                try? await Task.sleep(for: Self.settle)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.smooth) { state.phase = .line }
            }
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
                .foregroundStyle(filled ? style.filled.words : style.plain.words)
                .lineLimit(1)
                // The line fits where it sits, as its hidden copy does; the moment's words (and the line
                // back on the fill) take the width they need, past the line's own.
                .fixedSize(horizontal: filled, vertical: false)
                .padding(.horizontal, filled ? style.filled.padding : style.plain.padding)
                .frame(height: filled ? style.filled.height : style.plain.height)
                .background(filled ? style.filled.fill : style.plain.fill, in: Capsule())
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

    private func words(_ moment: GameMoment) -> Text {
        guard let detail = moment.detail else { return Text(moment.label) }
        return Text("\(moment.label) \(Text(detail).font(style.detailFont).foregroundStyle(style.filled.detail))")
    }
}

/// How the line and its capsule look on each surface (the mock's two phones).
struct MomentLineStyle {
    /// The line's own fill, side padding, height and words' color.
    let plain: (fill: Color, padding: CGFloat, height: CGFloat, words: Color)
    /// The moment's, and its detail's color.
    let filled: (fill: Color, padding: CGFloat, height: CGFloat, words: Color, detail: Color)
    let font: Font
    let detailFont: Font

    /// The white game card (06): grey words under the score; a moment is an ink capsule.
    static let onWhite = MomentLineStyle(plain: (.clear, 0, 16, Hue.inkSecondary),
                                         filled: (Hue.ink, 10, 26, Hue.surface, Hue.surface.opacity(0.62)),
                                         font: .sansSemibold(13), detailFont: .sans(13))
    /// On team colors (the Event page's band, the card before 06): the clear pill; a moment is white.
    static let onColor = MomentLineStyle(plain: (.white.opacity(0.22), 9, 22, .white),
                                         filled: (.white.opacity(0.97), 9, 24, Hue.ink.onLightCanvas,
                                                  Hue.inkSecondary.onLightCanvas),
                                         font: .sansSemibold(12), detailFont: .sans(12))
}
