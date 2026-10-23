//
//  FollowButton.swift
//  Block Party — Follow, Instagram's button in the Friends buttons' family (BP app docs/plans/follows,
//  ticket 02; taste/buttons-and-pills.md, 2026-10-19): ink "Follow", grey "Following" once you do.
//  One tap follows with a light tick, one tap on Following undoes it with no question, and a tap
//  the server refuses turns back with Join's hold, flip, shake and buzz (`RealLifeActions`). With
//  no signed-up account it opens sign-up and sends nothing.
//
//  Sizes off the Check-in 1 mock (Figma BP · Follows, `references/follows/figma/build.js`): 36 pt
//  with 12 pt corners on a page, Instagram's 32 pt pill in a list, and on a person's page a smaller
//  grey one beside Add friend.
//
//  `FollowLine` is a page's line: the friends who follow it on the left ("Followed by Sam and 2
//  others"), Follow on the right. The count rides the page's kind line (`FollowWords.count`).
//

import SwiftUI

enum FollowMetric {
    static let pageHeight: CGFloat = 36
    static let rowHeight: CGFloat = 32
    static let pageWidth: CGFloat = 104
    /// A host's row and a list's (the mock's 88 and Instagram's 104).
    static let rowWidth: CGFloat = 88
    static let listWidth: CGFloat = 104
    /// Beside Add friend on a person's page.
    static let besideWidth: CGFloat = 96
    static let pagePad: CGFloat = 16
    static let rowPad: CGFloat = 14
    /// The faces to their words on the follow line.
    static let facesGap: CGFloat = 8
}

/// The words, in one place (BP app words page: `follow-button`, `follower-count`, `followed-by`).
enum FollowWords {
    /// "128 followers", "1 follower"; none for nobody, as the app never shows a zero.
    static func count(_ n: Int) -> String? {
        n <= 0 ? nil : n == 1 ? "1 follower" : "\(n.formatted()) followers"
    }

    /// "Followed by Sam", "Followed by Sam and Ana", "Followed by Sam and 2 others": first names,
    /// the one named first A to Z, as the server sends them.
    static func followedBy(_ friends: [String], count: Int) -> String? {
        let first = friends.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        guard let one = first.first, count > 0 else { return nil }
        switch count {
        case 1: return "Followed by \(one)"
        case 2: return "Followed by \(one) and \(first.count > 1 ? first[1] : "1 other")"
        default: return "Followed by \(one) and \(count - 1) others"
        }
    }
}

struct FollowButton: View {
    enum Size {
        /// Under a Place's name: 36 pt, ink until you follow.
        case page
        /// A host's row or the Following list: Instagram's 32 pt pill.
        case row
        /// Beside Add friend on a person's page: 36 pt and always grey, the smaller action.
        case beside
    }

    let target: FollowTarget
    /// Whose: VoiceOver says "Follow, Krewe".
    let name: String
    var size: Size = .page
    var minWidth: CGFloat? = nil

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `followFailureCount` at the last tap: equal means a tap since the last turn back, so its
    /// shake stops (as the RSVP pill's).
    @State private var tappedAt = 0
    @State private var signingIn = false

    var body: some View {
        let following = actions.follow(target).isFollowing
        let failures = actions.followFailureCount(target)
        let ink = !following && size != .beside
        Button(action: tap) {
            Text(following ? "Following" : "Follow")
                .font(.sansSemibold(15))
                .foregroundStyle(ink ? Hue.surface : Hue.ink)
                .lineLimit(1)
                .padding(.horizontal, size == .row ? FollowMetric.rowPad : FollowMetric.pagePad)
                .frame(minWidth: minWidth ?? width, minHeight: height)
                .background(ink ? Hue.ink : Hue.fill, in: shape)
                // Drawn 32 or 36 pt, 44 pt to the finger.
                .contentShape(Rectangle().inset(by: (height - SearchMetric.tapMin) / 2))
        }
        .buttonStyle(PressableStyle())
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: following)
        .accessibilityLabel("\(following ? "Following" : "Follow"), \(name)")
        .accessibilityAddTraits(following ? .isSelected : [])
        .onAppear { actions.followOpened(target) }
        .onDisappear { actions.followClosed(target) }
        .signInSheet(isPresented: $signingIn)
    }

    private var height: CGFloat { size == .row ? FollowMetric.rowHeight : FollowMetric.pageHeight }

    private var width: CGFloat {
        switch size {
        case .page: FollowMetric.pageWidth
        case .row: FollowMetric.rowWidth
        case .beside: FollowMetric.besideWidth
        }
    }

    private var shape: AnyShape {
        size == .row ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }

    /// `follow-signup`: only signed-up accounts follow (follows spec), so the sign-up sheet opens.
    private func tap() {
        guard !actions.needsSignUp else { signingIn = true; return }
        tappedAt = actions.followFailureCount(target)
        actions.toggleFollow(target)
    }
}

/// A page's follow line: the friends who follow it, then Follow at the right. It reads the count and
/// the friends when it appears, for the kind line above it too.
struct FollowLine: View {
    let target: FollowTarget
    let name: String

    @Environment(RealLifeActions.self) private var actions

    var body: some View {
        let friends = actions.followFriends[target]
        HStack(spacing: FollowMetric.facesGap) {
            if let friends, let words = FollowWords.followedBy(friends.friends.map(\.name), count: friends.count) {
                FriendFaces(friends: friends.friends.map { FeedFriend(name: $0.name, photo: $0.avatarUrl.flatMap(URL.init)) })
                Text(words)
                    .font(.sans(13))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            FollowButton(target: target, name: name)
        }
        .animation(Motion.smooth, value: friends?.count)
        .task(id: target) { await actions.refreshFollow(target) }
    }
}
