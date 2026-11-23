//
//  ChatPicker.swift
//  Block Party — who an Event goes to (BP app five-tabs 05, share-sheet 01). The share sheet's people row shows them
//  as faces, and its Search lists them all with Instagram's Send; either sends the Event's card at once. A new
//  message's people are `NewMessagePage`.
//

import SwiftUI

/// Who an Event can go to, and who it has gone to: your chats first, then your Groups with no chat yet, then friends
/// you haven't one with. Kept as the sheet opened: a send moves a chat up the list behind it, and the face under your
/// thumb mustn't move.
@MainActor @Observable
final class ChatSendList {
    struct Target: Identifiable {
        let id: String
        let name: String
        var chat: Chat? = nil
        var group: TownGroup? = nil
        var person: Neighbor? = nil

        /// Its picture is a friend, or a chat of friends, not an Event's or a Group's.
        var isPeople: Bool { group == nil && chat?.card == nil && chat?.clubId == nil }
    }

    /// The Event being sent.
    let card: FeedCardItem
    let chats: ChatBook
    let book: FriendsBook
    /// Nil until read.
    private(set) var targets: [Target]?
    private(set) var sent: Set<String> = []

    init(card: FeedCardItem, chats: ChatBook, book: FriendsBook) {
        self.card = card
        self.chats = chats
        self.book = book
    }

    func load(you: YouModel?, actions: RealLifeActions?) async {
        guard targets == nil else { return }
        await book.refresh()
        let groups = await chats.groupsToSend(Self.yourGroups(you: you, actions: actions))
        guard targets == nil else { return }
        targets = chats.messages.filter { !$0.waiting && $0.kind != .going }.map { Target(id: $0.id, name: $0.title, chat: $0) }
            + groups.map { Target(id: $0.id, name: $0.name, group: $0) }
            + book.friends.filter { chats.chat(with: $0) == nil }.map { Target(id: $0.id, name: $0.displayName, person: $0) }
    }

    /// The Groups you're in, read now if nothing has read them yet.
    private static func yourGroups(you: YouModel?, actions: RealLifeActions?) async -> [TownGroup] {
        guard let you, let actions else { return [] }
        let all: [TownGroup]
        if let read = you.groups { all = read } else { all = await you.refreshGroups() ?? [] }
        return all.filter { actions.member($0).isMember }
    }

    /// Sent at once: the face says so, and turns back with a shake if it didn't go. A Group with no chat yet gets one
    /// first, as opening it from its page does.
    func deliver(_ target: Target) async {
        guard !sent.contains(target.id) else { return }
        withAnimation(Motion.snappy) { _ = sent.insert(target.id) }
        Haptics.light()
        do {
            var chat = target.chat?.id
            if let group = target.group?.id { chat = try await chats.api.joinGroup(group) }
            _ = try await chats.api.send(chat: chat, to: target.person?.id, client: UUID().uuidString.lowercased(),
                                         .event(card.id))
            await chats.refresh()
        } catch {
            Log.network("ChatSendList send: \(error)")
            withAnimation(Motion.snappy) { _ = sent.remove(target.id) }
            Haptics.error()
        }
    }
}

/// A target's picture: the chat's, the Group's, or the friend's face.
struct ChatTargetFace: View {
    let target: ChatSendList.Target
    var size = ChatMetric.face

    var body: some View {
        if let chat = target.chat {
            ChatFace(chat: chat, size: size)
        } else if let group = target.group {
            ChatGroupFace(group: group, size: size)
        } else {
            Avatar(avatarUrl: target.person?.avatarUrl, size: size)
        }
    }
}

/// The share sheet's Search: everyone an Event can go to, with a search box and Instagram's Send.
struct ChatPicker: View {
    let list: ChatSendList
    let close: () -> Void
    @State private var words = ""

    private func matches(_ text: String) -> Bool {
        let typed = words.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty || TownSearch.score(typed, name: text, extra: [], aliases: []) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FriendsSearchField(words: $words)
                        .padding(.horizontal, ChatMetric.side)
                        .padding(.bottom, ChatMetric.sectionBottom)
                    if let targets = list.targets {
                        ForEach(targets.filter { matches($0.name) }) { row($0) }
                        if targets.isEmpty {
                            Text("Add a friend to start a chat.")
                                .font(.sans(14))
                                .foregroundStyle(Hue.inkSecondary)
                                .frame(maxWidth: .infinity, minHeight: ChatMetric.older)
                        }
                    } else {
                        SkeletonBlock(cornerRadius: ChatMetric.loadingLine / 2)
                            .frame(width: ChatMetric.loadingName, height: ChatMetric.loadingLine)
                            .frame(maxWidth: .infinity, minHeight: ChatMetric.older)
                            .shimmering()
                            .accessibilityLabel("Loading")
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Hue.surface)
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: close) }
            }
        }
    }

    private func row(_ target: ChatSendList.Target) -> some View {
        let done = list.sent.contains(target.id)
        return HStack(spacing: ChatMetric.rowGap) {
            ChatTargetFace(target: target)
            Text(target.name)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { Task { await list.deliver(target) } } label: {
                Text(done ? "Sent" : "Send")
                    .font(.sansSemibold(14))
                    .foregroundStyle(done ? Hue.ink : Hue.surface)
                    .padding(.horizontal, ChatMetric.chipPad)
                    .frame(height: ChatMetric.chipHeight)
                    .background(done ? Hue.fill : Hue.ink, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .frame(minHeight: PageMetric.tapMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .disabled(done)
            .accessibilityLabel(done ? "Sent to \(target.name)" : "Send to \(target.name)")
        }
        .padding(.horizontal, ChatMetric.side)
        .padding(.vertical, ChatMetric.rowPad)
    }
}
