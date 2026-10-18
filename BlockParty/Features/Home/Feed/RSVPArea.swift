//
//  RSVPArea.swift
//  Block Party — RSVP on the Town card (BP app docs/plans/rsvp-and-groups, ticket 01): the
//  going words at the left, Meetup's pill at the right, as the Figma page "Meetup depth"
//  draws it. One tap and you're Going: "You're going!", "Can't go?" under it to leave, and
//  the pill becomes Invite. Going itself is `RealLifeActions`'.
//

import SwiftUI

/// What the RSVP area says and which pill it shows: one rule for the Town card and, from
/// ticket 02, the Event page's bar (its grey Canceled pill), from an Event's Going, its
/// count, the friends going and whether it's called off (`RSVPWordsTests`).
nonisolated struct RSVPWords: Equatable {
    enum Pill: Equatable { case rsvp, invite, canceled }

    /// "41 going" or "You're going!"; nil while nobody is going.
    var top: String?
    /// The friends going, or "Can't go?".
    var second: String?
    /// The second line is "Can't go?", a button that leaves.
    var canLeave: Bool
    /// nil: no pill (called off while Going: nobody to invite to it).
    var pill: Pill?

    static func make(isGoing: Bool, count: Int, friends: [String], cancelled: Bool) -> RSVPWords {
        if isGoing {
            return RSVPWords(top: "You're going!", second: "Can't go?", canLeave: true,
                             pill: cancelled ? nil : .invite)
        }
        if cancelled { return RSVPWords(top: nil, second: nil, canLeave: false, pill: .canceled) }
        // Never fewer than the friends it names.
        let total = max(count, friends.count)
        return RSVPWords(top: total > 0 ? "\(total) going" : nil, second: friendsLine(friends),
                         canLeave: false, pill: .rsvp)
    }

    /// Facebook's words, picked at Check-in 1 (Jesse, 2026-10-17): "Avery is going", "Sam and
    /// Marlene are going", "Sam and 2 other friends are going". Newest Going first.
    private static func friendsLine(_ friends: [String]) -> String? {
        switch friends.count {
        case 0: nil
        case 1: "\(friends[0]) is going"
        case 2: "\(friends[0]) and \(friends[1]) are going"
        default: "\(friends[0]) and \(friends.count - 1) other friends are going"
        }
    }
}

/// The Town card's RSVP area, under the photo: friends' faces, the words, and the pill.
/// A called-off card shows no pill, so with nobody to say "You're going!" to it shows nothing.
struct CardRSVPArea: View {
    let item: FeedCardItem
    let words: RSVPWords
    /// The card's send: Invite opens the same invite card.
    let onInvite: (() -> Void)?

    /// The card's pill: 15 pt words, a 16 pt glyph 7 pt from them (Figma "Meetup depth").
    private enum Metric {
        static let glyphGap: CGFloat = 7
        static let sendSide: CGFloat = 16
        /// Apple's calendar at 13 pt draws about 13 x 12 pt, the size of the Figma page's.
        static let calendar: CGFloat = 13
        /// "Can't go?"'s 16 pt line, grown to a 44 pt target.
        static let leaveReach: CGFloat = -14
    }

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// `actions.failureCount` at the last tap, as the Event page's Join: a tap mid-shake stills it.
    @State private var tappedAt = 0

    var body: some View {
        let going = actions.going(item)
        HStack(spacing: 8) {
            faces(count: going.count)

            VStack(alignment: .leading, spacing: 1) {
                if let top = words.top {
                    // A count rolls; "You're going!" cross-fades in, as its own line.
                    Text(top)
                        .font(.sansBold(15))
                        .foregroundStyle(Hue.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .id(words.canLeave)
                }
                if let second = words.second {
                    if words.canLeave {
                        Button(action: toggle) {
                            Text(second)
                                .font(.sansSemibold(13))
                                .foregroundStyle(Hue.inkSecondary)
                                .contentShape(Rectangle().inset(by: Metric.leaveReach))
                        }
                        .buttonStyle(FeedCardJoinPressStyle(reduceMotion: reduceMotion))
                        .accessibilityHint("Takes you off the going list")
                    } else {
                        Text(second)
                            .font(.sans(13))
                            .foregroundStyle(Hue.inkSecondary)
                    }
                }
            }
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .layoutPriority(1)

            Spacer(minLength: 12)

            if let pill = words.pill, pill != .canceled {
                let failures = actions.failureCount(item.id)
                Button {
                    if pill == .invite { onInvite?() } else { toggle() }
                } label: { pillFace(pill) }
                    .buttonStyle(MeetupPillStyle())
                    .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
                    .accessibilityLabel(pill == .invite ? "Invite" : "RSVP")
                    .accessibilityValue(going.isGoing ? "Going" : "")
            }
        }
        // The pill turns into Invite and the words cross-fade over Join's flip, both ways,
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

    private func pillFace(_ pill: RSVPWords.Pill) -> some View {
        HStack(spacing: Metric.glyphGap) {
            if pill == .invite {
                FeedActionGlyphView(glyph: .send, size: Metric.sendSide)
                Text("Invite")
            } else {
                // Apple's calendar, white, where Meetup's page draws one (Jesse, 2026-10-17).
                Image(systemName: "calendar")
                    .font(.glyph(Metric.calendar, weight: .semibold))
                    .accessibilityHidden(true)
                Text("RSVP")
            }
        }
        .font(.sansSemibold(15))
    }

    /// RSVP and "Can't go?" both flip Going; a write the server refuses turns back and shakes the pill.
    private func toggle() {
        tappedAt = actions.failureCount(item.id)
        actions.toggleGoing(item)
    }
}
