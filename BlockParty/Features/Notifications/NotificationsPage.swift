//
//  NotificationsPage.swift
//  Block Party — what the Town bar's bell pushes (BP app docs/plans/school-activities, ticket 04):
//  the Events you follow or are Going to that were canceled or moved (`Notices`), in Instagram's
//  list: Today, Yesterday, Last 7 days, a round picture, the name in bold, the change and how long
//  ago. A row opens its Event. Under the Friends page's own large title and bar.
//
//  Reference: Instagram's Notifications (BP app references/moved-alert/mobbin/ig-4.jpg, 375pt at
//  1:1): 44pt pictures, 12pt gap, 16pt bold sections. Mock Jesse said yes to on 2026-10-26:
//  https://claude.ai/artifact/NYCPR86rDx4j7W8828TQMz
//

import SwiftUI

nonisolated enum NoticeMetric {
    static let face: CGFloat = 44
    static let gap: CGFloat = 12
    static let rowPad: CGFloat = 8
    static let sectionTop: CGFloat = 18
    static let sectionBottom: CGFloat = 8
}

/// The bell's page, as a route on the shell's stack.
struct NotificationsRoute: Hashable {}

struct NotificationsPage: View {
    @Environment(Notices.self) private var notices
    /// The large title has gone under the bar: the bar shows the small one.
    @State private var titleUnder = false

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Notifications")
                        .font(.sansBold(34))
                        .foregroundStyle(Hue.ink)
                        .frame(height: FriendsMetric.titleLine)
                        .padding(.horizontal, FriendsMetric.side)
                        .accessibilityAddTraits(.isHeader)
                    let now = Date()
                    ForEach(Notices.sections(notices.list ?? [], now: now), id: \.title) { section in
                        Text(section.title)
                            .font(.sansBold(16))
                            .foregroundStyle(Hue.ink)
                            .padding(.horizontal, FriendsMetric.side)
                            .padding(.top, NoticeMetric.sectionTop)
                            .padding(.bottom, NoticeMetric.sectionBottom)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.notices) { NoticeRow(notice: $0, now: now) }
                    }
                }
                .padding(.top, SearchMetric.pageBar)
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > FriendsMetric.titleLine
            } action: { _, under in
                titleUnder = under
            }
            // Drawn last so it sits over the rows, read first so Back comes first.
            FriendsTitleBar(title: "Notifications", titleUnder: titleUnder).accessibilitySortPriority(1)
        }
        // Nothing yet: Apple's empty page, in the middle of the screen, once the read has answered.
        .overlay {
            if notices.list?.isEmpty == true {
                ContentUnavailableView("No notifications yet", systemImage: "bell",
                                       description: Text("When something you follow or are going to changes, you'll see it here."))
                    .allowsHitTesting(false)
            } else if notices.failed {
                // The Town feed's words for a read that failed.
                ContentUnavailableView("Notifications", systemImage: "bell",
                                       description: Text("Check your connection and try again."))
                    .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Read on every visit; once drawn, the bell's dot goes.
        .task {
            await notices.refresh()
            notices.opened()
        }
    }
}

/// "**Kennedy Volleyball** Tonight's game vs Sartell moved to 7 PM. 2h", opening its Event.
private struct NoticeRow: View {
    let notice: Notice
    let now: Date

    var body: some View {
        NavigationLink(value: FeedCardItem(notice.event)) {
            HStack(spacing: NoticeMetric.gap) {
                NoticeFace(url: notice.picture)
                Text("\(Text(notice.name).font(.sansSemibold(15))) \(notice.words(now: now)) \(Text(PostingCard.relativeLabel(for: notice.changedAt, now: now)).foregroundStyle(Hue.inkSecondary))")
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, FriendsMetric.side)
            .padding(.vertical, NoticeMetric.rowPad)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

/// The round picture: a school's logo or the Event's photo, a calendar when it has neither.
private struct NoticeFace: View {
    let url: URL?

    var body: some View {
        Circle()
            .fill(Hue.surface)
            .overlay {
                if let url {
                    FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
                } else {
                    Image(systemName: "calendar")
                        .font(.glyph(NoticeMetric.face * 0.42))
                        .foregroundStyle(Hue.inkSecondary)
                }
            }
            .frame(width: NoticeMetric.face, height: NoticeMetric.face)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Hue.ink.opacity(0.16), lineWidth: FriendsMetric.ring))
            .accessibilityHidden(true)
    }
}
