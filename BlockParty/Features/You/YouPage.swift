//
//  YouPage.swift
//  Block Party — the You tab's own part: your three weeks (BP app docs/plans/you-tab), under your
//  Profile's head since You became your Profile (five-tabs 03, `ProfileView`). The Calendar,
//  Lapse's: three rows of seven days from this week's Sunday, each day you're Going to something
//  showing that Event's photo. Right under it the Agenda for the day picked there, today until you
//  tap another or swipe the Agenda to it. Only you ever see it; a neighbour's Profile shows Going rows.
//

import SwiftUI

/// The page's sizes. The Calendar's are MEASURED from Jesse's Reference, Lapse's calendar
/// (`references/profile-tab/mobbin/calendar-lapse-1.jpg` in the BP app folder, an @3x
/// 393pt screen; taste.md 2026-10-11): 48.3pt circles on a 51.7pt pitch, so about 3pt
/// apart; 60pt rows; 18.5pt side margins; 13pt weekdays over a 1pt rule inset 16pt, 21pt
/// above the first row; 20pt semibold numbers. The rest are the mock Jesse approved
/// (https://claude.ai/artifact/VQEwBiGQ47eMNY8JWnKSju).
enum YouMetric {
    /// From the Profile's "Going" title to the weekdays: the five-tabs mock's
    /// (https://claude.ai/artifact/29BVrCrrQ3WeWhS3egMozR).
    static let calendarTop: CGFloat = 12
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
    /// The Friends tab's own groups, Instagram's highlights as the mock draws them: a 62pt
    /// photo in a 70pt ring (2pt line, 2pt gap), the name 6pt under it in a 72pt column, 14pt apart.
    static let highlightPhoto: CGFloat = 62
    static let highlightRing: CGFloat = 70
    static let highlightRingLine: CGFloat = 2
    static let highlightColumn: CGFloat = 72
    static let highlightNameTop: CGFloat = 6
    static let highlightGap: CGFloat = 14
    /// A group's logo in its circle: Search's row logo (`SearchMetric.avatarLogo`), which
    /// leaves its 44pt square the margin a 62pt circle's own 44pt square leaves.
    static let groupLogo: CGFloat = SearchMetric.avatarLogo
    /// Search's group icon, grown with the circle from its 17pt in a 44pt square.
    static let groupGlyph: CGFloat = 24
    /// A Group get-together's logo inside its day's 48.3 pt circle, under the white number. Picked.
    static let dayLogo: CGFloat = 32
}

struct YouPage: View {
    let model: YouModel
    /// An Agenda card's tap: your Profile (`ProfileView`) pushes its Event page, where it outlives
    /// the day's cards.
    let open: (FeedCardItem) -> Void
    /// A Group get-together's card, and a Coming up row: the Group page (rsvp-and-groups 09).
    var openGroup: (TownGroup) -> Void = { _ in }
    @Environment(RealLifeActions.self) private var actions
    private let agenda = GroupAgenda.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The day the Agenda shows; nil is today.
    @State private var picked: Date?
    @Namespace private var ring

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let first = YouCalendar.firstDay(of: now)
            let today = YouCalendar.calendar.startOfDay(for: now)
            let days = YouCalendar.days(from: first)
            // The Groups you're in, this session's joins laid over the read, as your Profile's Groups.
            let mine = (model.groups ?? []).filter { actions.member($0).isMember }
            let gatherings = YouCalendar.groupPlans(mine, state: agenda.state, first: first)
            let going = model.going.map { read in
                YouCalendar.withGroups(YouCalendar.going(read: read, tapped: Array(actions.goingTapped.values),
                                                         isGoing: { actions.going($0).isGoing }, first: first),
                                       gatherings)
            }
            let day = picked.flatMap { days.contains($0) ? $0 : nil } ?? today
            plans(now: now, days: days, today: today, day: day, going: going,
                  comingUp: YouCalendar.comingUp(mine, state: agenda.state, now: now))
                // On every visit and each new week: the list on screen stays meanwhile.
                .task(id: first) { await model.refresh(now: now) }
        }
        // On every visit, for your Profile's groups and a neighbour's page.
        .task { await refreshGroups() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh(); await refreshGroups() } }
        }
    }

    private func plans(now: Date, days: [Date], today: Date, day: Date, going: [DailyEvent]?,
                       comingUp: [DailyEvent]) -> some View {
        VStack(spacing: 0) {
            calendar(days: days, today: today, day: day, going: going ?? [])
                .padding(.top, YouMetric.calendarTop)
            // A working word; Jesse writes the final one.
            DailySectionLabel(title: "Agenda", ink: Hue.ink)
                .padding(.top, YouMetric.calendarToLabel)
            // A tapped day's cards come in at once; only the ring travels (`calendar`),
            // so two days' cards never show over each other mid-fade.
            agenda(going: going, days: days, today: today, day: day, now: now)
                .padding(.top, YouMetric.labelToCards)
            if !comingUp.isEmpty {
                YouComingUp(gatherings: comingUp, open: openGroup)
                    .padding(.horizontal, EventPage.Metric.inset)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: comingUp.map(\.id))
    }

    /// The groups again, and, from a fresh read only, whether the neighbour is in each for
    /// every page that shows them.
    private func refreshGroups() async {
        if let groups = await model.refreshGroups() { actions.read(groups) }
    }

    /// The first word of the saved name, for the hello pill and onboarding's Done; nil when there's none.
    static func firstName(_ name: String?) -> String? {
        name?.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    // MARK: The Calendar

    private func calendar(days: [Date], today: Date, day: Date, going: [DailyEvent]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { weekday in
                    Text(Town.format(weekday, "EEE"))
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
                        YouDay(date: date, month: YouCalendar.month(on: date, first: days.first),
                               events: events, isToday: date == today,
                               isPast: date < today, isPicked: date == day, ring: ring)
                    }
                    .buttonStyle(.press(.squish))
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
        return (today ? "Today, " : "") + "\(Town.format(date, "EEEEMMMMd")), \(count)"
    }

    private func pick(_ date: Date, from current: Date) {
        guard date != current else { return }
        Haptics.selection()
        picked = date
    }

    // MARK: The Agenda

    /// The day's cards, swiped day to day once the read is in (ticket 12): every day with plans,
    /// today, and the day picked. Before that, the skeleton or the retry.
    @ViewBuilder
    private func agenda(going: [DailyEvent]?, days: [Date], today: Date, day: Date, now: Date) -> some View {
        if let going {
            AgendaPager(pages: YouCalendar.pages(going, days: days, today: today, day: day), day: day,
                        pick: { pick($0, from: day) }) { page in
                agendaList(going, day: page, now: now)
            }
        } else {
            agendaList(nil, day: day, now: now)
                .padding(.horizontal, YouMetric.side)
        }
    }

    private func agendaList(_ going: [DailyEvent]?, day: Date, now: Date) -> some View {
        // "Nothing planned" is a working line; Jesse writes the final words.
        AgendaList(events: going.map { YouCalendar.on(day, $0) }, failed: model.failed,
                   empty: "Nothing planned", loading: "Loading your plans", now: now, faces: true,
                   // An empty today points to the next plan; a tap on it picks its day, as a tap
                   // on that day does (ticket 11).
                   next: going.flatMap { YouCalendar.next($0, day: day, now: now) },
                   pick: { pick(YouCalendar.calendar.startOfDay(for: $0.starts), from: day) },
                   retry: { Task { await model.refresh() } }, open: open, openGroup: openGroup)
    }
}

/// One of Instagram's highlights: the picture in a ring with the name under it, cut at the
/// column's width, never reworded: the Friends tab's groups.
struct YouHighlight<Picture: View>: View {
    let name: String
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        VStack(spacing: YouMetric.highlightNameTop) {
            Hue.fill
                .overlay { picture() }
                .frame(width: YouMetric.highlightPhoto, height: YouMetric.highlightPhoto)
                .clipShape(Circle())
                .frame(width: YouMetric.highlightRing, height: YouMetric.highlightRing)
                .overlay(Circle().strokeBorder(Hue.ink.opacity(0.14), lineWidth: YouMetric.highlightRingLine))
            Text(name)
                .font(.sans(12))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
        }
        .frame(width: YouMetric.highlightColumn)
        .contentShape(Rectangle())
    }
}

/// A group's picture: its logo on its backdrop as Search draws it, else Search's group icon on
/// the grey. Never its photos: a saved photo carries its credit wherever it shows (MEMORY.md,
/// 2026-10-16) and a circle this size has no room for one (Jesse, ticket 09 Check-in 1).
struct YouGroupPicture: View {
    let group: TownGroup?
    var logoSide = YouMetric.groupLogo
    var glyph = YouMetric.groupGlyph

    var body: some View {
        if let logo = group?.logo.flatMap({ FeedCardImageSource($0).logo }) {
            ZStack {
                SearchBackdrop(colors: logo.backdrop)
                SearchFloor()
                CastLogo(logo: logo, side: logoSide)
            }
        } else {
            Image(systemName: "person.2")
                .font(.glyph(glyph))
                .foregroundStyle(Hue.inkSecondary)
        }
    }
}

/// One day on the Calendar: the first Event's photo with the date over it in white; a
/// plan with no photo of its own, a light grey circle (picked, 2026-10-11: a Google photo
/// can't carry its credit in a circle this size); today with nothing planned, a filled ink
/// disc; any other day, its number in grey.
private struct YouDay: View {
    let date: Date
    /// "NOV" on the 1st of a new month, over a smaller number (ticket 10); nil on every other day.
    let month: String?
    let events: [DailyEvent]
    let isToday: Bool
    let isPast: Bool
    let isPicked: Bool
    let ring: Namespace.ID

    var body: some View {
        let photo = events.first?.photo
        // A Group get-together shows its Group's logo on its backdrop, as Search draws it; a Group with
        // no logo, the grey (rsvp-and-groups 09).
        let group = events.first?.group.flatMap { $0.logo == nil ? nil : $0 }
        ZStack {
            if !events.isEmpty {
                if let photo {
                    FeedCardURLPhoto(url: photo, loadingFill: Hue.fill)
                } else if let group {
                    YouGroupPicture(group: group, logoSide: YouMetric.dayLogo)
                } else {
                    Hue.fill
                }
            } else if isToday {
                Hue.ink
            }
            // The month is Apple Fitness's "Oct" where a month starts, inside the circle, since the
            // three weeks are one block (Jesse, ticket 10 Check-in 1); its sizes are picked.
            VStack(spacing: 0) {
                if let month {
                    Text(month).font(.sansBold(11))
                }
                Text(Town.format(date, "d"))
                    .font(.sansSemibold(month == nil ? 20 : 17))
            }
            .foregroundStyle(numberInk(photo: photo != nil || group != nil))
            .shadow(color: photo != nil || group != nil ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
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

/// You's Coming up (BP app rsvp-and-groups 09): the next get-togethers of your Groups that aren't on
/// your Agenda with their whole Group, as the Group page's date tiles, each with a green Add where an
/// Event has Attend (Jesse, 2026-11-13). Add turns into the light Added, as Join turns into Joined, and
/// lights the day on the Calendar; Added tapped again takes it off. A row's tap opens its Group page.
struct YouComingUp: View {
    let gatherings: [DailyEvent]
    let open: (TownGroup) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let agenda = GroupAgenda.shared
    private typealias Sizes = GroupPage.Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A working word, the Group page's own; Jesse approved it on the mock (2026-11-13).
            Text("Coming up")
                .font(.displaySemi(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Sizes.sectionTop)
            ForEach(gatherings) { gathering in
                if let group = gathering.group, let meeting = gathering.meeting {
                    row(gathering, group: group, meeting: meeting)
                        .padding(.top, Sizes.rowTop)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ gathering: DailyEvent, group: TownGroup, meeting: TownGroup.Meeting) -> some View {
        let on = agenda.state(group, meeting) == .one
        let tile = GroupPage.tile(meeting.day)
        return HStack(spacing: Sizes.rowGap) {
            Button { open(group) } label: {
                HStack(spacing: Sizes.rowGap) {
                    VStack(spacing: 0) {
                        Text(tile.month)
                            .font(.apple(11, weight: .semibold))
                            .foregroundStyle(Hue.inkSecondary)
                        Text(tile.day)
                            .font(.apple(20, weight: .semibold))
                            .foregroundStyle(Hue.ink)
                            .monospacedDigit()
                    }
                    .frame(width: Sizes.tile, height: Sizes.tile)
                    .background(Hue.fill, in: RoundedRectangle(cornerRadius: Sizes.tileCorner, style: .continuous))
                    VStack(alignment: .leading, spacing: ProfileMetric.rowText) {
                        Text(meeting.what)
                            .font(.apple(15, weight: .semibold))
                            .foregroundStyle(Hue.ink)
                        Text(Self.line(meeting, group: group))
                            .font(.apple(13))
                            .foregroundStyle(Hue.inkSecondary)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(group.name)")
            Button {
                Haptics.light()
                agenda.toggle(group, meeting)
            } label: {
                ZStack {
                    Text("Add").opacity(on ? 0 : 1)
                    Label("Added", systemImage: "checkmark").labelStyle(.titleAndIcon).opacity(on ? 1 : 0)
                }
                .font(.displaySemi(15))
            }
            .buttonStyle(MeetupPillStyle(height: FriendsMetric.joinPill, minWidth: 0, fill: Hue.add, light: on,
                                         sidePadding: FriendsMetric.joinSide))
            .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: on)
            .accessibilityLabel(on ? "Added to your Agenda, \(meeting.what)" : "Add \(meeting.what) to your Agenda")
        }
    }

    /// "Mon 7 PM · St. Joe Rod and Gun Club": the tile has the date.
    static func line(_ meeting: TownGroup.Meeting, group: TownGroup) -> String {
        var when: [String] = []
        if let day = Town.midnight(meeting.day) { when.append(Town.format(day, "EEE")) }
        if let minutes = EventWhen.minutes(meeting.time) { when.append(Town.clock(minutes: minutes)) }
        return [when.joined(separator: " "), group.name].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
