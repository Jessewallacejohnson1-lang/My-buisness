//
//  NotificationsPage.swift
//  Block Party — what the Town bar's bell pushes (BP app docs/plans/school-activities, ticket 04):
//  the Events you follow or are Going to that were canceled or moved (`Notices`), and everything
//  the hello pill said this past week (`HelloInbox`, hello-drop 05), in Instagram's list: Today,
//  Yesterday, Last 7 days, a round picture, the name in bold, what happened and how long ago. A
//  change opens its Event, a contact who joined their page. Under the Friends page's own large
//  title and bar.
//
//  Reference: Instagram's Notifications (BP app references/moved-alert/mobbin/ig-4.jpg, 375pt at
//  1:1): 44pt pictures, 12pt gap, 16pt bold sections. Mock Jesse said yes to on 2026-10-26:
//  https://claude.ai/artifact/NYCPR86rDx4j7W8828TQMz
//

import SwiftUI

nonisolated enum NoticeMetric {
    static let face: CGFloat = 44
    /// A team's logo inside its 44 pt white disc, as the mock's 5 pt inset (hello-drop 05).
    static let logo: CGFloat = 34
    static let gap: CGFloat = 12
    static let rowPad: CGFloat = 8
    static let sectionTop: CGFloat = 18
    static let sectionBottom: CGFloat = 8
}

/// The bell's page, as a route on the shell's stack.
struct NotificationsRoute: Hashable {}

/// An Event opened from the bell's page: its Event page, not counted as a Town feed open.
struct NoticeEventRoute: Hashable {
    let item: FeedCardItem
}

struct NotificationsPage: View {
    @Environment(Notices.self) private var notices
    private let inbox = HelloInbox.shared
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
                    let items = inbox.recent(now: now)
                    // Nothing read yet and nothing kept on the phone: the rows' own shape, shimmering.
                    if notices.list == nil && !notices.failed && items.isEmpty { LoadingNotices() }
                    ForEach(Notices.sections(BellRow.merged(notices.list ?? [], items), now: now), id: \.title) { section in
                        Text(section.title)
                            .font(.sansBold(16))
                            .foregroundStyle(Hue.ink)
                            .padding(.horizontal, FriendsMetric.side)
                            .padding(.top, NoticeMetric.sectionTop)
                            .padding(.bottom, NoticeMetric.sectionBottom)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.rows) { row in
                            switch row {
                            case .change(let notice): NoticeRow(notice: notice, now: now)
                            case .item(let item): HelloItemRow(item: item, now: now)
                            }
                        }
                    }
                }
                .padding(.top, SearchMetric.pageBar)
            }
            // Pull to read again, as Instagram's list does; also the way to retry a failed read.
            .refreshable { await notices.refresh() }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > FriendsMetric.titleLine
            } action: { _, under in
                titleUnder = under
            }
            // Drawn last so it sits over the rows, read first so Back comes first.
            FriendsTitleBar(title: "Notifications", titleUnder: titleUnder).accessibilitySortPriority(1)
        }
        // Nothing yet: Apple's empty page, in the middle of the screen, once the read has answered;
        // never over what the phone kept.
        .overlay {
            if !inbox.recent(now: Date()).isEmpty {
                // The rows say it.
            } else if notices.list?.isEmpty == true {
                ContentUnavailableView("No notifications yet", systemImage: "bell",
                                       description: Text("When friends join, your teams play or your plans change, you'll see it here."))
                    .allowsHitTesting(false)
            } else if notices.failed {
                // The Town feed's words for a read that failed.
                ContentUnavailableView("Couldn't load", systemImage: "bell",
                                       description: Text("Check your connection and try again."))
                    .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Read on every visit; once drawn, the bell's dot goes. What the phone kept is drawn at
        // once, so the pill never says it after this, even offline.
        .task {
            inbox.toldAll()
            await notices.refresh()
            notices.opened()
        }
        // One found while the page was up was shown on it too.
        .onDisappear { inbox.toldAll() }
    }
}

/// "**Kennedy Volleyball** Tonight's game vs Sartell moved to 7 PM. 2h", opening its Event.
private struct NoticeRow: View {
    let notice: Notice
    let now: Date

    var body: some View {
        NavigationLink(value: NoticeEventRoute(item: FeedCardItem(notice.event))) {
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

/// "**Sam Rivera** joined Block Party. 2h" with Add friend beside it, as Instagram's Follow back;
/// "**Johnnies** beat Gusties 33–23. 5h"; "**You** attended your first event! 1d" by the green
/// tick (hello-drop 05). A contact who joined opens their page, a final its team's page; a first
/// opens nothing. Pressed, a row darkens as a change's does.
private struct HelloItemRow: View {
    let item: HelloItem
    let now: Date

    var body: some View {
        let row = item.row
        let words = HStack(spacing: NoticeMetric.gap) {
            HelloItemFace(picture: row.picture, name: row.name)
            Text("\(Text(row.name).font(.sansSemibold(15))) \(row.words) \(Text(PostingCard.relativeLabel(for: item.at, now: now)).foregroundStyle(Hue.inkSecondary))")
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        switch item.what {
        case .joined(let person):
            HStack(spacing: 0) {
                NavigationLink(value: person) {
                    words
                        .padding(.leading, FriendsMetric.side)
                        .padding(.trailing, NoticeMetric.gap)
                        .padding(.vertical, NoticeMetric.rowPad)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                // The Contacts page's button, at its own width beside the words.
                RelationButtons(person: person) {}
                    .fixedSize()
                    .padding(.trailing, FriendsMetric.side)
            }
        case .final(let final):
            if let team = final.teamPage {
                NavigationLink(value: team) { padded(words).contentShape(Rectangle()) }
                    .buttonStyle(RowPressStyle())
            } else {
                padded(words).accessibilityElement(children: .combine)
            }
        case .moment:
            padded(words).accessibilityElement(children: .combine)
        }
    }

    private func padded(_ words: some View) -> some View {
        words
            .padding(.horizontal, FriendsMetric.side)
            .padding(.vertical, NoticeMetric.rowPad)
    }
}

/// A person's photo (the blank face without one), a team's logo on white, or the green tick.
private struct HelloItemFace: View {
    let picture: HelloItem.Picture
    let name: String

    var body: some View {
        switch picture {
        case .photo(let url):
            NeighborFace(url: url, size: NoticeMetric.face)
        case .logo(let logo):
            LogoDisc(logo: logo, initial: String(name.prefix(1)), logoSide: NoticeMetric.logo,
                     letter: .sansSemibold(17))
                .frame(width: NoticeMetric.face, height: NoticeMetric.face)
                .overlay(Circle().strokeBorder(Hue.ink.opacity(0.16), lineWidth: FriendsMetric.ring))
                .accessibilityHidden(true)
        case .tick:
            // The pill's own tick, finished, at the row's 44 pt.
            HelloTick(stage: 3)
                .scaleEffect(NoticeMetric.face / HelloTick.size)
                .frame(width: NoticeMetric.face, height: NoticeMetric.face)
        }
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

/// Three rows' shape while the first read is out (the Friends page's).
private struct LoadingNotices: View {
    var body: some View {
        ForEach(0..<3, id: \.self) { _ in
            HStack(spacing: NoticeMetric.gap) {
                SkeletonBlock(cornerRadius: NoticeMetric.face / 2)
                    .frame(width: NoticeMetric.face, height: NoticeMetric.face)
                SkeletonBlock(cornerRadius: FriendsMetric.loadingLine / 2)
                    .frame(width: FriendsMetric.loadingName * 1.6, height: FriendsMetric.loadingLine)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, FriendsMetric.side)
            .padding(.vertical, NoticeMetric.rowPad)
            .shimmering()
            .accessibilityHidden(true)
        }
    }
}
