//
//  FeedCommentSheet.swift
//  Block Party — a post's comments (BP app backlog 38; Jesse's yes at Check-in 1, 2026-11-21, mock
//  https://claude.ai/artifact/PS7c9ZLvGzf2cy44NBgCgH beside Instagram's, references/comments-work/ig-sheet-medium.jpg).
//  Apple's sheet at 70% and full, under Instagram's thin handle and centred title, no X. Each comment is a 32 pt
//  photo, the name and its age, the words, and Reply; pressed and held, Apple's menu: Reply, Report, Delete (Delete at
//  once, Jesse's pick). Your comment shows at once as "Posting…" and stays when the check says yes; a no takes it out
//  and puts the words back with the reason in red.
//

import SwiftUI

struct FeedCommentSheet: View {
    let thread: CommentThread

    @Environment(RealLifeActions.self) private var actions: RealLifeActions?
    @Environment(FriendsBook.self) private var book: FriendsBook?
    @Environment(SearchModel.self) private var search: SearchModel?
    @Environment(ProfileModel.self) private var me: ProfileModel?
    @Environment(\.hostOpener) private var opener
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    /// The `@` names picked into `draft`; those still in the words go with it.
    @State private var names: [AtName] = []
    @State private var selection: TextSelection?
    @State private var refusal: CommentRefusal?
    @State private var reporting: PostComment?
    @FocusState private var typing: Bool
    /// The list's frame: a place named in a comment flies out from its middle.
    @State private var listFrame = FrameBox()

    /// Instagram's sheet, measured (references/comments-work, 393 pt wide).
    private enum Metric {
        static let header: CGFloat = 71
        static let grabberTop: CGFloat = 16
        static let grabber = CGSize(width: 34, height: 2.5)
        static let titleTop: CGFloat = 28
        static let photo: CGFloat = 32
        static let photoGap: CGFloat = 8
        static let rowLeading: CGFloat = 12
        static let rowTrailing: CGFloat = 16
        static let rowBottom: CGFloat = 16
        static let listTop: CGFloat = 10
        static let me: CGFloat = 44
        static let field: CGFloat = 42
        static let send = CGSize(width: 50, height: 31)
        static let side: CGFloat = 16
        /// The reason lines up with the field's words: past your photo and its gap.
        static let reasonLeading: CGFloat = 52
        static let limit = 500
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            composer
        }
        .background(Hue.surface)
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Hue.surface)
        .task { await thread.load() }
        .confirmationDialog("Why are you reporting this?", isPresented: reportAsked, titleVisibility: .visible) {
            ForEach(ReportReason.allCases.filter(\.hides)) { reason in
                Button(reason.label) { report(reason) }
            }
            Button("Cancel", role: .cancel) { reporting = nil }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .top) {
            // Instagram's #A8A8A8 on white: the secondary ink at 60%.
            Capsule()
                .fill(Hue.inkSecondary.opacity(0.6))
                .frame(width: Metric.grabber.width, height: Metric.grabber.height)
                .padding(.top, Metric.grabberTop)
                .accessibilityHidden(true)
            Text(CommentCopy.title)
                .font(.displaySemi(16))
                .foregroundStyle(Hue.ink)
                .padding(.top, Metric.titleTop)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, minHeight: Metric.header, alignment: .top)
        .overlay(alignment: .bottom) { Rectangle().fill(Hue.hairline).frame(height: 1) }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if thread.loading && thread.comments.isEmpty {
                        CommentListSkeleton()
                    } else if thread.failed {
                        Button { Task { await thread.load() } } label: {
                            Text(CommentCopy.loadFailed)
                                .font(.sans(15))
                                .foregroundStyle(Hue.inkSecondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 80)
                    } else if thread.comments.isEmpty {
                        empty
                    } else {
                        ForEach(thread.comments) { comment in
                            row(comment).id(comment.id)
                        }
                    }
                }
                .padding(.top, Metric.listTop)
                .padding(.bottom, 12)
                .animation(reduceMotion ? nil : Motion.smooth, value: thread.comments)
            }
            .scrollDismissesKeyboard(.interactively)
            .trackFrame(listFrame)
            .onChange(of: thread.comments.last?.id) { _, newest in
                guard let newest, thread.comments.last?.posting == true else { return }
                withAnimation(reduceMotion ? nil : Motion.smooth) { proxy.scrollTo(newest, anchor: .bottom) }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text(CommentCopy.empty)
                .font(.display(22))
                .foregroundStyle(Hue.ink)
            Text(CommentCopy.emptyLine)
                .font(.sans(14))
                .foregroundStyle(Hue.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .accessibilityElement(children: .combine)
    }

    private func row(_ comment: PostComment) -> some View {
        HStack(alignment: .top, spacing: Metric.photoGap) {
            Avatar(comment.authorPhoto, size: Metric.photo, blank: .initial(comment.author.name))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(comment.author.name).font(.sansSemibold(13)).foregroundStyle(Hue.ink)) \(Text(age(comment)).foregroundStyle(Hue.inkSecondary))")
                    .font(.sans(13))
                Text(PostWords.attributed(comment.body, names: comment.atNames))
                    .font(.sans(15))
                    .lineSpacing(2)
                    .foregroundStyle(Hue.ink)
                    .tint(Hue.link)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard case .name(let name)? = PostWords.target(url, names: comment.atNames) else { return .discarded }
                        open(name)
                        return .handled
                    })
                if !comment.posting && canComment {
                    Button { reply(comment) } label: {
                        Text(CommentCopy.reply)
                            .font(.sansSemibold(13))
                            .foregroundStyle(Hue.inkSecondary)
                            .padding(.vertical, 14)
                            .padding(.trailing, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, -10)
                    .padding(.bottom, -14)
                    .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Metric.rowLeading)
        .padding(.trailing, Metric.rowTrailing)
        .padding(.bottom, Metric.rowBottom)
        .opacity(comment.posting ? 0.5 : 1)
        .background(Hue.surface)
        .contentShape(.contextMenuPreview, Rectangle())
        .contextMenu { if !comment.posting { menu(comment) } }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if !comment.posting { menu(comment) }
        }
    }

    @ViewBuilder private func menu(_ comment: PostComment) -> some View {
        if canComment {
            Button(CommentCopy.reply, systemImage: "arrowshape.turn.up.left") { reply(comment) }
        }
        if canComment && !comment.mine {
            Button(CommentCopy.report, systemImage: "flag") { reporting = comment }
        }
        if comment.canDelete {
            Button(CommentCopy.delete, systemImage: "trash", role: .destructive) { delete(comment) }
        }
    }

    private func age(_ comment: PostComment) -> String {
        comment.posting ? CommentCopy.posting : PostingCard.relativeLabel(for: comment.createdAt)
    }

    // MARK: - Composer

    /// Anonymous accounts read but don't write (Jesse's decision 2).
    private var canComment: Bool { actions?.hasAccount == true && AuthStore.shared.userId != nil }

    @ViewBuilder private var composer: some View {
        if canComment {
            VStack(spacing: 0) {
                if let at, case let found = candidates(at.query), !found.isEmpty {
                    AtRow(candidates: found) { pick($0, replacing: at.range) }
                        .transition(.opacity)
                }
                Rectangle().fill(Hue.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    if let refusal {
                        Text(refusal.words)
                            .font(.sans(13))
                            .foregroundStyle(refusal.red ? Hue.declined : Hue.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, Metric.reasonLeading)
                            .transition(.opacity)
                    }
                    HStack(spacing: 8) {
                        Avatar(me?.avatarUrl.flatMap(URL.init(string:)), size: Metric.me)
                        field
                    }
                }
                .padding(.horizontal, Metric.side)
                .padding(.vertical, 10)
            }
            .background(Hue.surface)
            .animation(reduceMotion ? nil : Motion.snappy, value: refusal)
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField(CommentCopy.placeholder(poster: mine ? nil : thread.post.poster.name), text: $draft,
                      selection: $selection, axis: .vertical)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.vertical, 11)
                .accessibilityLabel("Add a comment")
                .onChange(of: draft) { was, now in
                    if now.count > Metric.limit { draft = String(now.prefix(Metric.limit)) }
                    if !was.isEmpty { refusal = nil }
                }
            if canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.sansSemibold(15))
                        .foregroundStyle(Hue.surface)
                        .frame(width: Metric.send.width, height: Metric.send.height)
                        .background(Hue.ink, in: Capsule())
                        .padding(.vertical, (Metric.field - Metric.send.height) / 2)
                        // 44 pt to the finger: a point past the field's edge above and below.
                        .contentShape(Rectangle().inset(by: -1))
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("Post")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .frame(minHeight: Metric.field)
        .overlay { RoundedRectangle(cornerRadius: Metric.field / 2, style: .continuous).strokeBorder(Hue.hairline) }
        .animation(reduceMotion ? nil : Motion.snappy, value: canSend)
    }

    private var mine: Bool { thread.post.poster.id == AuthStore.shared.userId }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - @ names

    /// The `@` typed before the cursor.
    private var at: (range: Range<String.Index>, query: String)? {
        guard typing, case .selection(let range)? = selection?.indices, range.isEmpty else { return nil }
        return AtTyping.typed(draft, cursor: range.upperBound, picked: names)
    }

    /// The thread's people first, then your friends, then the places with a page.
    private func candidates(_ query: String) -> [AtCandidate] {
        let people = thread.people(me: AuthStore.shared.userId)
        let ids = Set(people.map(\.name.id))
        let friends = AtCandidate.friends(book?.friends ?? []).filter { !ids.contains($0.name.id) }
        return AtTyping.matches(query, friends: people + friends,
                                places: AtCandidate.places(NewEventPlaces.ordered(search?.items ?? [])))
    }

    private func pick(_ candidate: AtCandidate, replacing range: Range<String.Index>) {
        Haptics.light()
        let typed = candidate.name.typed + " "
        draft.replaceSubrange(range, with: typed)
        if !names.contains(candidate.name) { names.append(candidate.name) }
        let end = draft.index(range.lowerBound, offsetBy: typed.count)
        selection = TextSelection(insertionPoint: end)
    }

    // MARK: - Acts

    /// "@Ana " at the start of the box, the cursor after it.
    private func reply(_ comment: PostComment) {
        let name = AtName(kind: .user, id: comment.author.id, name: comment.author.name)
        if !draft.contains(name.typed) { draft = name.typed + " " + draft }
        if !names.contains(name) { names.append(name) }
        selection = TextSelection(insertionPoint: draft.endIndex)
        typing = true
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let id = AuthStore.shared.userId else { return }
        let kept = names.filter { body.contains($0.typed) }
        draft = ""
        names = []
        refusal = nil
        Haptics.light()
        let person = TownPost.Person(id: id, name: me?.displayName.isEmpty == false ? me?.displayName ?? "" : "You")
        let photo = me?.avatarUrl.flatMap(URL.init(string:))
        Task {
            guard let said = await thread.send(body, names: kept, me: person, photo: photo) else { return }
            // Words typed since stay; the box was empty, so these go back.
            if draft.isEmpty {
                draft = body
                names = kept
            }
            refusal = said
            Haptics.error()
        }
    }

    private func delete(_ comment: PostComment) {
        Haptics.light()
        Task {
            if !(await thread.delete(comment)) {
                refusal = CommentRefusal(words: CommentCopy.deleteFailed)
                Haptics.error()
            }
        }
    }

    private var reportAsked: Binding<Bool> {
        Binding { reporting != nil } set: { if !$0 { reporting = nil } }
    }

    private func report(_ reason: ReportReason) {
        guard let comment = reporting else { return }
        reporting = nil
        Task {
            let sent = await thread.report(comment, reason)
            let said = CommentRefusal(words: sent ? CommentCopy.reported : CommentCopy.reportFailed)
            refusal = said
            guard sent else { return }
            // The thanks goes by itself, as the mock's toast did.
            try? await Task.sleep(for: .seconds(1.8))
            if refusal == said { refusal = nil }
        }
    }

    /// A name in a comment opens its page once the sheet is down.
    private func open(_ name: AtName) {
        guard let opener else { return }
        let row = FollowRow(targetType: name.kind == .place ? .place : .profile, targetId: name.id, name: name.name,
                            kind: nil, picture: nil, pictureKind: nil)
        guard opener.opens(row) else { return }
        dismiss()
        let box = listFrame.rect
        opener.open(row, CGRect(x: box.midX - 22, y: box.midY - 22, width: 44, height: 44))
    }
}

/// Three comment-shaped placeholders in the row's own layout: a 32 pt photo, the name line and two lines of words.
struct CommentListSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Hue.fill).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 5) {
                        SkeletonLine(widthFraction: 0.3, height: 12)
                        SkeletonLine(widthFraction: 0.9, height: 14)
                        SkeletonLine(widthFraction: 0.5, height: 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
        .shimmering()
        .accessibilityLabel("Loading comments")
    }
}
