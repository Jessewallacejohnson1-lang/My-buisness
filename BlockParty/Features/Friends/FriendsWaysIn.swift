//
//  FriendsWaysIn.swift
//  Block Party — ways to bring friends in, on the Friends page (BP app docs/plans/friends,
//  ticket 05). Under the search, a white card of round buttons, Lapse's "find friends
//  elsewhere" measured at 3x (BP app references/friends-tab-ideas/refs/lapse-add-friends.jpg):
//  52pt circles 80pt apart from the left, the word under each. With no friends and no
//  requests, the page under it shows three grey faces, one line and Invite friends.
//  Mock Jesse said yes to on 2026-10-22: https://claude.ai/artifact/VMjT4AVQBogeL47oJhG9Sh
//
//  Every button sends one message with the website (Jesse: blockpartymn.com). A link that
//  opens your own page in the app comes with ticket 07 and Apple's paid developer account.
//

import SwiftUI
import UIKit

extension FriendsMetric {
    static let waysTop: CGFloat = 14
    static let waysRadius: CGFloat = 16
    static let waysPadTop: CGFloat = 16
    static let waysPadBottom: CGFloat = 14
    static let waysPadSide: CGFloat = 8
    /// Lapse's circle and the width each button takes, measured.
    static let wayCircle: CGFloat = 52
    static let waySlot: CGFloat = 80
    static let wayLabelTop: CGFloat = 8
    /// The empty page, from the approved draft.
    static let emptyTop: CGFloat = 56
    static let ghost: CGFloat = 64
    static let ghostOverlap: CGFloat = 14
    static let ghostRing: CGFloat = 3
    static let emptyTitleTop: CGFloat = 20
    static let emptyLineTop: CGFloat = 6
    static let inviteTop: CGFloat = 24
    static let invite: CGFloat = 50
    static let inviteSide: CGFloat = 32
    /// "Copied" shows this long under Copy link.
    static let copiedHold: Duration = .seconds(1.5)
}

/// What every way in sends.
enum FriendsInvite {
    static let link = URL(string: "https://blockpartymn.com")!
    /// The words alone: Apple's share sheet sends them beside the link, so the link isn't twice.
    static let words = "Join me on Block Party, \(Town.everyday)'s events, clubs and neighbors in one app."
    /// Messages gets one text, the words and the website.
    static let message = words + " blockpartymn.com"
}

/// The card of round buttons under the Friends page's search: Messages, Copy link, Contacts
/// (friends 06), More. Your code takes More's place when ticket 07 lands. Messages shows only
/// where the phone can send texts, as the share row's does.
struct FriendsWaysCard: View {
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            if MessagesComposer.canSend {
                way("Messages", fill: Color(uiColor: .systemGreen)) {
                    Image(systemName: "message.fill").font(.glyph(24, weight: .regular)).foregroundStyle(.white)
                } action: {
                    FriendsInvitePresenter.messages()
                }
            }
            way(copied ? "Copied" : "Copy link") {
                Image(systemName: copied ? "checkmark" : "link")
                    .font(.glyph(21, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .contentTransition(.symbolEffect(.replace))
            } action: {
                UIPasteboard.general.url = FriendsInvite.link
                Haptics.light()
                copied = true
            }
            .accessibilityLabel("Copy link")
            .accessibilityValue(copied ? "Copied" : "")
            // Pushed, and only there does iPhone ask for contacts.
            NavigationLink(value: FriendsRoute.contacts) {
                face("Contacts") {
                    Image(systemName: "person.text.rectangle").font(.glyph(21, weight: .medium)).foregroundStyle(Hue.ink)
                }
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            ShareLink(item: FriendsInvite.link, message: Text(FriendsInvite.words)) {
                face("More") {
                    Image(systemName: "ellipsis").font(.glyph(21, weight: .bold)).foregroundStyle(Hue.ink)
                }
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            Spacer(minLength: 0)
        }
        .padding(.top, FriendsMetric.waysPadTop)
        .padding(.bottom, FriendsMetric.waysPadBottom)
        .padding(.horizontal, FriendsMetric.waysPadSide)
        .background {
            RoundedRectangle(cornerRadius: FriendsMetric.waysRadius, style: .continuous)
                .fill(Hue.surface)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: FriendsMetric.waysRadius, style: .continuous)
                        .strokeBorder(Hue.hairline, lineWidth: FriendsMetric.hairline)
                }
        }
        .padding(.horizontal, FriendsMetric.side)
        .padding(.top, FriendsMetric.waysTop)
        .animation(.easeInOut(duration: 0.18), value: copied)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: FriendsMetric.copiedHold)
            copied = false
        }
    }

    private func way(_ word: String, fill: Color = Hue.fill, @ViewBuilder glyph: () -> some View,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) { face(word, fill: fill, glyph: glyph) }
            .buttonStyle(PressableStyle(scale: 0.9))
    }

    private func face(_ word: String, fill: Color = Hue.fill, @ViewBuilder glyph: () -> some View) -> some View {
        VStack(spacing: FriendsMetric.wayLabelTop) {
            glyph()
                .frame(width: FriendsMetric.wayCircle, height: FriendsMetric.wayCircle)
                .background(Circle().fill(fill))
            Text(word)
                .font(.sansMedium(13))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                // The word swaps at once; only the glyph turns (the review: a cross-fade smeared them).
                .animation(nil, value: word)
        }
        .frame(width: FriendsMetric.waySlot)
        .contentShape(Rectangle())
    }
}

/// No friends and no requests: three grey faces, one line, and Invite friends (Apple's share sheet).
struct FriendsEmptyInvite: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: -FriendsMetric.ghostOverlap) {
                ForEach(0..<3, id: \.self) { _ in
                    Image(systemName: "person.fill")
                        .font(.glyph(28, weight: .regular))
                        .foregroundStyle(Hue.inkSecondary.opacity(0.55))
                        .frame(width: FriendsMetric.ghost, height: FriendsMetric.ghost)
                        .background(Circle().fill(Hue.hairline))
                        .overlay(Circle().strokeBorder(Hue.paper, lineWidth: FriendsMetric.ghostRing))
                }
            }
            .accessibilityHidden(true)
            Text("No friends yet")
                .font(.sansBold(20))
                .foregroundStyle(Hue.ink)
                .padding(.top, FriendsMetric.emptyTitleTop)
                .accessibilityAddTraits(.isHeader)
            Text("Invite your neighbors to Block Party.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, FriendsMetric.emptyLineTop)
            ShareLink(item: FriendsInvite.link, message: Text(FriendsInvite.words)) {
                Label("Invite friends", systemImage: "square.and.arrow.up")
                    .font(.sansSemibold(17))
                    .foregroundStyle(Hue.surface)
                    .frame(maxWidth: .infinity)
                    .frame(height: FriendsMetric.invite)
                    .background(Capsule().fill(Hue.ink))
            }
            .buttonStyle(PressableStyle())
            .padding(.top, FriendsMetric.inviteTop)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FriendsMetric.inviteSide)
        .padding(.top, FriendsMetric.emptyTop)
    }
}

/// Messages: Apple's message composer with the message filled in, to `phone` when Contacts gives
/// one. Where the phone can't text, Contacts' Invite opens Apple's share sheet with the same words.
@MainActor
enum FriendsInvitePresenter {
    static func messages(to phone: String? = nil) {
        guard let top = topController() else { return }
        if MessagesComposer.canSend {
            MessagesComposer.present(from: top, text: FriendsInvite.message, image: nil, recipients: phone.map { [$0] } ?? [])
        } else {
            let sheet = UIActivityViewController(activityItems: [FriendsInvite.message], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = top.view
            top.present(sheet, animated: true)
        }
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
