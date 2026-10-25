//
//  DetailPageParts.swift
//  Block Party — the pieces the Event page (`FeedEventDetailDestination`) and a business's page
//  in Search (`BusinessPage`) share: the photos that swipe at the top, their counter, the grey
//  rows that open something outside the app, and the About that clamps at four lines. Sizes are
//  the Event page's Reference's (Fresha's venue page, `FeedEventDetailDestination.Metric`).
//

import SwiftUI

/// Photos side by side, a page at a time. A photo shimmers until its bitmap is on screen
/// (`shown`), and one that can't load goes to `onFailure`, so the page can take it out. For
/// VoiceOver the pager is one adjustable element: swipe up or down for the next or previous
/// photo; the page says which it is (`value`), since it knows whose photo it is.
struct PhotoPager: View {
    let urls: [URL]
    @Binding var page: Int?
    @Binding var shown: Set<URL>
    let value: String
    let onFailure: (URL) -> Void
    /// A shimmer until each photo lands. Off on a Town card, which waits on ink so its white
    /// title stays readable (`FeedCardURLPhoto`).
    var skeleton = true
    /// One photo still rubber-bands sideways, so a sideways swipe moves it instead of reaching
    /// what's under it: on a Town card, the link that opens the Event page (event-card 02).
    var bounces = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    photo(url)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollDisabled(urls.count < 2 && !bounces)
        .scrollBounceBehavior(bounces ? .always : .basedOnSize, axes: .horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photos")
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            let next = (page ?? 0) + (direction == .increment ? 1 : -1)
            guard urls.indices.contains(next) else { return }
            withAnimation(Motion.smooth) { page = next }
        }
        // One photo has nothing to adjust.
        .accessibilityHidden(urls.count < 2)
    }

    private func photo(_ url: URL) -> some View {
        let isShown = Self.isShown(url, in: shown)
        return FeedCardURLPhoto(url: url, onReady: { shown.insert(url) }, onFailure: { onFailure(url) })
            .frame(maxHeight: .infinity)
            .clipped()
            .overlay {
                if skeleton && !isShown {
                    SkeletonBlock(cornerRadius: 0)
                        .shimmering()
                        .transition(.opacity)
                }
            }
            .animation(Motion.smooth, value: isShown)
            .accessibilityHidden(true)
    }

    /// Drawn already (by its card, at another size) counts as shown: no skeleton.
    static func isShown(_ url: URL, in shown: Set<URL>) -> Bool {
        shown.contains(url) || FeedCardImageLoader.shared.largest(for: url) != nil
    }
}

/// "2/3" in the photo's bottom right corner. The pager says it to VoiceOver, with the credit.
struct PhotoCounter: View {
    let text: String

    var body: some View {
        // 13: the Reference's digits stand 9 pt tall.
        Text(text)
            .font(.sansSemibold(13))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: FeedEventDetailDestination.Metric.counterSize.width,
                   minHeight: FeedEventDetailDestination.Metric.counterSize.height)
            // The Reference's chip is ink at about 55% over a light photo. Black rather than
            // `Hue.ink` so it stays dark in the dark ramp, like `PhotoCredit`.
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityHidden(true)
    }
}

/// The Maps search for a named place in this town, or nil when there is none. There is no
/// coordinate on an Event, so this is a text search against the town — good enough to open
/// the right pin, and honest about being a search. An Event's place pill and a business's
/// address pill open it. (Was `DayScheduleLogic.directionsURL(forPlace:)` until 2026-10-25.)
nonisolated enum Directions {
    static func url(forPlace place: String?) -> URL? {
        guard let location = place?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty
        else { return nil }

        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(location), \(Town.display)")]
        return components?.url
    }
}

/// A grey row that opens something outside the app: an Event's place, a business's address
/// (Maps) and its website and social pages. The Reference's location pill: 44 pt tall, its
/// glyph 15 pt in and its words after it.
struct InfoPill: View {
    let glyph: String
    let text: String
    let url: URL?
    let hint: String
    /// The glyph's box. The pin's is the Reference's 10.7 pt, putting the words 35 pt in; a page
    /// with wider glyphs widens every row's, so their words line up.
    var glyphBox = FeedEventDetailDestination.Metric.pinBox
    /// Marks a row that leaves the app with an arrow at its end.
    var leaves = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        let m = FeedEventDetailDestination.Metric.self
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: m.pinGap) {
                // SF Symbols has no filled teardrop like the Reference's; this is its pin.
                Image(systemName: glyph)
                    .frame(width: glyphBox)
                Text(text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if leaves {
                    Image(systemName: "arrow.up.right")
                        .font(.sans(12))
                        .foregroundStyle(Hue.inkSecondary)
                }
            }
            .font(.sans(15))
            .foregroundStyle(Hue.ink)
            .padding(.horizontal, m.pillInset)
            .frame(height: m.pillHeight)
            .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(FeedCardPressStyle())
        .accessibilityLabel(text)
        .accessibilityHint(hint)
    }
}

/// "About" over words that clamp at four lines, with "Read more" only when the clamp cuts them.
struct AboutSection: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    /// The words' height in full and at four lines, so "Read more" shows only when the clamp
    /// actually cuts something.
    @State private var fullHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0

    private static let lines = 4
    /// About → its first line, tuned with the page's rhythm (`FeedEventDetailDestination.Metric`).
    private static let bodyTop: CGFloat = 12.7

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About")
                .font(.sansBold(20))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)

            // The text itself switches at once; only the box around it moves. Letting the
            // text animate cross-faded the two layouts, and a "lem" fragment floated at the
            // old place while it collapsed (independent review). Opening, the box uncovers
            // the lines; closing, it shuts over the space they leave.
            Text(text)
                .font(.sans(17))
                .foregroundStyle(Hue.ink)
                .lineLimit(expanded ? nil : Self.lines)
                .animation(nil, value: expanded)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { probe }
                .frame(height: boxHeight, alignment: .top)
                .clipped()
                .padding(.top, Self.bodyTop)

            // Its own line, in ink, and only when four lines really cut the text.
            if fullHeight > clampedHeight + 1 {
                Button {
                    withAnimation(Motion.smooth) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Read more")
                        .font(.sansSemibold(17))
                        .foregroundStyle(Hue.ink)
                        .animation(nil, value: expanded)
                        // 12 pt round the 20.3 pt line: a 44.3 pt target (measured with
                        // AXe; 11 gave 42.3).
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(FeedCardJoinPressStyle(reduceMotion: reduceMotion))
            }
        }
    }

    /// The box: the full text's height open, four lines' shut. nil until the probe has
    /// measured, so the first frame lays out naturally.
    private var boxHeight: CGFloat? {
        guard fullHeight > 0 else { return nil }
        return expanded ? fullHeight : clampedHeight
    }

    /// The text set twice out of sight, in full and at four lines, to learn whether the clamp
    /// cuts it. Text measuring text: nothing here reads the scroll.
    private var probe: some View {
        ZStack(alignment: .top) {
            Text(text)
                .font(.sans(17))
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            Text(text)
                .font(.sans(17))
                .lineLimit(Self.lines)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { clampedHeight = $0 }
        }
        .hidden()
        .accessibilityHidden(true)
    }
}
