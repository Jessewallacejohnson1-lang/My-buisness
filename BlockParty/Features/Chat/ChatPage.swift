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
//  Apple's pieces: a bottom-anchored scroll (`defaultScrollAnchor`), the composer in `safeAreaInset`, a growing
//  `TextField`, `PhotosPicker`, `contextMenu` on a bubble and a sheet for the +. Ours: the bubble's colour by its
//  height, its rise from the composer and the drag for the times (`ChatTimesPan`). How Instagram builds its own
//  is a guess.
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
                         report: { reporting = $0 },
                         block: { blocking = $0 })
                .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { foot(thread) }
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
            composer(thread)
        }
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
        let text = words, id = UUID().uuidString.lowercased()
        words = ""
        rising = reduceMotion ? nil : id
        Task {
            await thread.send(text, id: id)
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
    let report: (ChatMessage) -> Void
    let block: (Neighbor) -> Void
    /// How far a finger has dragged the chat left, for its times.
    @State private var pull: CGFloat = 0

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
                                   showsName: isGroup && firstOfRun, showsFace: lastOfRun, isGroup: isGroup,
                                   joinsAbove: joinsAbove, joinsBelow: joinsBelow, screen: screen,
                                   risesFrom: rises ? composerWords : nil, timeShown: min(1, shift / ChatMetric.timesShown),
                                   reduceMotion: reduceMotion, report: report, block: block)
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
            }
            .defaultScrollAnchor(.bottom)
            // A short chat with a friend starts under the bar, its profile block on top; any other sits on the composer.
            .defaultScrollAnchor(profile != nil && thread.loaded && !thread.hasOlder ? .top : .bottom, for: .alignment)
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
/// their name at its start. A failed one says so and taps to try again. Press and hold: Copy, Report.
private struct ChatBubble: View {
    let message: ChatMessage
    let thread: ChatThread
    let sender: Neighbor?
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
    let report: (ChatMessage) -> Void
    let block: (Neighbor) -> Void
    /// Up in its place; false while it is still down in the composer.
    @State private var up: Bool

    init(message: ChatMessage, thread: ChatThread, sender: Neighbor?, showsName: Bool, showsFace: Bool, isGroup: Bool,
         joinsAbove: Bool, joinsBelow: Bool, screen: CGFloat, risesFrom: CGPoint?, timeShown: CGFloat, reduceMotion: Bool,
         report: @escaping (ChatMessage) -> Void, block: @escaping (Neighbor) -> Void) {
        self.message = message
        self.thread = thread
        self.sender = sender
        self.showsName = showsName
        self.showsFace = showsFace
        self.isGroup = isGroup
        self.joinsAbove = joinsAbove
        self.joinsBelow = joinsBelow
        self.screen = screen
        self.risesFrom = risesFrom
        self.timeShown = timeShown
        self.reduceMotion = reduceMotion
        self.report = report
        self.block = block
        _up = State(initialValue: risesFrom == nil)
    }

    private var mine: Bool { thread.isMine(message) }

    private var shape: UnevenRoundedRectangle { ChatLook.bubble(mine: mine, joinsAbove: joinsAbove, joinsBelow: joinsBelow) }

    var body: some View {
        VStack(alignment: message.host ? .center : mine ? .trailing : .leading, spacing: 2) {
            if message.host, case .text(let words) = message.content {
                update(words)
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
        .accessibilityElement(children: .contain)
        .onAppear {
            if !up { withAnimation(ChatMotion.rise) { up = true } }
        }
    }

    /// A host's update: Instagram's channel card, in the middle of the thread, their face on its top edge.
    private func update(_ words: String) -> some View {
        let name = mine ? "You" : sender?.displayName ?? "Host"
        return VStack(spacing: ChatMetric.updateLineGap) {
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
        .contextMenu { menu }
        .overlay(alignment: .top) { updateFace.offset(y: -ChatMetric.updateFace / 2) }
        .padding(.top, ChatMetric.updateFace / 2)
        .padding(.bottom, ChatMetric.updateBelow)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var updateFace: some View {
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
            body(for: message.content)
                // Still on its way once it has landed: faint, as before.
                .opacity(!up ? 0.7 : message.state == .sending && risesFrom == nil ? 0.6 : 1)
                .contextMenu { menu }
                // Just sent: it starts down where the composer's words were and comes up to its place.
                .visualEffect { [up, risesFrom] view, proxy in
                    let frame = proxy.frame(in: .global)
                    let from = up ? nil : risesFrom
                    return view.offset(x: from.map { $0.x - ChatMetric.bubbleX - frame.minX } ?? 0,
                                       y: from.map { $0.y - ChatMetric.typingHeight / 2 - frame.minY } ?? 0)
                }
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
                .appleFont(16)
                .foregroundStyle(mine ? .white : Hue.ink)
                .padding(.horizontal, ChatMetric.bubbleX)
                .padding(.vertical, ChatMetric.bubbleY)
                .background {
                    if mine { ChatMineFill(screen: screen).clipShape(shape) } else { shape.fill(Hue.chatFill) }
                }
                .contentShape(.contextMenuPreview, shape)
                .frame(maxWidth: ChatMetric.bubbleMax, alignment: mine ? .trailing : .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(spokenSender): \(words), \(ChatWords.agoSpoken(message.at))")
        case .photo(let path, let width, let height):
            ChatPhoto(image: thread.picked[message.id], link: path.flatMap { thread.links[$0] },
                      width: width, height: height, shape: shape)
                .accessibilityLabel("\(spokenSender) sent a photo, \(ChatWords.agoSpoken(message.at))")
        case .event(let card):
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
