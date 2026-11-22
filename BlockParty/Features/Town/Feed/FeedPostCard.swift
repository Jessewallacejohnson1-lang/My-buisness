//
//  FeedPostCard.swift
//  Block Party — a neighbour's post in the Town feed (BP app docs/plans/town-feed, ticket 29).
//
//  Facebook's post, picked at post-screen's Check-in 1 (Jesse: "A yes"; mock
//  https://claude.ai/artifact/9M6EyMvnwRZk8d1AGL8vjD, BP app references/post-screen/checkin1.py, card A):
//  their picture, the name line and when, then the words, then the photo edge to edge in its own shape
//  (several swipe sideways as Instagram's do, town-feed 46), then the heart and send, with a light grey band
//  before the next card. The ••• is Report for someone
//  else's post; on your own it is Apple's menu with Edit and Delete (town-feed 44).
//

import SwiftUI

struct FeedPostCard: View {
    /// The post as its list holds it; `post` lays this session's edit over it (town-feed 44).
    private let given: TownPost
    /// Off in the share sheet's picture, which draws the post without its controls.
    var sendable = true
    /// Its comments open as it lands: a comment row on the bell (backlog 38).
    var opensComments = false

    init(post: TownPost, sendable: Bool = true, opensComments: Bool = false) {
        given = post
        self.sendable = sendable
        self.opensComments = opensComments
    }

    @Environment(RealLifeActions.self) private var actions: RealLifeActions?
    @Environment(TownFeed.self) private var feed: TownFeed?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Where an `@` name or a `#` tag in the words goes (town-feed 60).
    @Environment(\.hostOpener) private var opener
    /// The words' frame, where a place's page flies out from.
    @State private var wordsFrame = FrameBox()
    /// A link just opened: the tap under it doesn't also fold or open See more.
    @State private var linkTappedAt = Date.distantPast
    @State private var menuPresented = false
    @State private var deleting = false
    @State private var expanded = false
    /// The words as shown and in full, for See more.
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    /// `heartFailureCount` at the last tap: a tap mid-shake stills it.
    @State private var heartTappedAt = 0
    /// The photo on show of several (town-feed 46).
    @State private var photoPage: Int?
    /// Its comments (backlog 38), read the first time the sheet opens and kept per post, so the pill follows the sheet.
    private var thread: CommentThread? { CommentThread.existing(post.id) }
    @State private var commentsOpen = false
    @State private var openedComments = false

    /// Card A's measurements (checkin1.py `.fb`): 16 pt sides, a 40 pt picture 10 pt from the name, words
    /// 16 on 22 with 10 above and 12 below, the row 14 pt in, an 8 pt band.
    private enum Metric {
        static let side: CGFloat = 16
        static let picture: CGFloat = 40
        static let pictureGap: CGFloat = 10
        static let wordsTop: CGFloat = 10
        static let wordsBottom: CGFloat = 12
        /// The pills line up with the words above, 16 from the edge (like-comment-share).
        static let rowSide: CGFloat = 16
        static let band: CGFloat = 8
        /// Facebook's See more: past six lines.
        static let lines = 6
    }

    private var post: TownPost { feed?.hides.edited(given) ?? given }
    private var mine: Bool { given.editable(by: AuthStore.shared.userId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Metric.side)
            if !post.words.isEmpty {
                words
                    .padding(.horizontal, Metric.side)
                    .padding(.top, Metric.wordsTop)
                    .padding(.bottom, post.photo == nil ? 0 : Metric.wordsBottom)
            }
            if post.photos.count > 1 && sendable {
                PostPhotos(urls: post.photos, aspect: post.photoAspect, page: $photoPage, zooms: true,
                           label: post.words.isEmpty ? "Photos from \(post.poster.name)" : "Photos")
                    .padding(.top, post.words.isEmpty ? Metric.wordsTop : 0)
                    // A photo swiped to (feed-learns 02); VoiceOver's pages too. The first is where it starts.
                    .onChange(of: photoPage) { _, page in if (page ?? 0) > 0 { feed?.views.tapped(post.id, .photo) } }
            } else if let url = post.photo {
                // One photo as it always was; the share's picture takes the first of several.
                photo(url)
                    .padding(.top, post.words.isEmpty ? Metric.wordsTop : 0)
            }
            if sendable, let actions {
                actionRow(actions)
                    .padding(.horizontal, Metric.rowSide)
            }
            Rectangle()
                .fill(Hue.fill)
                .frame(height: Metric.band)
                .padding(.top, sendable ? 0 : Metric.wordsBottom)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $commentsOpen) {
            if let thread { FeedCommentSheet(thread: thread) }
        }
        .task {
            guard opensComments, !openedComments else { return }
            openedComments = true
            openComments()
        }
    }

    private func openComments() {
        _ = CommentThread.of(post, api: CommunityAPI(auth: AuthStore.shared))
        commentsOpen = true
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Metric.pictureGap) {
            HStack(spacing: Metric.pictureGap) {
                Avatar(post.posterPhoto, size: Metric.picture)
                VStack(alignment: .leading, spacing: 0) {
                    Text(nameLine)
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subLine)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if sendable && mine {
                // Your own post (town-feed 44; Jesse at Check-in 1: "i agree"): Apple's menu from the •••, Edit and then
                // Delete in red, which asks first in Apple's dialog (the `isPresented` form 26.5 has).
                Menu {
                    if let feed {
                        Button(PostEditCopy.edit, systemImage: "pencil") { feed.hides.editing = post }
                    }
                    Button(PostEditCopy.delete, systemImage: "trash", role: .destructive) { deleting = true }
                } label: {
                    FeedCardMenuGlyph()
                }
                // The •••'s own press, as every other ••• has (taste.md, press): Apple's menu takes the button's style.
                .menuStyle(.button)
                .buttonStyle(MenuPressStyle())
                .accessibilityLabel("More options")
                .confirmationDialog("Delete post?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        Haptics.light()
                        Task { await feed?.hides.delete(post) }
                    }
                } message: {
                    Text("You can't undo this.")
                }
            } else if sendable {
                FeedCardMenuButton { menuPresented = true }
                    .modifier(FeedCardMenuSheet(isPresented: $menuPresented, post: post))
            }
        }
    }

    /// "**Jesse** is with **Sam Lee** at **Sal's**.": the names and the Place in semibold, as Facebook's.
    private var nameLine: AttributedString {
        var line = AttributedString(post.line)
        line.font = .sans(15)
        let tagged = post.tagged.count > 2 ? [post.tagged[0].name, "\(post.tagged.count - 1) others"] : post.tagged.map(\.name)
        for bold in [post.poster.name] + tagged + [post.place ?? ""] where !bold.isEmpty {
            if let range = line.range(of: bold) { line[range].font = .sansSemibold(15) }
        }
        return line
    }

    /// "2h · Public", or "· Friends" when only friends see it.
    private var subLine: String {
        PostingCard.relativeLabel(for: post.posted) + " · " + (post.friendsOnly ? NewPostCopy.friends : NewPostCopy.everyone)
    }

    // MARK: - Words and photo

    /// Facebook's words: past six lines they fold, with See more under them to open. An `@` name or a `#` tag in
    /// them is a link in Instagram's blue (town-feed 60).
    private var words: some View {
        let folds = !expanded && !dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 2) {
            wordsText
                .lineLimit(folds ? Metric.lines : nil)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                // The whole of it, measured unseen, says whether the fold hides any.
                .background(alignment: .top) {
                    wordsText.hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if folds && fullHeight > shownHeight + 1 {
                Text("See more")
                    .font(.sansSemibold(16))
                    .foregroundStyle(Hue.inkSecondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .trackFrame(wordsFrame)
        .onTapGesture {
            guard Date().timeIntervalSince(linkTappedAt) > 0.4 else { return }
            withAnimation(reduceMotion ? nil : Motion.snappy) { expanded.toggle() }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let target = PostWords.target(url, names: post.atNames) else { return .discarded }
            linkTappedAt = Date()
            open(target)
            return .handled
        })
        .accessibilityElement(children: .combine)
        // Each link, for VoiceOver: the words read as one, so a double tap can't reach them.
        .accessibilityActions {
            ForEach(links, id: \.self) { target in
                Button(PostWords.label(target)) { open(target) }
            }
        }
    }

    /// The words' links, each target once.
    private var links: [PostWords.Target] {
        var seen = Set<PostWords.Target>()
        return PostWords.links(post.words, names: post.atNames).map(\.target).filter { seen.insert($0).inserted }
    }

    private var wordsText: some View {
        Text(PostWords.attributed(post.words, names: post.atNames))
            .font(.sans(16))
            .lineSpacing(3)
            .foregroundStyle(Hue.ink)
            .tint(Hue.link)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A friend's page, a place's page flying out of the words as from a card's logo, or the tag's own page.
    /// No haptic: opening a page isn't a commit (taste.md, haptics).
    private func open(_ target: PostWords.Target) {
        guard let opener else { return }
        switch target {
        case .name(let name):
            let row = FollowRow(targetType: name.kind == .place ? .place : .profile, targetId: name.id, name: name.name,
                                kind: nil, picture: nil, pictureKind: nil)
            guard opener.opens(row) else { return }
            if name.kind == .place { feed?.views.tapped(post.id, .place) }
            // From the words' middle: a link's own spot isn't known to the tap.
            let box = wordsFrame.rect
            opener.open(row, CGRect(x: box.midX - 22, y: box.midY - 22, width: 44, height: 44))
        case .tag(let word):
            opener.push(TagRoute(tag: word))
        }
    }

    /// Edge to edge in its own shape (4:5 to 1.91:1), known before it loads.
    private func photo(_ url: URL) -> some View {
        FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
            .aspectRatio(CGFloat(post.photoAspect), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            // Two fingers lift it where it sits (BP app photo-zoom).
            .pinchToZoom(slot: Hue.paper)
            .accessibilityLabel(post.words.isEmpty ? "Photo from \(post.poster.name)" : "Photo")
    }

    // MARK: - Heart, comments and send

    private func actionRow(_ actions: RealLifeActions) -> some View {
        FeedEventCardActionRow(
            kind: .posting,
            commentCount: thread?.count ?? post.comments,
            showsHeart: actions.canAct,
            heartFailures: actions.heartFailureCount(post.id),
            state: Binding {
                let heart = actions.heart(post)
                return FeedCardActionState(likeCount: heart.count, isLiked: heart.isHearted)
            } set: { new in
                if new.isLiked != actions.heart(post).isHearted { actions.toggleHeart(post) }
            },
            reduceMotion: reduceMotion,
            autoplayStep: 0,
            onLike: nil,
            onComment: openComments,
            onShare: share
        )
    }

    private func share() {
        let name = post.poster.name
        ShareCenter.shared.present(
            SharePayload(story: ShareStory(title: post.words.isEmpty ? name : post.words, line: name, photo: post.photo),
                         shareText: post.words.isEmpty ? "\(name) posted on Block Party." : "\(name): \(post.words)")
        )
    }
}

/// A post's photos (BP app town-feed 46; Jesse at Check-in 1, 2026-11-14: "yes" to Instagram's several-photo post,
/// `references/several-photos/`): one alone fills the post's shape as a single photo always has; several swipe sideways
/// in the Event page's pager, each in the first one's shape and filled around where the eye goes, with the Event
/// page's counter in Instagram's spot, 14 pt in from the top right, and Instagram's dots under them, ink on paper,
/// centred 15 pt under the photo in a 20 pt row (SPEC.md). New post shows its picks through it too, from their files,
/// so what you pick is what neighbours see.
struct PostPhotos: View {
    let urls: [URL]
    /// The first photo's shape, width over height.
    let aspect: Double
    @Binding var page: Int?
    /// The "2/4" pill: Instagram's top right on a post; New post's at the bottom right, its trash in the top corner
    /// (Jesse at Check-in 2, 2026-11-14: "i agree").
    var counter = true
    var counterAt: Alignment = .topTrailing
    /// Two fingers lift it where it sits (BP app photo-zoom), as a post's one photo does.
    var zooms = false
    var label = "Photos"

    @State private var shown: Set<URL> = []
    /// Two fingers have lifted the photo: its counter steps aside till it lands.
    @State private var lifted = false
    /// A photo that can't load leaves the set rather than holding a grey page.
    @State private var failed: Set<URL> = []

    private enum Metric {
        static let counterInset: CGFloat = 14
        static let dotsCentre: CGFloat = 15
        static let dotsRow: CGFloat = 20
    }

    var body: some View {
        let urls = self.urls.filter { !failed.contains($0) }
        let on = min(page ?? 0, max(urls.count - 1, 0))
        VStack(spacing: 0) {
            pager(urls, on: on)
                .aspectRatio(CGFloat(aspect), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: counterAt) {
                    if counter && urls.count > 1 {
                        PhotoCounter(text: "\(on + 1)/\(urls.count)")
                            .padding(Metric.counterInset)
                            .stepsAside(lifted)
                    }
                }
                .modifier(Zooms(on: zooms, lifted: $lifted))
            if urls.count > 1 {
                EventPageDots(count: urls.count, page: CGFloat(on), onPaper: true)
                    .padding(.top, Metric.dotsCentre - EventPageDots.side / 2)
                    .frame(maxWidth: .infinity, minHeight: Metric.dotsRow, alignment: .top)
            }
        }
        .animation(Motion.smooth, value: urls)
    }

    @ViewBuilder private func pager(_ urls: [URL], on: Int) -> some View {
        if urls.count > 1 {
            PhotoPager(urls: urls, page: $page, shown: $shown, value: "\(on + 1) of \(urls.count)",
                       onFailure: { failed.insert($0) }, skeleton: false, loadingFill: Hue.fill)
                .accessibilityLabel(label)
        } else if let url = urls.first {
            FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
                .clipped()
                .accessibilityLabel(label == "Photos" ? "Photo" : label)
        } else {
            Hue.fill
        }
    }

    private struct Zooms: ViewModifier {
        let on: Bool
        let lifted: Binding<Bool>
        func body(content: Content) -> some View {
            if on { content.pinchToZoom(slot: Hue.paper, lifted: lifted) } else { content }
        }
    }
}
