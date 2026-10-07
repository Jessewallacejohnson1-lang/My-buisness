//
//  FriendsPage.swift
//  Block Party — the friends inbox, pushed on the shell's stack from the Town bar's friends
//  mark. Option B of Jesse's Figma (2026-10-06): WhatsApp's large-title list (title, field,
//  filter pills, 76pt rows with 52pt photos) with option A's 8pt black unread dot. The
//  field, the pills and the back button are Search's, so the two read as one app.
//

import SwiftUI

/// Sizes in points, measured off the Figma frame "B · Friends, iOS list (WhatsApp)" and
/// WhatsApp's chats list (references/friends-inbox/whatsapp-chats.jpg).
nonisolated enum FriendsMetric {
    static let side: CGFloat = 16
    /// The large title's line; WhatsApp's "Chats" is 34pt bold with 24pt caps.
    static let titleLine: CGFloat = 41
    static let titleToField: CGFloat = 11
    static let row: CGFloat = 76
    static let avatar: CGFloat = 52
    static let avatarGap: CGFloat = 12
    static let lineGap: CGFloat = 2
    /// Option A's unread dot, centred under the time where WhatsApp's count sits.
    static let dot: CGFloat = 8
    static let dotTrail: CGFloat = 6
    static let ring: CGFloat = 0.5
    static let hairline: CGFloat = 0.5

    // The chat, off Instagram's (references/friends-inbox/instagram-chat.jpg): the bar runs
    // from the safe area to its hairline 70pt down, a 32pt face 10pt after the back button.
    static let chatBar: CGFloat = 70
    static let barFace: CGFloat = 32
    static let barFaceGap: CGFloat = 10
    static let heroTop: CGFloat = 20
    static let hero: CGFloat = 96
    static let heroNameTop: CGFloat = 12
    static let stampTop: CGFloat = 28
    static let stampBottom: CGFloat = 16
    static let bubbleFace: CGFloat = 28
    static let bubbleFaceGap: CGFloat = 8
    /// The Figma frame's 250pt of text plus the bubble's 14pt sides.
    static let bubbleMax: CGFloat = 278
    static let bubbleH: CGFloat = 14
    static let bubbleV: CGFloat = 9
    /// 4 between one person's bubbles, 32 when the other person answers: the Figma frame's.
    static let sameGap: CGFloat = 4
    static let turnGap: CGFloat = 32
    static let historyBottom: CGFloat = 16
    // The composer: Instagram's 44pt pill, 9pt in from each side and above the home bar.
    static let composer: CGFloat = 44
    static let composerSide: CGFloat = 9
    static let composerTextLead: CGFloat = 16
    static let composerTextV: CGFloat = 11
    static let send: CGFloat = 34
    static let sendInset: CGFloat = 5
}

struct FriendsPage: View {
    @Environment(FriendsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @Namespace private var chipNS
    /// The large title has gone under the bar: the bar shows the small one.
    @State private var titleUnder = false

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Friends")
                        .font(.sansBold(34))
                        .foregroundStyle(Hue.ink)
                        .frame(height: FriendsMetric.titleLine)
                        .padding(.horizontal, FriendsMetric.side)
                        .accessibilityAddTraits(.isHeader)
                    field
                        .padding(.horizontal, FriendsMetric.side)
                        .padding(.top, FriendsMetric.titleToField)
                    chips
                        .padding(.top, SearchMetric.chipsTop)
                        .padding(.bottom, SearchMetric.headBottom)
                    ForEach(model.visible) { chat in
                        NavigationLink(value: FriendsRoute.chat(chat.id)) {
                            FriendRow(chat: chat)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                .padding(.top, SearchMetric.pageBar)
            }
            .scrollDismissesKeyboard(.immediately)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > FriendsMetric.titleLine
            } action: { _, under in
                titleUnder = under
            }
            bar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var bar: some View {
        ZStack {
            Text("Friends")
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .opacity(titleUnder ? 1 : 0)
                .accessibilityHidden(true)
            HStack {
                FriendsBackButton { dismiss() }
                Spacer()
            }
            .padding(.leading, SearchMetric.pageBackLead)
        }
        .frame(height: SearchMetric.pageBar)
        .frame(maxWidth: .infinity)
        .background(Hue.paper.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Hue.hairline).frame(height: FriendsMetric.hairline).opacity(titleUnder ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: titleUnder)
    }

    /// Search's field, without Cancel: typing narrows the rows by name.
    private var field: some View {
        @Bindable var model = model
        return HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(15, weight: .medium))
                .foregroundStyle(Hue.searchFaint)
                .frame(width: SearchMetric.fieldIcon, height: SearchMetric.fieldIcon)
                .padding(.leading, SearchMetric.fieldIconLead)
                .padding(.trailing, SearchMetric.fieldIconGap)
                .accessibilityHidden(true)
            TextField("Search", text: $model.words, prompt: Text("Search").foregroundStyle(Hue.searchFaint))
                .font(.sans(16))
                .foregroundStyle(Hue.ink)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !model.words.isEmpty {
                Button {
                    model.words = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Hue.surface, Hue.searchClear)
                        .font(.glyph(17))
                        .frame(width: SearchMetric.clearSide, height: SearchMetric.clearSide)
                        .contentShape(Rectangle().inset(by: (SearchMetric.clearSide - SearchMetric.tapMin) / 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .frame(height: SearchMetric.fieldHeight)
        .background(Hue.searchField, in: RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous))
    }

    /// Search's pills: the ink one slides to the picked filter.
    private var chips: some View {
        HStack(spacing: SearchMetric.chipGap) {
            ForEach(FriendsFilter.allCases, id: \.self) { f in
                let on = f == model.filter
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { model.filter = f }
                } label: {
                    Text(f.title)
                        .font(.sansSemibold(14))
                        .foregroundStyle(on ? Hue.surface : Hue.ink)
                        .padding(.horizontal, SearchMetric.chipPad)
                        .frame(height: SearchMetric.chipHeight)
                        .background {
                            if on {
                                Capsule().fill(Hue.ink).matchedGeometryEffect(id: "chip", in: chipNS)
                            } else {
                                Capsule().strokeBorder(Hue.searchChipEdge, lineWidth: 1)
                            }
                        }
                        .contentShape(Rectangle().inset(by: (SearchMetric.chipHeight - SearchMetric.tapMin) / 2))
                }
                .buttonStyle(SquishStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: SearchMetric.chipsHeight)
    }
}

/// One chat in the inbox: face, name and time, last message and the unread dot.
private struct FriendRow: View {
    let chat: FriendChat

    var body: some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            FriendFace(photo: chat.photo, size: FriendsMetric.avatar)
            VStack(alignment: .leading, spacing: FriendsMetric.lineGap) {
                HStack(spacing: 8) {
                    Text(chat.name)
                        .font(.sansSemibold(17))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let last = chat.last {
                        Text(FriendsModel.timeLabel(last.at))
                            .font(chat.unread ? .sansSemibold(15) : .sans(15))
                            .foregroundStyle(chat.unread ? Hue.ink : Hue.inkSecondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(chat.preview)
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if chat.unread {
                        Circle()
                            .fill(Hue.ink)
                            .frame(width: FriendsMetric.dot, height: FriendsMetric.dot)
                            .padding(.trailing, FriendsMetric.dotTrail)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Hue.hairline).frame(height: FriendsMetric.hairline)
            }
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: FriendsMetric.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([chat.name, chat.preview, chat.last.map { FriendsModel.timeLabel($0.at) } ?? "",
                             chat.unread ? "Unread" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// A round face: a bundled town photo in a hairline ring, as Search's faces are drawn.
struct FriendFace: View {
    let photo: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Hue.fill)
            .overlay {
                if let url = Bundle.main.url(forResource: photo, withExtension: "jpg") {
                    FeedCardURLPhoto(url: url, loadingFill: .clear)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Hue.ink.opacity(0.16), lineWidth: FriendsMetric.ring))
            .accessibilityHidden(true)
    }
}

/// Search's back chevron: 44pt, fades while pressed.
struct FriendsBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.glyph(20, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: SearchMetric.pageBar, height: SearchMetric.pageBar)
                .contentShape(Rectangle())
        }
        .buttonStyle(DimStyle())
        .accessibilityLabel("Back")
    }
}
