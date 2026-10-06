//
//  DailyFollowing.swift
//  Block Party — Daily's last section: today's events and updates from the people,
//  clubs and places you follow (`docs/plans/daily-tab/SPEC.md` §5 in the BP app folder).
//

import SwiftUI

/// One row: who it's from, what, when, and a small photo. An event opens the event
/// page; a place's update ("a new fall menu") opens the post on its own page.
struct DailyFollowing: Identifiable {
    enum Opens {
        case event(DailyEvent)
        case update(PostingItem)
    }

    var id: String
    /// The person, club or place you follow.
    var name: String
    /// Their round photo; a person without one shows their initial.
    var avatar: URL?
    /// What, after the name: "has live music." Working words; Jesse writes the final ones.
    var what: String
    var opens: Opens

    var event: DailyEvent? {
        if case .event(let event) = opens { return event }
        return nil
    }

    var post: PostingItem? {
        if case .update(let post) = opens { return post }
        return nil
    }

    /// The event's start, or when the update went up.
    var when: Date { event?.starts ?? post?.createdAt ?? .distantPast }

    var photo: URL? {
        if let event { return event.photo }
        if case .eventPhoto(let url) = post?.image { return url }
        return nil
    }

    /// In grey after the words: when the event starts ("7 PM", or "Now"), or how long
    /// ago the update went up ("2h"), as Instagram writes it.
    func time(now: Date) -> String {
        if let event { return event.startTime(now: now) }
        let minutes = max(1, Int(now.timeIntervalSince(when) / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    /// Today's from everyone you follow. There is no read for them yet, so a release
    /// build gets none, which hides the section, and DEBUG gets the samples. When the
    /// read exists, this is the one function that changes.
    static func today(now: Date) -> [DailyFollowing] {
        #if DEBUG
        return samples(on: now)
        #else
        return []
        #endif
    }

    /// What the section shows (Jesse, 2026-10-06): events still on or to come, soonest
    /// first, then today's updates so far, newest first.
    static func showing(_ items: [DailyFollowing], now: Date) -> [DailyFollowing] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let events = items.filter { ($0.event?.ends ?? .distantPast) > now }
            .sorted { $0.when < $1.when }
        let updates = items.filter { $0.post != nil && $0.when <= now && calendar.isDate($0.when, inSameDayAs: now) }
            .sorted { $0.when > $1.when }
        return events + updates
    }

    #if DEBUG
    /// INVENTED: a neighbour, a club and three places you might follow, with the bundled
    /// town photos. Every name but the real places', every time and every word is made up.
    static func samples(on date: Date) -> [DailyFollowing] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let day = calendar.startOfDay(for: date)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        func photo(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "jpg") }
        func update(_ id: String, _ author: String, _ name: String, at hour: Double, _ caption: String) -> PostingItem {
            PostingItem(id: id, authorName: author, authorAvatar: photo(name), createdAt: at(hour),
                        image: photo(name).map { .eventPhoto($0) } ?? .fallback, caption: caption,
                        likeCount: 0, commentCount: 0, isLiked: false, isSaved: false,
                        signals: FeedSignals(isFollowed: true))
        }
        return [
            DailyFollowing(
                id: "follow-1", name: "Kay Lindqvist", avatar: nil, what: "is hosting a porch sale.",
                opens: .event(DailyEvent.sample(
                    id: "daily-f1", title: "Porch sale", host: "Kay Lindqvist", photo: "downtown",
                    place: "College Avenue", starts: at(9), ends: at(13), category: .other,
                    description: "Kids' bikes, books and a lot of kitchen things. Everything goes."))),
            DailyFollowing(
                id: "follow-2", name: "College of Saint Benedict", avatar: photo("saint-bens"),
                what: "has an open choir rehearsal.",
                opens: .event(DailyEvent.sample(
                    id: "daily-f2", title: "Open choir rehearsal", host: "College of Saint Benedict",
                    photo: "saint-bens", place: "Saint Benedict's Monastery", starts: at(15), ends: at(16),
                    category: .musicArts, description: "Sit in on the choirs getting ready for Sunday."))),
            DailyFollowing(
                id: "follow-3", name: "St. Joseph Running Club", avatar: photo("klinefelter-park-trail"),
                what: "has a group run.",
                opens: .event(DailyEvent.sample(
                    id: "daily-f3", title: "Group run", host: "St. Joseph Running Club",
                    photo: "centennial-park", place: "Klinefelter Park", starts: at(17.5), ends: at(18.5),
                    category: .sports, description: "Three or five miles at an easy pace. Everyone welcome."))),
            DailyFollowing(
                id: "follow-4", name: "Bad Habit Brewing", avatar: photo("bad-habit-brewing"),
                what: "put a new beer on tap.",
                opens: .update(update("daily-p1", "Bad Habit Brewing", "bad-habit-brewing", at: 11,
                                      "New on tap today: an apple ale made with fruit from up the road."))),
            DailyFollowing(
                id: "follow-5", name: "The Local Blend", avatar: photo("the-local-blend"),
                what: "has a new fall menu.",
                opens: .update(update("daily-p2", "The Local Blend", "the-local-blend", at: 7.25,
                                      "Our fall menu starts today: maple lattes, apple cider and pumpkin bread."))),
        ]
    }
    #endif
}

/// The section: its label, then one row per thing, as Instagram's activity rows.
struct FollowingSection: View {
    let items: [DailyFollowing]
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            DailySectionLabel(title: "Following", ink: Hue.ink)
                .padding(.bottom, DailyMetric.followingLabelToRows)
            ForEach(items) { item in
                FollowingRow(item: item, now: now)
            }
        }
        // A finished event's row closes up instead of vanishing.
        .animation(reduceMotion ? nil : Motion.smooth, value: items.map(\.id))
    }
}

/// Instagram's activity row: the round photo, the name in bold and what in plain, the
/// time in grey, and a small photo on the right. The whole row is the tap.
private struct FollowingRow: View {
    let item: DailyFollowing
    let now: Date

    var body: some View {
        Group {
            switch item.opens {
            case .event(let event): NavigationLink(value: event.item) { face }
            case .update(let post): NavigationLink(value: post) { face }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("\(item.name) \(item.what) \(item.time(now: now))")
    }

    private var face: some View {
        HStack(spacing: DailyMetric.followingGap) {
            FeedAuthorAvatar(url: item.avatar, name: item.name, side: DailyMetric.followingPhoto)
            Text(words)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Hue.fill
                .frame(width: DailyMetric.followingPhoto, height: DailyMetric.followingPhoto)
                .overlay { if let url = item.photo { FeedCardURLPhoto(url: url) } }
                .clipShape(RoundedRectangle(cornerRadius: DailyMetric.followingPhotoRadius, style: .continuous))
        }
        .padding(.horizontal, DailyMetric.side)
        .padding(.vertical, DailyMetric.followingRowInset)
        .contentShape(Rectangle())
    }

    /// "**The Local Blend** has live music. 7 PM"
    private var words: AttributedString {
        var name = AttributedString(item.name)
        name.font = .sansSemibold(15)
        var time = AttributedString(item.time(now: now))
        time.foregroundColor = Hue.inkSecondary
        return name + AttributedString(" \(item.what) ") + time
    }
}

/// An update from someone you follow on its own page, as Instagram opens a post from its
/// activity rows: the Town feed's post card under a back button.
struct DailyPostPage: View {
    let posting: PostingItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            PostingCard(posting: posting)
        }
        .background(Hue.paper.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.sansSemibold(17))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DailyMetric.followingBackInset)
            .background(Hue.paper)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
