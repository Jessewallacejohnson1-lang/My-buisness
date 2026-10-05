//
//  DailyEventOfTheDay.swift
//  Block Party — Daily's second section: the event Daily puts forward for you today,
//  and on a busy day up to three, morning, afternoon and evening, side by side
//  (`docs/plans/daily-tab/SPEC.md` §2 in the BP app folder).
//

import SwiftUI

/// One event on the Daily page, with the times and the address its card shows. The
/// event page it opens is the Town feed's own (`FeedCardItem`).
struct DailyEvent: Identifiable {
    var item: FeedCardItem
    var starts: Date
    var ends: Date
    /// The address's second line, under the place (`item.location`).
    var town: String

    var id: String { item.id }

    var photo: URL? {
        if case .eventPhoto(let url) = item.image { return url }
        return nil
    }

    /// Today's picks for you. An agent will pick them from the Town's events and your
    /// interests; until that exists a release build gets none, which hides the section,
    /// and DEBUG gets the samples. When the read exists, this is the one function
    /// that changes.
    static func today(now: Date) -> [DailyEvent] {
        #if DEBUG
        return samples(on: now)
        #else
        return []
        #endif
    }

    /// What the section shows: the ones on now or still to come, soonest first, three
    /// at most. When one ends the next takes its spot; with none left the section goes.
    static func showing(_ events: [DailyEvent], now: Date) -> [DailyEvent] {
        Array(events.filter { $0.ends > now }.sorted { $0.starts < $1.starts }.prefix(3))
    }

    /// The pill on the photo: how soon it starts, as the Reference's "In 3 months" does.
    /// Working words; Jesse writes the final ones.
    func startsLabel(now: Date) -> String {
        guard starts > now else { return "Now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        let text = formatter.localizedString(for: starts, relativeTo: now)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The line under the title, the Reference's "Sep 5 – 6 · Hosted by Allison":
    /// "4 – 5 PM · Hosted by Saint John's Abbey", in the Town's time. Minutes show only
    /// when there are some, so the line fits on one row more often.
    var timeLine: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let onTheHour = [starts, ends].allSatisfy { calendar.component(.minute, from: $0) == 0 }
        let template = onTheHour ? "h" : "hmm"
        let times: String
        if calendar.isDate(starts, inSameDayAs: ends) {
            let formatter = DateIntervalFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.timeZone = Town.timeZone
            formatter.dateTemplate = template
            times = formatter.string(from: starts, to: ends)
        } else {
            // Past midnight the interval formatter writes both dates out in full.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.timeZone = Town.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            times = "\(formatter.string(from: starts)) – \(formatter.string(from: ends))"
        }
        return item.hostName.isEmpty ? times : "\(times) · Hosted by \(item.hostName)"
    }

    /// The card's address: the place, then the town.
    var address: String {
        [item.location, town].compactMap { $0 }.joined(separator: "\n")
    }

    #if DEBUG
    /// INVENTED: three events today, morning, afternoon and evening, at real St. Joseph
    /// places with the bundled town photos. The titles and hosts are the Town feed's
    /// fixtures (`DailyFixtures`); the times are made up.
    static func samples(on date: Date) -> [DailyEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let day = calendar.startOfDay(for: date)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        return [
            sample(id: "daily-e1", title: "Farmers Market", host: "Resurrection Lutheran",
                   photo: "farmers-market", place: "Resurrection Lutheran",
                   starts: at(8), ends: at(12), category: .food,
                   description: "Produce, eggs, honey and bread in the church parking lot."),
            sample(id: "daily-e2", title: "Abbey organ recital", host: "Saint John's Abbey",
                   photo: "saint-johns-abbey", place: "Saint John's Abbey",
                   starts: at(16), ends: at(17), category: .musicArts,
                   description: "An hour of Bach and a few newer pieces on the Abbey church organ. Open to everyone."),
            sample(id: "daily-e3", title: "Music in Millstream Park", host: "St. Joseph Parks & Rec",
                   photo: "memorial-park", place: "Millstream Park",
                   starts: at(19), ends: at(21), category: .musicArts,
                   description: "Bring a blanket or a lawn chair and find a spot on the grass by the river. A local bluegrass trio plays two sets."),
        ]
    }

    static func sample(id: String, title: String, host: String, photo: String,
                               place: String, starts: Date, ends: Date,
                               category: EventCategory, description: String) -> DailyEvent {
        let url = Bundle.main.url(forResource: photo, withExtension: "jpg")
        // The event page's when line reads these, so it shows the day and the time.
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = Town.timeZone
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US")
        time.timeZone = Town.timeZone
        time.dateFormat = "h:mm a"
        let item = FeedCardItem(
            id: id, title: title, dateChip: "TODAY", metaLine: place,
            image: url.map { .eventPhoto($0) } ?? .fallback, recurrence: nil,
            hostName: host, goingCount: 0, goingAvatars: [], goingSummary: "",
            likeCount: 0, isLiked: false, isSaved: false, isJoined: false,
            eventDate: day.string(from: starts), startTime: time.string(from: starts),
            location: place, description: description, category: category
        )
        return DailyEvent(item: item, starts: starts, ends: ends, town: "St. Joseph, MN")
    }
    #endif
}

/// The section: its label, then the card, or on a busy day the cards in a row that
/// the finger pages through, one card at a time, with the next one's edge showing.
struct EventOfTheDaySection: View {
    let events: [DailyEvent]
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            DailySectionLabel(title: "Event of the day", ink: Hue.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DailyMetric.eventGap) {
                    ForEach(events) { event in
                        NavigationLink(value: event.item) {
                            EventOfTheDayCard(event: event, now: now)
                        }
                        .buttonStyle(PressableCardStyle())
                        // The title first; drawn, the pill comes before it.
                        .accessibilityLabel([event.item.title, event.startsLabel(now: now),
                                             event.timeLine, event.item.location]
                            .compactMap { $0 }.joined(separator: ", "))
                        .containerRelativeFrame(.horizontal)
                    }
                }
                // Every card as tall as the tallest, so a long title doesn't leave the
                // others short in the row.
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DailyMetric.side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollDisabled(events.count < 2)
            // The cards' shadows reach past the row; don't cut them off.
            .scrollClipDisabled()
            .padding(.top, DailyMetric.eventLabelToCard)
        }
    }
}

/// Airbnb's trip card: a rounded photo with a pill, a big title, a time line, a
/// divider and the address. The Reference's grey button waits (Jesse, 2026-10-02).
private struct EventOfTheDayCard: View {
    let event: DailyEvent
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hue.fill
                .aspectRatio(DailyMetric.eventPhotoAspect, contentMode: .fit)
                .overlay { if let url = event.photo { FeedCardURLPhoto(url: url) } }
                .clipShape(RoundedRectangle(cornerRadius: Radius.bento - DailyMetric.eventPhotoInset,
                                            style: .continuous))
                .overlay(alignment: .topLeading) { pill.padding(DailyMetric.eventChipInset) }
                .padding(DailyMetric.eventPhotoInset)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.item.title)
                    .font(.display(26))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(2)
                Text(event.timeLine)
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, DailyMetric.eventTimeTop)
                Rectangle()
                    .fill(Hue.hairline)
                    .frame(height: 1)
                    .padding(.top, DailyMetric.eventDividerTop)
                Text(event.address)
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, DailyMetric.eventPlaceTop)
            }
            .padding(.horizontal, DailyMetric.eventTextInset)
            .padding(.top, DailyMetric.eventTitleTop - DailyMetric.eventPhotoInset)
            .padding(.bottom, DailyMetric.eventBottom)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                .fill(Hue.surface)
                .modifier(CardShadow())
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                        .strokeBorder(Hue.hairline, lineWidth: 0.5)
                }
        }
    }

    private var pill: some View {
        Text(event.startsLabel(now: now))
            .font(.sansMedium(14))
            .foregroundStyle(Hue.ink)
            .padding(.horizontal, DailyMetric.eventChipPadding)
            .frame(minHeight: DailyMetric.eventChipHeight)
            .background(Capsule().fill(Hue.surface))
    }
}
