//
//  RSVPArea.swift
//  Block Party — RSVP on the Town card and in the Event page's floating bar (BP app
//  docs/plans/rsvp-and-groups, tickets 01 and 02): the going words at the left, Meetup's pill
//  at the right, as the Figma page "Meetup depth" draws it. One tap on Attend and you're Going:
//  "You're going!", "Can't go?" under it to leave, a check on the pill's calendar, and then the
//  pill becomes Invite; on Town it shrinks into a round X that leaves instead (attend-x). Going
//  itself is `RealLifeActions`'.
//

import SwiftUI

/// What the RSVP area says and which pill it shows: one rule for the Town card and the Event
/// page's bar, from an Event's Going, its count, the friends going and whether it's called
/// off (`RSVPWordsTests`).
nonisolated struct RSVPWords: Equatable {
    /// `leave`: Town's round X, which takes you off the going list.
    enum Pill: Equatable { case rsvp, invite, leave, canceled }

    /// "41 going" or "You're going!", or once a game's final is in "212 went"; nil while nobody is going.
    var top: String?
    /// The friends going, or "Can't go?".
    var second: String?
    /// The second line is "Can't go?", a button that leaves.
    var canLeave: Bool
    /// The pill. Called off, it says "Canceled", Going or not (Jesse, 2026-10-17); none once a
    /// game is over (game-card 02).
    var pill: Pill?

    /// `bar`: the Event page's floating bar says less (Jesse at rsvp-and-groups 02's Check-in 2):
    /// no "Can't go?" (leaving stays on the Town card), and beside the friends' faces only
    /// their names, which fit by its bigger words where "… are going" didn't.
    /// `town`: the Town card and the poster on top of Town. Going, the pill turns into a round X
    /// that leaves, so there's no "Can't go?", and a yellow share comes up beside it (event-card 06).
    /// No friends' names: the count alone.
    /// Called off, the pill says Canceled and "Can't go?" still leaves.
    /// `over`: a game whose final is in, "212 went" and no pill, whoever went (game-card 02).
    static func make(isGoing: Bool, count: Int, friends: [String], cancelled: Bool, bar: Bool = false,
                     town: Bool = false, over: Bool = false) -> RSVPWords {
        var words = unshortened(isGoing: isGoing, count: count, friends: friends, cancelled: cancelled, bar: bar,
                                town: town, over: over)
        // On Town the words share one line with the send and the pill, so the friends' names go and
        // the count stays (Jesse at event-card 06's Check-in 1, 2026-10-21). "Can't go?" stays.
        if town && !words.canLeave { words.second = nil }
        return words
    }

    private static func unshortened(isGoing: Bool, count: Int, friends: [String], cancelled: Bool, bar: Bool,
                                    town: Bool, over: Bool) -> RSVPWords {
        if over {
            let total = max(count, friends.count)
            return RSVPWords(top: total > 0 ? "\(total) went" : nil, second: friendsLine(friends, bar: bar, went: true),
                             canLeave: false, pill: nil)
        }
        if isGoing && town && !cancelled {
            return RSVPWords(top: "You're going!", second: nil, canLeave: false, pill: .leave)
        }
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
    /// in the Event page's bar the names alone. Newest Going first. After a game, "Sam and
    /// Marlene went".
    /// The You Agenda's VoiceOver reads it too (you-tab 07).
    static func friendsLine(_ friends: [String], bar: Bool, went: Bool = false) -> String? {
        let names: String
        switch friends.count {
        case 0: return nil
        case 1: names = friends[0]
        case 2: names = "\(friends[0]) and \(friends[1])"
        default: names = "\(friends[0]) and \(friends.count - 1) friends"
        }
        if bar { return names }
        return names + (went ? " went" : friends.count == 1 ? " is going" : " are going")
    }

    /// The pill on screen: Attend, its calendar checked, while a tap's check shows, then Invite
    /// or Town's X (Jesse at attend-pill's Check-in 1, 2026-10-19). A called-off pill stays Canceled.
    func shownPill(checking: Bool) -> Pill? {
        checking && (pill == .invite || pill == .leave) ? .rsvp : pill
    }

    /// "You're going!" is its own line, which cross-fades in over the count instead of rolling.
    var goingLine: Bool { canLeave || pill == .leave }
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
    /// The Town card: its send leads the line, and once you're going it leaves for the yellow share
    /// beside the X (event-card 06).
    var leadingSend = false
    /// The Town card's •••, after the send (found-posts): it stays when the send leaves.
    var onMenu: (() -> Void)? = nil

    /// The yellow share is up beside the X, so the send at the left has gone.
    @State private var shareUp = false

    /// The glyph sits 7 pt from the word (Figma "Meetup depth").
    static let glyphGap: CGFloat = 7
    /// The send at the line's left: the action row's 24 pt glyph in its 28 pt target.
    static let sendGlyph: CGFloat = 24
    static let sendWidth: CGFloat = 28

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let going = actions.going(item)
        HStack(spacing: 8) {
            if leadingSend && !shareUp, let onInvite {
                Button(action: onInvite) {
                    FeedActionGlyphView(glyph: .send, size: Self.sendGlyph)
                        .foregroundStyle(Hue.ink)
                        .frame(width: Self.sendWidth, height: MeetupPillStyle.minTarget)
                        // Apple's 44 pt wide, past the glyph's own 28 into the gap beside it.
                        .contentShape(Rectangle().inset(by: (Self.sendWidth - MeetupPillStyle.minTarget) / 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")
                // Out the way it came: to the left, as the share pops up beside the X.
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if let onMenu {
                FeedCardMenuButton(action: onMenu)
                    .padding(.leading, leadingSend && !shareUp && onInvite != nil ? FeedCardMenuButton.gap : 0)
            }

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
                        .id(words.goingLine)
                }
                if let second = words.second {
                    if words.canLeave {
                        Self.leave(second, size: size, hint: "Takes you off the going list",
                                   reduceMotion: reduceMotion) { actions.toggleGoing(item) }
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

            if words.pill != nil {
                AttendPill(item: item, words: words, size: size, onInvite: onInvite,
                           shareBeside: leadingSend ? .leading : nil, shareUp: $shareUp)
            }
        }
        // The pill's height with no pill too, so a game's "212 went" sits where its Attend did.
        .frame(minHeight: size.pillHeight)
        // The words cross-fade over `RealLifeActions.flip`, both ways, a failed Attend's turn back
        // included, as the pill turns; a count that moves rolls.
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: going.isGoing)
        // A final that comes in while it's on screen fades Attend out and "went" in (game-card 02).
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: words.pill)
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
    /// `tint`: white at 60% on the Event of the day poster's dark (event-card 03).
    static func leave(_ words: String, size: Size, hint: String, reduceMotion: Bool,
                      tint: Color = Hue.inkSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(words)
                .font(.sansSemibold(size.second))
                .foregroundStyle(tint)
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
}

/// Meetup's pill alone: Attend, its calendar's check for a moment after the tap, then Invite, or
/// on Town a light grey round X that leaves (attend-x); a called-off Event's red Canceled. The
/// RSVP area draws it at its right, the Town's Event of the day poster in its own row (event-card 03).
struct AttendPill: View {
    let item: FeedCardItem
    /// The pill they name (`RSVPWords.pill`).
    let words: RSVPWords
    var size: RSVPArea.Size = .card
    let onInvite: (() -> Void)?
    /// On Town, which side of the X the yellow share pops up on once you're going (event-card 06):
    /// the card's, before it; the poster's, after it. Its tap is `onInvite`'s.
    var shareBeside: HorizontalEdge? = nil
    /// Set while the yellow share is up, so the card's send can leave as it comes.
    var shareUp: Binding<Bool> = .constant(false)
    /// On a dark ground (the Event of the day poster), Attend is BP yellow (Jesse, attend-yellow).
    var yellow = false

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `actions.failureCount` at the last tap: a tap mid-shake stills it.
    @State private var tappedAt = 0
    /// Attend was just tapped: its calendar shows the check for `RealLifeActions.checkHold`.
    @State private var checking = false

    var body: some View {
        let going = actions.going(item)
        let shown = words.shownPill(checking: checking)
        let share = shown == .leave && onInvite != nil ? shareBeside : nil
        HStack(spacing: Self.shareGap) {
            if share == .leading { yellowShare }
            if shown == .canceled {
                Button {} label: { face(.canceled) }
                    .buttonStyle(MeetupPillStyle(height: size.pillHeight, minWidth: size.pillMinWidth, fill: Hue.canceled))
                    .accessibilityRemoveTraits(.isButton)
            } else if let shown {
                // (None once a game is over: nothing to tap, game-card 02.)
                let failures = actions.failureCount(item.id)
                let x = shown == .leave
                Button {
                    // A tap while the check shows cuts it short: Invite or the X comes up now
                    // (taste.md, everything can be interrupted), without acting yet.
                    if checking { checking = false; return }
                    switch shown {
                    case .invite: onInvite?()
                    case .leave: toggleGoing()
                    default: attend()
                    }
                } label: { face(shown) }
                    // The X is the pill shrunk to a circle its own height, light grey with an ink X
                    // (Jesse at attend-x's Check-in 1, 2026-10-21).
                    .buttonStyle(MeetupPillStyle(height: size.pillHeight, minWidth: x ? size.pillHeight : size.pillMinWidth,
                                                 grey: x, yellow: yellow && !x, sidePadding: x ? 0 : 20))
                    .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
                    // The X reads "Going" with how to leave, not "Can't go, Going" (the review).
                    .accessibilityLabel(shown == .invite ? "Invite" : x ? "Going" : "Attend")
                    .accessibilityHint(x ? "Takes you off the going list" : "")
                    .accessibilityValue(going.isGoing && !x ? "Going" : "")
            }
            if share == .trailing { yellowShare }
        }
        // The card's send leaves on the same beat the share comes in.
        // Set without motion as the card comes on screen: a going card scrolled back into view
        // shows the share already up instead of playing the send out again (the review).
        .onChange(of: share != nil, initial: true) { was, up in
            withAnimation(was == up ? nil : shareAnimation) { shareUp.wrappedValue = up }
        }
        // The pill turns into Invite or the X over `RealLifeActions.flip`, both ways, a failed
        // Attend's turn back included.
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: going.isGoing)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: checking)
        // The check holds, then Invite or the X comes up. Changed only after the sleep, so it never
        // cancels itself.
        .task(id: checking) {
            guard checking else { return }
            try? await Task.sleep(for: RealLifeActions.checkHold)
            checking = false
        }
        // Left, or a refused write turned back: plain Attend again.
        .onChange(of: going.isGoing) { _, isGoing in
            if !isGoing { checking = false }
        }
    }

    /// The yellow share and the X sit 8 pt apart.
    static let shareGap: CGFloat = 8

    /// It pops up as the X lands, on a spring that overshoots a little, and shrinks away as you leave.
    private var shareAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.62)
    }

    private var yellowShare: some View {
        YellowShareButton { onInvite?() }
            .transition(.asymmetric(insertion: reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity),
                                    removal: reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                .animation(shareAnimation))
    }

    private func face(_ pill: RSVPWords.Pill) -> some View {
        HStack(spacing: RSVPArea.glyphGap) {
            if pill == .canceled {
                Text("Canceled")
            } else if pill == .invite {
                RSVPArea.invite(size)
            } else if pill == .leave {
                // Apple's xmark at the calendar's size and weight.
                Image(systemName: "xmark")
                    .font(.glyph(size.calendar, weight: .semibold))
                    .accessibilityHidden(true)
            } else {
                // Apple's calendar, white, where Meetup's page draws one (Jesse, 2026-10-17). A tap
                // swaps in Apple's checked twin, its badge drawn in by Magic Replace (2026-10-19).
                Image(systemName: checking ? "calendar.badge.checkmark" : "calendar")
                    .font(.glyph(size.calendar, weight: .semibold))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                    .accessibilityHidden(true)
                Text("Attend")
            }
        }
        .font(.sansSemibold(size.top))
    }

    /// Attend: Going, and the calendar's check shows before Invite comes up. A write the server
    /// refuses turns back and shakes the pill.
    private func attend() {
        checking = true
        toggleGoing()
    }

    /// Attend's tap, or the X's: off the going list in one tap, back to Attend.
    private func toggleGoing() {
        tappedAt = actions.failureCount(item.id)
        actions.toggleGoing(item)
    }
}
