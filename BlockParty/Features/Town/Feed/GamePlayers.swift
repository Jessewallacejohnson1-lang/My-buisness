//
//  GamePlayers.swift
//  Block Party — each player's stats on a college basketball game's page (BP app game-card 35)
//

import SwiftUI

/// "Player stats" under a basketball game's scoring plays: Apple's segmented control for the two teams, ours first, then
/// one team's players in Apple Sports' table (number, name and position, PTS, REB, AST, FG, 3PT), most points first, and
/// its totals. Jesse, 2026-11-18: "yes and each players stats", then "yes to all" to the mock
/// (`references/all-plays/mock.html`); the table's sizes are Apple Sports' (`references/all-plays/`, `as-3.jpg`).
struct GamePlayers: View {
    let game: Game
    /// Both teams' lines, in `teams` order.
    let boxes: [Game.Box]
    var top: CGFloat = 0

    @State private var side = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Apple Sports' rows: 30 pt, the totals 36 under a hairline, in a play's card 6 pt in from its top and 12 from its sides.
    static let rowHeight: CGFloat = 30
    static let totalHeight: CGFloat = 36
    static let cardInset = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    /// The number's column, then PTS, REB, AST, FG and 3PT's, as the mock has them.
    static let uniWidth: CGFloat = 28
    static let columns: [(title: String, width: CGFloat)] = [("PTS", 34), ("REB", 34), ("AST", 34), ("FG", 52), ("3PT", 48)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Player stats")
                .font(.displaySemi(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            Picker("Team", selection: $side) {
                ForEach(game.teams.indices, id: \.self) { k in Text(game.teams[k].short).tag(k) }
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: side)
            table(boxes[min(side, boxes.count - 1)])
                // The other team's table fades in where this one was, its height following.
                .id(side)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: side)
        .padding(.top, top)
    }

    private func table(_ box: Game.Box) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("#").frame(width: Self.uniWidth, alignment: .leading)
                Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Self.columns, id: \.title) { Text($0.title).frame(width: $0.width, alignment: .trailing) }
            }
            .font(.sans(12))
            .foregroundStyle(Hue.inkSecondary)
            .frame(height: Self.rowHeight)
            .accessibilityHidden(true)
            ForEach(Array(box.rows.enumerated()), id: \.offset) { _, line in
                row(line).frame(height: Self.rowHeight)
            }
            row(box.total, team: true)
                .frame(height: Self.totalHeight)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
                .padding(.top, 2)
        }
        .padding(Self.cardInset)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }

    private func row(_ line: Game.Box.Line, team: Bool = false) -> some View {
        let numbers = ["\(line.pts)", "\(line.reb)", "\(line.ast)", line.fg, line.tp]
        return HStack(spacing: 0) {
            Text(line.uni ?? "")
                .foregroundStyle(Hue.inkSecondary)
                .frame(width: Self.uniWidth, alignment: .leading)
            Group {
                if team {
                    Text("Team")
                } else {
                    Text("\(line.name ?? "") \(Text(line.pos ?? "").foregroundStyle(Hue.inkSecondary))")
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(numbers.enumerated()), id: \.offset) { k, number in
                Text(number)
                    .fontWeight(k == 0 || team ? .semibold : nil)
                    .frame(width: Self.columns[k].width, alignment: .trailing)
            }
        }
        .font(team ? .sansSemibold(15) : .sans(15))
        .monospacedDigit()
        .foregroundStyle(Hue.ink)
        // One line for VoiceOver: "L. Arnold, guard, 5 points, 1 rebound, 6 assists, 1 of 1 field goals, 1 of 1 threes".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(line, team: team))
    }

    nonisolated static func spoken(_ line: Game.Box.Line, team: Bool = false) -> String {
        let who = team ? ["Team"] : [line.name, line.pos.flatMap(position)].compactMap { $0 }
        let count = { (n: Int, one: String, many: String) in "\(n) \(n == 1 ? one : many)" }
        let of = { (ma: String, what: String) in ma.split(separator: "-").map(String.init).joined(separator: " of ") + " " + what }
        return (who + [count(line.pts, "point", "points"), count(line.reb, "rebound", "rebounds"),
                       count(line.ast, "assist", "assists"), of(line.fg, "field goals"), of(line.tp, "threes")])
            .joined(separator: ", ")
    }

    private nonisolated static func position(_ p: String) -> String? {
        switch p.uppercased() {
        case "G": "guard"
        case "F": "forward"
        case "C": "center"
        case "": nil
        default: p
        }
    }
}
