//
//  DayScheduleSheet.swift
//  Block Party — the whole day, opened from one rail card.
//
//  The Today rail is deliberately terse: three cards, a title and a time each. This
//  is where that terseness is paid back — the same items on a clock, in order, with
//  the day's shape visible at a glance and one live orange line showing where it has
//  got to.
//
//  PRESENTATION. This view carries its own `.presentation*` modifiers, so wiring it
//  up is one line:
//
//      .sheet(isPresented: $showsDay) {
//          DayScheduleSheet(items: module.items, selectedID: tapped,
//                           namespace: railNS, dates: ctx.dates) { showsDay = false }
//      }
//
//  MATCHED GEOMETRY, HONESTLY. The accent bar and title carry the agreed ids
//  (`dayitem-accent-<id>` / `dayitem-title-<id>`) in the rail's namespace, so the
//  pairing is real code and merges cleanly. But SwiftUI does NOT run
//  `matchedGeometryEffect` across a `.sheet` boundary — a sheet is a separate
//  presentation hierarchy, and a namespace does not reach into it. The morph
//  therefore only animates if this view is presented in-hierarchy (a ZStack overlay)
//  instead of as a sheet. Everything else here is unaffected either way.
//
//  THE CLOCK is `dates`, never `Date()` — including the now line, which re-reads the
//  injected provider on every minute boundary. A `FixedDateProvider` therefore pins
//  the whole screen, which is what makes the DEBUG fixtures deterministic.
//

import SwiftUI

struct DayScheduleSheet: View {
    let items: [DayItem]
    let selectedID: String?
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
        selectedID: String?,
        namespace: Namespace.ID,
        dates: any DateProviding,
        onDismiss: @escaping () -> Void,
        completion: DayCompletionStore? = nil
    ) {
        self.items = items
        self.selectedID = selectedID
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

    var body: some View {
        timeline
            .background(DaySchedulePalette.page)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { callToAction }
            .presentationDetents([.large])
            .presentationCornerRadius(DayScheduleMetrics.sheetCornerRadius)
            .presentationDragIndicator(.hidden)
            .presentationBackground {
                // The frosted backdrop: the Today tab reads through the page at the
                // sheet's top edge instead of being replaced by a flat slab.
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    DaySchedulePalette.page.opacity(0.92)
                }
                .ignoresSafeArea()
            }
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
        }
    }

    /// The big date scrolls away under the pinned bar, the way a large title does —
    /// so the header can collapse without the content jumping under it.
    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DayScheduleLogic.headerDate(now))
                .font(.display(28))
                .foregroundStyle(DaySchedulePalette.ink)

            Text(DayScheduleLogic.headerCount(items.count))
                .font(.sans(15))
                .foregroundStyle(DaySchedulePalette.muted)
        }
        .padding(.top, 4)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// A day with nothing on it still has a page to fill. One line, pointing at the
    /// button already at the bottom of the screen — an empty screen is an
    /// invitation, not a void.
    private var emptyDay: some View {
        Text("Add the first thing and your neighbours will see it here.")
            .font(.sans(15))
            .foregroundStyle(DaySchedulePalette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
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
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DaySchedulePalette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Text(DayScheduleLogic.headerDate(now))
                .font(.sansSemibold(17))
                .foregroundStyle(DaySchedulePalette.ink)
                .lineLimit(1)
                .opacity(isScrolled ? 1 : 0)

            Spacer(minLength: 0)
        }
        // The glyph's own left edge lands on the page margin, not the 44pt target's.
        .padding(.leading, 4)
        .padding(.trailing, DayScheduleMetrics.pageMargin)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
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
            Text("＋ Add to today")
                .font(.sansSemibold(17))
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
        .padding(.horizontal, DayScheduleMetrics.ctaMargin)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            LinearGradient(
                colors: [
                    DaySchedulePalette.page.opacity(0),
                    DaySchedulePalette.page,
                    DaySchedulePalette.page,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Behaviour

    /// The tapped item comes to rest a third of the way down, so the rows before it
    /// are visible as context rather than scrolled off.
    private func restPosition(_ proxy: ScrollViewProxy) {
        guard let selectedID else { return }
        proxy.scrollTo(selectedID, anchor: DayScheduleMetrics.openAnchor)
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
