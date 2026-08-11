//
//  DayScheduleSheet.swift
//  Block Party — the whole day, opened from one rail card.
//
//  The Today rail is deliberately terse: three cards, a title and a time each. This
//  is where that terseness is paid back — the same items on a clock, in order, with
//  the day's shape visible at a glance and one live orange line showing where it has
//  got to.
//
//  PRESENTATION. This is the day's CONTENT only. It carries no `.presentation*`
//  modifiers, because it is no longer a `.sheet`: `DayScheduleHost` presents it in
//  the app's own hierarchy and hand-builds the resting detent, the corner radius,
//  the backdrop, drag-to-dismiss and the modal accessibility container.
//
//  MATCHED GEOMETRY, AND WHY THE PRESENTATION CHANGED. The accent bar and title
//  carry the agreed ids (`dayitem-accent-<id>` / `dayitem-title-<id>`) in the rail's
//  namespace. SwiftUI does NOT run `matchedGeometryEffect` across a `.sheet`
//  boundary — a sheet is a separate presentation hierarchy and a namespace does not
//  reach into it — so the spec's two asks, a `.large` sheet AND the morph, could
//  not both be had. The owner chose the morph; hence the host.
//
//  THE CLOCK is `dates`, never `Date()` — including the now line, which re-reads the
//  injected provider on every minute boundary. A `FixedDateProvider` therefore pins
//  the whole screen, which is what makes the DEBUG fixtures deterministic.
//

import SwiftUI

struct DayScheduleSheet: View {
    let items: [DayItem]
    /// Where the day comes to rest on open: the tapped row, the bottom CTA (what
    /// the rail's add tile asks for), or the top.
    let anchor: DayScheduleAnchor
    let namespace: Namespace.ID
    let dates: any DateProviding
    let onDismiss: () -> Void

    /// The completion seam. Optional-defaulted rather than `= .shared`, because a
    /// default argument is evaluated in a nonisolated context and `.shared` is
    /// main-actor state — the CLAUDE.md default-argument gotcha. The published
    /// five-argument entry point is unchanged either way.
    @ObservedObject private var completion: DayCompletionStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now: Date
    @State private var isScrolled = false
    @State private var detailEvent: UpcomingEvent?
    @State private var isComposing = false

    init(
        items: [DayItem],
        anchor: DayScheduleAnchor,
        namespace: Namespace.ID,
        dates: any DateProviding,
        onDismiss: @escaping () -> Void,
        completion: DayCompletionStore? = nil
    ) {
        self.items = items
        self.anchor = anchor
        self.namespace = namespace
        self.dates = dates
        self.onDismiss = onDismiss
        _completion = ObservedObject(wrappedValue: completion ?? .shared)
        _now = State(initialValue: dates.now)
    }

    /// The matched-geometry contract, spelled once. The rail applies the same ids to
    /// its own accent bar and title; ids are unique per item, so every card pairs
    /// with its own row.
    nonisolated static func accentID(_ itemID: String) -> String { "dayitem-accent-\(itemID)" }
    nonisolated static func titleID(_ itemID: String) -> String { "dayitem-title-\(itemID)" }

    /// The scroll target for `.callToAction` — a hairline at the very end of the
    /// timeline, so "open on the add button" lands on the bottom of the real day
    /// rather than on whichever row happens to be last.
    private static let bottomAnchorID = "dayschedule-bottom"

    var body: some View {
        timeline
            // Opaque now. The frosted layer moved OUT to `DayScheduleHost`, where it
            // belongs: it is the scrim over the town, not the page under the day.
            .background(DaySchedulePalette.page)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { callToAction }
            .task { await followTheMinute() }
            .sheet(item: $detailEvent) { FeedEventDetailDestination(event: $0) }
            .sheet(isPresented: $isComposing) { AddView() }
    }

    // MARK: - The timeline

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    dateBlock
                    if items.isEmpty {
                        emptyDay
                    } else {
                        rows
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding(.horizontal, DayScheduleMetrics.pageMargin)
                .padding(.bottom, 24)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 24
            } action: { _, scrolled in
                guard isScrolled != scrolled else { return }
                withAnimation(DayScheduleMotion.reduced) { isScrolled = scrolled }
            }
            .task { restPosition(proxy) }
            .modifier(
                DayScheduleDemoDriver(
                    proxy: proxy,
                    items: items,
                    completion: completion,
                    onDismiss: onDismiss
                )
            )
        }
    }

    /// The big date scrolls away under the pinned bar, the way a large title does —
    /// so the header can collapse without the content jumping under it.
    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DayScheduleLogic.headerDate(now))
                .font(.dayDisplay(DayType.sectionHeader))
                .foregroundStyle(DaySchedulePalette.ink)

            Text(DayScheduleLogic.headerCount(items.count))
                .font(.sans(DayType.body))
                .foregroundStyle(DaySchedulePalette.muted)
        }
        .padding(.top, 4)
        .padding(.bottom, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// A day with nothing on it still has a page to fill. One line, pointing at the
    /// button already at the bottom of the screen — an empty screen is an
    /// invitation, not a void.
    private var emptyDay: some View {
        Text("Add the first thing and your neighbours will see it here.")
            .font(.sans(DayType.body))
            .foregroundStyle(DaySchedulePalette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: DayScheduleMetrics.rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index == nowLineIndex {
                    DayNowLine(now: now)
                }
                row(item)
            }

            if nowLineIndex == items.count {
                DayNowLine(now: now)
            }
        }
        // ONE unbroken hairline behind every row, so the gaps between cards do not
        // dash it. Sits 12pt right of the gutter, per the spec.
        .background(alignment: .leading) {
            Rectangle()
                .fill(DaySchedulePalette.rule)
                .frame(width: DayScheduleMetrics.spineWidth)
                .padding(.leading, DayScheduleMetrics.spineOffset)
        }
    }

    private func row(_ item: DayItem) -> some View {
        let isComplete = completion.isComplete(item)
        let state = DayScheduleLogic.state(for: item, now: now, isComplete: isComplete)

        return DayTimelineRow(
            item: item,
            state: state,
            isComplete: isComplete,
            stats: DayScheduleLogic.stats(for: item, state: state, now: now),
            namespace: namespace,
            morphs: !reduceMotion,
            onToggleComplete: { completion.setComplete(!isComplete, for: item.id) },
            onDetails: { detailEvent = item.event }
        )
        .id(item.id)
    }

    private var nowLineIndex: Int? {
        DayScheduleLogic.nowLineIndex(items: items, now: now)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DaySchedulePalette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Text(DayScheduleLogic.headerDate(now))
                .font(.sansSemibold(DayType.cardTitle))
                .foregroundStyle(DaySchedulePalette.ink)
                .lineLimit(1)
                .opacity(isScrolled ? 1 : 0)

            Spacer(minLength: 0)
        }
        // The glyph's own left edge lands on the page margin, not the 44pt target's.
        .padding(.leading, 4)
        .padding(.trailing, DayScheduleMetrics.pageMargin)
        // OPAQUE PAGE COLOUR, NOT `.ultraThinMaterial`. A material does not follow
        // the page — it follows the system blur recipe — so in dark mode the pinned
        // bar rendered as a mid-grey slab sitting on the day rather than as the top
        // of it. The bar's job is to be the page while the page scrolls under it,
        // and `DaySchedulePalette.page` is the page in both appearances.
        .background {
            Rectangle()
                .fill(DaySchedulePalette.page)
                .opacity(isScrolled ? 1 : 0)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DaySchedulePalette.rule)
                        .frame(height: 1)
                        .opacity(isScrolled ? 1 : 0)
                }
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Sticky CTA

    private var callToAction: some View {
        Button {
            Haptics.light()
            isComposing = true
        } label: {
            // A pill, deliberately — the one place in the app that gets one. It is
            // the single primary action on a full-height surface and reads as a
            // floating control rather than as part of the card stack.
            // U+FF0B FULLWIDTH PLUS, chosen for its optical weight next to 17pt
            // semibold. VoiceOver reads it aloud as a character, so the button
            // carries an explicit label below and this glyph is decoration only.
            Text("＋ Add to today")
                .font(.sansSemibold(DayType.cardTitle))
                .foregroundStyle(DaySchedulePalette.card)
                .frame(maxWidth: .infinity)
                .frame(height: DayScheduleMetrics.ctaHeight)
                .background(
                    DaySchedulePalette.ink,
                    in: RoundedRectangle(
                        cornerRadius: DayScheduleMetrics.ctaRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(FeedCardPressStyle())
        .accessibilityLabel("Add to today")
        .padding(.horizontal, DayScheduleMetrics.ctaMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        // THE SCRIM FINISHES ABOVE THE PILL, not behind it.
        //
        // It used to be a three-stop gradient across the CTA's own inset, which put
        // full page colour at the gradient's MIDPOINT — measured, about 43pt down
        // inside the pill. So a row scrolling under the CTA met a hard horizontal
        // edge level with the button's waist and was guillotined rather than faded.
        //
        // Now: solid page behind the whole inset, and the fade is a separate band
        // sitting directly above it. Stated in points rather than as a fraction
        // because the inset's height depends on the device's bottom safe area, and
        // a fraction of an unknown is how the first version went wrong.
        .background {
            DaySchedulePalette.page
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [
                            DaySchedulePalette.page.opacity(0),
                            DaySchedulePalette.page,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: DayScheduleMetrics.ctaScrimFade)
                    .offset(y: -DayScheduleMetrics.ctaScrimFade)
                }
        }
    }

    // MARK: - Behaviour

    /// The tapped item comes to rest a third of the way down, so the rows before it
    /// are visible as context rather than scrolled off. The add tile asks for the
    /// other end — the day's tail and the "Add to today" button under it.
    private func restPosition(_ proxy: ScrollViewProxy) {
        switch anchor {
        case .top:
            break
        case let .item(id):
            proxy.scrollTo(id, anchor: DayScheduleMetrics.openAnchor)
        case .callToAction:
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    /// Re-read the injected clock on every minute boundary. A fixed provider simply
    /// keeps returning the same instant, so previews stay still.
    private func followTheMinute() async {
        while !Task.isCancelled {
            let instant = dates.now
            if instant != now { now = instant }

            let secondsIntoMinute = instant.timeIntervalSince1970
                .truncatingRemainder(dividingBy: 60)
            do {
                try await Task.sleep(for: .seconds(60 - secondsIntoMinute))
            } catch {
                return
            }
        }
    }
}
