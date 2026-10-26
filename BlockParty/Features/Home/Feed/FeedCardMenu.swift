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
//  and Report join as a group below it (tickets 21 and 22). A card showing a photo Block
//  Party saved of its place starts that group with a red Report photo (BP app place-photos
//  06), which opens the neighbour's mail app on an email to Block Party.
//
//  Apple's sheet carries it, so it drags down under the finger and can be stopped
//  halfway; a solid surface keeps iOS 26 and 27 alike.
//
//  Not interested and Mute (ticket 21, mock https://claude.ai/artifact/HAJWN4Zj2Xh4wAeJA5UNcg)
//  sit in their own group under Edit your interests, Instagram's crossed-out eye beside the
//  first. Either closes the sheet; the card goes once it has closed (`FeedCardMenuSheet`).
//

import SwiftUI

struct FeedCardMenu: View {
    let why: String
    let score: FeedScore?
    var report: PhotoReport? = nil
    /// The host Mute names; nil, no Mute (a neighbour's own posting names none).
    var hostName: String? = nil
    /// Not interested (false) or Mute (true); nil, neither row (signed out, or off the Town feed).
    var onHide: ((Bool) -> Void)? = nil

    @State private var height: CGFloat = 220
    @State private var editingInterests = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

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

            if let onHide {
                group {
                    VStack(spacing: 0) {
                        // `menu-not-interested`
                        hideRow("eye.slash", "Not interested") { onHide(false) }
                        if let hostName {
                            // `menu-mute`
                            hideRow("speaker.slash", "Mute \(hostName)") { onHide(true) }
                        }
                    }
                }
                .padding(.top, 12)
            }

            if let report {
                group {
                    Button {
                        dismiss()
                        openURL(report.mail)
                    } label: {
                        HStack(spacing: Metric.iconGap) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.sans(20))
                                .frame(width: Metric.iconWidth)
                            Text("Report photo")
                                .font(.sans(17))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(Hue.report)
                        .padding(.leading, Metric.rowLeading)
                        .padding(.trailing, 16)
                        .frame(minHeight: Metric.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
                .padding(.top, 12)
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

    private func hideRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: Metric.iconGap) {
                Image(systemName: icon)
                    .font(.sans(20))
                    .frame(width: Metric.iconWidth)
                Text(title)
                    .font(.sans(17))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Hue.ink)
            .padding(.leading, Metric.rowLeading)
            .padding(.trailing, 16)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
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
        // Instagram's "Your algorithm" says "Lately you've been into ..." (town-feed 30).
        case "tapped": return name.map { "You've been into \($0) lately" }
        case "interest":
            let label = Interests.all.first { $0.id == name }?.label ?? name
            return label.map { "Matches \($0)" }
        case "popular": return "Popular in town"
        case "size": return "Big in town"
        case "today": return "Happening today"
        case "tomorrow": return "Happening tomorrow"
        case "soon": return "Coming up soon"
        case "final": return "Final score"
        default: return nil
        }
    }
}

/// Every term behind a card's place, for Jesse's account: lifts in points, then the
/// multipliers, the total and the card's place in the feed. A term that changes nothing
/// is greyed. Rows 14pt apart and plain words (Jesse, 2026-10-11).
private struct ScoreBox: View {
    let score: FeedScore

    /// Which half of the feed it fills (town-feed 31).
    private var poolWords: String {
        switch score.pool {
        case "yours": ", from your people"
        case "discovery": ", to discover"
        default: ""
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Score")
                Spacer()
                Text(Self.number(score.total))
            }
            .font(.sansSemibold(17))
            .foregroundStyle(Hue.ink)
            .padding(.bottom, 3)

            row("Start", "1", idle: false)
            row("Your interests", "+" + Self.number(score.interest), idle: score.interest == 0)
            row("Friends going", "+" + Self.number(score.friend), idle: score.friend == 0)
            row("You follow it", "+" + Self.number(score.follow), idle: score.follow == 0)
            row("Host you've been into", "+" + Self.number(score.tapped ?? 0), idle: (score.tapped ?? 0) == 0)
            row("Popular in town", "+" + Self.number(score.popular), idle: score.popular == 0)
            row((score.sizeStep == 3 ? "Big" : score.sizeStep == 2 ? "Medium" : "Small") + " event",
                "+" + Self.number(score.size), idle: score.size == 0)
            row("Draws the town out", "+" + Self.number(score.draw ?? 0), idle: (score.draw ?? 0) == 0)
            row(startsIn, "×" + Self.number(score.soon), idle: score.soon == 1)
            row("You're going or saved it", "×" + Self.number(score.acted), idle: score.acted == 1)
            row("Like one you hid", "×" + Self.number(score.notInterested ?? 1), idle: (score.notInterested ?? 1) == 1)
            row(sameHost, "×" + Self.number(score.spacing), idle: score.spacing == 1)
            row("Same interest again", "×" + Self.number(score.topicSpacing ?? 1), idle: (score.topicSpacing ?? 1) == 1)

            Rectangle().fill(Hue.hairline).frame(height: 1)
            Text("Place \(score.spot) of \(score.of) in your feed" + (score.newSpot ? ", moved up as new" : "") + poolWords)
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

    /// "Starts in 6 hours", "Starts in 2 days": what the time multiplier is about.
    private var startsIn: String {
        let hours = Int((score.daysAway * 24).rounded())
        if hours == 0 { return "Happening now" }
        if hours < 24 { return "Starts in \(hours) hour" + (hours == 1 ? "" : "s") }
        let days = Int(score.daysAway.rounded())
        return "Starts in \(days) day" + (days == 1 ? "" : "s")
    }

    /// "2nd card from this host": the spacing halves for each earlier card from it.
    private var sameHost: String {
        let earlier = Int((log(score.spacing) / log(0.5)).rounded())
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        return (ordinal.string(from: NSNumber(value: earlier + 1)) ?? "") + " card from this host"
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

/// A Town card's ••• sheet with Not interested and Mute (ticket 21): the choice waits until the
/// sheet has closed, so the card it hangs on isn't taken away under it. Off the Town feed (no
/// `TownFeed` around) or signed out, the sheet has neither row.
struct FeedCardMenuSheet: ViewModifier {
    @Binding var isPresented: Bool
    let item: FeedCardItem
    let report: PhotoReport?

    @Environment(TownFeed.self) private var feed: TownFeed?
    @Environment(RealLifeActions.self) private var actions
    @State private var chosen: Bool?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: hide) {
            if let why = item.why {
                FeedCardMenu(why: why, score: item.score, report: report,
                             hostName: item.hostName.isEmpty ? nil : item.hostName,
                             onHide: feed != nil && actions.canAct ? { (mute: Bool) in chosen = mute } : nil)
            }
        }
    }

    private func hide() {
        guard let mute = chosen, let feed else { return }
        chosen = nil
        Haptics.light()
        Task { await feed.hide(item, mute: mute) }
    }
}
