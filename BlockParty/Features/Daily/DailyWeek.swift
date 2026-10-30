//
//  DailyWeek.swift
//  Block Party — the week at the top of Daily: today and the six days after it as the Town
//  tab's bubbles, with the friends going each day under them. Tap a day and the page turns to
//  it (BP app docs/plans/daily-tab, ticket 16; the drafts on Figma "BP · Daily tab inspo").
//

import SwiftUI

/// One day of Daily's week, in the Town's time.
nonisolated struct DailyWeekDay: Identifiable, Equatable {
    /// "2026-10-21", the Town day as `club_events.event_date` stores it.
    let id: String
    /// "Wed".
    let weekday: String
    /// "Wednesday", for VoiceOver.
    let spokenWeekday: String
    /// "21".
    let number: String
    /// Midnight that day in the Town: a read for the day asks from there.
    let start: Date
}

enum DailyWeek {
    nonisolated static let length = 7

    /// Today and the six days after it, in the Town's time, whatever the phone's time zone.
    nonisolated static func days(from now: Date) -> [DailyWeekDay] {
        var calendar = Town.gregorian
        calendar.locale = Locale(identifier: "en_US")
        let today = calendar.startOfDay(for: now)
        return (0..<length).compactMap { offset in
            // By calendar day, not 24 hours, so the days stay midnights across a clock change.
            guard let start = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let weekday = calendar.component(.weekday, from: start) - 1
            return DailyWeekDay(id: Town.day(start), weekday: calendar.shortWeekdaySymbols[weekday],
                                spokenWeekday: calendar.weekdaySymbols[weekday],
                                number: String(calendar.component(.day, from: start)), start: start)
        }
    }

    /// The day the page shows: the one picked, else today; a picked day that has gone by (the
    /// week moves on at midnight) gives today too.
    nonisolated static func shown(picked: String?, today: String) -> String {
        guard let picked, picked > today else { return today }
        return picked
    }

    /// The friends going each day, from the Town feed's cards: each face once a day, in the
    /// feed's order, so the first faces belong to the cards the feed puts first.
    static func friendsGoing(in cards: [FeedCardItem]) -> [String: [FeedFriend]] {
        var days: [String: [FeedFriend]] = [:]
        for card in cards {
            guard let day = card.eventDate else { continue }
            for friend in card.friendsGoing where days[day]?.contains(friend) != true {
                days[day, default: []].append(friend)
            }
        }
        return days
    }

    #if DEBUG
    /// INVENTED: friends going on four of the days, faces with no photos, for `-daily-samples`.
    static func sampleFriends(from now: Date) -> [String: [FeedFriend]] {
        let days = days(from: now)
        func friends(_ names: [String]) -> [FeedFriend] { names.map { FeedFriend(name: $0, photo: nil) } }
        return [days[1].id: friends(["Sam"]),
                days[2].id: friends(["Marlene", "Dale"]),
                days[3].id: friends(["Sam", "Ana", "Kim", "Tom"]),
                days[6].id: friends(["Joe"])]
    }
    #endif
}

/// Event of the day for the week's other days (daily-tab 16). No morning picks are written
/// ahead, so `get_event_of_the_day` asked for a day's midnight gives the Town's top pick there.
/// Kept across tab switches, and read again at most every `EventOfTheDay.rereadAfter`.
@MainActor @Observable
final class DailyDayPicks {
    /// Each day's picks once read; a day not read yet is missing, and shows nothing below the week.
    private(set) var picks: [String: [DailyEvent]] = [:]
    @ObservationIgnored private var readAt: [String: Date] = [:]
    @ObservationIgnored private let read: (DailyWeekDay) async throws -> [DailyEvent]

    init(read: @escaping (DailyWeekDay) async throws -> [DailyEvent]) {
        self.read = read
    }

    /// The live read, or under DEBUG `-daily-samples` that day's three samples.
    convenience init() {
        #if DEBUG
        if DailySamples.on {
            self.init(read: { DailyEvent.samples(on: $0.start) })
            return
        }
        #endif
        self.init(read: {
            try await CommunityAPI(auth: AuthStore.shared).getEventOfTheDay(at: $0.start).compactMap(DailyEvent.init(row:))
        })
    }

    func refresh(_ day: DailyWeekDay, now: Date = Date()) async {
        if let at = readAt[day.id], now.timeIntervalSince(at) < EventOfTheDay.rereadAfter { return }
        // Marked first, so a second tap on the day while this read is out doesn't send another.
        readAt[day.id] = now
        do {
            picks[day.id] = try await read(day)
        } catch {
            readAt[day.id] = nil
            // Called off (Daily left mid-read): no answer, so the day still reads as loading.
            guard !Task.isCancelled else { return }
            // A failed read keeps what the day had, or shows nothing for it, and tries again next time.
            if picks[day.id] == nil { picks[day.id] = [] }
        }
    }

    /// A new account gets its own picks: each day reads again when it's next shown.
    func accountChanged() {
        readAt = [:]
    }
}

/// The week's sizes, from the draft Jesse picked on the Figma board (2026-10-21), drawn at his
/// iPhone 16 Pro's 402pt: 48 x 64 bubbles 6pt apart inside the page's margin, and the Town card's
/// one soft lift. Picked there, not measured from another app: the References (Structured, Joi)
/// gave the idea, the Town tab the look (taste.md, 2026-10-21).
private nonisolated enum DailyWeekMetric {
    static let side: CGFloat = 15
    static let gap: CGFloat = 6
    static let bubbleHeight: CGFloat = 64
    static let radius: CGFloat = 24
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    /// Between the weekday and the number inside a bubble, and from the bubble to its faces.
    static let lineGap: CGFloat = 3
    static let facesTop: CGFloat = 6
    /// The faces under a day: 18pt circles overlapping by 5, at most two and a count.
    static let face: CGFloat = 18
    static let faceOverlap: CGFloat = 5
    static let faceRing: CGFloat = 1.5
    static let faces = 2
    /// Today's ring while another day is picked.
    static let todayRing: CGFloat = 1.5
    /// The picked bubble lifts a little more than the rest.
    static let pickedShadowRadius: CGFloat = 7
    static let pickedShadowY: CGFloat = 6
    static let pickedShadowOpacity: Double = 0.22
}

/// The row of day bubbles. The picked day is the black bubble, which slides to the day you tap;
/// today keeps a thin ring while another day is picked. The bubbles draw under the row's words in
/// two layers, the white ones and then the one black one over them, each following its day's place
/// (`matchedGeometryEffect`), so the black one moves as one solid shape over the days between:
/// drawn inside each day, it was two that cross-faded grey, or one that jumped.
struct DailyWeekRow: View {
    let days: [DailyWeekDay]
    /// The day the page shows.
    let shown: String
    let friends: [String: [FeedFriend]]
    let pick: (DailyWeekDay) -> Void
    @Namespace private var bubble
    /// The day under the finger, so its bubble squishes with its words.
    @State private var pressed: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: DailyWeekMetric.gap) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                DailyWeekBubble(day: day, isToday: index == 0, isShown: day.id == shown,
                                friends: friends[day.id] ?? [], bubble: bubble, pressed: $pressed) { pick(day) }
            }
        }
        .background {
            ZStack {
                ForEach(days) { day in
                    if day.id != shown {
                        DailyWeekMetric.shape.fill(Hue.surface)
                            .overlay { DailyWeekMetric.shape.strokeBorder(Hue.hairline, lineWidth: 0.5) }
                            .modifier(CardShadow())
                            .matchedGeometryEffect(id: day.id, in: bubble, isSource: false)
                            .scaleEffect(squish(day.id))
                    }
                }
                DailyWeekMetric.shape.fill(Hue.ink)
                    .shadow(color: .black.opacity(DailyWeekMetric.pickedShadowOpacity),
                            radius: DailyWeekMetric.pickedShadowRadius, y: DailyWeekMetric.pickedShadowY)
                    .matchedGeometryEffect(id: shown, in: bubble, isSource: false)
                    .scaleEffect(squish(shown))
            }
            .animation(PressableCardStyle.press, value: pressed)
        }
        .padding(.horizontal, DailyWeekMetric.side)
    }

    private func squish(_ day: String) -> CGFloat {
        pressed == day && !reduceMotion ? PressableCardStyle.pressedScale : 1
    }
}

/// One day: its words in the bubble's place, today's ring, and the faces under it. Its bubble
/// draws in the row's layers under it (`DailyWeekRow`), placed by this day's frame.
private struct DailyWeekBubble: View {
    let day: DailyWeekDay
    let isToday: Bool
    let isShown: Bool
    let friends: [FeedFriend]
    let bubble: Namespace.ID
    @Binding var pressed: String?
    let tap: () -> Void

    var body: some View {
        VStack(spacing: DailyWeekMetric.facesTop) {
            Button(action: tap) { face }
                .buttonStyle(DailyWeekPressStyle(day: day.id, pressed: $pressed))
            DailyWeekFaces(friends: friends)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
    }

    private var face: some View {
        VStack(spacing: DailyWeekMetric.lineGap) {
            Text(day.weekday)
                .font(.sansMedium(12))
                .foregroundStyle(isShown ? Hue.surface.opacity(0.72) : Hue.inkSecondary)
            Text(day.number)
                .font(.sansSemibold(20))
                .monospacedDigit()
                .foregroundStyle(isShown ? Hue.surface : Hue.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: DailyWeekMetric.bubbleHeight)
        // Where this day's bubble goes, for the row's layers.
        .background { Color.clear.matchedGeometryEffect(id: day.id, in: bubble) }
        .overlay {
            if isToday && !isShown { DailyWeekMetric.shape.strokeBorder(Hue.ink, lineWidth: DailyWeekMetric.todayRing) }
        }
        .contentShape(DailyWeekMetric.shape)
    }

    /// "Wednesday 21, today, Sam and Marlene going".
    private var spoken: String {
        var words = ["\(day.spokenWeekday) \(day.number)"]
        if isToday { words.append("today") }
        if !friends.isEmpty {
            let names = friends.map(\.name)
            let who = names.count <= 2 ? names.joined(separator: " and ") : "\(names[0]) and \(names.count - 1) more"
            words.append("\(who) going")
        }
        return words.joined(separator: ", ")
    }
}

/// The card press (`PressableCardStyle`'s scale and spring) on a day's words, telling the row
/// which day is down so its bubble, in the layer under them, squishes with them.
private struct DailyWeekPressStyle: ButtonStyle {
    let day: String
    @Binding var pressed: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? PressableCardStyle.pressedScale : 1)
            .animation(PressableCardStyle.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isDown in
                if isDown { pressed = day } else if pressed == day { pressed = nil }
            }
    }
}

/// The friends going that day under its bubble: two faces at most, then the count of the rest.
/// The row keeps its height with nobody going, so the page under it doesn't move as faces load.
private struct DailyWeekFaces: View {
    let friends: [FeedFriend]

    var body: some View {
        HStack(spacing: -DailyWeekMetric.faceOverlap) {
            ForEach(Array(friends.prefix(DailyWeekMetric.faces).enumerated()), id: \.offset) { index, friend in
                Avatar(friend.photo, size: DailyWeekMetric.face)
                    .overlay(Circle().strokeBorder(Hue.paper, lineWidth: DailyWeekMetric.faceRing))
                    .zIndex(Double(DailyWeekMetric.faces - index))
            }
            if friends.count > DailyWeekMetric.faces {
                Text("+\(friends.count - DailyWeekMetric.faces)")
                    .font(.sansSemibold(11))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(width: DailyWeekMetric.face, height: DailyWeekMetric.face)
                    .background(Circle().fill(Hue.fill))
                    .overlay(Circle().strokeBorder(Hue.paper, lineWidth: DailyWeekMetric.faceRing))
            }
        }
        .frame(height: DailyWeekMetric.face)
        .accessibilityHidden(true)
    }
}
