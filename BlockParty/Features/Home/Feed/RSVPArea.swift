//
//  RSVPArea.swift
//  Block Party — RSVP on the Town card and in the Event page's floating bar (BP app
//  docs/plans/rsvp-and-groups, tickets 01 and 02): the going words at the left, Meetup's pill
//  at the right, as the Figma page "Meetup depth" draws it. One tap and you're Going:
//  "You're going!", "Can't go?" under it to leave, and the pill becomes Invite. Going itself
//  is `RealLifeActions`'.
//

import SwiftUI

/// What the RSVP area says and which pill it shows: one rule for the Town card and the Event
/// page's bar, from an Event's Going, its count, the friends going and whether it's called
/// off (`RSVPWordsTests`).
nonisolated struct RSVPWords: Equatable {
    enum Pill: Equatable { case rsvp, invite, canceled }

    /// "41 going" or "You're going!"; nil while nobody is going.
    var top: String?
    /// The friends going, or "Can't go?".
    var second: String?
    /// The second line is "Can't go?", a button that leaves.
    var canLeave: Bool
    /// The pill. Called off, it says "Canceled", Going or not (Jesse, 2026-10-17).
    var pill: Pill

    /// `bar`: the Event page's floating bar says less (Jesse at rsvp-and-groups 02's Check-in 2):
    /// no "Can't go?" (leaving stays on the Town card), and beside the friends' faces only
    /// their names, which fit by its bigger words where "… are going" didn't.
    static func make(isGoing: Bool, count: Int, friends: [String], cancelled: Bool, bar: Bool = false) -> RSVPWords {
        if isGoing {
            return RSVPWords(top: "You're going!", second: bar ? nil : "Can't go?", canLeave: !bar,
                             pill: cancelled ? .canceled : .invite)
        }
        if cancelled { return RSVPWords(top: nil, second: nil, canLeave: false, pill: .canceled) }
        // Never fewer than the friends it names.
        let total = max(count, friends.count)
        return RSVPWords(top: total > 0 ? "\(total) going" : nil, second: friendsLine(friends, bar: bar),
                         canLeave: false, pill: .rsvp)
    }

    /// Facebook's words (Jesse, 2026-10-17): "Avery is going", "Sam and Marlene are going",
    /// "Sam and 2 friends are going", short enough to sit beside the pill on a 402 pt phone;
    /// in the Event page's bar the names alone. Newest Going first.
    private static func friendsLine(_ friends: [String], bar: Bool) -> String? {
        let names: String
        switch friends.count {
        case 0: return nil
        case 1: names = friends[0]
        case 2: names = "\(friends[0]) and \(friends[1])"
        default: names = "\(friends[0]) and \(friends.count - 1) friends"
        }
        return bar ? names : names + (friends.count == 1 ? " is going" : " are going")
    }
}

/// The RSVP area: friends' faces (the card's only), the words, and the pill. A called-off
/// Event's pill is red and says "Canceled" (Jesse, 2026-10-17); it squishes like every pill
/// and does nothing.
struct RSVPArea: View {
    /// The Town card's, under the photo, or the Event page's, inside its floating capsule.
    enum Size {
        case card, page

        /// Words 15 and 13 pt on the card, 17 and 15 in the Event page's bar (Figma "Meetup depth").
        var top: CGFloat { self == .card ? 15 : 17 }
        var second: CGFloat { self == .card ? 13 : 15 }
        /// The pill: 38 pt tall and at least 100 wide on the card, 46 and 131 on the page.
        var pillHeight: CGFloat { self == .card ? 38 : 46 }
        var pillMinWidth: CGFloat { self == .card ? 100 : 131 }
        /// The glyph's box is the word's size plus one (16 and 18 pt on the Figma page); Apple's
        /// calendar at 13 pt draws about 13 x 12, the size of the card's, so 14.6 for the page's.
        var send: CGFloat { top + 1 }
        var calendar: CGFloat { self == .card ? 13 : 14.6 }
        /// "Can't go?"'s line (16 and 18 pt), grown to a 44 pt target.
        var leaveReach: CGFloat { self == .card ? -14 : -13 }
    }

    let item: FeedCardItem
    let words: RSVPWords
    var size: Size = .card
    /// The card's send: Invite opens the same invite card.
    let onInvite: (() -> Void)?

    /// The glyph sits 7 pt from the word (Figma "Meetup depth").
    static let glyphGap: CGFloat = 7

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// `actions.failureCount` at the last tap: a tap mid-shake stills it.
    @State private var tappedAt = 0

    var body: some View {
        let going = actions.going(item)
        HStack(spacing: 8) {
            // Faces only beside words: a called-off card with no "You're going!" has none.
            if words.top != nil {
                faces(count: going.count)
            }

            VStack(alignment: .leading, spacing: 1) {
                if let top = words.top {
                    // A count rolls; "You're going!" cross-fades in, as its own line.
                    Text(top)
                        .font(.sansBold(size.top))
                        .foregroundStyle(Hue.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .id(words.canLeave)
                }
                if let second = words.second {
                    if words.canLeave {
                        Self.leave(second, size: size, hint: "Takes you off the going list",
                                   reduceMotion: reduceMotion, action: toggle)
                    } else {
                        // Shrinks a little before it cuts: a 402 pt phone leaves the Event page's bar
                        // 125 pt beside the faces and the pill, and "Sam and 2 friends" needs 125.
                        Text(second)
                            .font(.sans(size.second))
                            .foregroundStyle(Hue.inkSecondary)
                            .minimumScaleFactor(0.9)
                    }
                }
            }
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .layoutPriority(1)

            Spacer(minLength: 12)

            if words.pill == .canceled {
                Button {} label: { pillFace(.canceled) }
                    .buttonStyle(MeetupPillStyle(height: size.pillHeight, minWidth: size.pillMinWidth, fill: Hue.canceled))
                    .accessibilityRemoveTraits(.isButton)
            } else {
                let failures = actions.failureCount(item.id)
                Button {
                    if words.pill == .invite { onInvite?() } else { toggle() }
                } label: { pillFace(words.pill) }
                    .buttonStyle(MeetupPillStyle(height: size.pillHeight, minWidth: size.pillMinWidth))
                    .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
                    .accessibilityLabel(words.pill == .invite ? "Invite" : "RSVP")
                    .accessibilityValue(going.isGoing ? "Going" : "")
            }
        }
        // The pill turns into Invite and the words cross-fade over `RealLifeActions.flip`, both ways,
        // a failed RSVP's turn back included; a count that moves rolls.
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: going.isGoing)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.smooth, value: going.count)
    }

    /// Friends' faces lead, as on Facebook's event card (town-feed 28), else neighbours' photos.
    @ViewBuilder
    private func faces(count: Int) -> some View {
        if !item.friendsGoing.isEmpty {
            FriendFaces(friends: item.friendsGoing)
        } else if !item.goingAvatars.isEmpty {
            FeedCardFacepile(neighborAvatars: item.goingAvatars, goingCount: count, reduceMotion: reduceMotion)
        }
    }

    /// "Can't go?", and the Group page's "Leave group?": quiet words that undo, grown to a 44 pt target.
    static func leave(_ words: String, size: Size, hint: String, reduceMotion: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(words)
                .font(.sansSemibold(size.second))
                .foregroundStyle(Hue.inkSecondary)
                .contentShape(Rectangle().inset(by: size.leaveReach))
        }
        .buttonStyle(FeedCardJoinPressStyle(reduceMotion: reduceMotion))
        .accessibilityHint(hint)
    }

    /// Invite's face, the send glyph before the word; the Group page's pill shows it too.
    @ViewBuilder
    static func invite(_ size: Size) -> some View {
        FeedActionGlyphView(glyph: .send, size: size.send)
        Text("Invite")
    }

    private func pillFace(_ pill: RSVPWords.Pill) -> some View {
        HStack(spacing: Self.glyphGap) {
            if pill == .canceled {
                Text("Canceled")
            } else if pill == .invite {
                Self.invite(size)
            } else {
                // Apple's calendar, white, where Meetup's page draws one (Jesse, 2026-10-17).
                Image(systemName: "calendar")
                    .font(.glyph(size.calendar, weight: .semibold))
                    .accessibilityHidden(true)
                Text("RSVP")
            }
        }
        .font(.sansSemibold(size.top))
    }

    /// RSVP and "Can't go?" both flip Going; a write the server refuses turns back and shakes the pill.
    private func toggle() {
        tappedAt = actions.failureCount(item.id)
        actions.toggleGoing(item)
    }
}
