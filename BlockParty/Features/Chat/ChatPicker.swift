//
//  ChatPicker.swift
//  Block Party — who an Event goes to (BP app five-tabs 05). "Send in a chat" on an Event's share sheet lists your
//  chats, your Groups and friends, each with Instagram's Send, which sends the Event's card at once. A new message's
//  people are `NewMessagePage`.
//

import SwiftUI

struct ChatPicker: View {
    /// The Event being sent.
    let card: FeedCardItem

    @Environment(ChatBook.self) private var chats
    @Environment(FriendsBook.self) private var book
    @Environment(YouModel.self) private var you: YouModel?
    @Environment(RealLifeActions.self) private var actions: RealLifeActions?
    @Environment(\.dismiss) private var dismiss
    @State private var words = ""
    @State private var sent: Set<String> = []
    /// Who an Event can go to, kept as the sheet opened: a send moves a chat up the list behind it,
    /// and the row under your thumb mustn't move.
    @State private var targets: [Target] = []
    /// Your Groups with no chat on your list yet (five-tabs 09); nil until asked.
    @State private var groups: [TownGroup]?

    private func matches(_ text: String) -> Bool {
        let typed = words.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty || TownSearch.score(typed, name: text, extra: [], aliases: []) != nil
    }

    private var friends: [Neighbor] { book.friends.filter { matches($0.displayName) } }

    /// A chat, a Group with none yet, or a friend you haven't one with.
    private struct Target: Identifiable {
        let id: String
        let name: String
        var chat: Chat? = nil
        var group: TownGroup? = nil
        var person: Neighbor? = nil
    }

    /// For an Event: your chats first, then your Groups with no chat yet, then friends you haven't one with.
    private func listTargets() -> [Target] {
        chats.messages.filter { !$0.waiting && $0.kind != .going }.map { Target(id: $0.id, name: $0.title, chat: $0) }
            + (groups ?? []).map { Target(id: $0.id, name: $0.name, group: $0) }
            + book.friends.filter { chats.chat(with: $0) == nil }
                .map { Target(id: $0.id, name: $0.displayName, person: $0) }
    }

    /// The Groups you're in, read now if nothing has read them yet.
    private func yourGroups() async -> [TownGroup] {
        guard let you, let actions else { return [] }
        let all: [TownGroup]
        if let read = you.groups { all = read } else { all = await you.refreshGroups() ?? [] }
        return all.filter { actions.member($0).isMember }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FriendsSearchField(words: $words)
                        .padding(.horizontal, ChatMetric.side)
                        .padding(.bottom, ChatMetric.sectionBottom)
                    sending
                    if !book.loaded || groups == nil {
                        SkeletonBlock(cornerRadius: ChatMetric.loadingLine / 2)
                            .frame(width: ChatMetric.loadingName, height: ChatMetric.loadingLine)
                            .frame(maxWidth: .infinity, minHeight: ChatMetric.older)
                            .shimmering()
                            .accessibilityLabel("Loading")
                    } else if friends.isEmpty && targets.isEmpty {
                        Text("Add a friend to start a chat.")
                            .font(.sans(14))
                            .foregroundStyle(Hue.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: ChatMetric.older)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Hue.paper)
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { await book.refresh() }
        .task { groups = await chats.groupsToSend(yourGroups()) }
        .onChange(of: book.loaded && groups != nil, initial: true) { _, ready in
            if ready, targets.isEmpty { targets = listTargets() }
        }
        .presentationDetents([.large])
    }

    // MARK: Sending an Event

    @ViewBuilder private var sending: some View {
        ForEach(targets.filter { matches($0.name) }) { target in
            row(key: target.id, name: target.name) {
                if let chat = target.chat {
                    ChatFace(chat: chat)
                } else if let group = target.group {
                    ChatGroupFace(group: group)
                } else if let person = target.person {
                    Avatar(avatarUrl: person.avatarUrl, size: ChatMetric.face)
                }
            } send: {
                await deliver(key: target.id, chat: target.chat?.id, group: target.group?.id, to: target.person?.id)
            }
        }
    }

    private func row<Face: View>(key: String, name: String, @ViewBuilder face: () -> Face,
                                 send: @escaping () async -> Void) -> some View {
        let done = sent.contains(key)
        return HStack(spacing: ChatMetric.rowGap) {
            face()
            Text(name)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { Task { await send() } } label: {
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
            .accessibilityLabel(done ? "Sent to \(name)" : "Send to \(name)")
        }
        .padding(.horizontal, ChatMetric.side)
        .padding(.vertical, ChatMetric.rowPad)
    }

    /// Sent at once: the button says so, and turns back with a shake if it didn't go.
    /// A Group with no chat yet gets one first, as opening it from its page does.
    private func deliver(key: String, chat: String?, group: String?, to person: String?) async {
        withAnimation(Motion.snappy) { _ = sent.insert(key) }
        Haptics.light()
        do {
            var chat = chat
            if let group { chat = try await chats.api.joinGroup(group) }
            _ = try await chats.api.send(chat: chat, to: person, client: UUID().uuidString.lowercased(), .event(card.id))
            await chats.refresh()
        } catch {
            Log.network("ChatPicker send: \(error)")
            withAnimation(Motion.snappy) { _ = sent.remove(key) }
            Haptics.error()
        }
    }
}
