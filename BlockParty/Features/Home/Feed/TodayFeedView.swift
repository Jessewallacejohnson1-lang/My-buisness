import SwiftUI

struct TodayFeedView: View {
    let sections: [FeedCardSection]
    var isLoading = false
    var isRefreshing = false
    var onCompose: (() -> Void)?
    var onLike: ((String, Bool) -> Void)?
    var onLoadComments: ((String) async throws -> [EventComment])?
    var onComment: ((String, String) async throws -> EventComment)?
    var onShare: ((FeedCardItem) -> Void)?
    var onJoin: ((String, Bool) -> Void)?
    var onSave: ((String, Bool) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var initialEntranceCardIDs: [String]?
    @State private var revealedCardIDs: Set<String> = []

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if isLoading {
                TodayFeedSkeleton()
            } else {
                todayContent

                ForEach(sections.filter { $0.kind != .today }) { section in
                    sectionContent(section)
                }
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .top) {
            if isRefreshing {
                BlockMotifSpinner()
                    .padding(.top, 7)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isRefreshing)
    }

    @ViewBuilder
    private var todayContent: some View {
        sectionLabel(.today)
        if let today = sections.first(where: { $0.kind == .today }), !today.items.isEmpty {
            cardStack(today.items)
        } else {
            emptyToday
        }
    }

    private func sectionContent(_ section: FeedCardSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(section.kind)
            cardStack(section.items)
        }
    }

    private func sectionLabel(_ kind: FeedSectionKind) -> some View {
        Text(kind.title)
            .font(.sansSemibold(11))
            .tracking(1)
            .foregroundStyle(Hue.ink.opacity(0.35))
            .padding(.top, 32)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func cardStack(_ items: [FeedCardItem]) -> some View {
        LazyVStack(spacing: 28) {
            ForEach(items) { item in
                let entranceIndex = entranceIndex(for: item.id)
                FeedEventCard(
                    item: item,
                    onJoin: { joined in onJoin?(item.id, joined) },
                    onLike: { liked in onLike?(item.id, liked) },
                    onSave: { saved in onSave?(item.id, saved) },
                    onLoadComments: commentLoader(for: item.id),
                    onComment: commentSender(for: item.id),
                    onShare: { onShare?(item) }
                )
                .opacity(cardIsRevealed(item.id, at: entranceIndex) ? 1 : 0)
                .offset(
                    y: reduceMotion || cardIsRevealed(item.id, at: entranceIndex)
                        ? 0
                        : 12
                )
                .onAppear { revealCardIfNeeded(item.id) }
            }
        }
    }

    private var initialEntranceCandidates: [String] {
        let todayItems = sections
            .first(where: { $0.kind == .today })?
            .items ?? []
        let laterItems = sections
            .filter { $0.kind != .today }
            .flatMap(\.items)
        return Array((todayItems + laterItems).prefix(6).map(\.id))
    }

    private func entranceIndex(for id: String) -> Int? {
        (initialEntranceCardIDs ?? initialEntranceCandidates)
            .firstIndex(of: id)
    }

    private func cardIsRevealed(_ id: String, at index: Int?) -> Bool {
        reduceMotion || index == nil || revealedCardIDs.contains(id)
    }

    private func revealCardIfNeeded(_ id: String) {
        if initialEntranceCardIDs == nil {
            // Freeze the first loaded six. A later refresh can replace the feed,
            // but it must not create a second "first-load" entrance.
            initialEntranceCardIDs = initialEntranceCandidates
        }

        guard let index = initialEntranceCardIDs?.firstIndex(of: id),
              !revealedCardIDs.contains(id)
        else { return }

        if reduceMotion {
            revealedCardIDs.insert(id)
        } else {
            withAnimation(
                .spring(response: 0.4, dampingFraction: 0.8)
                    .delay(Double(index) * 0.05)
            ) {
                _ = revealedCardIDs.insert(id)
            }
        }
    }

    private var emptyToday: some View {
        HStack(spacing: 12) {
            Text("Nothing planned today")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)

            Spacer()

            Button { onCompose?() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Hue.ink.opacity(0.35))
                    .frame(width: 28, height: 28)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Hue.hairline, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an event")
        }
        .frame(minHeight: 44)
    }

    private func commentLoader(
        for eventID: String
    ) -> (() async throws -> [EventComment])? {
        guard let onLoadComments else { return nil }
        return { try await onLoadComments(eventID) }
    }

    private func commentSender(
        for eventID: String
    ) -> ((String) async throws -> EventComment)? {
        guard let onComment else { return nil }
        return { body in try await onComment(eventID, body) }
    }
}

private struct TodayFeedSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            VStack(spacing: 28) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: Radius.card)
                        .aspectRatio(5.0 / 4.0, contentMode: .fit)
                }
            }
            .opacity(reduceMotion ? 0.75 : shimmerOpacity(at: context.date))
        }
        .padding(.top, 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the social feed")
    }

    private func shimmerOpacity(at date: Date) -> Double {
        let period = 1.2
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        return 0.75 - 0.25 * cos(progress * 2 * .pi)
    }
}
