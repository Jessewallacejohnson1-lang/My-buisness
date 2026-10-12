//
//  YouPage.swift
//  Block Party — the You tab: the neighbour's own three weeks (BP app docs/plans/you-tab).
//  Their photo at the top left opens Profile. Under it the Calendar, Lapse's: three rows
//  of seven days from this week's Sunday, each day they're Going to something showing
//  that Event's photo. Right under it the Agenda for the day picked there, today until
//  they tap another. Only they ever see it.
//

import SwiftUI

/// The page's sizes. The Calendar's are MEASURED from Jesse's Reference, Lapse's calendar
/// (`references/profile-tab/mobbin/calendar-lapse-1.jpg` in the BP app folder, an @3x
/// 393pt screen; taste.md 2026-10-11): 48.3pt circles on a 51.7pt pitch, so about 3pt
/// apart; 60pt rows; 18.5pt side margins; 13pt weekdays over a 1pt rule inset 16pt, 21pt
/// above the first row; 20pt semibold numbers. The rest are the mock Jesse approved
/// (https://claude.ai/artifact/VQEwBiGQ47eMNY8JWnKSju).
enum YouMetric {
    /// X's photo button, about 32pt, 16pt from the edge
    /// (`references/profile-tab/mobbin/button-x-1.jpg`), in a 44pt tap target.
    static let photo: CGFloat = 32
    static let photoEdge: CGFloat = 16
    static let target: CGFloat = 44
    /// The bar the photo sits in, and from it to the weekdays: the mock's.
    static let bar: CGFloat = 52
    static let calendarTop: CGFloat = 8
    static let calendarSide: CGFloat = 18.5
    static let day: CGFloat = 48.3
    static let rowGap: CGFloat = 11.7
    static let weekdayToRule: CGFloat = 9
    static let ruleToDays: CGFloat = 21
    /// The rule runs 16pt from the screen's edges, past the days' 18.5.
    static let ruleOutset: CGFloat = 2.5
    /// The picked day's ring, inside its circle: ink, then a paper gap (the mock's).
    static let ring: CGFloat = 2.5
    static let ringGap: CGFloat = 2
    /// Today with plans, while another day is picked: a dot under it (the mock's).
    static let todayDot: CGFloat = 4
    static let todayDotDrop: CGFloat = 7
    /// Two or more plans on a day: the count, at the circle's lower right (the mock's).
    static let count: CGFloat = 17
    static let countEdge: CGFloat = 2
    static let countOffset = CGSize(width: 3, height: 2)
    /// Past days this week (picked, 2026-10-10).
    static let pastOpacity: Double = 0.45
    /// Under the Calendar to the Agenda's label, and the label to the first card: the mock's.
    static let calendarToLabel: CGFloat = 26
    static let labelToCards: CGFloat = 13
    static let side: CGFloat = 16
    static let emptyLine: CGFloat = 18
    /// Cards the Agenda's skeleton draws while the first read is out.
    static let skeletonCards = 2
    /// The Places row, Instagram's highlights as the mock draws them: a 62pt photo in a
    /// 70pt ring (2pt line, 2pt gap), the name 6pt under it in a 72pt column, 14pt apart.
    static let placePhoto: CGFloat = 62
    static let placeRing: CGFloat = 70
    static let placeRingLine: CGFloat = 2
    static let placeColumn: CGFloat = 72
    static let placeNameTop: CGFloat = 6
    static let placeGap: CGFloat = 14
}

struct YouPage: View {
    let model: YouModel
    /// The neighbour's photo; nil draws the person icon.
    let avatarURL: String?
    let onProfile: () -> Void
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The day the Agenda shows; nil is today.
    @State private var picked: Date?
    /// The event page an Agenda card opened. Held here, where it outlives the day's cards.
    @State private var pushed: FeedCardItem?
    /// How far the page has scrolled, held only up to the frosted band's fade.
    @State private var scrolled: CGFloat = 0
    @Namespace private var ring

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let first = YouCalendar.firstDay(of: now)
            let today = YouCalendar.calendar.startOfDay(for: now)
            let days = YouCalendar.days(from: first)
            let going = model.going.map { read in
                YouCalendar.going(read: read, tapped: Array(actions.goingTapped.values),
                                  isGoing: { actions.going($0).isGoing }, first: first)
            }
            let day = picked.flatMap { days.contains($0) ? $0 : nil } ?? today
            page(now: now, days: days, today: today, day: day, going: going)
                // On every visit and each new week: the list on screen stays meanwhile.
                .task(id: first) { await model.refresh(now: now) }
        }
        .navigationDestination(item: $pushed) { FeedEventDetailDestination(item: $0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    private func page(now: Date, days: [Date], today: Date, day: Date, going: [DailyEvent]?) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                bar
                calendar(days: days, today: today, day: day, going: going ?? [])
                    .padding(.top, YouMetric.calendarTop)
                // A working word; Jesse writes the final one.
                DailySectionLabel(title: "Agenda", ink: Hue.ink)
                    .padding(.top, YouMetric.calendarToLabel)
                // Another day's cards come in at once; only the ring travels (`calendar`),
                // so two days' cards never show over each other mid-fade.
                agenda(going: going, day: day, now: now)
                    .padding(.top, YouMetric.labelToCards)
                    .padding(.horizontal, YouMetric.side)
                // Left out while there's nowhere to go, as on Daily.
                let places = YouCalendar.places(going ?? [], today: today)
                if !places.isEmpty {
                    // A working word; Jesse writes the final one.
                    DailySectionLabel(title: "Places", ink: Hue.ink)
                        .padding(.top, YouMetric.calendarToLabel)
                    YouPlaces(events: places, open: { pushed = $0 })
                        .padding(.top, YouMetric.labelToCards)
                }
                Color.clear.frame(height: DailyMetric.tabBarClearance)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            min(max(geometry.contentOffset.y + geometry.contentInsets.top, 0), DailyMetric.edgeFade)
        } action: { _, offset in scrolled = offset }
        .background(Hue.paper.ignoresSafeArea())
        // The Town feed's frosted band behind the clock, in with the first bit of scroll.
        .statusEdge(opacity: scrolled / DailyMetric.edgeFade)
    }

    // MARK: The photo

    private var bar: some View {
        HStack(spacing: 0) {
            Button(action: onProfile) {
                YouPhoto(url: avatarURL)
                    .frame(width: YouMetric.target, height: YouMetric.target)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel("Your profile")
            Spacer(minLength: 0)
        }
        .padding(.leading, YouMetric.photoEdge - (YouMetric.target - YouMetric.photo) / 2)
        .frame(height: YouMetric.bar)
    }

    // MARK: The Calendar

    private func calendar(days: [Date], today: Date, day: Date, going: [DailyEvent]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { weekday in
                    Text(DailyEvent.townTime("EEE", weekday))
                        .font(.sansMedium(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            Hue.hairline
                .frame(height: 1)
                .padding(.horizontal, -YouMetric.ruleOutset)
                .padding(.top, YouMetric.weekdayToRule)
            let byDay = YouCalendar.byDay(going)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                      spacing: YouMetric.rowGap) {
                ForEach(days, id: \.self) { date in
                    let events = byDay[date] ?? []
                    Button { pick(date, from: day) } label: {
                        YouDay(date: date, events: events, isToday: date == today,
                               isPast: date < today, isPicked: date == day, ring: ring)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel(Self.spoken(date, plans: events.count, today: date == today))
                    .accessibilityAddTraits(date == day ? .isSelected : [])
                }
            }
            .padding(.top, YouMetric.ruleToDays)
            // The ring travels to the picked day; nothing outside the grid animates.
            .animation(reduceMotion ? nil : Motion.select, value: day)
        }
        .padding(.horizontal, YouMetric.calendarSide)
    }

    /// "Today, Tuesday, October 13, 2 plans". Working words; Jesse writes the final ones.
    static func spoken(_ date: Date, plans: Int, today: Bool = false) -> String {
        let count = plans == 0 ? "nothing planned" : plans == 1 ? "1 plan" : "\(plans) plans"
        return (today ? "Today, " : "") + "\(DailyEvent.townTime("EEEEMMMMd", date)), \(count)"
    }

    private func pick(_ date: Date, from current: Date) {
        guard date != current else { return }
        Haptics.selection()
        picked = date
    }

    // MARK: The Agenda

    @ViewBuilder
    private func agenda(going: [DailyEvent]?, day: Date, now: Date) -> some View {
        if let going {
            let events = YouCalendar.on(day, going)
            if events.isEmpty {
                // A working line; Jesse writes the final words.
                Text("Nothing planned")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, YouMetric.emptyLine)
            } else {
                AgendaCards(events: events, now: now, open: { pushed = $0 })
                    // A new day starts with every card closed.
                    .id(day)
            }
        } else if model.failed {
            FeedRetryButton { Task { await model.refresh() } }
        } else {
            VStack(spacing: AgendaMetric.rowGap) {
                ForEach(0..<YouMetric.skeletonCards, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: Radius.tile).frame(height: AgendaMetric.row)
                }
            }
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading your plans")
        }
    }
}

/// Where the neighbour's plans are, as Instagram's highlights: each place's next Event's
/// photo in a ring with the place's name under it, cut at the column's width, never
/// reworded. A tap opens that Event. No photo of its own: a grey circle, as on the Calendar.
private struct YouPlaces: View {
    let events: [DailyEvent]
    let open: (FeedCardItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: YouMetric.placeGap) {
                ForEach(events) { event in
                    let place = YouCalendar.place(of: event) ?? ""
                    Button { open(event.item) } label: {
                        VStack(spacing: YouMetric.placeNameTop) {
                            Group {
                                if let photo = event.photo {
                                    FeedCardURLPhoto(url: photo, loadingFill: Hue.fill)
                                } else {
                                    Hue.fill
                                }
                            }
                            .frame(width: YouMetric.placePhoto, height: YouMetric.placePhoto)
                            .clipShape(Circle())
                            .frame(width: YouMetric.placeRing, height: YouMetric.placeRing)
                            .overlay(Circle().strokeBorder(Hue.ink.opacity(0.14), lineWidth: YouMetric.placeRingLine))
                            Text(place)
                                .font(.sans(12))
                                .foregroundStyle(Hue.ink)
                                .lineLimit(1)
                        }
                        .frame(width: YouMetric.placeColumn)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("\(place), \(event.item.title)")
                }
            }
        }
        .contentMargins(.horizontal, YouMetric.side, for: .scrollContent)
    }
}

/// The neighbour's photo in the bar, or the person icon until there is one.
private struct YouPhoto: View {
    let url: String?

    var body: some View {
        Circle()
            .fill(Hue.fill)
            .overlay {
                if let url, let photo = URL(string: url) {
                    AsyncImage(url: photo) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            person
                        }
                    }
                } else {
                    person
                }
            }
            .frame(width: YouMetric.photo, height: YouMetric.photo)
            .clipShape(Circle())
    }

    private var person: some View {
        Image(systemName: "person.fill")
            .font(.sans(15))
            .foregroundStyle(Hue.inkSecondary)
    }
}

/// One day on the Calendar: the first Event's photo with the date over it in white; a
/// plan with no photo of its own, a light grey circle (picked, 2026-10-11: a Google photo
/// can't carry its credit in a circle this size); today with nothing planned, a filled ink
/// disc; any other day, its number in grey.
private struct YouDay: View {
    let date: Date
    let events: [DailyEvent]
    let isToday: Bool
    let isPast: Bool
    let isPicked: Bool
    let ring: Namespace.ID

    var body: some View {
        let photo = events.first?.photo
        ZStack {
            if !events.isEmpty {
                if let photo {
                    FeedCardURLPhoto(url: photo, loadingFill: Hue.fill)
                } else {
                    Hue.fill
                }
            } else if isToday {
                Hue.ink
            }
            Text(DailyEvent.townTime("d", date))
                .font(.sansSemibold(20))
                .foregroundStyle(numberInk(photo: photo != nil))
                .shadow(color: photo != nil ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
        }
        .frame(width: YouMetric.day, height: YouMetric.day)
        .clipShape(Circle())
        // The whole circle takes the tap, not only the number of an empty day.
        .contentShape(Circle())
        .overlay {
            if isPicked {
                Circle()
                    .strokeBorder(Hue.paper, lineWidth: YouMetric.ring + YouMetric.ringGap)
                    .overlay { Circle().strokeBorder(Hue.ink, lineWidth: YouMetric.ring) }
                    .matchedGeometryEffect(id: "ring", in: ring)
            }
        }
        .overlay(alignment: .bottom) {
            if isToday && !isPicked && !events.isEmpty {
                Circle()
                    .fill(Hue.ink)
                    .frame(width: YouMetric.todayDot, height: YouMetric.todayDot)
                    .offset(y: YouMetric.todayDotDrop)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if events.count > 1 {
                Text("\(events.count)")
                    .font(.sansBold(11))
                    .monospacedDigit()
                    .foregroundStyle(Hue.paper)
                    .padding(.horizontal, YouMetric.countEdge)
                    .frame(minWidth: YouMetric.count, minHeight: YouMetric.count)
                    .background(Capsule().fill(Hue.ink))
                    .padding(YouMetric.countEdge)
                    .background(Capsule().fill(Hue.paper))
                    .offset(YouMetric.countOffset)
            }
        }
        .opacity(isPast ? YouMetric.pastOpacity : 1)
    }

    private func numberInk(photo: Bool) -> Color {
        if photo { return .white }
        if !events.isEmpty { return Hue.ink }
        return isToday ? Hue.paper : Hue.inkSecondary
    }
}
