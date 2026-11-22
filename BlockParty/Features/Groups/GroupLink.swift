//
//  GroupLink.swift
//  Block Party — a Group's own link and code (BP app docs/plans/start-a-group, ticket 07; Figma frame 5 Jesse said
//  yes to on 2026-11-21). Invite friends shows Share link, Copy link and Code as the Friends card's round buttons;
//  Code is Your code's sheet with the Group's link. The link is the website's `/g/<id>`, which shows the Group to
//  someone without the app and hands it to the app with `blockparty://group/<id>`. It opens the app by itself once
//  Apple's paid developer account turns on app links (BP app backlog 10); the app reads both forms.
//

import SwiftUI
import UIKit

/// What a Group's link says, and which Group an opened link names.
nonisolated enum GroupLink {
    static let host = "group"
    static let webPath = "g"

    /// The Group's link: the website's page for it.
    static func link(for groupID: String) -> URL {
        URL(string: "https://blockpartymn.com/\(webPath)/\(groupID.lowercased())")!
    }

    /// The Group a link names, as a lowercase id: the website's `/g/<id>` or the app link. Anything else is nil.
    static func groupID(from url: URL) -> String? {
        YourCode.id(in: url, appHost: host, webPath: webPath)
    }
}

/// Invite friends' row of round buttons (frame 5): Share link (Block Party's share sheet), Copy link, Code.
struct GroupInviteWays: View {
    let group: TownGroup
    @State private var copied = false
    @State private var showingCode = Self.codeAtLaunch

    /// DEBUG `-group-invite code`: Code open at once.
    private static var codeAtLaunch: Bool {
        #if DEBUG
        return LaunchFlags.value(.groupInvite) == "code"
        #else
        return false
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            way("Share link") {
                Image(systemName: "square.and.arrow.up").font(.glyph(21, weight: .medium)).foregroundStyle(Hue.ink)
            } action: {
                ShareCenter.shared.present(.group(group))
            }
            way(copied ? "Copied" : "Copy link") {
                Image(systemName: copied ? "checkmark" : "link")
                    .font(.glyph(21, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .contentTransition(.symbolEffect(.replace))
            } action: {
                UIPasteboard.general.url = GroupLink.link(for: group.id)
                Haptics.light()
                copied = true
            }
            .accessibilityLabel("Copy link")
            .accessibilityValue(copied ? "Copied" : "")
            way("Code") {
                Image(systemName: "qrcode").font(.glyph(21, weight: .medium)).foregroundStyle(Hue.ink)
            } action: {
                showingCode = true
            }
            Spacer(minLength: 0)
        }
        // The first circle's edge on the friends' faces' line.
        .padding(.horizontal, FriendsMetric.side - (FriendsMetric.waySlot - FriendsMetric.wayCircle) / 2)
        .padding(.vertical, FriendsMetric.waysPadBottom)
        .sheet(isPresented: $showingCode) { GroupCodeSheet(group: group) }
        .animation(.easeInOut(duration: 0.18), value: copied)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: FriendsMetric.copiedHold)
            copied = false
        }
    }

    private func way(_ word: String, @ViewBuilder glyph: () -> some View,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) { WayFace(word: word, glyph: glyph) }
            .buttonStyle(.press(.squish))
    }
}

/// A Group's code: Your code's sheet with the Group's picture, name and kind, and its link.
struct GroupCodeSheet: View {
    let group: TownGroup

    var body: some View {
        let link = GroupLink.link(for: group.id)
        CodeSheet(name: group.name, line: GroupPage.kindLine(group), link: link, label: "\(group.name) code",
                  hint: "Let a friend scan this.") {
            Hue.fill
                .overlay {
                    // You's Group circle, grown from its 62 pt to the code's face.
                    YouGroupPicture(group: group,
                                    logoSide: YouMetric.groupLogo * FriendsMetric.codeFace / YouMetric.highlightPhoto,
                                    glyph: YouMetric.groupGlyph * FriendsMetric.codeFace / YouMetric.highlightPhoto)
                }
                .frame(width: FriendsMetric.codeFace, height: FriendsMetric.codeFace)
                .clipShape(Circle())
        } buttons: { share in
            if let share {
                let image = Image(uiImage: share)
                ShareLink(item: image, message: Text(SharePayload.group(group).shareText),
                          preview: SharePreview(group.name, image: image)) {
                    CodeAction(word: "Share", glyph: "square.and.arrow.up", ink: true)
                }
                .buttonStyle(.press(.squish))
            }
        }
    }
}
