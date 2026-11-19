//
//  ChatLook.swift
//  Block Party — what Messages' look works out (BP app messages 02): which corners of a bubble are tight, how far the
//  chat follows a drag for its times, which Events the + lists, and the moves' timing. The sizes are `ChatMetric`,
//  the colours `Hue.chat…`; the numbers are Instagram's where a still shows them (BP app
//  `references/messages-instagram/SPEC.md`), and guessed where none does.
//

import SwiftUI

enum ChatLook {
    /// A bubble's shape in its run: 20 all round, 4 on its own side where the bubble above or below is the same
    /// person's. Yours join on the right, theirs on the left.
    nonisolated static func bubble(mine: Bool, joinsAbove: Bool, joinsBelow: Bool) -> UnevenRoundedRectangle {
        let round = ChatMetric.bubbleCorner, top = joinsAbove ? ChatMetric.bubbleJoin : round
        let bottom = joinsBelow ? ChatMetric.bubbleJoin : round
        return UnevenRoundedRectangle(topLeadingRadius: mine ? round : top, bottomLeadingRadius: mine ? round : bottom,
                                      bottomTrailingRadius: mine ? bottom : round, topTrailingRadius: mine ? top : round)
    }

    /// How far the chat has come left for a finger `pull` points left: with it to 64, then a fifth as fast.
    nonisolated static func timesShift(_ pull: CGFloat) -> CGFloat {
        let pull = max(0, pull)
        return pull < ChatMetric.timesPull ? pull : ChatMetric.timesPull + (pull - ChatMetric.timesPull) * 0.18
    }

    /// What the + lists: the Events you're Going to and the ones you hearted, each once, soonest first; with none,
    /// the Town feed's next ten. Never one that's over or called off.
    static func eventsToSend(going: [DailyEvent], liked: [DailyEvent], town: [FeedCardItem], now: Date) -> [FeedCardItem] {
        func soonest(_ events: [DailyEvent]) -> [FeedCardItem] {
            var seen = Set<String>()
            return events
                .filter { $0.group == nil && !$0.item.cancelled && $0.ends > now && seen.insert($0.id).inserted }
                .sorted { ($0.starts, $0.item.title) < ($1.starts, $1.item.title) }
                .map(\.item)
        }
        let yours = soonest(going + liked)
        return yours.isEmpty ? Array(soonest(town.compactMap { YouCalendar.event(from: $0) }).prefix(10)) : yours
    }

    // MARK: Hearts and replies (BP app messages 03)

    /// The hold's six, in Instagram's order, and the only ones the server takes. No "+" for more (Jesse, 2026-11-18).
    nonisolated static let emoji = ["❤️", "😂", "😮", "😢", "😡", "👍"]
    nonisolated static let heart = "❤️"

    /// A message's reactions after you pick `emoji`: yours goes when it was the same one, else the new one takes its
    /// place, last, as the server orders them by when.
    nonisolated static func reacted(_ reactions: [ChatReaction], me: String, _ emoji: String) -> [ChatReaction] {
        let had = reactions.first { $0.userId == me }?.emoji
        let others = reactions.filter { $0.userId != me }
        return had == emoji ? others : others + [ChatReaction(userId: me, emoji: emoji)]
    }

    /// What the small pill under a message shows: each emoji once, the most picked first (then the earliest), up to
    /// three, and how many people when more than one. Picked: Instagram's pill, which the mock drew with one.
    nonisolated static func pill(_ reactions: [ChatReaction]) -> (emoji: [String], count: Int?) {
        var tally: [String: (n: Int, first: Int)] = [:]
        for (i, r) in reactions.enumerated() { tally[r.emoji, default: (0, i)].n += 1 }
        let order = tally.sorted { ($1.value.n, $0.value.first) < ($0.value.n, $1.value.first) }.map(\.key)
        return (Array(order.prefix(3)), reactions.count > 1 ? reactions.count : nil)
    }

    /// How far a reply's drag has taken its row: with the finger to 64, then a fifth as fast, as the times' drag.
    nonisolated static func replyShift(_ pull: CGFloat) -> CGFloat { timesShift(pull) }
}

/// The moves' timing. Guessed: Mobbin has no Instagram recording, so Jesse judges them on his phone.
enum ChatMotion {
    /// Your words come up out of the composer.
    static let rise: Animation = .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.38)
    /// A photo, an Event, their message and the typing dots pop in from their corner.
    static let pop: Animation = .timingCurve(0.2, 0.9, 0.3, 1.25, duration: 0.26)
    /// The chat goes back after a drag for its times.
    static let timesBack: Animation = .timingCurve(0.2, 0.9, 0.3, 1.15, duration: 0.38)
    /// The send pill comes with the first letter.
    static let send: Animation = .timingCurve(0.2, 0.9, 0.3, 1.3, duration: 0.22)
    /// The small pill under a message pops in (the mock's 0.32 s).
    static let reaction: Animation = .timingCurve(0.2, 0.9, 0.3, 1.4, duration: 0.32)
    /// A held message: the page washes out, the bubble moves to where its row and menu fit, the row and menu grow in
    /// from its side; letting go fades it all.
    static let holdWash: Animation = .easeOut(duration: 0.2)
    static let holdMove: Animation = .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)
    static let holdRow: Animation = .timingCurve(0.2, 0.9, 0.3, 1.25, duration: 0.28)
    static let holdMenu: Animation = .timingCurve(0.2, 0.9, 0.3, 1.1, duration: 0.28)
    static let holdClose: Animation = .easeOut(duration: 0.16)
    /// The big heart of a double tap: in past full size, settles, then floats up and fades, 0.8 s in all.
    static let heartGrow: TimeInterval = 0.28
    static let heartSettle: TimeInterval = 0.16
    static let heartStay: TimeInterval = 0.2
    static let heartLeave: TimeInterval = 0.16
    /// How long a press holds before the menu opens (the mock's 450 ms).
    static let hold: TimeInterval = 0.45
}
