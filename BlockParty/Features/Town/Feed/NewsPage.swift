//
//  NewsPage.swift
//  Block Party — a News on its own page, with its post's own words (BP app docs/plans/town-feed, ticket 65).
//
//  Jesse, 2026-11-13: "copy their description and be able to click card and read more", then "i agree" to the mock
//  (https://claude.ai/artifact/V8D2dU5Pmqhx2XHzBmDUSs, BP app references/news-page/): a tap on a News card whose post
//  is the place's own opens this page, our post page's look (`PostPage`, Facebook's post): the place's logo and name,
//  "27m · Facebook", every word they posted, their photo edge to edge, the heart and send, then "View on Facebook". The
//  logo and name open the place's page. A News with no words of its own still opens its post (`TownNewsCard.open`).
//

import SwiftUI

/// A News's post's own words, as the place wrote them (`board_items.post_words`), and its place's `places.id`.
nonisolated struct NewsCaption: Hashable, Sendable {
    let text: String
    let placeID: String?
}

/// The News words the app has read (town-feed 65). A card asks as it comes on screen, and every card asking within
/// `gather` goes in one read, so a feed's News cost one request, not one each. Only an answer is kept: a read that fails
/// is asked again the next time a card asks.
@MainActor @Observable
final class NewsPostWords {
    static let shared = NewsPostWords { try await CommunityAPI(auth: AuthStore.shared).getNewsWords($0) }

    /// Each read News with words of its own, by id.
    private(set) var words: [String: NewsCaption] = [:]
    /// Each read News with none: its card opens its post.
    private(set) var none: Set<String> = []
    /// A read is on its way.
    private(set) var reading = false
    @ObservationIgnored private var waiting: Set<String> = []
    @ObservationIgnored private let load: ([String]) async throws -> [String: NewsCaption]
    /// How long a read waits for the other cards coming on screen with this one.
    @ObservationIgnored var gather: Duration = .milliseconds(80)

    init(load: @escaping ([String]) async throws -> [String: NewsCaption]) {
        self.load = load
    }

    /// Its words, asking for them now when they aren't read and waiting up to `wait` for the answer: a card tapped or
    /// a hello pill opened before its read landed, or after one failed, still finds its page.
    /// A second, as a card waits to hear who its host is (`HostOpener.readWait`).
    func caption(_ id: String, wait: Duration = .seconds(1)) async -> NewsCaption? {
        want(id)
        let end = ContinuousClock.now + wait
        // ponytail: looks every 30 ms; a continuation per id if a tap ever needs the answer sooner.
        while words[id] == nil, !none.contains(id), ContinuousClock.now < end {
            try? await Task.sleep(for: .milliseconds(30))
        }
        return words[id]
    }

    func want(_ id: String) {
        guard words[id] == nil, !none.contains(id), waiting.insert(id).inserted, !reading else { return }
        reading = true
        Task { await read() }
    }

    private func read() async {
        while !waiting.isEmpty {
            try? await Task.sleep(for: gather)
            let ids = waiting
            if let got = try? await load(ids.sorted()) {
                words.merge(got) { $1 }
                none.formUnion(ids.subtracting(got.keys))
            }
            waiting.subtract(ids)
        }
        reading = false
    }
}

/// A News pushed onto the shell's stack.
struct NewsRoute: Hashable {
    let news: TownNews
}

extension TownNews {
    /// Where its post was made, for the page's line and its last row; nil for a website story.
    var via: String? {
        let host = post.host()?.lowercased() ?? ""
        if host == "facebook.com" || host.hasSuffix(".facebook.com") { return "Facebook" }
        if host == "instagram.com" || host.hasSuffix(".instagram.com") { return "Instagram" }
        return nil
    }
}

struct NewsPage: View {
    let news: TownNews

    /// Our post page's measurements (`FeedPostCard`, card A): 16 pt sides, a 40 pt mark 10 pt from the name, words
    /// 16 on 22 with 10 above and 12 below, the row 14 pt in.
    private enum Metric {
        static let side: CGFloat = 16
        static let mark: CGFloat = 40
        static let markGap: CGFloat = 10
        static let wordsTop: CGFloat = 10
        static let wordsBottom: CGFloat = 12
        static let rowSide: CGFloat = 14
        static let row: CGFloat = 44
    }

    @Environment(RealLifeActions.self) private var actions: RealLifeActions?
    @Environment(\.hostOpener) private var opener
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markFrame = FrameBox()
    private var store: NewsPostWords { .shared }

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, Metric.side)
                    Text(words)
                        .font(.sans(16))
                        .lineSpacing(3)
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metric.side)
                        .padding(.top, Metric.wordsTop)
                        .padding(.bottom, Metric.wordsBottom)
                    if let photo = news.photoSource, let url = photo.url {
                        FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
                            .aspectRatio(CGFloat(photo.cardAspect), contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            // Two fingers lift it where it sits, as a post's photo (BP app photo-zoom).
                            .pinchToZoom(slot: Hue.paper)
                            .accessibilityLabel("Photo from \(news.place)")
                    }
                    if let actions {
                        actionRow(actions)
                            .padding(.horizontal, Metric.rowSide)
                    }
                    if let via = news.via {
                        Button(action: openPost) {
                            Text("View on \(via)")
                                .font(.sansSemibold(15))
                                .foregroundStyle(Hue.inkSecondary)
                                .frame(maxWidth: .infinity, minHeight: Metric.row, alignment: .leading)
                                .padding(.horizontal, Metric.side)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.press(.dim))
                    }
                }
                .padding(.top, PageMetric.bar + 8)
                .padding(.bottom, 24)
            }
            FriendsTitleBar(title: "News", titleUnder: true).accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
        // Only while it's open does a heart the server turns back shake here, as on its card.
        .onAppear { actions?.cardOpened(news.id) }
        .onDisappear { actions?.cardClosed(news.id) }
    }

    /// The post's own words; while they aren't read, the card's own, so the page is never empty.
    private var words: String {
        store.words[news.id]?.text ?? [news.headline, news.facts].compactMap { $0 }.joined(separator: "\n")
    }

    /// Its place's logo (else its first letter), its name, and when · where it was posted. Opens the place's page
    /// when Search can, as a card's mark does.
    private var header: some View {
        let mark = HStack(spacing: Metric.markGap) {
            HostMarkDisc(picture: news.picture, name: news.place, size: Metric.mark)
                .trackFrame(markFrame)
            VStack(alignment: .leading, spacing: 0) {
                Text(news.place)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subLine)
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metric.row)
        .accessibilityElement(children: .combine)
        return Group {
            if let row = placeRow, opener?.opens(row) == true {
                Button { opener?.open(row, markFrame.rect) } label: { mark.contentShape(Rectangle()) }
                    .buttonStyle(.press(.dim))
                    .accessibilityHint("Opens \(news.place)")
            } else {
                mark
            }
        }
    }

    /// "27m · Facebook": how long ago Block Party found it, and where it was posted.
    private var subLine: String {
        [news.published.map { PostingCard.relativeLabel(for: $0) }, news.via].compactMap { $0 }.joined(separator: " · ")
    }

    private var placeRow: FollowRow? {
        store.words[news.id]?.placeID.map {
            FollowRow(targetType: .place, targetId: $0, name: news.place, kind: nil, picture: news.picture?.url.absoluteString,
                      pictureKind: news.picture?.kind == .logo ? "logo" : nil)
        }
    }

    private func actionRow(_ actions: RealLifeActions) -> some View {
        FeedEventCardActionRow(
            kind: .event,
            showsHeart: actions.canAct,
            heartFailures: actions.newsHeartFailureCount(news.id),
            state: Binding {
                let heart = actions.heart(news)
                return FeedCardActionState(likeCount: heart.count, isLiked: heart.isHearted)
            } set: { new in
                if new.isLiked != actions.heart(news).isHearted { actions.toggleHeart(news) }
            },
            reduceMotion: reduceMotion,
            autoplayStep: 0,
            onLike: nil,
            onComment: {},
            onShare: { TownNewsCard.share(news) }
        )
    }

    /// The post in its own app when it's on the phone, else Apple's in-app browser, as the card opened it before.
    private func openPost() {
        let post = news.post
        Task {
            if await !UIApplication.shared.open(post, options: [.universalLinksOnly: true]) {
                InAppBrowser.open(post)
            }
        }
    }
}
