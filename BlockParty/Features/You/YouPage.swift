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
    /// A Group get-together's logo inside its day's 48.3 pt circle, the mock's 38 pt (Jesse approved
    /// it, https://claude.ai/artifact/VdKZpF5NX8n4hdLVpKAY6J), faded under the ink number. The fade is picked.
    static let dayLogo: CGFloat = 38
    static let dayLogoOpacity: Double = 0.45
    /// The fold's handle, Structured's measured 50 x 5 (BP app `references/profile-middle/SPEC.md`,
    /// "The folded Calendar"), centred in `calendarToLabel`'s 26 pt so it adds no height. The width it
    /// takes a touch across is picked.
    static let handleWidth: CGFloat = 50
    static let handleHeight: CGFloat = 5
    static let handleTouchWidth: CGFloat = 120
    /// The touch reaches this far under the 26 pt, over the "Agenda" label, which takes no tap, so it
    /// is 44 pt tall without adding height or covering the days above.
    static let handleTouchBelow: CGFloat = 44 - calendarToLabel
    /// Under the finger the handle darkens and swells a little (picked), on `Press`'s timing.
    static let handlePressedScale: CGFloat = 1.1
    /// How far below the folded row the fold still draws: today's dot (7 pt down) and the plans count
    /// (2 pt down) show, the next week's top (11.7 pt down) doesn't.
    static let foldSpill: CGFloat = 9
    /// Reduce Motion's fold: the three weeks fade in or out (ticket 14).
    static let foldFade: Double = 0.15
}

/// You's Calendar folded to one week (BP app you-tab 14): 0 is the picked day's week alone, 1 the
/// three weeks. Between the two the window grows from the folded row while the rows above it slide
/// down into place, so the picked week never jumps.
enum CalendarFold {
    static let pitch = YouMetric.day + YouMetric.rowGap
    /// The height folding takes off: the two other weeks' rows.
    static let travel = pitch * CGFloat(YouCalendar.length / 7 - 1)

    /// Which week of the three a day's index falls in; the first when it's off them.
    static func row(of index: Int?) -> Int { (index ?? 0) / 7 }

    static func height(openness: CGFloat) -> CGFloat { YouMetric.day + travel * openness }

    static func offset(openness: CGFloat, row: CGFloat) -> CGFloat { -row * pitch * (1 - openness) }

    /// Where a pull of `pulled` points (down opens) takes a fold that was at `start`.
    static func openness(from start: CGFloat, pulled: CGFloat) -> CGFloat {
        min(1, max(0, start + pulled / travel))
    }

    /// Whether a let-go settles open: the nearer end to where the flick would carry it.
    static func settlesOpen(from start: CGFloat, flung: CGFloat) -> Bool {
        start + flung / travel >= 0.5
    }
}

/// The fold as it is drawn this frame, which the fold's spring moves between the two ends. A pull
/// that catches it mid-spring starts from here, not from the end it was heading to.
final class FoldShown {
    var openness: CGFloat = 0
}

/// The fold's handle: Structured's grey capsule at the top of its touch, darker and a little wider
/// while the finger is on it or pulling.
private struct FoldHandleStyle: ButtonStyle {
    let held: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || held
        return configuration.label
            .overlay(alignment: .top) {
                Capsule()
                    .fill(down ? Hue.inkSecondary : Hue.edge)
                    .frame(width: YouMetric.handleWidth, height: YouMetric.handleHeight)
                    .scaleEffect(down ? YouMetric.handlePressedScale : 1)
                    .frame(height: YouMetric.calendarToLabel)
                    .animation(Press.animation(down: down, reduceMotion: reduceMotion), value: down)
            }
    }
}

/// Draws the fold: the window's height and the roll that keeps the picked week in it. Animatable, so
/// the page under it moves with every frame.
private struct FoldWindow: ViewModifier, Animatable {
    var openness: CGFloat
    var row: CGFloat
    let shown: FoldShown

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(openness, row) }
        set { openness = newValue.first; row = newValue.second }
    }

    func body(content: Content) -> some View {
        shown.openness = openness
        return content
            .offset(y: CalendarFold.offset(openness: openness, row: row))
            .frame(height: CalendarFold.height(openness: openness), alignment: .top)
            .mask(alignment: .top) { Rectangle().padding(.bottom, -YouMetric.foldSpill) }
    }
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
    /// The Calendar's fold (ticket 14): 0 one week, 1 three. Folded on every open of the app.
    @State private var openness: CGFloat = 0
    @State private var shown = FoldShown()
    /// Where a pull on the handle started; nil while nothing pulls.
    @State private var pullStart: CGFloat?
    /// Reduce Motion's fold: the other two weeks fade in or out rather than move.
    @State private var othersHidden = false

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
            foldHandle
            // A working word; Jesse writes the final one.
            DailySectionLabel(title: "Agenda", ink: Hue.ink)
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
            let row = CalendarFold.row(of: days.firstIndex(of: day))
            // Folded and at rest, the other weeks take no tap and VoiceOver skips them.
            let folded = openness == 0 && pullStart == nil
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                      spacing: YouMetric.rowGap) {
                ForEach(Array(days.enumerated()), id: \.element) { index, date in
                    let events = byDay[date] ?? []
                    let other = CalendarFold.row(of: index) != row
                    let away = folded && other
                    Button { pick(date, from: day) } label: {
                        YouDay(date: date, month: YouCalendar.month(on: date, first: days.first),
                               events: events, isToday: date == today,
                               isPast: date < today, isPicked: date == day, ring: ring,
                               gapColor: Hue.onboardingCanvas, dayFill: Hue.onboardingField)
                    }
                    .buttonStyle(.press(.squish))
                    .opacity(othersHidden && other ? 0 : 1)
                    .accessibilityLabel(Self.spoken(date, plans: events.count, today: date == today))
                    .accessibilityAddTraits(date == day ? .isSelected : [])
                    .allowsHitTesting(!away)
                    .accessibilityHidden(away)
                }
            }
            // The ring travels to the picked day; nothing outside the grid animates.
            .animation(reduceMotion ? nil : Motion.select, value: day)
            .modifier(FoldWindow(openness: openness, row: CGFloat(row), shown: shown))
            // Folded, the row rolls to the week the Agenda swipes into.
            .animation(reduceMotion ? nil : Motion.smooth, value: row)
            .padding(.top, YouMetric.ruleToDays)
        }
        .padding(.horizontal, YouMetric.calendarSide)
    }

    // MARK: The fold

    /// Structured's handle under the Calendar (ticket 14): a tap opens or folds the three weeks, a
    /// pull follows the finger both ways and settles on the nearer end, and either can catch the
    /// fold mid-spring. Only a touch that starts on it pulls; the page scrolls from everywhere else.
    private var foldHandle: some View {
        let open = openness >= 0.5
        return Button { settle(open: !open, from: openness) } label: {
            Color.clear
                .frame(width: YouMetric.handleTouchWidth, height: YouMetric.calendarToLabel)
                .padding(.bottom, YouMetric.handleTouchBelow)
                .contentShape(Rectangle())
        }
        .buttonStyle(FoldHandleStyle(held: pullStart != nil))
        .padding(.bottom, -YouMetric.handleTouchBelow)
        // Wins over the button once the finger moves, so a pull never also taps. Read on the screen,
        // not on the handle, which moves with the fold: a local read only counted half the finger.
        .highPriorityGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { drag in
                    // Caught mid-spring, it carries on from where it is drawn.
                    let start = pullStart ?? shown.openness
                    pullStart = start
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) {
                        openness = CalendarFold.openness(from: start, pulled: drag.translation.height)
                    }
                }
                .onEnded { drag in
                    let start = pullStart ?? openness
                    pullStart = nil
                    settle(open: CalendarFold.settlesOpen(from: start, flung: drag.predictedEndTranslation.height),
                           from: start, pulled: true)
                }
        )
        .accessibilityLabel(open ? "Show one week" : "Show three weeks")
    }

    /// Takes the fold to one end on `Motion.smooth`, from wherever it is drawn. With Reduce Motion a
    /// tap fades the other two weeks in after the height opens, or out before it folds; a pull, which
    /// followed the finger, just lands.
    private func settle(open: Bool, from start: CGFloat, pulled: Bool = false) {
        let target: CGFloat = open ? 1 : 0
        // A tick when it changes ends, as a day's pick ticks; a pull let go where it began doesn't.
        if (start >= 0.5) != open { Haptics.selection() }
        guard reduceMotion else {
            withAnimation(Motion.smooth) { openness = target }
            return
        }
        var still = Transaction()
        still.disablesAnimations = true
        let fade = Animation.easeInOut(duration: YouMetric.foldFade)
        if pulled {
            withTransaction(still) { openness = target }
        } else if open {
            withTransaction(still) {
                openness = target
                othersHidden = true
            }
            // A turn later, or the two changes cancel out and nothing fades.
            DispatchQueue.main.async { withAnimation(fade) { othersHidden = false } }
        } else {
            withAnimation(fade) { othersHidden = true } completion: {
                withTransaction(still) {
                    openness = target
                    othersHidden = false
                }
            }
        }
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
/// disc; any other day, its number in grey, on a grey disc where every day is one (Search's Event calendar,
/// BP app five-tabs 10).
struct YouDay: View {
    let date: Date
    /// "NOV" on the 1st of a new month, over a smaller number (ticket 10); nil on every other day.
    let month: String?
    let events: [DailyEvent]
    let isToday: Bool
    let isPast: Bool
    let isPicked: Bool
    let ring: Namespace.ID
    var disc = false
    /// The gap inside the picked day's ring and the rim round the plans count: the colour of the
    /// page under the Calendar, the Profile's grey on You (profile-middle), paper on Search's.
    var gapColor: Color = Hue.paper
    /// A plan's disc with no photo, and any day's while its photo loads. On You's grey (onboarding's
    /// canvas, `Hue.onboardingCanvas`) it takes onboarding's field grey, the one set on that same
    /// canvas, since `Hue.fill` all but vanishes there; Search's keeps `Hue.fill`.
    var dayFill: Color = Hue.fill

    var body: some View {
        // The first Event with a photo, so a day whose first has none still shows one (the plan's review).
        let photo = disc ? events.lazy.compactMap(\.photo).first : events.first?.photo
        // A Group get-together shows its Group's logo on its backdrop, as Search draws it; a Group with
        // no logo, the grey (rsvp-and-groups 09).
        let group = events.first?.group.flatMap { $0.logo == nil ? nil : $0 }
        ZStack {
            if !events.isEmpty {
                if let photo {
                    FeedCardURLPhoto(url: photo, loadingFill: dayFill)
                } else if let group {
                    // Faded under an ink number: the logo's own letters fought a white one (review).
                    YouGroupPicture(group: group, logoSide: YouMetric.dayLogo)
                        .opacity(YouMetric.dayLogoOpacity)
                } else if disc {
                    // White on the Event calendar's grey fade, as an empty day, its number in ink (the run's review).
                    Circle().fill(Hue.surface).overlay { Circle().strokeBorder(Hue.hairline, lineWidth: 0.5) }
                } else {
                    dayFill
                }
            } else if isToday {
                Hue.ink
            } else if disc {
                // White on the Event calendar's grey fade, with a hairline (mock round 4).
                Circle().fill(Hue.surface).overlay { Circle().strokeBorder(Hue.hairline, lineWidth: 0.5) }
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
                    .strokeBorder(gapColor, lineWidth: YouMetric.ring + YouMetric.ringGap)
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
                    .background(Capsule().fill(gapColor))
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
                    // The line says the day; the Group page hides its tile the same way.
                    .accessibilityHidden(true)
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
