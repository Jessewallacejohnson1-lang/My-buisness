//
//  ChatPicker.swift
//  Block Party — who a message goes to (BP app five-tabs 05). The pencil in Messages picks one friend or several,
//  a group of friends with a name if you like, and opens the chat. "Send in a chat" on an Event's share sheet
//  lists your chats and friends, each with Instagram's Send, which sends the Event's card at once.
//

import SwiftUI

struct ChatPicker: View {
    /// The Event being sent; nil for a new message.
    var card: FeedCardItem? = nil

    @Environment(ChatBook.self) private var chats
    @Environment(FriendsBook.self) private var book
    @Environment(\.dismiss) private var dismiss
    @State private var words = ""
    @State private var picked: [Neighbor] = []
    @State private var name = ""
    @State private var sent: Set<String> = []
    /// Who an Event can go to, kept as the sheet opened: a send moves a chat up the list behind it,
    /// and the row under your thumb mustn't move.
    @State private var targets: [Target] = []
    @State private var failures = 0
    @State private var starting = false
    @State private var failed = false

    private static let groupMax = 31

    private func matches(_ text: String) -> Bool {
        let typed = words.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty || TownSearch.score(typed, name: text, extra: [], aliases: []) != nil
    }

    private var friends: [Neighbor] { book.friends.filter { matches($0.displayName) } }

    /// A chat, or a friend you haven't one with.
    private struct Target: Identifiable {
        let id: String
        let name: String
        var chat: Chat? = nil
        var person: Neighbor? = nil
    }

    /// For an Event: your chats first, then friends you haven't one with.
    private func listTargets() -> [Target] {
        chats.messages.filter { !$0.waiting }.map { Target(id: $0.id, name: $0.title, chat: $0) }
            + book.friends.filter { chats.chat(with: $0) == nil }
                .map { Target(id: $0.id, name: $0.displayName, person: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FriendsSearchField(words: $words)
                        .padding(.horizontal, ChatMetric.side)
                        .padding(.bottom, ChatMetric.sectionBottom)
                    if card == nil { picking } else { sending }
                    if !book.loaded {
                        ProgressView().frame(maxWidth: .infinity, minHeight: ChatMetric.older)
                    } else if friends.isEmpty && (card == nil || targets.isEmpty) {
                        Text("Add a friend to start a chat.")
                            .font(.sans(14))
                            .foregroundStyle(Hue.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: ChatMetric.older)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Hue.paper)
            .navigationTitle(card == nil ? "New message" : "Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { if card == nil && !picked.isEmpty { start } }
        }
        .task { await book.refresh() }
        .onChange(of: book.loaded, initial: true) { _, loaded in
            if loaded, targets.isEmpty { targets = listTargets() }
        }
        .presentationDetents([.large])
    }

    // MARK: New message

    @ViewBuilder private var picking: some View {
        if picked.count > 1 {
            TextField("Group name (optional)", text: $name)
                .font(.sans(16))
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, ChatMetric.side)
                .frame(minHeight: PageMetric.tapMin)
        }
        ForEach(friends) { person in
            let on = picked.contains(person)
            Button { toggle(person) } label: {
                HStack(spacing: ChatMetric.rowGap) {
                    PersonFace(person: person)
                    Text(person.displayName)
                        .font(.sansSemibold(15))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.glyph(22))
                        .foregroundStyle(on ? Hue.ink : Hue.edge)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, ChatMetric.side)
                .padding(.vertical, ChatMetric.rowPad)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    private func toggle(_ person: Neighbor) {
        Haptics.selection()
        if picked.contains(person) {
            picked.removeAll { $0 == person }
        } else if picked.count < Self.groupMax {
            picked.append(person)
        }
    }

    private var start: some View {
        Button { open() } label: {
            Text(picked.count == 1 ? "Chat" : "Start group of \(picked.count + 1)")
                .font(.sansSemibold(16))
                .foregroundStyle(Hue.surface)
                .frame(maxWidth: .infinity, minHeight: PageMetric.tapMin + 4)
                .background(Hue.ink, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
        .disabled(starting)
        .turnBackShake(failures: failures, shakes: true)
        .padding(.horizontal, ChatMetric.side)
        .padding(.vertical, ChatMetric.composerY)
        .background(Hue.paper)
    }

    private func open() {
        guard let first = picked.first else { return }
        if picked.count == 1 {
            dismiss()
            chats.push?(.person(first))
            return
        }
        starting = true
        Task {
            do {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = trimmed.isEmpty ? nil : trimmed
                let id = try await chats.api.startGroup(picked.map(\.id), name: label)
                dismiss()
                chats.push?(.group(id: id, others: picked, name: label))
            } catch {
                Log.network("ChatPicker: \(error)")
                failures += 1
                Haptics.error()
            }
            starting = false
        }
    }

    // MARK: Sending an Event

    @ViewBuilder private var sending: some View {
        ForEach(targets.filter { matches($0.name) }) { target in
            row(key: target.id, name: target.name) {
                if let chat = target.chat {
                    ChatFace(chat: chat)
                } else if let person = target.person {
                    PersonFace(person: person)
                }
            } send: {
                await deliver(key: target.id, chat: target.chat?.id, to: target.person?.id)
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
            .buttonStyle(SquishStyle())
            .disabled(done)
            .accessibilityLabel(done ? "Sent to \(name)" : "Send to \(name)")
        }
        .padding(.horizontal, ChatMetric.side)
        .padding(.vertical, ChatMetric.rowPad)
    }

    /// Sent at once: the button says so, and turns back with a shake if it didn't go.
    private func deliver(key: String, chat: String?, to person: String?) async {
        guard let card else { return }
        withAnimation(Motion.snappy) { _ = sent.insert(key) }
        Haptics.light()
        do {
            _ = try await chats.api.send(chat: chat, to: person, client: UUID().uuidString.lowercased(), .event(card.id))
            await chats.refresh()
        } catch {
            Log.network("ChatPicker send: \(error)")
            withAnimation(Motion.snappy) { _ = sent.remove(key) }
            Haptics.error()
        }
    }
}

private struct PersonFace: View {
    let person: Neighbor

    var body: some View {
        Avatar(avatarUrl: person.avatarUrl, size: ChatMetric.face)
    }
}
