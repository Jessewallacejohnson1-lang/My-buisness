//
//  MessagesPage.swift
//  Block Party — Messages (BP app five-tabs 05): the paper plane on Friends opens it. Instagram's inbox
//  without Notes (mock round 2): the pencil, search, your chats newest first with Requests across from their
//  title, and when you have no chats yet, your friends to start one with. Requests is its own list.
//

import SwiftUI

/// Sizes from the mock's Messages (`references/five-tabs/mock`), itself Instagram's inbox measured.
nonisolated enum ChatMetric {
    static let side: CGFloat = 16
    static let face: CGFloat = 56
    /// Two faces for a group: 40 each, one up and right, one down and left.
    static let duoFace: CGFloat = 40
    static let rowGap: CGFloat = 12
    static let rowPad: CGFloat = 8
    static let unreadDot: CGFloat = 8
    static let sectionTop: CGFloat = 14
    static let sectionBottom: CGFloat = 6
    static let loadingRows = 6
    static let loadingName: CGFloat = 140
    static let loadingLine: CGFloat = 12
    static let planeGlyph: CGFloat = 25
    /// The plane's red dot, on its top right.
    static let planeDot: CGFloat = 9
    static let planeDotInset: CGFloat = 8
    /// On a neighbour's Profile, in the cover's white circle (picked).
    static let profileGlyph: CGFloat = 18

    // A chat (`ChatPage`), from the mock's chat.
    static let barFace: CGFloat = 34
    static let bubbleMax: CGFloat = 262
    static let bubbleX: CGFloat = 14
    static let bubbleY: CGFloat = 9
    static let threadSide: CGFloat = 12
    static let runGap: CGFloat = 4
    static let groupGap: CGFloat = 10
    static let theirFace: CGFloat = 28
    /// Their bubbles start here, past the face.
    static let theirLead: CGFloat = 36
    static let stampTop: CGFloat = 6
    static let stampBottom: CGFloat = 8
    static let photoWidth: CGFloat = 240
    static let photoTallest: CGFloat = 320
    static let photoQuality: CGFloat = 0.8
    /// What goes up: the same 1290 as a post's photo.
    static let photoUpload: CGFloat = 1290
    static let eventWidth: CGFloat = 250
    static let eventPhoto: CGFloat = 150
    static let eventInsetX: CGFloat = 12
    static let eventInsetY: CGFloat = 10
    static let chipHeight: CGFloat = 32
    static let chipPad: CGFloat = 14
    static let chipGap: CGFloat = 8
    static let typingDot: CGFloat = 7
    static let composerY: CGFloat = 8
    static let composerX: CGFloat = 12
    static let composerButton: CGFloat = 38
    static let composerField: CGFloat = 40
    static let composerLines = 5
    static let sendGlyph: CGFloat = 15
    static let older: CGFloat = 44
}

/// Where chat pushes, on the shell's stack.
enum ChatRoute: Hashable {
    case messages
    case requests
    case chat(Chat)
    /// A chat with one person, whether or not you've one yet.
    case person(Neighbor)
    /// A group just started: it reaches its people with its first message.
    case group(id: String, others: [Neighbor], name: String?)
}

/// The paper plane at the top right of Friends: it shows once you've a friend or a chat, and its red dot
/// only for an unread message (mock round 2). Requests light nothing.
struct MessagesPlane: View {
    @Environment(ChatBook.self) private var chats

    var body: some View {
        NavigationLink(value: ChatRoute.messages) {
            FeedActionGlyphView(glyph: .send, size: ChatMetric.planeGlyph)
                .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                .overlay(alignment: .topTrailing) {
                    if chats.unread {
                        Circle().fill(Hue.unread)
                            .frame(width: ChatMetric.planeDot, height: ChatMetric.planeDot)
                            .overlay(Circle().stroke(Hue.paper, lineWidth: 2))
                            .padding(ChatMetric.planeDotInset)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
        .animation(Motion.smooth, value: chats.unread)
        .accessibilityLabel(chats.unread ? "Messages, unread message" : "Messages")
    }
}

struct MessagesPage: View {
    @Environment(ChatBook.self) private var chats
    @Environment(FriendsBook.self) private var book
    @State private var words = ""
    @State private var picking = false

    private var typing: Bool { !words.trimmingCharacters(in: .whitespaces).isEmpty }

    private func matches(_ name: String) -> Bool {
        TownSearch.score(words, name: name, extra: [], aliases: []) != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FriendsSearchField(words: $words)
                        .padding(.horizontal, ChatMetric.side)
                    if typing { results } else { list }
                }
                .padding(.top, PageMetric.bar)
                .padding(.bottom, ChatMetric.sectionTop)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await chats.refresh() }
            FriendsTitleBar(title: "Messages", titleUnder: true) {
                Button { picking = true } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.glyph(20))
                        .foregroundStyle(Hue.ink)
                        .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel("New message")
            }
            .accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await chats.refresh() }
        .task { await book.refresh() }
        .sheet(isPresented: $picking) { ChatPicker() }
    }

    @ViewBuilder private var list: some View {
        let mine = chats.messages, requests = chats.requests
        HStack(alignment: .firstTextBaseline) {
            Text("Messages")
                .font(.displaySemi(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !requests.isEmpty {
                NavigationLink(value: ChatRoute.requests) {
                    Text("Requests (\(requests.count))")
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(minHeight: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DimStyle())
            }
        }
        .padding(.horizontal, ChatMetric.side)
        .padding(.top, ChatMetric.sectionTop)
        .padding(.bottom, requests.isEmpty ? ChatMetric.sectionBottom : 0)
        if chats.chats == nil {
            if chats.failed {
                ChatFailedLine { await chats.refresh() }
            } else {
                ChatLoadingRows()
            }
        } else if mine.isEmpty {
            // Nothing yet: your friends to start with, never an empty box.
            ForEach(book.friends) { person in
                NavigationLink(value: ChatRoute.person(person)) { FriendToChatRow(person: person) }
                    .buttonStyle(RowPressStyle())
            }
        } else {
            ForEach(mine) { chat in ChatRow(chat: chat) }
        }
    }

    /// What's typed, by name: your chats, then friends you haven't one with.
    @ViewBuilder private var results: some View {
        let found = (chats.chats ?? []).filter { matches($0.title) }
        let friends = book.friends.filter { person in matches(person.displayName) && chats.chat(with: person) == nil }
        Color.clear.frame(height: ChatMetric.sectionTop)
        if found.isEmpty && friends.isEmpty {
            NothingFound()
        } else {
            ForEach(found) { chat in ChatRow(chat: chat) }
            ForEach(friends) { person in
                NavigationLink(value: ChatRoute.person(person)) { FriendToChatRow(person: person) }
                    .buttonStyle(RowPressStyle())
            }
        }
    }
}

/// Requests: messages from people who aren't your friends. Opening one tells them nothing.
struct RequestsPage: View {
    @Environment(ChatBook.self) private var chats

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Only you can see these until you accept. They won't know you've read them.")
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .padding(.horizontal, ChatMetric.side)
                        .padding(.vertical, ChatMetric.sectionBottom)
                    ForEach(chats.requests) { chat in ChatRow(chat: chat) }
                }
                .padding(.top, PageMetric.bar)
            }
            FriendsTitleBar(title: "Requests", titleUnder: true).accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One chat in the list: its face or faces, its name, what was said and when, and the mock's ink dot when unread.
private struct ChatRow: View {
    let chat: Chat

    var body: some View {
        NavigationLink(value: ChatRoute.chat(chat)) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: ChatMetric.rowGap) {
                    ChatFace(chat: chat)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(chat.title)
                            .font(.sansSemibold(15))
                            .foregroundStyle(Hue.ink)
                            .lineLimit(1)
                        Text("\(ChatWords.preview(chat)) · \(ChatWords.ago(chat.lastDate, now: context.date))")
                            .font(chat.unread ? .sansSemibold(14) : .sans(14))
                            .foregroundStyle(chat.unread ? Hue.ink : Hue.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if chat.unread {
                        Circle().fill(Hue.ink).frame(width: ChatMetric.unreadDot, height: ChatMetric.unreadDot)
                    }
                }
                .padding(.horizontal, ChatMetric.side)
                .padding(.vertical, ChatMetric.rowPad)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([chat.title, chat.unread ? "Unread" : nil, ChatWords.preview(chat),
                             ChatWords.ago(chat.lastDate)].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// A friend you haven't a chat with: Instagram's Suggestions row.
private struct FriendToChatRow: View {
    let person: Neighbor

    var body: some View {
        HStack(spacing: ChatMetric.rowGap) {
            Avatar(avatarUrl: person.avatarUrl, size: ChatMetric.face)
            VStack(alignment: .leading, spacing: 0) {
                Text(person.displayName)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                Text("Tap to chat")
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ChatMetric.side)
        .padding(.vertical, ChatMetric.rowPad)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A chat's picture: the friend's face, or for a group two faces overlapping.
struct ChatFace: View {
    let chat: Chat
    var size = ChatMetric.face

    var body: some View {
        if chat.kind == .direct || chat.others.count < 2 {
            Avatar(avatarUrl: chat.others.first?.avatarUrl, size: size)
        } else {
            let small = size * ChatMetric.duoFace / ChatMetric.face
            ZStack {
                Avatar(avatarUrl: chat.others[0].avatarUrl, size: small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Avatar(avatarUrl: chat.others[1].avatarUrl, size: small)
                    .overlay(Circle().stroke(Hue.paper, lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(width: size, height: size)
        }
    }
}

private struct ChatLoadingRows: View {
    var body: some View {
        ForEach(0..<ChatMetric.loadingRows, id: \.self) { _ in
            HStack(spacing: ChatMetric.rowGap) {
                SkeletonBlock(cornerRadius: ChatMetric.face / 2)
                    .frame(width: ChatMetric.face, height: ChatMetric.face)
                SkeletonBlock(cornerRadius: ChatMetric.loadingLine / 2)
                    .frame(width: ChatMetric.loadingName, height: ChatMetric.loadingLine)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ChatMetric.side)
            .padding(.vertical, ChatMetric.rowPad)
            .shimmering()
            .accessibilityHidden(true)
        }
    }
}

/// A read that failed, with nothing to show: the Town feed's words, and a way to try again.
struct ChatFailedLine: View {
    let retry: () async -> Void

    var body: some View {
        Button { Task { await retry() } } label: {
            Text("Check your connection and try again.")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: PageMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(DimStyle())
    }
}
