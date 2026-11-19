//
//  MessagesPage.swift
//  Block Party — Messages (BP app five-tabs 05, messages 02): the paper plane on Friends opens it. Instagram's inbox
//  without Notes, measured (BP app `references/messages-instagram/SPEC.md`): the pencil, search, your chats newest
//  first with Requests across from their title, then your friends with no chat yet. Requests is its own list.
//  Apple's font on white, as Instagram's.
//

import SwiftUI

/// Sizes from Instagram's inbox and chat, measured (BP app `references/messages-instagram/SPEC.md`).
nonisolated enum ChatMetric {
    static let side: CGFloat = 16
    static let face: CGFloat = 56
    /// Two faces for a group of friends: 38 each on the 56, one up and left, one down and right.
    static let duoFace: CGFloat = 38
    static let rowGap: CGFloat = 12
    static let rowPad: CGFloat = 8
    static let sectionTop: CGFloat = 14
    static let sectionBottom: CGFloat = 6

    // Messages and Requests.
    /// A list page's own top: the back chevron, the title and the pencil.
    static let listBar: CGFloat = 58
    static let listTitleTop: CGFloat = 11
    static let listTitleLine: CGFloat = 28
    /// The chevron's middle, down the bar and in from the left.
    static let backMid: CGFloat = 28
    static let backLead: CGFloat = 9.3
    static let pencilTrail: CGFloat = 7.5
    static let pencilLift: CGFloat = 4.6
    static let searchLead: CGFloat = 13.3
    static let searchTrail: CGFloat = 13.7
    static let searchHeight: CGFloat = 44
    static let searchIcon: CGFloat = 16
    static let searchIconLead: CGFloat = 13.7
    static let searchIconGap: CGFloat = 8.3
    static let titleTop: CGFloat = 19.6
    static let titleLine: CGFloat = 20
    /// Under a title to its first face, and from a face to the next title, less a row's own 8.
    static let titleBottom: CGFloat = 11.6
    static let nextTitleTop: CGFloat = 15.6
    static let titleTrail: CGFloat = 17
    static let rowLead: CGFloat = 14
    static let rowTextGap: CGFloat = 12.5
    static let rowLine: CGFloat = 20
    static let unreadDot: CGFloat = 6.4
    static let unreadGap: CGFloat = 12
    static let requestsTop: CGFloat = 4
    static let noneTop: CGFloat = 60
    static let loadingRows = 6
    static let loadingName: CGFloat = 140
    static let loadingLine: CGFloat = 12
    static let planeGlyph: CGFloat = 25
    /// The plane's red dot, on its top right.
    static let planeDot: CGFloat = 9
    static let planeDotInset: CGFloat = 8
    /// On a neighbour's Profile, in the cover's white circle (picked).
    static let profileGlyph: CGFloat = 18
    /// A Going chat's Event photo, as the mock's row: this corner on the 56 pt face, and in scale on the bar's.
    static let eventFaceCorner: CGFloat = 14
    /// The "Going chat" tag beside its name (the mock's).
    static let tagX: CGFloat = 6
    static let tagHeight: CGFloat = 18
    static let tagCorner: CGFloat = 6
    /// A host's update: Instagram's channel card, measured (`references/going-chat/SPEC.md`).
    static let updateWidth: CGFloat = 288
    static let updateFace: CGFloat = 44
    static let updateTop: CGFloat = 30
    static let updateSide: CGFloat = 16
    static let updateLineGap: CGFloat = 6
    static let updateAbove: CGFloat = 12
    static let updateBelow: CGFloat = 12

    // A chat (`ChatPage`).
    static let chatBar: CGFloat = 66
    /// A friend's face in the bar; a room's square and a group's two faces are `barSquare`.
    static let barFace: CGFloat = 32
    static let barSquare: CGFloat = 34
    static let barFaceLead: CGFloat = 60.5
    static let barFaceGap: CGFloat = 9.2
    static let barSquareGap: CGFloat = 8.2
    static let barChevron: CGFloat = 10
    static let barChevronGap: CGFloat = 6
    static let line: CGFloat = 0.5
    static let bubbleMax: CGFloat = 268
    static let bubbleX: CGFloat = 13
    static let bubbleY: CGFloat = 10
    static let bubbleLine: CGFloat = 20
    static let bubbleCorner: CGFloat = 20
    /// The corners where two bubbles in a run meet.
    static let bubbleJoin: CGFloat = 4
    static let threadLead: CGFloat = 16
    static let threadTrail: CGFloat = 8
    static let threadY: CGFloat = 8
    static let runGap: CGFloat = 2
    static let groupGap: CGFloat = 10
    static let theirFace: CGFloat = 28
    /// Their bubbles start here, past the face.
    static let theirLead: CGFloat = 40
    static let stampTop: CGFloat = 22
    static let stampBottom: CGFloat = 14
    static let nameBottom: CGFloat = 3
    /// A friend's chat opens on them: face, name, mutual friends, View profile.
    static let profileTop: CGFloat = 20
    static let profileFace: CGFloat = 96
    static let profileNameTop: CGFloat = 12
    static let profileNameLine: CGFloat = 24
    static let profileLine: CGFloat = 22.5
    static let profileButtonTop: CGFloat = 15.8
    static let profileButton: CGFloat = 32
    static let profileButtonPad: CGFloat = 15.4
    static let profileButtonCorner: CGFloat = 8.3
    /// The times at the side: how far the chat comes left, and where each time sits past its row.
    static let timesPull: CGFloat = 64
    static let timesShown: CGFloat = 40
    static let timesWidth: CGFloat = 56
    static let timesOut: CGFloat = 58
    static let timesUp: CGFloat = 12
    // Hearts and replies (BP app messages 03): mock 1's numbers, guessed (no Instagram still; `references/messages-instagram/`).
    /// The small pill under a message: 24 tall, 7 in, a 2 pt white ring, 10 in from the bubble's side, 8 up over it.
    static let reactionHeight: CGFloat = 24
    static let reactionPad: CGFloat = 7
    static let reactionRing: CGFloat = 2
    static let reactionSide: CGFloat = 10
    static let reactionOver: CGFloat = 8
    static let reactionEmoji: CGFloat = 13
    static let reactionGap: CGFloat = 2
    /// A double tap's big heart.
    static let bigHeart: CGFloat = 46
    static let bigHeartRise: CGFloat = 14
    /// A held message: the emoji row over it, the menu under it.
    static let holdRowHeight: CGFloat = 48
    static let holdRowPad: CGFloat = 10
    static let holdRowGap: CGFloat = 9
    static let holdRowAbove: CGFloat = 8
    static let holdEmoji: CGFloat = 28
    static let holdEmojiSlot: CGFloat = 30
    static let holdMenuWidth: CGFloat = 210
    static let holdMenuRow: CGFloat = 44
    static let holdMenuCorner: CGFloat = 14
    static let holdMenuPad: CGFloat = 16
    static let holdMenuBelow: CGFloat = 8
    static let holdSideIn: CGFloat = 4
    static let holdEdge: CGFloat = 8
    /// The held bubble stays below this and above the composer's band, moving only when it must.
    static let holdTopMost: CGFloat = 120
    static let holdBottomMost: CGFloat = 60
    static let holdBlur: CGFloat = 14
    /// A swipe right to reply: the arrow sits this far left of the row, shows by 44, and the reply takes at 52.
    static let replyArrow: CGFloat = 20
    static let replyArrowOut: CGFloat = 30
    static let replyShows: CGFloat = 44
    static let replyTakes: CGFloat = 52
    /// A swipe that starts this near the left edge is the stack's swipe back.
    static let replyEdge: CGFloat = 24
    /// The quote over a reply: "You replied to Maya", then the quoted words beside a 3 pt bar.
    static let quoteTop: CGFloat = 6
    static let quoteSide: CGFloat = 4
    static let quoteCaptionBelow: CGFloat = 4
    static let quoteBar: CGFloat = 3
    static let quoteBarGap: CGFloat = 6
    static let quoteX: CGFloat = 12
    static let quoteY: CGFloat = 8
    static let quoteCorner: CGFloat = 18
    static let quoteMax: CGFloat = 230
    static let quoteBelow: CGFloat = 2
    /// "Replying to Maya" over the composer.
    static let replyingTop: CGFloat = 9
    static let replyingBottom: CGFloat = 6
    static let photoWidth: CGFloat = 240
    static let photoTallest: CGFloat = 320
    static let photoQuality: CGFloat = 0.8
    /// What goes up: the same 1290 as a post's photo.
    static let photoUpload: CGFloat = 1290
    static let eventWidth: CGFloat = 250
    static let eventPhoto: CGFloat = 150
    /// A place with no photo on the Event card: its logo bare, at Search's old row size (search-logo-size 01).
    static let eventLogo: CGFloat = 80
    static let eventInsetX: CGFloat = 12
    static let eventInsetY: CGFloat = 10
    static let chipHeight: CGFloat = 32
    static let chipPad: CGFloat = 14
    static let chipGap: CGFloat = 8
    static let typingDot: CGFloat = 7
    static let typingGap: CGFloat = 4
    static let typingX: CGFloat = 15
    static let typingHeight: CGFloat = 40
    static let typingJump: CGFloat = 4
    static let composerY: CGFloat = 7.7
    static let composerLead: CGFloat = 8
    static let composerTrail: CGFloat = 7.3
    static let composerField: CGFloat = 44.7
    /// With words in it: taller, and the send pill sits this far in from its right.
    static let composerTyping: CGFloat = 48
    static let composerWordsLead: CGFloat = 16
    static let composerIconsTrail: CGFloat = 18.9
    static let composerIcon: CGFloat = 24
    static let composerIconGap: CGFloat = 16
    static let composerSendTrail: CGFloat = 5.5
    static let sendWidth: CGFloat = 50
    static let sendHeight: CGFloat = 34
    static let sendGlyph: CGFloat = 20
    static let composerLines = 5
    static let older: CGFloat = 44
    /// A request's foot: Instagram's Decline and Join, measured.
    static let requestTop: CGFloat = 12
    static let requestButton: CGFloat = 44
    static let requestCorner: CGFloat = 12
    // The + sheet (guessed: no Instagram still).
    static let sheetCorner: CGFloat = 22
    static let sheetTitleTop: CGFloat = 27
    static let sheetPhoto: CGFloat = 56
    static let sheetPhotoCorner: CGFloat = 12
    // New message: Instagram's people picker.
    static let pickX: CGFloat = 18.7
    static let pickXTop: CGFloat = 10.3
    static let pickXSide: CGFloat = 22
    static let pickTitleLine: CGFloat = 20
    static let pickFieldTrail: CGFloat = 12
    static let pickField: CGFloat = 36.7
    static let pickFieldCorner: CGFloat = 10.8
    static let pickFieldIcon: CGFloat = 13
    static let pickFieldIconLead: CGFloat = 12.3
    static let pickFieldIconGap: CGFloat = 6.7
    static let pickCountTop: CGFloat = 19.3
    static let pickCountTrail: CGFloat = 14.3
    static let pickListTop: CGFloat = 17
    static let pickFace: CGFloat = 44
    static let pickTick: CGFloat = 23
    static let pickTickRing: CGFloat = 1.5
    static let pickTickGlyph: CGFloat = 11
    static let pickFootTop: CGFloat = 10
    static let pickFootBottom: CGFloat = 16.4
    static let pickNameGap: CGFloat = 10
    static let pickButton: CGFloat = 43.3
    static let pickButtonCorner: CGFloat = 13
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
    /// An Event's Going chat, from its page (five-tabs 06), whether or not anyone has written.
    case going(FeedCardItem, isHost: Bool)
    /// A Group's chat, from its page (five-tabs 07), whether or not anyone has written.
    case groupChat(TownGroup)
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
        .buttonStyle(.press(.squish))
        .animation(Motion.smooth, value: chats.unread)
        .accessibilityLabel(chats.unread ? "Messages, unread message" : "Messages")
    }
}

/// A Messages page's own top (Instagram's): the back chevron, the title in the middle, and what the page puts at the
/// right (the pencil). Flat white, no line.
struct MessagesBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Text(title)
                .appleFont(24, weight: .bold)
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .frame(height: ChatMetric.listTitleLine)
                .padding(.top, ChatMetric.listTitleTop)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                ChatBackButton { dismiss() }
                Spacer(minLength: 0)
                // The pencil's middle sits 2.3 above the chevron's.
                trailing.padding(.trailing, ChatMetric.pencilTrail).padding(.bottom, ChatMetric.pencilLift)
            }
            .frame(height: ChatMetric.backMid * 2)
        }
        .frame(height: ChatMetric.listBar, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Hue.surface.ignoresSafeArea(edges: .top))
    }
}

extension MessagesBar where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Instagram's back chevron, 12 by 21, its middle 31 in from the left; 44 to the finger.
struct ChatBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.glyph(23, weight: .medium))
                .foregroundStyle(Hue.ink)
                .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
        .accessibilityLabel("Back")
        .padding(.leading, ChatMetric.backLead)
    }
}

/// Instagram's search bar: a grey pill, the glass in ink.
struct ChatSearchBar: View {
    @Binding var words: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: ChatMetric.searchIconGap) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(16.5, weight: .medium))
                .foregroundStyle(Hue.ink)
                .frame(width: ChatMetric.searchIcon, height: ChatMetric.searchIcon)
                .accessibilityHidden(true)
            TextField("Search", text: $words, prompt: Text("Search").foregroundStyle(Hue.chatGrey))
                .appleFont(17)
                .foregroundStyle(Hue.ink)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.leading, ChatMetric.searchIconLead)
        .padding(.trailing, ChatMetric.side)
        .frame(height: ChatMetric.searchHeight)
        .background(Hue.chatFill, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .padding(.leading, ChatMetric.searchLead)
        .padding(.trailing, ChatMetric.searchTrail)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if typing { results } else { list }
            }
            .padding(.bottom, ChatMetric.sectionTop)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await chats.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                MessagesBar(title: "Messages") {
                    Button { picking = true } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.glyph(24))
                            .foregroundStyle(Hue.ink)
                            .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.squish))
                    .accessibilityLabel("New message")
                }
                ChatSearchBar(words: $words)
            }
            .background(Hue.surface)
        }
        .background(Hue.surface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await chats.refresh() }
        .task { await book.refresh() }
        .sheet(isPresented: $picking) { NewMessagePage() }
    }

    @ViewBuilder private var list: some View {
        let mine = chats.messages, requests = chats.requests
        ChatSectionTitle("Messages") {
            // Always there; its count in blue is how you know, since a request lights no dot.
            NavigationLink(value: ChatRoute.requests) {
                Text(requests.isEmpty ? "Requests" : requests.count == 1 ? "1 request" : "\(requests.count) requests")
                    .appleFont(14, weight: .semibold)
                    .foregroundStyle(requests.isEmpty ? Hue.chatGrey : Hue.chatBlue)
                    .contentShape(TapArea())
            }
            .buttonStyle(.press(.dim))
        }
        .padding(.top, ChatMetric.titleTop)
        if chats.chats == nil {
            if chats.failed {
                ChatFailedLine { await chats.refresh() }
            } else {
                ChatLoadingRows()
            }
        } else {
            ForEach(mine) { chat in ChatRow(chat: chat) }
            // Your friends with no chat yet, under your chats: never an empty box.
            let friends = book.friends.filter { chats.chat(with: $0) == nil }
            if mine.isEmpty, friends.isEmpty, book.loaded {
                Text("Add a friend to start a chat.")
                    .appleFont(14)
                    .foregroundStyle(Hue.chatGrey)
                    .frame(maxWidth: .infinity, minHeight: ChatMetric.older)
            }
            if !friends.isEmpty {
                if !mine.isEmpty { ChatSectionTitle("Friends").padding(.top, ChatMetric.nextTitleTop) }
                ForEach(friends) { person in
                    NavigationLink(value: ChatRoute.person(person)) { FriendToChatRow(person: person) }
                        .buttonStyle(.press(.row))
                }
            }
        }
    }

    /// What's typed, by name: your chats, then friends you haven't one with.
    @ViewBuilder private var results: some View {
        let found = (chats.chats ?? []).filter { matches($0.title) }
        let friends = book.friends.filter { person in matches(person.displayName) && chats.chat(with: person) == nil }
        Color.clear.frame(height: ChatMetric.titleBottom)
        if found.isEmpty && friends.isEmpty {
            NothingFound()
        } else {
            ForEach(found) { chat in ChatRow(chat: chat) }
            ForEach(friends) { person in
                NavigationLink(value: ChatRoute.person(person)) { FriendToChatRow(person: person) }
                    .buttonStyle(.press(.row))
            }
        }
    }
}

/// "Messages", with Requests across from it; "Friends".
private struct ChatSectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .appleFont(16, weight: .bold)
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: ChatMetric.titleLine)
        .padding(.leading, ChatMetric.side)
        .padding(.trailing, ChatMetric.titleTrail)
        .padding(.bottom, ChatMetric.titleBottom)
    }
}

extension ChatSectionTitle where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

/// Requests: messages from people who aren't your friends. Opening one tells them nothing.
struct RequestsPage: View {
    @Environment(ChatBook.self) private var chats

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(chats.requests) { chat in ChatRow(chat: chat) }
                if chats.requests.isEmpty {
                    Text("No requests")
                        .appleFont(14)
                        .foregroundStyle(Hue.chatGrey)
                        .frame(maxWidth: .infinity)
                        .padding(.top, ChatMetric.noneTop - ChatMetric.requestsTop)
                }
            }
            .padding(.top, ChatMetric.requestsTop)
        }
        .safeAreaInset(edge: .top, spacing: 0) { MessagesBar(title: "Requests") }
        .background(Hue.surface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One chat in the list: its face or faces, its name, what was said and when, and Instagram's blue dot when unread.
private struct ChatRow: View {
    let chat: Chat

    var body: some View {
        TimelineView(.everyMinute) { context in
            let ago = ChatWords.ago(chat.lastDate, now: context.date)
            NavigationLink(value: ChatRoute.chat(chat)) {
                HStack(spacing: 0) {
                    ChatFace(chat: chat)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: ChatMetric.tagX) {
                            Text(chat.title)
                                .appleFont(14, weight: chat.unread ? .semibold : .regular)
                                .foregroundStyle(Hue.ink)
                                .lineLimit(1)
                            if let tag {
                                Text(tag)
                                    .appleFont(11, weight: .semibold)
                                    .foregroundStyle(Hue.chatGrey)
                                    .padding(.horizontal, ChatMetric.tagX)
                                    .frame(height: ChatMetric.tagHeight)
                                    .background(Hue.chatFill, in: RoundedRectangle(cornerRadius: ChatMetric.tagCorner, style: .continuous))
                                    .fixedSize()
                            }
                        }
                        .frame(height: ChatMetric.rowLine)
                        HStack(spacing: 0) {
                            Text(ChatWords.preview(chat))
                                .appleFont(14, weight: chat.unread ? .semibold : .regular)
                                .foregroundStyle(chat.unread ? Hue.ink : Hue.chatGrey)
                                .lineLimit(1)
                            Text(" · \(ago)")
                                .appleFont(14)
                                .foregroundStyle(Hue.chatGrey)
                                .fixedSize()
                        }
                        .frame(height: ChatMetric.rowLine)
                    }
                    .padding(.leading, ChatMetric.rowTextGap)
                    Spacer(minLength: 0)
                    if chat.unread {
                        Circle().fill(Hue.chatDot)
                            .frame(width: ChatMetric.unreadDot, height: ChatMetric.unreadDot)
                            .padding(.leading, ChatMetric.unreadGap)
                    }
                }
                .padding(.leading, ChatMetric.rowLead)
                .padding(.trailing, ChatMetric.side)
                .padding(.vertical, ChatMetric.rowPad)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.row))
            .accessibilityLabel([chat.title, tag, chat.unread ? "Unread" : nil, ChatWords.preview(chat),
                                 ChatWords.agoSpoken(chat.lastDate)]
                .compactMap { $0 }.joined(separator: ", "))
        }
    }

    private var tag: String? {
        switch chat.kind {
        case .going: "Going chat"
        case .club: "Group"
        case .direct, .group: nil
        }
    }
}

/// A friend you haven't a chat with: Instagram's Suggestions row.
private struct FriendToChatRow: View {
    let person: Neighbor

    var body: some View {
        HStack(spacing: ChatMetric.rowTextGap) {
            Avatar(avatarUrl: person.avatarUrl, size: ChatMetric.face)
            VStack(alignment: .leading, spacing: 0) {
                Text(person.displayName)
                    .appleFont(14, weight: .semibold)
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                    .frame(height: ChatMetric.rowLine)
                Text("Tap to chat")
                    .appleFont(14)
                    .foregroundStyle(Hue.chatGrey)
                    .frame(height: ChatMetric.rowLine)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, ChatMetric.rowLead)
        .padding(.trailing, ChatMetric.side)
        .padding(.vertical, ChatMetric.rowPad)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// An Event in a Going chat's row and bar: its photo, else its place's logo, in a rounded square.
struct ChatEventFace: View {
    let card: FeedCardItem
    var size = ChatMetric.face

    var body: some View {
        Hue.chatFill
            .frame(width: size, height: size)
            .overlay {
                if let url = card.image.url {
                    FeedCardURLPhoto(url: url, loadingFill: Hue.chatFill)
                } else if let logo = card.image.logo {
                    CastLogo(logo: logo, side: size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * ChatMetric.eventFaceCorner / ChatMetric.face, style: .continuous))
    }
}

/// A Group in a Group chat's row and bar: its logo on its backdrop, else Search's group icon (the spec's rule), in the
/// Going chat's rounded square. nil: the Group isn't read yet, which shows the icon.
struct ChatGroupFace: View {
    let group: TownGroup?
    var size = ChatMetric.face

    var body: some View {
        let scale = size / ChatMetric.face
        Hue.chatFill
            .frame(width: size, height: size)
            .overlay {
                YouGroupPicture(group: group, logoSide: YouMetric.groupLogo * scale, glyph: YouMetric.groupGlyph * scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: ChatMetric.eventFaceCorner * scale, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A chat's picture: the friend's face, for a group two faces overlapping, for a Going chat its Event, for a Group chat
/// its Group.
struct ChatFace: View {
    let chat: Chat
    var size = ChatMetric.face
    @Environment(YouModel.self) private var you: YouModel?

    var body: some View {
        if let card = chat.card {
            ChatEventFace(card: card, size: size)
        } else if let club = chat.clubId {
            ChatGroupFace(group: you?.groups?.first { $0.id == club }, size: size)
        } else if chat.kind == .direct || chat.others.count < 2 {
            Avatar(avatarUrl: chat.others.first?.avatarUrl, size: size)
        } else {
            ChatDuoFace(first: chat.others[0], second: chat.others[1], size: size)
        }
    }
}

/// Two faces for a group of friends: one up and left, one down and right in a white ring.
struct ChatDuoFace: View {
    let first: Neighbor
    let second: Neighbor
    var size = ChatMetric.face

    var body: some View {
        let small = size * ChatMetric.duoFace / ChatMetric.face
        ZStack {
            Avatar(avatarUrl: first.avatarUrl, size: small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Avatar(avatarUrl: second.avatarUrl, size: small)
                .overlay(Circle().stroke(Hue.surface, lineWidth: size < ChatMetric.face ? 1.5 : 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
            .padding(.leading, ChatMetric.rowLead)
            .padding(.trailing, ChatMetric.side)
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
                .appleFont(13)
                .foregroundStyle(Hue.chatGrey)
                .frame(maxWidth: .infinity, minHeight: PageMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
    }
}
