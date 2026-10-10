//
//  FeedCardMenu.swift
//  Block Party — a Town feed card's ••• sheet: why the card is there, a way to change
//  that, and for the admin the points behind its place (BP app docs/plans/town-feed,
//  ticket 18).
//
//  Instagram's ••• sheet is the Reference (BP app references/recipe-why-score/),
//  measured off its frames: grey groups 16pt in from each side with 16pt corners, 51pt
//  rows, a 22pt icon 20pt in and the label 22pt after it, 17pt text. The reason sits
//  right at the top, not behind its own row (Jesse, 2026-10-10). Not interested, Mute
//  and Report join as a group below it (tickets 21 and 22).
//
//  Apple's sheet carries it, so it drags down under the finger and can be stopped
//  halfway; a solid surface keeps iOS 26 and 27 alike.
//

import SwiftUI

struct FeedCardMenu: View {
    let why: String
    let score: FeedScore?

    @State private var height: CGFloat = 220
    @State private var editingInterests = false

    private enum Metric {
        static let rowHeight: CGFloat = 51
        static let rowLeading: CGFloat = 20
        static let iconGap: CGFloat = 22
        static let iconWidth: CGFloat = 22
        /// Below the system grabber, to the title's top.
        static let titleTop: CGFloat = 32
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Why you're seeing this")
                    .font(.sansSemibold(17))
                    .foregroundStyle(Hue.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(why)
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.top, Metric.titleTop)
            .padding(.bottom, 20)

            group {
                Button { editingInterests = true } label: {
                    HStack(spacing: Metric.iconGap) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.sans(20))
                            .frame(width: Metric.iconWidth)
                        Text("Edit your interests")
                            .font(.sans(17))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.sansSemibold(13))
                            .foregroundStyle(Hue.inkSecondary)
                    }
                    .foregroundStyle(Hue.ink)
                    .padding(.leading, Metric.rowLeading)
                    .padding(.trailing, 16)
                    .frame(minHeight: Metric.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }

            if let score {
                group { ScoreBox(score: score) }
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Hue.surface)
        .sheet(isPresented: $editingInterests) { FeedInterestEditorDestination() }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(Hue.fill)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }

    /// The line under the title, from `get_town_feed`'s reason code and the one name it
    /// needs. Working words from the recipe playground; Jesse writes the final ones.
    /// nil for a code this app has no words for, which leaves the card without its •••.
    static func line(reason: String, name: String?) -> String? {
        switch reason {
        case "new": return "New in town"
        case "friend": return name.map { "\($0) is going" }
        case "follow": return name.map { "You follow \($0)" }
        case "interest":
            let label = Interests.all.first { $0.id == name }?.label ?? name
            return label.map { "Matches \($0)" }
        case "popular": return "Popular in town"
        case "size": return "Big in town"
        case "today": return "Happening today"
        case "tomorrow": return "Happening tomorrow"
        case "soon": return "Coming up soon"
        default: return nil
        }
    }
}

/// Every term behind a card's place, for Jesse's account: lifts in points, then the
/// multipliers, the total and the spot. A term that changes nothing is greyed.
private struct ScoreBox: View {
    let score: FeedScore

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Score")
                Spacer()
                Text(Self.number(score.total))
            }
            .font(.sansSemibold(17))
            .foregroundStyle(Hue.ink)
            .padding(.bottom, 3)

            row("Start", "1", idle: false)
            row("Interests", "+" + Self.number(score.interest), idle: score.interest == 0)
            row("Friends going", "+" + Self.number(score.friend), idle: score.friend == 0)
            row("Follows", "+" + Self.number(score.follow), idle: score.follow == 0)
            row("Popular", "+" + Self.number(score.popular), idle: score.popular == 0)
            row("Size · " + (score.sizeStep == 3 ? "big" : score.sizeStep == 2 ? "medium" : "small"),
                "+" + Self.number(score.size), idle: score.size == 0)
            row("Soon · " + Self.number(score.daysAway) + " days", "×" + Self.number(score.soon),
                idle: score.soon == 1)
            row("Going or saved", "×" + Self.number(score.acted), idle: score.acted == 1)
            row(sameHost, "×" + Self.number(score.spacing), idle: score.spacing == 1)

            Rectangle().fill(Hue.hairline).frame(height: 1)
            Text("Spot \(score.spot) of \(score.of)" + (score.newSpot ? " · moved up as new" : ""))
                .font(.sans(13))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .monospacedDigit()
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    /// "Same host · 2nd from this host": the spacing halves for each earlier card from it.
    private var sameHost: String {
        let earlier = Int((log(score.spacing) / log(0.5)).rounded())
        guard earlier > 0 else { return "Same host" }
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        return "Same host · " + (ordinal.string(from: NSNumber(value: earlier + 1)) ?? "") + " from this host"
    }

    private func row(_ label: String, _ value: String, idle: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(Hue.inkSecondary)
            Spacer()
            Text(value).foregroundStyle(Hue.ink)
        }
        .font(.sans(13))
        .opacity(idle ? 0.45 : 1)
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
