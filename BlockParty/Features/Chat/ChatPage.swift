//
//  ChatPage.swift
//  Block Party — one chat (BP app five-tabs 05): Instagram's thread (mock round 2). Your bubbles are ink with
//  white words, theirs the light fill, never yellow (taste, 2026-10-06). Text, a photo or an Event, whose card
//  carries the same Attend as everywhere, with I'm in, Maybe and Can't under one sent to you. Typing dots and
//  Seen, no online status. A request shows Accept, Delete and Block where the composer goes.
//
//  A Going chat (five-tabs 06) is the same thread among strangers: the bar shows its Event, it takes words only, with no
//  Seen or typing dots, and whatever its host writes is an update, drawn as Instagram's channel card.
//
//  Apple's pieces: a bottom-anchored scroll (`defaultScrollAnchor`), the composer in `safeAreaInset`, a growing
//  `TextField`, `PhotosPicker`, and `contextMenu` on a bubble. How Instagram builds its own is a guess.
//

import PhotosUI
import SwiftUI

struct ChatPage: View {
    /// The chat as the list had it; nil for a first message to someone or a group not yet written to.
    let chat: Chat?
    /// Who you're writing to, with no chat yet.
    var person: Neighbor? = nil
    /// A group just made, before its first message reaches the list.
    var groupID: String? = nil
    var groupOthers: [Neighbor] = []
    var groupName: String? = nil
    /// A Going chat's Event, from its page, before the chat reaches the list.
    var event: FeedCardItem? = nil
    var eventHost = false

    @Environment(ChatBook.self) private var chats
    @Environment(FriendsBook.self) private var book
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thread: ChatThread?
    @State private var words = ""
    @State private var pick: PhotosPickerItem?
    @State private var reporting: ChatMessage?
    @State private var reported = false
    /// Who Block is asking about: the friend, or someone in a group from a long press.
    @State private var blocking: Neighbor?
    @State private var askingLeave = false
    @State private var problem: String?
    @FocusState private var typing: Bool

    /// The list's newest word on this chat: a request accepted, a person now waiting.
    private var current: Chat? {
        let id = thread?.chatID ?? chat?.id ?? groupID
        return chats.chats?.first { $0.id == id } ?? chat
    }

    private var others: [Neighbor] {
        if let current, !current.others.isEmpty { return current.others }
        if let person { return [person] }
        return groupOthers
    }

    /// The Event, newest from the list, while this is a Going chat.
    private var goingCard: FeedCardItem? { current?.card ?? event }

    private var isGroup: Bool { goingCard != nil || (current?.kind ?? (groupID != nil ? .group : .direct)) == .group }

    private var title: String {
        goingCard?.title ?? current?.title ?? groupName ?? others.map(isGroup ? \.firstName : \.displayName).joined(separator: ", ")
    }

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            if let thread { content(thread) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Coming back from an Event or a Profile keeps what's here, what failed to send included.
            if thread == nil {
                // A chat with this person that's already there, from their Profile or a search.
                if chats.chats == nil { await chats.refresh() }
                let known = chat ?? person.flatMap { chats.chat(with: $0) }
                let me = (try? chats.api.db.userID) ?? ""
                thread = ChatThread(api: chats.api, me: me, chat: known?.id ?? groupID, to: person?.id, book: chats,
                                    actions: actions, going: goingCard?.id, isHost: event == nil ? chat?.isHost == true : eventHost)
            }
            guard let thread else { return }
            chats.open = thread
            thread.startTyping()
            await thread.read()
            if thread.gone { problem = ChatWords.refused(SupabaseError(message: "chat_not_going", status: nil)) }
        }
        .onDisappear {
            thread?.stopTyping()
            if chats.open === thread { chats.open = nil }
            Task { await chats.refresh() }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await sendPicked(item) }
        }
        #if DEBUG
        .onAppear { if let draft = LaunchFlags.value(.chatDraft) { words = draft } }
        #endif
        .confirmationDialog("Why are you reporting this?", isPresented: reportAsked, titleVisibility: .visible) {
            ForEach(ReportReason.allCases.filter(\.hides)) { reason in
                Button(reason.label) { report(reason) }
            }
            Button("Cancel", role: .cancel) { reporting = nil }
        }
        .alert("Thanks for telling us", isPresented: $reported) {
            if !isGroup, let other = others.first {
                Button("Block \(other.firstName)", role: .destructive) { book.act(.block, other) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("We'll look at it. Nobody is told you reported it.")
        }
        .alert("Block \(blocking?.firstName ?? "")?", isPresented: blockAsked, presenting: blocking) { person in
            Button("Block", role: .destructive) {
                book.act(.block, person)
                thread?.dropMessages(from: person.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see each other's messages or profiles. They won't be told.")
        }
        .alert("Leave this chat?", isPresented: $askingLeave) {
            Button("Leave", role: .destructive) { leave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if goingCard != nil { Text("You'll still be going. Tap Going chat on the Event to come back.") }
        }
        .alert(problem ?? "", isPresented: problemShown) {
            Button("OK", role: .cancel) { if thread?.gone == true { dismiss() } }
        }
        // Blocked, by you or from the friend sheet: this chat is gone.
        .onChange(of: !isGroup && others.first.map { book.relation($0) } == .blocked) { _, gone in
            if gone { dismiss() }
        }
    }

    private var reportAsked: Binding<Bool> {
        Binding { reporting != nil } set: { if !$0 { reporting = nil } }
    }

    private var blockAsked: Binding<Bool> {
        Binding { blocking != nil } set: { if !$0 { blocking = nil } }
    }

    private var problemShown: Binding<Bool> {
        Binding { problem != nil } set: { if !$0 { problem = nil } }
    }

    private func content(_ thread: ChatThread) -> some View {
        VStack(spacing: 0) {
            bar(thread)
            ChatMessages(thread: thread, isGroup: isGroup, others: others, reduceMotion: reduceMotion,
                         answer: { answer($0, card: $1, thread) },
                         report: { reporting = $0 },
                         block: { blocking = $0 })
                .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { foot(thread) }
    }

    // MARK: The bar

    /// Back, who it is (a tap opens their Profile), and the ••• (Apple's menu): Report, then Block or a group's Leave.
    private func bar(_ thread: ChatThread) -> some View {
        HStack(spacing: 0) {
            BackButton { dismiss() }
            Group {
                if let card = goingCard {
                    NavigationLink(value: card) { who }
                        .buttonStyle(.press(.dim))
                } else if !isGroup, let other = others.first {
                    NavigationLink(value: other) { who }
                        .buttonStyle(.press(.dim))
                } else {
                    who
                }
            }
            Spacer(minLength: 0)
            Menu {
                // Not in a Going chat, where whoever spoke last is a stranger: a press reports the right one.
                if goingCard == nil {
                    Button { reporting = thread.lastFromOthers } label: { Label("Report", systemImage: "flag") }
                        .disabled(thread.lastFromOthers == nil)
                }
                if isGroup {
                    Button(role: .destructive) { askingLeave = true } label: {
                        Label("Leave chat", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else if let other = others.first {
                    Button(role: .destructive) { blocking = other } label: {
                        Label("Block \(other.firstName)", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.glyph(18, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options")
            .padding(.trailing, PageMetric.backLead)
        }
        .frame(height: PageMetric.bar)
        .background(Hue.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Hue.hairline).frame(height: FriendsMetric.hairline) }
    }

    private var who: some View {
        HStack(spacing: ChatMetric.chipGap) {
            if let card = goingCard {
                ChatEventFace(card: card, size: ChatMetric.barFace)
            } else if let current {
                ChatFace(chat: current, size: ChatMetric.barFace)
            } else {
                Avatar(avatarUrl: others.first?.avatarUrl, size: ChatMetric.barFace)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.sansSemibold(16))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                if let line {
                    Text(line)
                        .font(.sans(12))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// "Friends since 2024" (the mock's), how many are in a group, or how many are Going, never 0.
    private var line: String? {
        if let card = goingCard {
            let count = actions.going(card).count
            return count > 0 ? "\(count) going" : nil
        }
        if isGroup { return "\(others.count + 1) people" }
        guard let other = others.first, book.relation(other) == .friends,
              let since = other.friendsSince.flatMap(DateHelpers.timestamp) else { return nil }
        return "Friends since \(Town.format(since, "yyyy"))"
    }

    // MARK: The foot

    @ViewBuilder private func foot(_ thread: ChatThread) -> some View {
        if current?.request == true, let current {
            ChatRequestBar(chat: current, name: others.first?.firstName ?? "") { done in
                if done { dismiss() }
            } block: { blocking = others.first }
        } else if current?.waiting == true {
            Text("Sent as a request. You can write more once \(others.first?.firstName ?? "they") accepts.")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ChatMetric.side)
                .padding(.vertical, ChatMetric.composerY)
                .background(Hue.paper)
        } else {
            composer(thread)
        }
    }

    /// The camera's place holds the photo button, the field grows to five lines, and the arrow comes with words.
    private func composer(_ thread: ChatThread) -> some View {
        let empty = words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Before a chat exists with someone who isn't your friend, words alone go.
        let strangers = current == nil && !isGroup && others.first.map { book.relation($0) != .friends } == true
        // A Going chat is words only, and has nowhere to send them until it's joined.
        let ready = !thread.isGoing || thread.chatID != nil
        return HStack(alignment: .bottom, spacing: ChatMetric.chipGap) {
            if !strangers, !thread.isGoing { photoButton(thread) }
            HStack(alignment: .bottom, spacing: 0) {
                TextField(thread.isHost ? "Post an update…" : "Message…", text: $words, axis: .vertical)
                    .font(.sans(16))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1 ... ChatMetric.composerLines)
                    .focused($typing)
                    .padding(.vertical, ChatMetric.bubbleY)
                    .onChange(of: words) { _, new in if !new.isEmpty { thread.typed() } }
                if !empty, ready {
                    Button { send(thread) } label: {
                        Image(systemName: "arrow.up")
                            .font(.glyph(ChatMetric.sendGlyph, weight: .bold))
                            .foregroundStyle(Hue.surface)
                            .frame(width: ChatMetric.composerField - 8, height: ChatMetric.composerField - 8)
                            .background(Hue.ink, in: Circle())
                            .frame(width: PageMetric.tapMin, height: ChatMetric.composerField)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.squish))
                    .accessibilityLabel("Send")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, ChatMetric.side)
            .padding(.trailing, empty ? ChatMetric.side : 0)
            .frame(minHeight: ChatMetric.composerField)
            .background(Hue.fill, in: RoundedRectangle(cornerRadius: ChatMetric.composerField / 2, style: .continuous))
            .animation(reduceMotion ? nil : Motion.snappy, value: empty)
        }
        .padding(.horizontal, ChatMetric.composerX)
        .padding(.vertical, ChatMetric.composerY)
        .background(Hue.paper)
    }

    @ViewBuilder private func photoButton(_ thread: ChatThread) -> some View {
        #if DEBUG
        // `-new-event-photo <file>`: a bundled photo as if picked; AXe can't reach Apple's picker.
        if let file = LaunchFlags.value(.newEventPhoto), let image = UIImage(named: file) {
            Button { Task { await thread.send(photo: image) } } label: { photoGlyph }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("Send a photo")
        } else {
            photoPicker
        }
        #else
        photoPicker
        #endif
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $pick, matching: .images) { photoGlyph }
            .buttonStyle(.press(.squish))
            .accessibilityLabel("Send a photo")
    }

    private var photoGlyph: some View {
        Image(systemName: "photo")
            .font(.glyph(16, weight: .semibold))
            .foregroundStyle(Hue.surface)
            .frame(width: ChatMetric.composerButton, height: ChatMetric.composerButton)
            .background(Hue.ink, in: Circle())
            .frame(width: PageMetric.tapMin, height: ChatMetric.composerField)
            // Apple's 44 reaches a little past the field's height.
            .contentShape(Rectangle().inset(by: (ChatMetric.composerField - PageMetric.tapMin) / 2))
    }

    // MARK: Actions

    private func send(_ thread: ChatThread) {
        let text = words
        words = ""
        Task {
            await thread.send(text)
            surfaceRefusal(thread)
        }
    }

    /// I'm in also marks you Going, unless you already are (Jesse, 2026-11-03); Maybe and Can't say so.
    private func answer(_ words: String, card: FeedCardItem, _ thread: ChatThread) {
        if words == ChatAnswer.yes.sent, !actions.going(card).isGoing { actions.toggleGoing(card) }
        Task { await thread.send(words) }
    }

    private func sendPicked(_ item: PhotosPickerItem) async {
        defer { pick = nil }
        guard let thread, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        // Shrunk to what goes up before anything else, as New post does: a 48 MP photo never sits whole in memory.
        let k = min(1, ChatMetric.photoUpload / max(image.size.width * image.scale, 1))
        let size = CGSize(width: image.size.width * image.scale * k, height: image.size.height * image.scale * k)
        await thread.send(photo: await image.byPreparingThumbnail(ofSize: size) ?? image)
    }

    private func surfaceRefusal(_ thread: ChatThread) {
        if let why = thread.lastRefusal { problem = why }
    }

    private func report(_ reason: ReportReason) {
        guard let id = reporting?.serverID else { return }
        reporting = nil
        Task {
            do {
                try await chats.api.report(message: id, reason: reason)
                reported = true
            } catch {
                problem = "Check your connection and try again."
            }
        }
    }

    private func leave() {
        guard let id = thread?.chatID ?? current?.id else { dismiss(); return }
        Task {
            do {
                try await chats.leave(id)
                dismiss()
            } catch {
                problem = "Check your connection and try again."
            }
        }
    }
}

/// The three answers under an Event sent to you, and what each sends. Working words.
enum ChatAnswer: CaseIterable, Identifiable {
    case yes, maybe, no

    var id: Self { self }

    var label: String {
        switch self {
        case .yes: "I'm in"
        case .maybe: "Maybe"
        case .no: "Can't"
        }
    }

    var sent: String {
        switch self {
        case .yes: "I'm in!"
        case .maybe: "Maybe!"
        case .no: "Can't make it."
        }
    }
}

// MARK: - The messages

private struct ChatMessages: View {
    let thread: ChatThread
    let isGroup: Bool
    let others: [Neighbor]
    let reduceMotion: Bool
    let answer: (String, FeedCardItem) -> Void
    let report: (ChatMessage) -> Void
    let block: (Neighbor) -> Void

    private var names: [String: Neighbor] {
        Dictionary(others.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if thread.hasOlder {
                        // Older messages read as this comes into view: a bubble's shape, shimmering.
                        SkeletonBlock(cornerRadius: Radius.card)
                            .frame(width: ChatMetric.loadingName, height: ChatMetric.composerField)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .shimmering()
                            .accessibilityLabel("Loading")
                            .task { await thread.readOlder() }
                    }
                    if !thread.loaded {
                        if thread.failed {
                            ChatFailedLine { await thread.read() }
                        } else {
                            ChatLoadingBubbles()
                        }
                    }
                    let messages = thread.messages
                    if thread.isGoing, thread.loaded, messages.isEmpty {
                        Text("Say hi to everyone going.")
                            .font(.sans(14))
                            .foregroundStyle(Hue.inkSecondary)
                            .padding(.bottom, ChatMetric.sectionTop)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let last = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil
                        let stamped = ChatWords.needsStamp(message, after: last)
                        if stamped {
                            TimelineView(.everyMinute) { context in
                                Text(ChatWords.stamp(message.at, now: context.date))
                                    .font(.sansMedium(12))
                                    .foregroundStyle(Hue.inkSecondary)
                            }
                            .padding(.top, ChatMetric.stampTop)
                            .padding(.bottom, ChatMetric.stampBottom)
                        }
                        // A host's update stands alone, so its face never sits on the card above.
                        let firstOfRun = stamped || last?.senderID != message.senderID || message.host || last?.host == true
                        let lastOfRun = next?.senderID != message.senderID || message.host || next?.host == true
                            || (next.map { ChatWords.needsStamp($0, after: message) } ?? true)
                        ChatBubble(message: message, thread: thread, sender: names[message.senderID] ?? message.sender,
                                   showsName: isGroup && firstOfRun, showsFace: lastOfRun, isGroup: isGroup,
                                   reduceMotion: reduceMotion, report: report, block: block)
                            .padding(.top, firstOfRun && !stamped ? ChatMetric.groupGap : stamped ? 0 : ChatMetric.runGap)
                            .id(message.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .scale(scale: 0.9, anchor: thread.isMine(message) ? .bottomTrailing : .bottomLeading)
                                    .combined(with: .opacity),
                                removal: .opacity))
                    }
                    if let card = thread.answerable {
                        ChatAnswers { answer($0.sent, card) }
                    }
                    if thread.seen {
                        Text("Seen")
                            .font(.sans(12))
                            .foregroundStyle(Hue.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, ChatMetric.runGap)
                            .padding(.trailing, ChatMetric.runGap)
                    }
                    if !thread.typing.isEmpty {
                        ChatTypingDots(reduceMotion: reduceMotion)
                            .padding(.top, ChatMetric.groupGap)
                            .id("typing")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, ChatMetric.threadSide)
                .padding(.vertical, ChatMetric.threadSide)
            }
            .defaultScrollAnchor(.bottom)
            // A message or the dots arriving: down to the end, as every chat does.
            .onChange(of: thread.messages.last?.id) { _, _ in
                withAnimation(reduceMotion ? nil : Motion.smooth) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: thread.typing.isEmpty) { _, none in
                if !none { withAnimation(reduceMotion ? nil : Motion.smooth) { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
    }
}

/// One message: yours on the right, theirs on the left with their face at the end of a run and, in a group,
/// their name at its start. A failed one says so and taps to try again. Press and hold: Copy, Report.
private struct ChatBubble: View {
    let message: ChatMessage
    let thread: ChatThread
    let sender: Neighbor?
    let showsName: Bool
    let showsFace: Bool
    let isGroup: Bool
    let reduceMotion: Bool
    let report: (ChatMessage) -> Void
    let block: (Neighbor) -> Void

    private var mine: Bool { thread.isMine(message) }

    var body: some View {
        VStack(alignment: message.host ? .center : mine ? .trailing : .leading, spacing: 2) {
            if message.host, case .text(let words) = message.content {
                update(words)
            } else {
                bubble
            }
            if message.state == .refused {
                Text("Not sent.")
                    .font(.sans(12))
                    .foregroundStyle(Hue.canceled)
                    .turnBackShake(failures: thread.failures, shakes: !reduceMotion)
            } else if message.state == .failed {
                Button { Task { await thread.retry(message) } } label: {
                    Label("Not sent. Tap to try again.", systemImage: "exclamationmark.circle")
                        .font(.sans(12))
                        .foregroundStyle(Hue.canceled)
                        .frame(minHeight: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.dim))
                .turnBackShake(failures: thread.failures, shakes: !reduceMotion)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A host's update: Instagram's channel card, in the middle of the thread, their face on its top edge.
    private func update(_ words: String) -> some View {
        let name = mine ? "You" : sender?.displayName ?? "Host"
        return VStack(spacing: ChatMetric.updateLineGap) {
            Text("\(Text(name).font(.sansSemibold(12)).foregroundStyle(Hue.ink)) · Host")
                .font(.sans(12))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
            Text(words)
                .font(.sansSemibold(16))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ChatMetric.updateTop)
        .padding(.horizontal, ChatMetric.updateSide)
        .padding(.bottom, ChatMetric.updateSide)
        .frame(width: ChatMetric.updateWidth)
        .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .opacity(message.state == .sending ? 0.6 : 1)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Host update, \(name): \(words), \(ChatWords.ago(message.at))")
        .overlay(alignment: .top) { updateFace.offset(y: -ChatMetric.updateFace / 2) }
        .padding(.top, ChatMetric.updateFace / 2)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var updateFace: some View {
        let face = Avatar(avatarUrl: sender?.avatarUrl, size: ChatMetric.updateFace)
            .overlay(Circle().stroke(Hue.paper, lineWidth: 2))
        if !mine, let sender {
            NavigationLink(value: sender) { face.contentShape(Circle()) }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("\(sender.displayName)'s profile")
        } else {
            face.accessibilityHidden(true)
        }
    }

    @ViewBuilder private var bubble: some View {
        if showsName, !mine, let sender {
            Text(sender.firstName)
                .font(.sans(12))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.leading, ChatMetric.theirLead)
        }
        HStack(alignment: .bottom, spacing: ChatMetric.theirLead - ChatMetric.theirFace) {
            if mine { Spacer(minLength: 0) }
            if !mine {
                Group {
                    if showsFace, let sender {
                        // Their Profile, where Block and everything else about them lives.
                        NavigationLink(value: sender) {
                            Avatar(avatarUrl: sender.avatarUrl, size: ChatMetric.theirFace)
                                .frame(width: ChatMetric.theirFace, height: ChatMetric.theirFace)
                                .contentShape(Circle().inset(by: (ChatMetric.theirFace - PageMetric.tapMin) / 2))
                        }
                        .buttonStyle(.press(.squish))
                        .accessibilityLabel("\(sender.displayName)'s profile")
                    } else if showsFace {
                        Avatar(avatarUrl: nil, size: ChatMetric.theirFace)
                    } else {
                        Color.clear.frame(width: ChatMetric.theirFace, height: 1)
                    }
                }
            }
            body(for: message.content)
                .opacity(message.state == .sending ? 0.6 : 1)
                .contextMenu { menu }
            if !mine { Spacer(minLength: 0) }
        }
    }

    @ViewBuilder private var menu: some View {
        if case .text(let words) = message.content {
            Button { UIPasteboard.general.string = words } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        if !mine, message.serverID != nil {
            Button(role: .destructive) { report(message) } label: { Label("Report", systemImage: "flag") }
        }
        if !mine, isGroup, let sender {
            Button(role: .destructive) { block(sender) } label: {
                Label("Block \(sender.firstName)", systemImage: "hand.raised")
            }
        }
    }

    private var spokenSender: String { mine ? "You" : sender?.firstName ?? "" }

    @ViewBuilder private func body(for content: ChatMessage.Content) -> some View {
        switch content {
        case .text(let words):
            Text(words)
                .font(.sans(16))
                .foregroundStyle(mine ? Hue.surface : Hue.ink)
                .padding(.horizontal, ChatMetric.bubbleX)
                .padding(.vertical, ChatMetric.bubbleY)
                .background(mine ? Hue.ink : Hue.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .frame(maxWidth: ChatMetric.bubbleMax, alignment: mine ? .trailing : .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(spokenSender): \(words), \(ChatWords.ago(message.at))")
        case .photo(let path, let width, let height):
            ChatPhoto(image: thread.picked[message.id], link: path.flatMap { thread.links[$0] },
                      width: width, height: height)
                .accessibilityLabel("\(spokenSender) sent a photo, \(ChatWords.ago(message.at))")
        case .event(let card):
            if let card {
                ChatEventCard(card: card)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(spokenSender) sent an Event, \(ChatWords.ago(message.at))")
            } else {
                Text("This Event is no longer available.")
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, ChatMetric.bubbleX)
                    .padding(.vertical, ChatMetric.bubbleY)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline))
            }
        }
    }
}

/// A photo in the chat, in its own shape; a tap opens it whole.
private struct ChatPhoto: View {
    let image: UIImage?
    let link: URL?
    let width: Int
    let height: Int
    @State private var open = false
    @Namespace private var zoom

    private var size: CGSize {
        let aspect = CGFloat(max(height, 1)) / CGFloat(max(width, 1))
        let tall = min(ChatMetric.photoWidth * aspect, ChatMetric.photoTallest)
        return CGSize(width: tall / aspect, height: tall)
    }

    var body: some View {
        Button { open = true } label: { picture.frame(width: size.width, height: size.height).clipped() }
            .buttonStyle(.press(.squish))
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .matchedTransitionSource(id: "photo", in: zoom)
            // Apple's zoom: it grows from the bubble, and a drag down takes it back there.
            .fullScreenCover(isPresented: $open) {
                ChatPhotoView(image: image, link: link, aspect: size.height / size.width)
                    .navigationTransition(.zoom(sourceID: "photo", in: zoom))
            }
    }

    @ViewBuilder private var picture: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let link {
            FeedCardURLPhoto(url: link, loadingFill: Hue.fill)
        } else {
            Rectangle().fill(Hue.fill).shimmering()
        }
    }
}

/// A chat's photo, whole, on black. Two fingers zoom it, and it settles back on letting go, as Instagram's.
private struct ChatPhotoView: View {
    let image: UIImage?
    let link: URL?
    /// Height over width, as the message knows it, so a photo from its link is whole on the screen.
    let aspect: CGFloat
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if let link {
                    GeometryReader { proxy in
                        let width = min(proxy.size.width, proxy.size.height / aspect)
                        FeedCardURLPhoto(url: link, loadingFill: .clear)
                            .frame(width: width, height: width * aspect)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .gesture(MagnifyGesture()
                .onChanged { scale = max(1, $0.magnification) }
                .onEnded { _ in withAnimation(Motion.smooth) { scale = 1 } })
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.glyph(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .accessibilityLabel("Close")
            .padding(.trailing, PageMetric.backLead)
        }
    }
}

/// An Event in the chat (the mock's card): its photo, what and when and where, friends going and the same
/// Attend as everywhere. It opens the Event page.
private struct ChatEventCard: View {
    let card: FeedCardItem
    @Environment(RealLifeActions.self) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: card) {
                VStack(alignment: .leading, spacing: 0) {
                    Hue.fill
                        .frame(height: ChatMetric.eventPhoto)
                        .overlay {
                            if let url = card.image.url {
                                FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
                            } else if let logo = card.image.logo {
                                // A place we have no photo of: its logo bare, as Search shows it.
                                CastLogo(logo: logo, side: SearchMetric.logoOnRow)
                            }
                        }
                        .clipped()
                    Text(card.title)
                        .font(.sansSemibold(16))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, ChatMetric.eventInsetY)
                        .padding(.horizontal, ChatMetric.eventInsetX)
                    Text(line)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, ChatMetric.eventInsetX)
                }
            }
            .buttonStyle(.press(.dim))
            HStack {
                FriendFaces(friends: card.friendsGoing, ring: Hue.surface)
                Spacer(minLength: 0)
                AttendPill(item: card, words: words) { ShareCenter.shared.present(.event(card)) }
            }
            .padding(.horizontal, ChatMetric.eventInsetX)
            .padding(.top, ChatMetric.chipGap)
            .padding(.bottom, ChatMetric.eventInsetY)
        }
        .frame(width: ChatMetric.eventWidth)
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline))
        .modifier(CardShadow())
    }

    private var line: String {
        [card.whenLine?.text, card.whereLine].compactMap { $0 }.joined(separator: " · ")
    }

    private var words: RSVPWords {
        let going = actions.going(card)
        return RSVPWords.make(isGoing: going.isGoing, count: going.count, friends: card.friendsGoing.map(\.name),
                              cancelled: card.cancelled)
    }
}

/// I'm in, Maybe, Can't, under an Event sent to you.
private struct ChatAnswers: View {
    let tap: (ChatAnswer) -> Void

    var body: some View {
        HStack(spacing: ChatMetric.chipGap) {
            ForEach(ChatAnswer.allCases) { answer in
                Button { tap(answer) } label: {
                    Text(answer.label)
                        .font(.sansSemibold(14))
                        .foregroundStyle(Hue.ink)
                        .padding(.horizontal, ChatMetric.chipPad)
                        .frame(height: ChatMetric.chipHeight)
                        .background(Hue.surface, in: Capsule())
                        .overlay(Capsule().stroke(Hue.hairline))
                        .frame(minHeight: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, ChatMetric.theirLead)
    }
}

/// Three dots, breathing while someone types, still with Reduce Motion.
private struct ChatTypingDots: View {
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: ChatMetric.theirLead, height: 1)
            HStack(spacing: ChatMetric.runGap) {
                ForEach(0..<3, id: \.self) { i in
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.2 - Double(i) * 1.05
                        Circle()
                            .fill(Hue.inkSecondary)
                            .frame(width: ChatMetric.typingDot, height: ChatMetric.typingDot)
                            .opacity(reduceMotion ? 0.6 : 0.35 + 0.65 * max(0, sin(phase)))
                    }
                }
            }
            .padding(.horizontal, ChatMetric.bubbleX)
            .padding(.vertical, ChatMetric.bubbleX)
            .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            Spacer(minLength: 0)
        }
        .accessibilityElement()
        .accessibilityLabel("Typing")
    }
}

private struct ChatLoadingBubbles: View {
    var body: some View {
        VStack(spacing: ChatMetric.groupGap) {
            ForEach([true, false, true, true, false], id: \.self) { mine in
                HStack {
                    if mine { Spacer(minLength: 0) }
                    SkeletonBlock(cornerRadius: Radius.card)
                        .frame(width: ChatMetric.bubbleMax * (mine ? 0.5 : 0.7), height: ChatMetric.composerField)
                    if !mine { Spacer(minLength: 0) }
                }
            }
        }
        .shimmering()
        .accessibilityLabel("Loading")
    }
}

/// A request's foot: Accept brings it into your chats, Delete takes it away and it can't ask again, Block ends it.
private struct ChatRequestBar: View {
    let chat: Chat
    let name: String
    let done: (Bool) -> Void
    let block: () -> Void
    @Environment(ChatBook.self) private var chats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var busy = false
    @State private var failures = 0

    var body: some View {
        VStack(spacing: ChatMetric.chipGap) {
            Text("\(name) isn't your friend yet. They won't know you've read this until you accept.")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: ChatMetric.chipGap) {
                pill("Block", fill: Hue.fill, ink: Hue.canceled, action: block)
                pill("Delete", fill: Hue.fill, ink: Hue.ink) { act { try await chats.decline(chat); done(true) } }
                pill("Accept", fill: Hue.ink, ink: Hue.surface) { act { try await chats.accept(chat); done(false) } }
            }
            .turnBackShake(failures: failures, shakes: !reduceMotion)
        }
        .padding(.horizontal, ChatMetric.side)
        .padding(.vertical, ChatMetric.composerY)
        .background(Hue.paper)
    }

    private func pill(_ words: String, fill: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(words)
                .font(.sansSemibold(15))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: PageMetric.tapMin)
                .background(fill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .disabled(busy)
    }

    private func act(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do {
                try await work()
            } catch {
                failures += 1
                Haptics.error()
            }
            busy = false
        }
    }
}
