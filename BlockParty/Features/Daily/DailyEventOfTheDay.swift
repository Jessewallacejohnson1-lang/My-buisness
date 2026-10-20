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
    /// False when its start couldn't be read ("after dark") or it runs all day: it
    /// starts at midnight then, and its card shows the organizer's own words.
    var timed = true

    var id: String { item.id }

    var photo: URL? {
        if case .eventPhoto(let url) = item.image { return url }
        return nil
    }

    /// The card's time: "Now" while it's on, else when it starts ("9 AM", "7:30 PM"), in
    /// the Town's time. An untimed Event shows the organizer's own words, or "All day".
    /// Working words; Jesse writes the final ones.
    func startTime(now: Date) -> String {
        guard timed else { return item.startTime ?? "All day" }
        return isOn(now) ? "Now" : Self.clock(starts)
    }

    /// Started and not yet over.
    func isOn(_ now: Date) -> Bool {
        timed && starts <= now && now < ends
    }

    /// "9 AM" or "7:30 PM" in the Town's time: minutes only when there are some.
    static func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        return townTime(calendar.component(.minute, from: date) == 0 ? "h" : "hmm", date)
    }

    /// `date` written from a date template ("EEE", "d", "h"), in English, in the Town's time.
    static func townTime(_ template: String, _ date: Date) -> String {
        if let formatter = townFormatters[template] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        townFormatters[template] = formatter
        return formatter.string(from: date)
    }

    /// One formatter per template, kept: the You tab's Calendar writes 49 dates each time
    /// it draws, and building a formatter is the slow part.
    private static var townFormatters: [String: DateFormatter] = [:]

    /// What a section shows: the ones on now or still to come, soonest first, leaving out
    /// any a section above it already shows, `limit` at most. When one ends the next
    /// takes its spot; with none left the section goes.
    static func showing(_ events: [DailyEvent], now: Date, without shown: [DailyEvent] = [],
                        limit: Int) -> [DailyEvent] {
        let shownIDs = Set(shown.map(\.id))
        return Array(events.filter { $0.ends > now && !shownIDs.contains($0.id) }
            .sorted { $0.starts < $1.starts }.prefix(limit))
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

    /// The card's address: the place, then the town. A live Event has no town line.
    var address: String {
        [item.location, town].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
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
            hostName: host, goingCount: 0, goingAvatars: [],
            likeCount: 0, isLiked: false, isSaved: false, isJoined: false,
            eventDate: day.string(from: starts), startTime: time.string(from: starts),
            location: place, description: description, category: category
        )
        return DailyEvent(item: item, starts: starts, ends: ends, town: "St. Joseph, MN")
    }
    #endif
}

extension DailyEvent {
    /// A row of `get_event_of_the_day` (the Town feed's own row) as Daily's card: the Town
    /// card's item, from its start until it leaves the feed. Untimed or all day, it runs the
    /// whole day, as the You tab reads it.
    init?(row: TownFeedRow) {
        var item = TownFeed.entry(row).card
        if row.event.isAllDay { item.startTime = nil }
        guard var event = YouCalendar.event(from: item) else { return nil }
        event.ends = row.leavesAt
        self = event
    }
}

/// Daily's Event of the day: the read's picks, kept across tab switches and failed reads, as
/// the You tab keeps its Going. The database works them out (`get_event_of_the_day`, BP app
/// daily-tab 14) from the morning's standouts. Each read works out the whole Town feed on the
/// server, so Daily reads again only after `rereadAfter`, on a new Town day, or once a pick is
/// over, when the next one may take its spot.
@MainActor @Observable
final class EventOfTheDay {
    /// nil until the first read lands; Daily shows paper until then.
    private(set) var events: [DailyEvent]?
    @ObservationIgnored private var readAt: Date?
    @ObservationIgnored private let read: () async throws -> [DailyEvent]

    static let rereadAfter: TimeInterval = 10 * 60

    init(read: @escaping () async throws -> [DailyEvent]) {
        self.read = read
    }

    /// The live read, or under DEBUG `-daily-samples` the three samples.
    convenience init() {
        #if DEBUG
        if DailySamples.on {
            self.init(read: { DailyEvent.samples(on: DailyClock.now(Date())) })
            return
        }
        #endif
        self.init(read: {
            try await CommunityAPI(auth: AuthStore.shared).getEventOfTheDay().compactMap(DailyEvent.init(row:))
        })
    }

    func refresh(now: Date = Date()) async {
        guard needsRead(now: now) else { return }
        do {
            events = try await read()
            readAt = now
        } catch {
            // Kept: a failed read leaves the last picks on screen and tries again next time.
        }
    }

    func needsRead(now: Date) -> Bool {
        guard let readAt, let events else { return true }
        return now.timeIntervalSince(readAt) >= Self.rereadAfter || Town.day(readAt) != Town.day(now)
            || events.contains { $0.ends <= now }
    }

    /// A new account gets its own picks.
    func accountChanged() {
        events = nil
        readAt = nil
    }
}

/// The section: its label, then the card, or on a busy day the cards in a row that
/// the finger pages through, one card at a time, with the next one's edge showing. With no
/// Spotlight above it, its first card marks where the page's yellow fades out.
struct EventOfTheDaySection: View {
    let events: [DailyEvent]
    let now: Date
    var marksYellowEdge = false

    var body: some View {
        VStack(spacing: 0) {
            DailySectionLabel(title: "Event of the day", ink: Hue.ink)
            // Only with no Spotlight: any guide here, even one at its own top, would move the
            // yellow's edge off the Spotlight.
            if marksYellowEdge {
                row.alignmentGuide(.dailyYellowEdge) { $0[.top] + DailyMetric.eventLabelToCard + DailyMetric.yellowIntoCard }
            } else {
                row
            }
        }
    }

    private var row: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DailyMetric.eventGap) {
                ForEach(events) { event in
                    EventOfTheDayCard(event: event, now: now)
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

/// Airbnb's trip card: a rounded photo with a pill, a big title, a time line, a divider,
/// and the place with Attend where Airbnb's grey button sits (Jesse, 2026-10-20). The card
/// is one link to the Event page; Attend's row sits over it, outside the link, so the pill's
/// taps are its own and VoiceOver reads it after the card, while the link's press squishes
/// the whole card, Attend included, as the Town card does.
private struct EventOfTheDayCard: View {
    let event: DailyEvent
    let now: Date
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        let rsvp = actions.rsvp(event.item)
        let going = rsvp != nil && actions.going(event.item).isGoing
        NavigationLink(value: event.item) {
            EventOfTheDayFace(event: event, now: now)
        }
        .buttonStyle(PressReport(pressed: $pressed))
        // The title first; drawn, the pill comes before it.
        .accessibilityLabel([event.item.title, event.startsLabel(now: now),
                             event.timeLine, event.item.location]
            .compactMap { $0 }.joined(separator: ", "))
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                if !going {
                    // The place, as Airbnb's address sits by its button. A tap on it reaches the
                    // link under it, and the card has already read it.
                    Text(event.address)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                if let rsvp {
                    // Going: "You're going!" over "Can't go?" where the place was, and Invite.
                    RSVPArea(item: event.item,
                             words: going ? rsvp : RSVPWords(top: nil, second: nil, canLeave: false, pill: rsvp.pill),
                             onInvite: { ShareCenter.shared.present(.event(event.item)) })
                        .fixedSize(horizontal: !going, vertical: false)
                }
            }
            .frame(minHeight: RSVPArea.Size.card.pillHeight)
            .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: going)
            .padding(.horizontal, DailyMetric.eventTextInset)
            .padding(.bottom, DailyMetric.eventRowBottom)
        }
        .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: pressed)
    }
}

/// The link's press, handed up to the card (`PressableCardStyle`'s numbers on the whole card).
private struct PressReport: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in pressed = isPressed }
    }
}

private struct EventOfTheDayFace: View {
    let event: DailyEvent
    let now: Date
    /// The photo has decoded, so its credit may show.
    @State private var photoShown = false

    /// The event's own photo, else its place's, credited, else its place's logo (iOS
    /// MEMORY.md, 2026-10-16), as the Town card shows them.
    private var picture: FeedCardImageSource { event.item.image }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hue.fill
                .aspectRatio(DailyMetric.eventPhotoAspect, contentMode: .fit)
                .overlay {
                    if let url = picture.url {
                        FeedCardURLPhoto(url: url, onReady: { photoShown = true })
                    } else if let logo = picture.logo {
                        FeedCardPlaceLogo(logo: logo, topClear: PhotoChip.inset + PhotoChip.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.bento - DailyMetric.eventPhotoInset,
                                            style: .continuous))
                .overlay(alignment: .top) {
                    HStack(spacing: 8) {
                        PhotoChip(text: event.startsLabel(now: now))
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        PhotoCredit(names: photoShown ? [picture.attribution].compactMap { $0 } : [])
                            .padding(-PhotoCredit.edgeInset)
                    }
                    .frame(minHeight: PhotoChip.height)
                    .padding(PhotoChip.inset)
                }
                // Its full 3:2 whatever the row's height: a taller card in the row gives its
                // room to the gap above the divider, never takes it from the photo.
                .fixedSize(horizontal: false, vertical: true)
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
                // In a row of cards the tallest sets the height: the divider and Attend's row
                // keep to the bottom.
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Hue.hairline)
                    .frame(height: 1)
                    .padding(.top, DailyMetric.eventDividerTop)
                // Attend's row: the place and the pill sit over it (`EventOfTheDayCard`).
                Color.clear
                    .frame(height: RSVPArea.Size.card.pillHeight)
                    .padding(.top, DailyMetric.eventRowTop)
            }
            .padding(.horizontal, DailyMetric.eventTextInset)
            .padding(.top, DailyMetric.eventTitleTop - DailyMetric.eventPhotoInset)
            .padding(.bottom, DailyMetric.eventRowBottom)
            .frame(maxHeight: .infinity, alignment: .top)
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
}
