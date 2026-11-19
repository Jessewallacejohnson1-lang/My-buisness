//
//  ChatPage.swift
//  Block Party — one chat (BP app five-tabs 05, messages 02): Instagram's thread, measured (BP app
//  `references/messages-instagram/SPEC.md`). Your bubbles run violet to blue down the screen, theirs are the light
//  fill, never yellow (taste, 2026-10-06). Text, a photo or an Event, whose card opens the Event page, with I'm in,
//  Maybe and Can't under one sent to you. Typing dots, no Seen and no online status. Your words come up out of the
//  composer, a drag left shows the times, and the + sends an Event. A request shows Accept, Delete and Block where
//  the composer goes.
//
//  A Going chat (five-tabs 06) is the same thread among strangers: the bar shows its Event, it takes words only, with no
//  typing dots, and whatever its host writes is an update, drawn as Instagram's channel card.
//
//  A Group chat (five-tabs 07) is that room for a Group's members: the bar shows the Group, words and Events go in, and
//  everyone is equal, since a Group has no host.
//
//  Hearts and replies (messages 03, mock 1): a double tap hearts a message, a hold opens the emoji row over it with
//  Reply, Copy and Report under it, a swipe right replies, a reply quotes what it answers, and the small pill under a
//  message shows everyone's emoji.
//
//  Apple's pieces: a bottom-anchored scroll (`defaultScrollAnchor`), the composer in `safeAreaInset`, a growing
//  `TextField`, `PhotosPicker`, a sheet for the + and `keyframeAnimator` for the heart. Ours: the bubble's colour by its
//  height, its rise from the composer, the drag for the times (`ChatTimesPan`), the swipe to reply and the hold
//  (`ChatTouch`), whose emoji row Apple's context menu has no room for. How Instagram builds its own is a guess.
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
    /// A Group chat's Group, from its page, before the chat reaches the list.
    var club: TownGroup? = nil

    @Environment(YouModel.self) private var you: YouModel?
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
    /// The + sheet is up.
    @State private var sendingEvent = false
    /// The whole screen's height: your bubbles' colour goes by where they sit on it.
    @State private var screen: CGFloat = Hue.chatMineScreen
    /// Where the composer's words start, on the screen: a message just sent comes up from there.
    @State private var composerWords: CGPoint?
    /// The message on its way up out of the composer.
    @State private var rising: String?
    /// The message a swipe or the hold's Reply picked: "Replying to" over the composer, quoted over what's sent.
    @State private var replying: ChatMessage?
    /// A held message: the page washes out behind it, its emoji row over it and its menu under it.
    @State private var held: ChatHeld?
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

    /// A Group chat's Group, by its id on the list while its page didn't open this.
    private var clubID: String? { club?.id ?? current?.clubId ?? chat?.clubId }

    private var townGroup: TownGroup? {
        club ?? clubID.flatMap { id in you?.groups?.first { $0.id == id } }
    }

    private var isGroup: Bool {
        goingCard != nil || clubID != nil || (current?.kind ?? (groupID != nil ? .group : .direct)) == .group
    }

    private var title: String {
        goingCard?.title ?? townGroup?.name ?? current?.title ?? groupName
            ?? others.map(isGroup ? \.firstName : \.displayName).joined(separator: ", ")
    }

    var body: some View {
        ZStack {
            Hue.surface.ignoresSafeArea()
            if let thread { content(thread) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: { screen = $0 }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $sendingEvent) {
            ChatEventSheet { card in
                guard let thread else { return }
                Task {
                    await thread.send(card: card)
                    surfaceRefusal(thread)
                }
            }
        }
        .task {
            // Coming back from an Event or a Profile keeps what's here, what failed to send included.
            if thread == nil {
                // A chat with this person that's already there, from their Profile or a search.
                if chats.chats == nil { await chats.refresh() }
                let known = chat ?? person.flatMap { chats.chat(with: $0) }
                let me = (try? chats.api.db.userID) ?? ""
                thread = ChatThread(api: chats.api, me: me, chat: known?.id ?? groupID, to: person?.id, book: chats,
                                    actions: actions, going: goingCard?.id, club: clubID,
                                    isHost: event == nil ? chat?.isHost == true : eventHost)
            }
            guard let thread else { return }
            // The first read of the Groups failed: the bar's Group, its count and leaving it need them.
            if clubID != nil, you?.groups == nil, let groups = await you?.refreshGroups() { actions.read(groups) }
            chats.open = thread
            // Back from the Profile of someone you've just blocked: their words go, the newest too.
            for person in thread.messages.compactMap(\.sender) where book.relation(person) == .blocked {
                thread.dropMessages(from: person.id)
            }
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
            if goingCard != nil {
                Text("You'll still be going. Tap Going chat on the Event to come back.")
            } else if clubID != nil {
                Text("You'll stay in the group. Tap Group chat on its page to come back.")
            }
        }
        .alert(problem ?? "", isPresented: problemShown) {
            Button("OK", role: .cancel) { if thread?.gone == true { dismiss() } }
        }
        // No longer Going, on the Event page behind a chat bar: leaving Going leaves the chat at once.
        .onChange(of: goingCard.map { actions.going($0).isGoing }) { _, going in
            if going == false, thread?.isHost != true { dismiss() }
        }
        // Left the Group from its page behind a chat bar: leaving the Group leaves the chat at once.
        .onChange(of: townGroup.map { actions.member($0).isMember }) { _, member in
            if member == false { dismiss() }
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
            ChatMessages(thread: thread, isGroup: isGroup, others: others, reduceMotion: reduceMotion, screen: screen,
                         composerWords: composerWords, rising: rising,
                         // A friend's chat opens on them, once there is nothing older to read.
                         profile: isGroup ? nil : others.first,
                         answer: { answer($0, card: $1, thread) },
                         react: { message, emoji in Task { await thread.react(message, emoji) } },
                         canReact: current?.request != true,
                         reply: canReply(thread) ? { reply(to: $0) } : nil,
                         hold: { hold($0) })
                .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { foot(thread) }
        .blur(radius: held == nil || reduceMotion ? 0 : ChatMetric.holdBlur)
        .overlay {
            if let held {
                ChatHeldView(held: held, thread: thread, screen: screen, items: heldItems(held, thread),
                             reduceMotion: reduceMotion,
                             react: { emoji in
                                 Task { await thread.react(held.message, emoji) }
                                 letGo()
                             },
                             close: letGo)
                    .transition(.opacity)
            }
        }
    }

    /// A reply needs the composer: not in a request, not while yours waits, not in a room not yet joined.
    private func canReply(_ thread: ChatThread) -> Bool {
        current?.request != true && current?.waiting != true && (!thread.isRoom || thread.chatID != nil)
    }

    private func reply(to message: ChatMessage) {
        withAnimation(reduceMotion ? nil : Motion.smooth) { replying = message }
        typing = true
    }

    private func hold(_ message: ChatHeld) {
        typing = false
        Haptics.light()
        withAnimation(reduceMotion ? nil : ChatMotion.holdWash) { held = message }
    }

    private func letGo() {
        withAnimation(reduceMotion ? nil : ChatMotion.holdClose) { held = nil }
    }

    /// The held message's menu, as mock 1 has it: Reply, Copy, then Report on someone else's; in a group, Block them
    /// too, as the press menu had it.
    private func heldItems(_ held: ChatHeld, _ thread: ChatThread) -> [ChatHeldItem] {
        let message = held.message, mine = thread.isMine(message)
        var items: [ChatHeldItem] = []
        if canReply(thread), message.serverID != nil, !message.host {
            items.append(ChatHeldItem(title: "Reply", icon: "arrow.uturn.backward", red: false) { reply(to: message) })
        }
        if case .text(let words) = message.content {
            items.append(ChatHeldItem(title: "Copy", icon: "doc.on.doc", red: false) { UIPasteboard.general.string = words })
        }
        if !mine, message.serverID != nil {
            items.append(ChatHeldItem(title: "Report", icon: "flag", red: true) { reporting = message })
        }
        if !mine, isGroup, let sender = held.sender {
            items.append(ChatHeldItem(title: "Block \(sender.firstName)", icon: "hand.raised", red: true) { blocking = sender })
        }
        return items
    }

    /// A message's writer by name, as the chat shows them: from the people in it, else as the message has them.
    private func name(of id: String?, fallback: String?) -> String? {
        others.first { $0.id.lowercased() == id }?.displayName ?? fallback
    }

    // MARK: The bar

    /// Back, who it is (a tap opens their Profile, the Event or the Group), and the ••• (Apple's menu): Report, then
    /// Block or a group's Leave. Flat white, a line under it.
    private func bar(_ thread: ChatThread) -> some View {
        HStack(spacing: 0) {
            ChatBackButton { dismiss() }
            Group {
                if let card = goingCard {
                    NavigationLink(value: card) { who(opens: true) }
                        .buttonStyle(.press(.dim))
                } else if let townGroup {
                    NavigationLink(value: townGroup) { who(opens: true) }
                        .buttonStyle(.press(.dim))
                        .accessibilityHint("Opens the group")
                } else if !isGroup, let other = others.first {
                    NavigationLink(value: other) { who(opens: true) }
                        .buttonStyle(.press(.dim))
                } else {
                    who(opens: false)
                }
            }
            .padding(.leading, ChatMetric.barFaceLead - ChatMetric.backLead - PageMetric.tapMin)
            Spacer(minLength: 0)
            Menu {
                // Not in a room, where whoever spoke last is a stranger: a press reports the right one.
                if !thread.isRoom {
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
                    .font(.glyph(20, weight: .medium))
                    .foregroundStyle(Hue.ink)
                    .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options")
            .padding(.trailing, ChatMetric.pencilTrail)
        }
        .frame(height: ChatMetric.backMid * 2)
        .frame(height: ChatMetric.chatBar, alignment: .top)
        .background(Hue.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Hue.chatLine).frame(height: ChatMetric.line) }
    }

    private func who(opens: Bool) -> some View {
        let square = goingCard != nil || clubID != nil || isGroup
        return HStack(spacing: square ? ChatMetric.barSquareGap : ChatMetric.barFaceGap) {
            if let card = goingCard {
                ChatEventFace(card: card, size: ChatMetric.barSquare)
            } else if clubID != nil {
                ChatGroupFace(group: townGroup, size: ChatMetric.barSquare)
            } else if isGroup, others.count > 1 {
                ChatDuoFace(first: others[0], second: others[1], size: ChatMetric.barSquare)
            } else {
                Avatar(avatarUrl: others.first?.avatarUrl, size: ChatMetric.barFace)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: ChatMetric.barChevronGap) {
                    Text(title)
                        .appleFont(16, weight: .bold)
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    if opens {
                        Image(systemName: "chevron.right")
                            .font(.glyph(ChatMetric.barChevron, weight: .semibold))
                            .foregroundStyle(Hue.ink)
                            .accessibilityHidden(true)
                    }
                }
                if let line {
                    Text(line)
                        .appleFont(12)
                        .foregroundStyle(Hue.chatGrey)
                        .lineLimit(1)
                }
            }
        }
        .frame(minHeight: PageMetric.tapMin)
        .contentShape(Rectangle())
    }

    /// How many are Going, a Group's members, or how many are in a group of friends, never 0. A friend's has none.
    private var line: String? {
        if let card = goingCard {
            let count = actions.going(card).count
            return count > 0 ? "\(count) going" : nil
        }
        if clubID != nil { return townGroup.flatMap { GroupPage.membersText(actions.member($0).count) } }
        return isGroup ? "\(others.count + 1) people" : nil
    }

    // MARK: The foot

    @ViewBuilder private func foot(_ thread: ChatThread) -> some View {
        if current?.request == true, let current {
            ChatRequestBar(chat: current, name: others.first?.firstName ?? "") { done in
                if done { dismiss() }
            } block: { blocking = others.first }
        } else if current?.waiting == true {
            Text("Sent as a request. You can write more once \(others.first?.firstName ?? "they") accepts.")
                .appleFont(13)
                .foregroundStyle(Hue.chatGrey)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ChatMetric.side)
                .padding(.vertical, ChatMetric.requestTop)
                .background(Hue.surface)
        } else {
            VStack(spacing: 0) {
                if let replying { replyingStrip(replying, thread) }
                composer(thread)
            }
        }
    }

    /// Mock 1's strip over the composer: "Replying to Maya", the quoted words, and an X to drop it.
    private func replyingStrip(_ message: ChatMessage, _ thread: ChatThread) -> some View {
        let who = thread.isMine(message) ? "yourself"
            : name(of: message.senderID, fallback: message.sender?.displayName)?.split(separator: " ").first.map(String.init) ?? ""
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Replying to \(Text(who).fontWeight(.semibold).foregroundStyle(Hue.ink))")
                Text(ChatWords.quoted(message.quote))
            }
            .appleFont(13)
            .foregroundStyle(Hue.chatGrey)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(reduceMotion ? nil : Motion.smooth) { replying = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.glyph(14, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.dim))
            .accessibilityLabel("Cancel reply")
            .padding(.top, -ChatMetric.replyingTop)
        }
        .padding(.leading, ChatMetric.side)
        .padding(.top, ChatMetric.replyingTop)
        .padding(.bottom, ChatMetric.replyingBottom)
        .frame(maxHeight: PageMetric.tapMin + ChatMetric.replyingBottom, alignment: .top)
        .background(Hue.surface)
        .overlay(alignment: .top) { Rectangle().fill(Hue.chatLine).frame(height: ChatMetric.line) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Instagram's composer: a grey pill with the photo button and the + at its right; with words in it, it grows a
    /// little and the send pill takes their place. The field grows to five lines.
    private func composer(_ thread: ChatThread) -> some View {
        let empty = words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Before a chat exists with someone who isn't your friend, words alone go.
        let strangers = current == nil && !isGroup && others.first.map { book.relation($0) != .friends } == true
        // A room has nowhere to send words until it's joined.
        let ready = !thread.isRoom || thread.chatID != nil
        let height = empty ? ChatMetric.composerField : ChatMetric.composerTyping
        return HStack(alignment: .bottom, spacing: 0) {
            TextField("", text: $words,
                      prompt: Text(thread.isHost ? "Post an update..." : "Message...").foregroundStyle(Hue.chatGrey), axis: .vertical)
                .appleFont(16)
                .foregroundStyle(Hue.ink)
                .lineLimit(1 ... ChatMetric.composerLines)
                .focused($typing)
                .padding(.vertical, (height - ChatMetric.bubbleLine) / 2)
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .global)
                    return CGPoint(x: frame.minX, y: frame.midY)
                } action: { composerWords = $0 }
                .onChange(of: words) { _, new in if !new.isEmpty { thread.typed() } }
            if !empty, ready {
                Button { send(thread) } label: {
                    FeedActionGlyphView(glyph: .send, size: ChatMetric.sendGlyph)
                        .foregroundStyle(.white)
                        .frame(width: ChatMetric.sendWidth, height: ChatMetric.sendHeight)
                        .background { ChatMineFill(screen: screen).clipShape(Capsule()) }
                        .contentShape(TapArea())
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("Send")
                .padding(.trailing, ChatMetric.composerSendTrail)
                .padding(.bottom, (ChatMetric.composerTyping - ChatMetric.sendHeight) / 2)
                .transition(.scale.combined(with: .opacity))
            } else if empty, !strangers, goingCard == nil {
                // A Going chat is words only; a Group chat takes Events; friends take photos too.
                HStack(spacing: ChatMetric.composerIconGap) {
                    if !thread.isRoom { photoButton(thread) }
                    Button { sendingEvent = true } label: { composerGlyph("plus.circle") }
                        .buttonStyle(.press(.dim))
                        .accessibilityLabel("Send an Event")
                }
                .frame(height: ChatMetric.composerField)
                .padding(.trailing, ChatMetric.composerIconsTrail)
            }
        }
        .padding(.leading, ChatMetric.composerWordsLead)
        .frame(minHeight: height)
        .background(Hue.chatComposer, in: RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .animation(reduceMotion ? nil : ChatMotion.send, value: empty)
        .padding(.leading, ChatMetric.composerLead)
        .padding(.trailing, ChatMetric.composerTrail)
        .padding(.vertical, ChatMetric.composerY)
        .background(Hue.surface)
    }

    @ViewBuilder private func photoButton(_ thread: ChatThread) -> some View {
        #if DEBUG
        // `-new-event-photo <file>`: a bundled photo as if picked; AXe can't reach Apple's picker.
        if let file = LaunchFlags.value(.newEventPhoto), let image = UIImage(named: file) {
            Button { Task { await thread.send(photo: image) } } label: { composerGlyph("photo") }
                .buttonStyle(.press(.dim))
                .accessibilityLabel("Send a photo")
        } else {
            photoPicker
        }
        #else
        photoPicker
        #endif
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $pick, matching: .images) { composerGlyph("photo") }
            .buttonStyle(.press(.dim))
            .accessibilityLabel("Send a photo")
    }

    /// One of the composer's two icons: 24 drawn, 44 to the finger.
    private func composerGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.glyph(23.5))
            .foregroundStyle(Hue.ink)
            .frame(width: ChatMetric.composerIcon, height: ChatMetric.composerIcon)
            .contentShape(TapArea())
    }

    // MARK: Actions

    /// The words leave the composer and come up as their bubble.
    private func send(_ thread: ChatThread) {
        let text = words, id = UUID().uuidString.lowercased(), answering = replying
        words = ""
        rising = reduceMotion ? nil : id
        withAnimation(reduceMotion ? nil : Motion.smooth) { replying = nil }
        Task {
            await thread.send(text, id: id, replying: answering)
            surfaceRefusal(thread)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if rising == id { withAnimation(Motion.snappy) { rising = nil } }
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
    let screen: CGFloat
    let composerWords: CGPoint?
    let rising: String?
    let profile: Neighbor?
    let answer: (String, FeedCardItem) -> Void
    let react: (ChatMessage, String) -> Void
    let canReact: Bool
    let reply: ((ChatMessage) -> Void)?
    let hold: (ChatHeld) -> Void
    /// How far a finger has dragged the chat left, for its times.
    @State private var pull: CGFloat = 0
    /// How tall the scroll is on the screen, between the bar and the composer.
    @State private var room: CGFloat = 0

    private var names: [String: Neighbor] {
        Dictionary(others.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let shift = ChatLook.timesShift(pull), names = self.names
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if thread.hasOlder {
                        // Older messages read as this comes into view: a bubble's shape, shimmering.
                        SkeletonBlock(cornerRadius: ChatMetric.bubbleCorner)
                            .frame(width: ChatMetric.loadingName, height: ChatMetric.typingHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, ChatMetric.threadLead)
                            .shimmering()
                            .accessibilityLabel("Loading")
                            .task { await thread.readOlder() }
                    } else if let profile, thread.loaded {
                        ChatProfileBlock(person: profile)
                    }
                    if !thread.loaded {
                        if thread.failed {
                            ChatFailedLine { await thread.read() }
                        } else {
                            ChatLoadingBubbles()
                        }
                    }
                    let messages = thread.messages
                    if thread.isRoom, thread.loaded, messages.isEmpty {
                        Text(thread.club == nil ? "Say hi to everyone going." : "Say hi to the group.")
                            .appleFont(14)
                            .foregroundStyle(Hue.chatGrey)
                            .padding(.vertical, ChatMetric.sectionTop)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let last = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil
                        let stamped = ChatWords.needsStamp(message, after: last)
                        if stamped {
                            TimelineView(.everyMinute) { context in
                                Text(ChatWords.stamp(message.at, now: context.date))
                                    .appleFont(12)
                                    .foregroundStyle(Hue.chatStamp)
                            }
                            .padding(.top, ChatMetric.stampTop)
                            .padding(.bottom, ChatMetric.stampBottom)
                        }
                        // A host's update stands alone, so its face never sits on the card above.
                        let firstOfRun = stamped || last?.senderID != message.senderID || message.host || last?.host == true
                        let lastOfRun = next?.senderID != message.senderID || message.host || next?.host == true
                            || (next.map { ChatWords.needsStamp($0, after: message) } ?? true)
                        // An Event's card joins nothing: the bubbles beside it keep their round corners.
                        let joinsAbove = !firstOfRun && message.card == nil && last?.card == nil
                        let joinsBelow = !lastOfRun && message.card == nil && next?.card == nil
                        let rises = message.id == rising && !message.host
                        ChatBubble(message: message, thread: thread, sender: names[message.senderID] ?? message.sender,
                                   names: names, showsName: isGroup && firstOfRun, showsFace: lastOfRun, isGroup: isGroup,
                                   joinsAbove: joinsAbove, joinsBelow: joinsBelow, screen: screen,
                                   risesFrom: rises ? composerWords : nil, timeShown: min(1, shift / ChatMetric.timesShown),
                                   reduceMotion: reduceMotion, react: react, canReact: canReact, reply: reply, hold: hold)
                            .padding(.top, message.host ? ChatMetric.updateAbove
                                     : firstOfRun && !stamped ? ChatMetric.groupGap : ChatMetric.runGap)
                            .id(message.id)
                            // Your words come up out of the composer (`ChatBubble`); everything else pops in from its corner.
                            .transition(reduceMotion ? .opacity : rises ? .identity : .asymmetric(
                                insertion: .scale(scale: 0.6, anchor: thread.isMine(message) ? .bottomTrailing : .bottomLeading)
                                    .combined(with: .opacity).animation(ChatMotion.pop),
                                removal: .opacity))
                    }
                    if let card = thread.answerable {
                        ChatAnswers { answer($0.sent, card) }
                    }
                    if let who = thread.typing.first {
                        ChatTypingDots(face: names[who], reduceMotion: reduceMotion)
                            .padding(.top, ChatMetric.groupGap)
                            .id("typing")
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .bottomLeading)
                                .combined(with: .opacity).animation(ChatMotion.pop))
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.vertical, ChatMetric.threadY)
                .offset(x: -shift)
                // A short chat with a friend starts under the bar, its profile block on top: the page is at least as
                // tall as the room the scroll has. Any other short chat sits on the composer.
                .frame(minHeight: profile != nil && thread.loaded && !thread.hasOlder ? room : nil, alignment: .top)
            }
            .defaultScrollAnchor(.bottom)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { room = $0 }
            // A drag left brings the times in at the right; letting go sends the chat back.
            .gesture(ChatTimesPan { pull = $0 } ended: {
                withAnimation(reduceMotion ? nil : ChatMotion.timesBack) { pull = 0 }
            })
            // A message or the dots arriving: down to the end, as every chat does.
            .onChange(of: thread.messages.last?.id) { _, _ in
                withAnimation(reduceMotion ? nil : ChatMotion.rise) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: thread.typing.isEmpty) { _, none in
                if !none { withAnimation(reduceMotion ? nil : ChatMotion.rise) { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
    }
}

/// The top of a friend's chat, Instagram's: their face, name, mutual friends and View profile.
private struct ChatProfileBlock: View {
    let person: Neighbor

    var body: some View {
        VStack(spacing: 0) {
            Avatar(avatarUrl: person.avatarUrl, size: ChatMetric.profileFace)
                .accessibilityHidden(true)
            Text(person.displayName)
                .appleFont(19, weight: .bold)
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .frame(height: ChatMetric.profileNameLine)
                .padding(.top, ChatMetric.profileNameTop)
            if let mutual = person.mutualLine {
                Text(mutual)
                    .appleFont(16)
                    .foregroundStyle(Hue.chatGrey)
                    .frame(height: ChatMetric.profileLine)
            }
            NavigationLink(value: person) {
                Text("View profile")
                    .appleFont(14, weight: .semibold)
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, ChatMetric.profileButtonPad)
                    .frame(height: ChatMetric.profileButton)
                    .background(Hue.chatViewProfile, in: RoundedRectangle(cornerRadius: ChatMetric.profileButtonCorner, style: .continuous))
                    .contentShape(TapArea())
            }
            .buttonStyle(.press(.squish))
            .padding(.top, ChatMetric.profileButtonTop)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ChatMetric.profileTop)
        .padding(.horizontal, ChatMetric.side)
    }
}

/// What sits behind your bubble and the send pill: Instagram's violet to blue, by where it is on the screen.
struct ChatMineFill: View {
    let screen: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global), k = Hue.chatMineScreen / max(screen, 1)
            LinearGradient(colors: [Hue.chatMine(y: frame.minY * k), Hue.chatMine(y: frame.maxY * k)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// One message: yours on the right, theirs on the left with their face at the end of a run and, in a group,
/// their name at its start. A failed one says so and taps to try again. A double tap hearts it, a hold opens its emoji
/// row and menu, and a swipe right replies to it (BP app messages 03).
private struct ChatBubble: View {
    let message: ChatMessage
    let thread: ChatThread
    let sender: Neighbor?
    /// Everyone's names in the chat, for a reply's quote.
    let names: [String: Neighbor]
    let showsName: Bool
    let showsFace: Bool
    let isGroup: Bool
    let joinsAbove: Bool
    let joinsBelow: Bool
    let screen: CGFloat
    /// Where the composer's words were, when this is the message just sent from it.
    let risesFrom: CGPoint?
    /// 0 to 1 as a drag left brings the times in.
    let timeShown: CGFloat
    let reduceMotion: Bool
    let react: (ChatMessage, String) -> Void
    /// False in a request not yet accepted, where the server takes no reaction.
    let canReact: Bool
    /// nil where there's no composer to reply from.
    let reply: ((ChatMessage) -> Void)?
    let hold: (ChatHeld) -> Void
    /// Up in its place; false while it is still down in the composer.
    @State private var up: Bool
    /// One more for each double tap that hearts it: its big heart's go.
    @State private var hearts = 0
    /// Where the bubble is on the screen, for the hold's copy of it: kept where a scroll's every frame redraws nothing.
    @State private var frame = FrameBox()
    /// A finger is down on it: it squishes until the hold opens or the finger goes.
    @State private var pressed = false
    /// How far a swipe right has come.
    @State private var pull: CGFloat = 0
    /// The swipe has come far enough that letting go replies.
    @State private var armed = false

    init(message: ChatMessage, thread: ChatThread, sender: Neighbor?, names: [String: Neighbor], showsName: Bool,
         showsFace: Bool, isGroup: Bool, joinsAbove: Bool, joinsBelow: Bool, screen: CGFloat, risesFrom: CGPoint?,
         timeShown: CGFloat, reduceMotion: Bool, react: @escaping (ChatMessage, String) -> Void, canReact: Bool,
         reply: ((ChatMessage) -> Void)?, hold: @escaping (ChatHeld) -> Void) {
        self.message = message
        self.thread = thread
        self.sender = sender
        self.names = names
        self.showsName = showsName
        self.showsFace = showsFace
        self.isGroup = isGroup
        self.joinsAbove = joinsAbove
        self.joinsBelow = joinsBelow
        self.screen = screen
        self.risesFrom = risesFrom
        self.timeShown = timeShown
        self.reduceMotion = reduceMotion
        self.react = react
        self.canReact = canReact
        self.reply = reply
        self.hold = hold
        _up = State(initialValue: risesFrom == nil)
    }

    private var mine: Bool { thread.isMine(message) }

    private var shape: UnevenRoundedRectangle { ChatLook.bubble(mine: mine, joinsAbove: joinsAbove, joinsBelow: joinsBelow) }

    /// Your own emoji on it, if any.
    private var yours: String? { message.reactions.first { thread.isMe($0.userId) }?.emoji }

    /// A reply can start here: it's on the server, and isn't a host's update.
    private var replies: Bool { reply != nil && message.serverID != nil && !message.host }

    private var shift: CGFloat { ChatLook.timesShift(pull) }

    var body: some View {
        let row = VStack(alignment: message.host ? .center : mine ? .trailing : .leading, spacing: 2) {
            if message.host, case .text(let words) = message.content {
                touches(ChatUpdateCard(message: message, words: words, mine: mine, sender: sender))
            } else {
                bubble
            }
            if message.state == .refused {
                Text("Not sent.")
                    .appleFont(12)
                    .foregroundStyle(Hue.canceled)
                    .turnBackShake(failures: thread.failures, shakes: !reduceMotion)
            } else if message.state == .failed {
                Button { Task { await thread.retry(message) } } label: {
                    Label("Not sent. Tap to try again.", systemImage: "exclamationmark.circle")
                        .appleFont(12)
                        .foregroundStyle(Hue.canceled)
                        .frame(minHeight: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.dim))
                .turnBackShake(failures: thread.failures, shakes: !reduceMotion)
            }
        }
        .padding(.leading, ChatMetric.threadLead)
        .padding(.trailing, ChatMetric.threadTrail)
        // Its time waits past the right edge until a drag left brings the chat over.
        .overlay(alignment: .bottomTrailing) {
            if !message.host {
                Text(Town.clock(message.at))
                    .appleFont(12)
                    .foregroundStyle(Hue.chatStamp)
                    .lineLimit(1)
                    .frame(width: ChatMetric.timesWidth, alignment: .trailing)
                    .offset(x: ChatMetric.timesOut, y: -ChatMetric.timesUp)
                    .opacity(timeShown)
                    .accessibilityHidden(true)
            }
        }
        // A swipe right: the reply arrow waits past the left edge and comes in with the row, bigger once letting go
        // replies.
        .overlay(alignment: .leading) {
            if pull > 0 {
                Image(systemName: "arrow.uturn.backward")
                    .font(.glyph(ChatMetric.replyArrow - 3))
                    .foregroundStyle(Hue.ink)
                    .frame(width: ChatMetric.replyArrow, height: ChatMetric.replyArrow)
                    .scaleEffect(armed ? 1.2 : 0.6 + 0.4 * min(1, shift / ChatMetric.replyTakes))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: armed)
                    .opacity(min(1, shift / ChatMetric.replyShows))
                    .offset(x: -ChatMetric.replyArrowOut)
                    .accessibilityHidden(true)
            }
        }
        .offset(x: shift)
        .accessibilityElement(children: .contain)
        .onAppear {
            if !up { withAnimation(ChatMotion.rise) { up = true } }
        }
        if replies {
            row.gesture(ChatReplyPan { pull = $0; arm() } ended: { letGo() })
        } else {
            row
        }
    }

    private func arm() {
        let now = shift >= ChatMetric.replyTakes
        if now != armed {
            armed = now
            if now { Haptics.selection() }
        }
    }

    private func letGo() {
        if armed, let reply { reply(message) }
        armed = false
        withAnimation(reduceMotion ? nil : ChatMotion.timesBack) { pull = 0 }
    }

    /// The double tap, the hold and what VoiceOver offers in their place, on whatever the message draws.
    private func touches(_ view: some View) -> some View {
        view
            .scaleEffect(pressed ? ChatLook.squish(frame.rect.width) : 1)
            .animation(pressed ? .easeOut(duration: 0.08) : Motion.snappy, value: pressed)
            // Outside the squish, so the hold's copy has the bubble's own size.
            .trackFrame(frame)
            .gesture(PhotoDoubleTap { _ in heart() })
            .gesture(ChatHold { openHold() } pressed: { pressed = $0 })
            .accessibilityActions {
                if reacts {
                    Button(yours == ChatLook.heart ? "Remove heart" : "Heart") { react(message, ChatLook.heart) }
                }
                if replies, let reply { Button("Reply") { reply(message) } }
                Button("More") { openHold() }
            }
    }

    /// A reaction can go on it: it's on the server, and this isn't a request you haven't accepted.
    private var reacts: Bool { message.serverID != nil && canReact }

    /// A double tap hearts it, with the big heart; on one you've hearted, it takes the heart back.
    private func heart() {
        guard reacts else { return }
        if yours != ChatLook.heart { hearts += 1 }
        react(message, ChatLook.heart)
    }

    private func openHold() {
        pressed = false
        hold(ChatHeld(message: message, frame: frame.rect, mine: mine, shape: shape, sender: sender, reacts: reacts))
    }

    @ViewBuilder private var bubble: some View {
        if showsName, !mine, let sender {
            Text(sender.firstName)
                .appleFont(12)
                .foregroundStyle(Hue.chatStamp)
                .padding(.leading, ChatMetric.theirLead + ChatMetric.bubbleX)
                .padding(.bottom, ChatMetric.nameBottom - 2)
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
            VStack(alignment: mine ? .trailing : .leading, spacing: 0) {
                if let quote = message.reply { quoted(quote) }
                touches(ChatBubbleBody(message: message, thread: thread, mine: mine, shape: shape, screen: screen,
                                       sender: sender, hearts: hearts, reduceMotion: reduceMotion))
                    // Still on its way once it has landed: faint, as before.
                    .opacity(!up ? 0.7 : message.state == .sending && risesFrom == nil ? 0.6 : 1)
                    // Just sent: it starts down where the composer's words were and comes up to its place.
                    .visualEffect { [up, risesFrom] view, proxy in
                        let frame = proxy.frame(in: .global)
                        let from = up ? nil : risesFrom
                        return view.offset(x: from.map { $0.x - ChatMetric.bubbleX - frame.minX } ?? 0,
                                           y: from.map { $0.y - ChatMetric.typingHeight / 2 - frame.minY } ?? 0)
                    }
                if !message.reactions.isEmpty {
                    ChatReactionPill(reactions: message.reactions)
                        .padding(.horizontal, ChatMetric.reactionSide)
                        .padding(.top, -ChatMetric.reactionOver)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.01, anchor: mine ? .topTrailing : .topLeading))
                }
            }
            if !mine { Spacer(minLength: 0) }
        }
    }

    /// Over a reply: who answered whom, then the words it answers beside a thin bar on the far side.
    private func quoted(_ quote: ChatQuote) -> some View {
        let writer = names[quote.senderId ?? ""]?.displayName ?? quote.name
        let caption = ChatWords.replied(mine: mine, by: sender?.displayName, to: writer, quotedMine: thread.isMe(quote.senderId),
                                        sameSender: quote.senderId == message.senderID)
        return VStack(alignment: mine ? .trailing : .leading, spacing: 0) {
            Text(caption)
                .appleFont(12)
                .foregroundStyle(Hue.chatStamp)
                .padding(.top, ChatMetric.quoteTop)
                .padding(.horizontal, ChatMetric.quoteSide)
                .padding(.bottom, ChatMetric.quoteCaptionBelow)
            HStack(spacing: ChatMetric.quoteBarGap) {
                if !mine { quoteBar }
                Text(ChatWords.quoted(quote))
                    .appleFont(14)
                    .foregroundStyle(Hue.chatGrey)
                    .lineLimit(3)
                    .padding(.horizontal, ChatMetric.quoteX)
                    .padding(.vertical, ChatMetric.quoteY)
                    .background(Hue.chatFill, in: RoundedRectangle(cornerRadius: ChatMetric.quoteCorner, style: .continuous))
                    .frame(maxWidth: ChatMetric.quoteMax, alignment: mine ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if mine { quoteBar }
            }
            .padding(.bottom, ChatMetric.quoteBelow)
        }
        .accessibilityElement(children: .combine)
    }

    private var quoteBar: some View {
        RoundedRectangle(cornerRadius: ChatMetric.quoteBar / 2).fill(Hue.chatQuoteBar).frame(width: ChatMetric.quoteBar)
    }
}

/// What a message draws: words in their bubble, a photo or an Event. The thread's bubble and the hold's copy of it.
private struct ChatBubbleBody: View {
    let message: ChatMessage
    let thread: ChatThread
    let mine: Bool
    let shape: UnevenRoundedRectangle
    let screen: CGFloat
    /// One more for each double tap that hearts it.
    var sender: Neighbor? = nil
    var hearts = 0
    var reduceMotion = false

    private var spokenSender: String { mine ? "You" : (sender ?? message.sender)?.firstName ?? "" }

    var body: some View {
        switch message.content {
        case .text(let words):
            Text(words)
                .appleFont(16)
                .foregroundStyle(mine ? .white : Hue.ink)
                .padding(.horizontal, ChatMetric.bubbleX)
                .padding(.vertical, ChatMetric.bubbleY)
                .background {
                    if mine { ChatMineFill(screen: screen).clipShape(shape) } else { shape.fill(Hue.chatFill) }
                }
                .contentShape(shape)
                .overlay { ChatBigHeart(go: hearts, reduceMotion: reduceMotion) }
                .frame(maxWidth: ChatMetric.bubbleMax, alignment: mine ? .trailing : .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(spokenSender): \(words), \(ChatWords.agoSpoken(message.at))")
        case .photo(let path, let width, let height):
            ChatPhoto(image: thread.picked[message.id], link: path.flatMap { thread.links[$0] },
                      width: width, height: height, shape: shape)
                .overlay { ChatBigHeart(go: hearts, reduceMotion: reduceMotion) }
                .accessibilityLabel("\(spokenSender) sent a photo, \(ChatWords.agoSpoken(message.at))")
        case .event(let card):
            Group {
                if let card {
                    ChatEventCard(card: card)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("\(spokenSender) sent an Event, \(ChatWords.agoSpoken(message.at))")
                } else {
                    Text("This Event is no longer available.")
                        .appleFont(14)
                        .foregroundStyle(Hue.chatGrey)
                        .padding(.horizontal, ChatMetric.bubbleX)
                        .padding(.vertical, ChatMetric.bubbleY)
                        .overlay(RoundedRectangle(cornerRadius: ChatMetric.bubbleCorner, style: .continuous).stroke(Hue.chatRing))
                }
            }
            .overlay { ChatBigHeart(go: hearts, reduceMotion: reduceMotion) }
        }
    }
}

/// A host's update: Instagram's channel card, in the middle of the thread, their face on its top edge.
private struct ChatUpdateCard: View {
    let message: ChatMessage
    let words: String
    let mine: Bool
    let sender: Neighbor?

    var body: some View {
        let name = mine ? "You" : sender?.displayName ?? "Host"
        VStack(spacing: ChatMetric.updateLineGap) {
            Text("\(Text(name).fontWeight(.semibold).foregroundStyle(Hue.ink)) · Host")
                .appleFont(12)
                .foregroundStyle(Hue.chatGrey)
                .lineLimit(1)
            Text(words)
                .appleFont(16, weight: .semibold)
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.top, ChatMetric.updateTop)
        .padding(.horizontal, ChatMetric.updateSide)
        .padding(.bottom, ChatMetric.updateSide)
        .frame(width: ChatMetric.updateWidth)
        .background(Hue.chatFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .opacity(message.state == .sending ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Host update, \(name): \(words), \(ChatWords.agoSpoken(message.at))")
        .overlay(alignment: .top) { face.offset(y: -ChatMetric.updateFace / 2) }
        .padding(.top, ChatMetric.updateFace / 2)
        .padding(.bottom, ChatMetric.updateBelow)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var face: some View {
        let face = Avatar(avatarUrl: sender?.avatarUrl, size: ChatMetric.updateFace)
            .overlay(Circle().stroke(Hue.surface, lineWidth: 2))
        if !mine, let sender {
            NavigationLink(value: sender) { face.contentShape(Circle()) }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("\(sender.displayName)'s profile")
        } else {
            face.accessibilityHidden(true)
        }
    }
}

/// The small pill under a message: its emoji, the most picked first, and how many when more than one. It pops in.
private struct ChatReactionPill: View {
    let reactions: [ChatReaction]

    var body: some View {
        let pill = ChatLook.pill(reactions)
        HStack(spacing: ChatMetric.reactionGap) {
            ForEach(pill.emoji, id: \.self) { Text($0).font(.glyph(ChatMetric.reactionEmoji)) }
            if let count = pill.count {
                Text("\(count)").appleFont(12).foregroundStyle(Hue.chatGrey)
            }
        }
        .padding(.horizontal, ChatMetric.reactionPad)
        .frame(height: ChatMetric.reactionHeight)
        .background(Hue.chatFill, in: Capsule())
        .overlay(Capsule().stroke(Hue.surface, lineWidth: ChatMetric.reactionRing))
        .animation(ChatMotion.reaction, value: reactions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reactions: \(pill.emoji.joined(separator: " "))\(pill.count.map { ", \($0) people" } ?? "")")
    }
}

/// A double tap's heart over the message: in past full size, settles, then floats up and fades.
private struct ChatBigHeart: View {
    let go: Int
    let reduceMotion: Bool

    private struct Pose {
        var scale: CGFloat = 0
        var rise: CGFloat = 0
        var opacity: Double = 0
    }

    var body: some View {
        Text(ChatLook.heart)
            .font(.glyph(ChatMetric.bigHeart))
            .keyframeAnimator(initialValue: Pose(), trigger: go) { heart, pose in
                heart.scaleEffect(pose.scale).offset(y: -pose.rise).opacity(go == 0 ? 0 : pose.opacity)
            } keyframes: { _ in
                // Each go starts from nothing, whatever the last one left.
                let stays = ChatMotion.heartGrow + ChatMotion.heartSettle + ChatMotion.heartStay
                KeyframeTrack(\.scale) {
                    LinearKeyframe(reduceMotion ? 1 : 0, duration: 0)
                    CubicKeyframe(reduceMotion ? 1 : 1.25, duration: ChatMotion.heartGrow)
                    CubicKeyframe(1, duration: ChatMotion.heartSettle)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0)
                    LinearKeyframe(1, duration: stays)
                    LinearKeyframe(0, duration: ChatMotion.heartLeave)
                }
                KeyframeTrack(\.rise) {
                    LinearKeyframe(0, duration: 0)
                    LinearKeyframe(0, duration: stays)
                    CubicKeyframe(reduceMotion ? 0 : ChatMetric.bigHeartRise, duration: ChatMotion.heartLeave)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A held message, as the page draws it over everything.
struct ChatHeld {
    let message: ChatMessage
    /// The bubble on the screen when the hold began.
    let frame: CGRect
    let mine: Bool
    let shape: UnevenRoundedRectangle
    let sender: Neighbor?
    /// Its emoji row shows: it's on the server and not in a request you haven't accepted.
    let reacts: Bool
}

/// One line of the held message's menu.
struct ChatHeldItem: Identifiable {
    let title: String
    let icon: String
    let red: Bool
    let action: () -> Void
    var id: String { title }
}

/// Mock 1's hold: the page washed out, the bubble lifted to where its row and menu fit, the six emoji over it (yours on a
/// grey disc) and the menu under it, both growing in from its side. A tap anywhere else lets go.
private struct ChatHeldView: View {
    let held: ChatHeld
    let thread: ChatThread
    let screen: CGFloat
    let items: [ChatHeldItem]
    let reduceMotion: Bool
    let react: (String) -> Void
    let close: () -> Void
    @State private var shown = false

    private var rowWidth: CGFloat {
        CGFloat(ChatLook.emoji.count) * ChatMetric.holdEmojiSlot + CGFloat(ChatLook.emoji.count - 1) * ChatMetric.holdRowGap
            + 2 * ChatMetric.holdRowPad
    }

    var body: some View {
        GeometryReader { proxy in
            let page = proxy.frame(in: .global)
            let r = held.frame.offsetBy(dx: -page.minX, dy: -page.minY)
            let menu = CGFloat(items.count) * ChatMetric.holdMenuRow
            let top = max(ChatMetric.holdTopMost,
                          min(r.minY, page.height - ChatMetric.holdBottomMost - r.height - ChatMetric.holdMenuBelow - menu))
            let anchor: UnitPoint = held.mine ? .trailing : .leading
            ZStack(alignment: .topLeading) {
                Hue.chatHoldWash
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
                copy
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: shown ? top : r.minY)
                    .animation(reduceMotion ? nil : ChatMotion.holdMove, value: shown)
                if held.reacts {
                    emojiRow
                        .scaleEffect(shown ? 1 : 0.5, anchor: UnitPoint(x: anchor.x, y: 1))
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? nil : ChatMotion.holdRow, value: shown)
                        .offset(x: side(rowWidth, r, page.width),
                                y: top - ChatMetric.holdRowHeight - ChatMetric.holdRowAbove)
                }
                if !items.isEmpty {
                    menuView
                        .scaleEffect(shown ? 1 : 0.5, anchor: UnitPoint(x: anchor.x, y: 0))
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? nil : ChatMotion.holdMenu, value: shown)
                        .offset(x: side(ChatMetric.holdMenuWidth, r, page.width), y: top + r.height + ChatMetric.holdMenuBelow)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { shown = true }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }

    /// Where something as wide as `width` starts: at the bubble's right edge for yours, just left of its left edge for
    /// theirs, never off the screen.
    private func side(_ width: CGFloat, _ r: CGRect, _ page: CGFloat) -> CGFloat {
        let x = held.mine ? r.maxX - width : max(ChatMetric.holdEdge, r.minX - ChatMetric.holdSideIn)
        return min(max(ChatMetric.holdEdge, x), page - ChatMetric.holdEdge - width)
    }

    @ViewBuilder private var copy: some View {
        Group {
            if held.message.host, case .text(let words) = held.message.content {
                ChatUpdateCard(message: held.message, words: words, mine: held.mine, sender: held.sender)
            } else {
                ChatBubbleBody(message: held.message, thread: thread, mine: held.mine, shape: held.shape, screen: screen,
                               sender: held.sender)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var yours: String? {
        held.message.reactions.first { thread.isMe($0.userId) }?.emoji
    }

    /// Each emoji's tap reaches halfway across the gaps beside it, 39 pt, while it draws in its 30.
    private var emojiRow: some View {
        HStack(spacing: 0) {
            ForEach(ChatLook.emoji, id: \.self) { emoji in
                Button { react(emoji) } label: {
                    Text(emoji)
                        .font(.glyph(ChatMetric.holdEmoji))
                        .frame(width: ChatMetric.holdEmojiSlot + ChatMetric.holdRowGap, height: ChatMetric.holdRowHeight)
                        .background {
                            if emoji == yours {
                                Circle().fill(Hue.chatFill).frame(width: ChatMetric.holdEmojiSlot + 6, height: ChatMetric.holdEmojiSlot + 6)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(ChatEmojiPress())
                .accessibilityLabel(emoji == yours ? "Remove \(emoji)" : "React \(emoji)")
            }
        }
        .padding(.horizontal, ChatMetric.holdRowPad - ChatMetric.holdRowGap / 2)
        .frame(height: ChatMetric.holdRowHeight)
        .background(Hue.surface, in: Capsule())
        .modifier(ChatHoldLift(shape: Capsule()))
    }

    private var menuView: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Rectangle().fill(Hue.chatMenuLine).frame(height: ChatMetric.line) }
                Button {
                    item.action()
                    close()
                } label: {
                    HStack {
                        Text(item.title).appleFont(16)
                        Spacer(minLength: 0)
                        Image(systemName: item.icon).font(.glyph(17))
                    }
                    .foregroundStyle(item.red ? Hue.chatBlock : Hue.ink)
                    .padding(.horizontal, ChatMetric.holdMenuPad)
                    .frame(height: ChatMetric.holdMenuRow)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
            }
        }
        .frame(width: ChatMetric.holdMenuWidth)
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: ChatMetric.holdMenuCorner, style: .continuous))
        .modifier(ChatHoldLift(shape: RoundedRectangle(cornerRadius: ChatMetric.holdMenuCorner, style: .continuous)))
    }
}

/// The held row's and menu's lift: a soft shadow and a hairline edge.
private struct ChatHoldLift<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .overlay(shape.stroke(Hue.chatHoldEdge, lineWidth: ChatMetric.line))
            .shadow(color: Hue.chatHoldShadow, radius: 12, x: 0, y: 4)
    }
}

/// An emoji grows under the finger, as mock 1's do.
private struct ChatEmojiPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.3 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A photo in the chat, in its own shape; a tap opens it whole.
private struct ChatPhoto: View {
    let image: UIImage?
    let link: URL?
    let width: Int
    let height: Int
    /// Its bubble's corners: tight where the run joins.
    let shape: UnevenRoundedRectangle
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
            .clipShape(shape)
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
            FeedCardURLPhoto(url: link, loadingFill: Hue.chatFill)
        } else {
            Rectangle().fill(Hue.chatFill).shimmering()
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

/// An Event in the chat (the mock's card): its photo, what and when and where, and friends going. It opens
/// the Event page, where Attend is (BP app event-card 07).
private struct ChatEventCard: View {
    let card: FeedCardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: card) {
                VStack(alignment: .leading, spacing: 0) {
                    Hue.chatFill
                        .frame(height: ChatMetric.eventPhoto)
                        .overlay {
                            if let url = card.image.url {
                                FeedCardURLPhoto(url: url, loadingFill: Hue.chatFill)
                            } else if let logo = card.image.logo {
                                // A place we have no photo of: its logo bare, as Search shows it.
                                CastLogo(logo: logo, side: ChatMetric.eventLogo)
                            }
                        }
                        .clipped()
                    Text(card.title)
                        .appleFont(16, weight: .semibold)
                        .foregroundStyle(Hue.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, ChatMetric.eventInsetY)
                        .padding(.horizontal, ChatMetric.eventInsetX)
                    Text(line)
                        .appleFont(13)
                        .foregroundStyle(Hue.chatGrey)
                        .lineLimit(1)
                        .padding(.horizontal, ChatMetric.eventInsetX)
                    if !card.friendsGoing.isEmpty {
                        FriendFaces(friends: card.friendsGoing, ring: Hue.surface)
                            .padding(.horizontal, ChatMetric.eventInsetX)
                            .padding(.top, ChatMetric.chipGap)
                    }
                }
                .padding(.bottom, ChatMetric.eventInsetY)
            }
            .buttonStyle(.press(.dim))
            // Called off, its red Canceled stays, as on a Town card (event-card 07).
            if card.cancelled {
                AttendPill(item: card, words: RSVPWords(top: nil, second: nil, canLeave: false, pill: .canceled),
                           onInvite: nil)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, ChatMetric.eventInsetX)
                    .padding(.bottom, ChatMetric.eventInsetY)
            }
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
}

/// I'm in, Maybe, Can't, under an Event sent to you.
private struct ChatAnswers: View {
    let tap: (ChatAnswer) -> Void

    var body: some View {
        HStack(spacing: ChatMetric.chipGap) {
            ForEach(ChatAnswer.allCases) { answer in
                Button { tap(answer) } label: {
                    Text(answer.label)
                        .appleFont(14, weight: .semibold)
                        .foregroundStyle(Hue.ink)
                        .padding(.horizontal, ChatMetric.chipPad)
                        .frame(height: ChatMetric.chipHeight)
                        .background(Hue.surface, in: Capsule())
                        .overlay(Capsule().stroke(Hue.chatRing))
                        .frame(minHeight: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, ChatMetric.threadLead + ChatMetric.theirLead)
        .padding(.top, ChatMetric.chipGap - (PageMetric.tapMin - ChatMetric.chipHeight) / 2)
    }
}

/// Three dots in their bubble, each hopping in turn while someone types; still with Reduce Motion.
private struct ChatTypingDots: View {
    /// Whoever is typing, when the chat knows their face.
    let face: Neighbor?
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: ChatMetric.theirLead - ChatMetric.theirFace) {
            Avatar(avatarUrl: face?.avatarUrl, size: ChatMetric.theirFace)
            HStack(spacing: ChatMetric.typingGap) {
                ForEach(0..<3, id: \.self) { i in
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        // 1.1 s a round, each dot 0.15 s after the last: up and back in the first 60%, then still.
                        let turn = (context.date.timeIntervalSinceReferenceDate - Double(i) * 0.15)
                            .truncatingRemainder(dividingBy: 1.1) / 1.1
                        let hop = reduceMotion || turn > 0.6 ? 0 : sin(.pi * turn / 0.6)
                        Circle()
                            .fill(Hue.chatTypingDot)
                            .frame(width: ChatMetric.typingDot, height: ChatMetric.typingDot)
                            .offset(y: -ChatMetric.typingJump * hop)
                            .opacity(0.55 + 0.45 * hop)
                    }
                }
            }
            .padding(.horizontal, ChatMetric.typingX)
            .frame(height: ChatMetric.typingHeight)
            .background(Hue.chatFill, in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.leading, ChatMetric.threadLead)
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
                    SkeletonBlock(cornerRadius: ChatMetric.bubbleCorner)
                        .frame(width: ChatMetric.bubbleMax * (mine ? 0.5 : 0.7), height: ChatMetric.typingHeight)
                    if !mine { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.leading, ChatMetric.threadLead)
        .padding(.trailing, ChatMetric.threadTrail)
        .shimmering()
        .accessibilityLabel("Loading")
    }
}

/// A request's foot: Accept brings it into your chats, Delete takes it away and it can't ask again, Block ends it.
/// Instagram's Decline and Join, measured: grey and blue, 44 tall.
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
                .appleFont(13)
                .foregroundStyle(Hue.chatGrey)
                .multilineTextAlignment(.center)
            HStack(spacing: ChatMetric.chipGap) {
                pill("Block", fill: Hue.chatButton, ink: Hue.chatBlock, action: block)
                pill("Delete", fill: Hue.chatButton, ink: Hue.ink) { act { try await chats.decline(chat); done(true) } }
                pill("Accept", fill: Hue.chatBlue, ink: .white) { act { try await chats.accept(chat); done(false) } }
            }
            .turnBackShake(failures: failures, shakes: !reduceMotion)
        }
        .padding(.horizontal, ChatMetric.side)
        .padding(.top, ChatMetric.requestTop)
        .padding(.bottom, ChatMetric.composerY)
        .background(Hue.surface)
        .overlay(alignment: .top) { Rectangle().fill(Hue.chatLine).frame(height: ChatMetric.line) }
    }

    private func pill(_ words: String, fill: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(words)
                .appleFont(15, weight: .semibold)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: ChatMetric.requestButton)
                .background(fill, in: RoundedRectangle(cornerRadius: ChatMetric.requestCorner, style: .continuous))
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
