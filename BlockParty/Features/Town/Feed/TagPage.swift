//
//  TagPage.swift
//  Block Party — a #tag's own page (BP app docs/plans/town-feed, ticket 63).
//
//  Jesse, 2026-11-14: "yes, I agree to all" to the mock (https://claude.ai/artifact/MbsdhHE9YETGJhs9s2LhZ3, BP app
//  references/tag-page/): a tap on a #tag in a post pushes this page, the tag as its title over every post that carries
//  it, newest first, at any age, as the Town feed shows a post (A on the mock, over Instagram's grid: many posts are
//  words alone). No count. Back and the edge swipe return to the post. Who sees which post is the Town feed's rule
//  (`get_tag_posts`); what you hide, delete or edit here changes as it does in Town (`TownFeed.hides`).
//

import SwiftUI

/// The tag tapped, as it was written in the post ("JoeTownNights").
struct TagRoute: Hashable {
    let tag: String
}

struct TagPage: View {
    let tag: String
    @Environment(TownFeed.self) private var feed: TownFeed?
    /// nil until the first read answers.
    @State private var posts: [TownPost]?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown, id: \.id) { FeedPostCard(post: $0) }
                }
                .padding(.top, PageMetric.bar + 8)
            }
            // Pull to read again; also the way to retry a failed read.
            .refreshable { await read() }
            // Drawn last so it sits over the posts, read first so Back comes first.
            FriendsTitleBar(title: "#" + tag, titleUnder: true).accessibilitySortPriority(1)
        }
        // A read that failed with nothing to show: the Town feed's words for it. Nothing while it reads (no spinner on
        // content), and an empty answer stays blank under the title.
        .overlay {
            if failed && shown.isEmpty {
                ContentUnavailableView("Couldn't load", systemImage: "number",
                                       description: Text("Check your connection and try again."))
                    .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if posts == nil { await read() } }
    }

    /// The posts, less any you took out or deleted since the read.
    private var shown: [TownPost] {
        (posts ?? []).filter { !(feed?.hides.isHidden(id: $0.id, host: "") ?? false) }
    }

    private func read() async {
        do {
            posts = try await CommunityAPI(auth: AuthStore.shared).tagPosts(tag)
            failed = false
        } catch {
            failed = true
        }
    }
}
