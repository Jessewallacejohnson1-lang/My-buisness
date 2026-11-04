//
//  SearchAtRest.swift
//  Block Party — Search with nothing typed under All (BP app five-tabs 04): a row named for the part
//  of the day ("This morning", "Tonight") of today's Events and the places open now, New in
//  St. Joseph (the week's new Events, each with a New tag), then Around town, Instagram's Explore
//  grid of what's around town, dealt again each visit. Everything comes from real things: the Town
//  feed's Events and the places Search already reads.
//
//  Reference: the five-tabs mock's round 2, "Search, 9 AM" and "Search, 6 PM" (Jesse: "okay",
//  2026-11-01, https://claude.ai/artifact/29BVrCrrQ3WeWhS3egMozR), and Instagram's Explore
//  (BP app `references/five-tabs/refs/r2/Instagram-explore-search-grid-*`).
//

import SwiftUI

nonisolated extension SearchMetric {
    /// Between Around town's tiles, edge to edge as Instagram's Explore (the mock's 2).
    static let exploreGap: CGFloat = 2
    /// The New tag: the mock's 8 in from the photo's corner, 20 tall, 7 either side of the word.
    static let newTagInset: CGFloat = 8
    static let newTagHeight: CGFloat = 20
    static let newTagPad: CGFloat = 7
}

struct SearchAtRest: View {
    /// Around town's shuffle, kept by the page for the visit.
    let seed: UInt64
    @Environment(SearchModel.self) private var model

    var body: some View {
        // Each minute, so "This morning" turns into "This afternoon" and an Event that started says Now.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let loading = !(model.eventsLoaded && model.placesLoaded)
            VStack(alignment: .leading, spacing: 0) {
                let happening = model.happening(at: now)
                row(SearchModel.dayPart(now).title, happening, loading: loading)
                let fresh = model.fresh(at: now, without: happening)
                let allFresh = model.fresh(at: now, without: happening, all: true)
                // The › only when its page holds more than the row.
                row("New in \(Town.everyday)", fresh, loading: loading, new: true,
                    more: allFresh.count > fresh.count ? allFresh : nil)
                around(loading: loading)
            }
        }
    }

    /// A sideways row of photo cards; shimmering while it's read, gone when it has nothing.
    @ViewBuilder
    private func row(_ title: String, _ items: [SearchItem], loading: Bool, new: Bool = false,
                     more: [SearchItem]? = nil) -> some View {
        if loading {
            ShelfTitle(title: title, shelf: nil, chevron: false)
            ShelfSkeleton(kind: .event)
        } else if !items.isEmpty {
            ShelfTitle(title: title, shelf: more.map { SearchShelf(kind: .event, title: title, items: $0) },
                       chevron: more != nil)
            Shelf(kind: .event, items: items, new: new)
        }
    }

    @ViewBuilder
    private func around(loading: Bool) -> some View {
        let tiles = loading ? [] : model.aroundTown(seed: seed)
        if loading || !tiles.isEmpty {
            ShelfTitle(title: "Around town", shelf: nil, chevron: false)
            LazyVStack(spacing: SearchMetric.exploreGap) {
                if loading {
                    ExploreBlock(tallLeading: false) {
                        ForEach(0..<ExploreBlock.tiles, id: \.self) { _ in SkeletonBlock(cornerRadius: 0) }
                    }
                    .shimmering()
                    .accessibilityLabel("Loading")
                } else {
                    let blocks = stride(from: 0, to: tiles.count, by: ExploreBlock.tiles).map {
                        Array(tiles[$0 ..< $0 + ExploreBlock.tiles])
                    }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                        // The tall tile on the right first, then the left, as Instagram's.
                        ExploreBlock(tallLeading: i % 2 == 1) {
                            ForEach(block) { ExploreTile(item: $0) }
                        }
                    }
                }
            }
        }
    }
}

/// Instagram's Explore block: three columns of square tiles, one of them two squares tall beside
/// four squares, all `SearchMetric.exploreGap` apart. Its first subview is the tall one.
struct ExploreBlock: Layout {
    nonisolated static let tiles = 5
    let tallLeading: Bool

    private nonisolated func side(_ width: CGFloat) -> CGFloat { max(0, (width - 2 * SearchMetric.exploreGap) / 3) }

    nonisolated func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: 2 * side(width) + SearchMetric.exploreGap)
    }

    nonisolated func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let side = side(bounds.width), step = side + SearchMetric.exploreGap
        let tallX: CGFloat = tallLeading ? 0 : 2 * step
        let squares: [CGFloat] = tallLeading ? [step, 2 * step] : [0, step]
        var frames = [CGRect(x: tallX, y: 0, width: side, height: side + step)]
        for y in [0, step] { for x in squares { frames.append(CGRect(x: x, y: y, width: side, height: side)) } }
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }
}

/// One of Around town's photos: it opens what it shows, an Event's page or a business's, the logo
/// flying out of the photo's middle as from a food card.
private struct ExploreTile: View {
    let item: SearchItem
    @Environment(SearchModel.self) private var model
    @Environment(BusinessOpener.self) private var opener
    @State private var frame = FrameBox()

    var body: some View {
        OpenButton(item: item, press: .squish, tap: tap) {
            SearchPhoto(item: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .trackFrame(frame)
        }
        .accessibilityLabel([item.name, item.sub].compactMap { $0 }.joined(separator: ", "))
    }

    private func tap() {
        model.remember(item.id)
        guard item.opens, let logo = item.logo else { return }
        let box = frame.rect, size = SearchMetric.logoOnTile
        opener.open(item, from: .init(
            logo: CGRect(x: box.midX - size / 2, y: box.midY - size / 2, width: size, height: size),
            box: box, radius: 0, shadow: logo.shadow, fades: true))
    }
}

/// New in St. Joseph's tag: "New" in ink on the exact BP yellow, as the mock drew it.
struct NewTag: View {
    var body: some View {
        Text("New")
            .font(.sansBold(11))
            .foregroundStyle(Hue.ink)
            .padding(.horizontal, SearchMetric.newTagPad)
            .frame(height: SearchMetric.newTagHeight)
            .background(Hue.brandDisc, in: RoundedRectangle(cornerRadius: Radius.newTag, style: .continuous))
            .padding(SearchMetric.newTagInset)
            .accessibilityHidden(true)
    }
}
