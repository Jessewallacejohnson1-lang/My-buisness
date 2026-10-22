//
//  YouAgenda.swift
//  Block Party — the You tab's Agenda: every Event the neighbour is Going to on the day
//  picked on the Calendar (BP app docs/plans/you-tab). Daily's Agenda cards, moved here
//  when the Agenda left Daily (Jesse, 2026-10-10), without the day rail beside them: the
//  Calendar above says the day.
//

import SwiftUI

enum AgendaMetric {
    /// MEASURED from Jesse's Reference for Daily's Agenda: Airbnb's trip day plan
    /// (`references/daily-agenda/airbnb-day-plan.jpg` in the BP app folder, an @3x 393pt
    /// screen). Each card: 80pt tall, a 64pt picture 8pt in, the text 16pt after it. The
    /// corners are tokens: the Reference's round 13.5 card and 10.5 picture read as
    /// `Radius.tile` and `Radius.button`, which are continuous and so look smaller than
    /// their numbers.
    static let row: CGFloat = 80
    static let photo: CGFloat = 64
    static let photoInset: CGFloat = 8
    static let textGap: CGFloat = 16
    /// Above and below the text, so a closed card's two lines sit centred on the photo
    /// as the Reference's one line does, and an open card grows only downward.
    static let textInset: CGFloat = 14
    /// Between the cards. Picked: the Reference's gap from the trip card above to its
    /// first row, since its rows never sit back to back.
    static let rowGap: CGFloat = 12
    /// Room the open card keeps on its right for the arrow.
    static let arrowRoom: CGFloat = 22
    /// The next plan's "In 2 days" pill, and the empty line's room above and below it over that
    /// card: the mock Jesse approved (you-tab 11, https://claude.ai/artifact/XqbVLhDiEH78VNfTz7NnDw),
    /// MEASURED in its render, 24.7pt from the label's ink to the line's and 16 on to the card.
    static let pill: CGFloat = 26
    static let pillSide: CGFloat = 10
    static let lineOverNext = EdgeInsets(top: 6, leading: 0, bottom: 3, trailing: 0)
}

/// What an Agenda shows, on the You page and in Profile's Saved (ticket 04): two skeleton
/// cards while the first read is out, the retry when it failed, one line when there's
/// nothing, else the cards.
struct AgendaList: View {
    /// nil until the first read lands.
    let events: [DailyEvent]?
    let failed: Bool
    let empty: String
    /// What VoiceOver says over the skeleton.
    let loading: String
    let now: Date
    var withDay = false
    /// The friends Going on each card: the You Agenda's, not Saved's (ticket 07).
    var faces = false
    /// An empty today's next plan, under the line with how far off it is; a tap goes to its
    /// day through `pick` (You, ticket 11).
    var next: DailyEvent?
    var pick: (DailyEvent) -> Void = { _ in }
    let retry: () -> Void
    let open: (FeedCardItem) -> Void

    var body: some View {
        if let events {
            if events.isEmpty {
                VStack(spacing: AgendaMetric.rowGap) {
                    Text(empty)
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, next == nil ? YouMetric.emptyLine : AgendaMetric.lineOverNext.top)
                        .padding(.bottom, next == nil ? YouMetric.emptyLine : AgendaMetric.lineOverNext.bottom)
                    if let next {
                        Button { pick(next) } label: {
                            AgendaCard(event: next, now: now, withDay: true, friends: [], open: false,
                                       pill: next.startsLabel(now: now))
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            } else {
                AgendaCards(events: events, now: now, withDay: withDay, faces: faces, open: open)
            }
        } else if failed {
            FeedRetryButton(action: retry)
        } else {
            VStack(spacing: AgendaMetric.rowGap) {
                ForEach(0..<YouMetric.skeletonCards, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: Radius.tile).frame(height: AgendaMetric.row)
                }
            }
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(loading)
        }
    }
}

/// The cards, soonest first. A tap opens a card in place; a tap on the open card opens
/// its event page through `open`. One card is open at a time, and it is still open when
/// you come back from the page. The page owns the push, not these cards: leaving the
/// day's last Event from its page empties the day, and a push held here would close it.
struct AgendaCards: View {
    let events: [DailyEvent]
    let now: Date
    /// The time line says the day too ("Sat, Oct 17 · Noon"), for a list that spans days.
    var withDay = false
    var faces = false
    let open: (FeedCardItem) -> Void
    @State private var openID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        VStack(spacing: AgendaMetric.rowGap) {
            ForEach(events) { event in
                Button { tap(event) } label: {
                    AgendaCard(event: event, now: now, withDay: withDay,
                               friends: faces ? event.item.friendsGoing : [], open: openID == event.id)
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }

    /// What VoiceOver reads for a card, the words page's `agenda-friends-vo`: "Trivia Night,
    /// 7 PM, Anna and Ben are going", the Town card's friends line after the time, then what an
    /// open card adds.
    static func spoken(title: String, when: String, friends: [String], more: String) -> String {
        [title, when, RSVPWords.friendsLine(friends, bar: false), more]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// VoiceOver reads the whole card at once, so its first tap opens the page.
    private func tap(_ event: DailyEvent) {
        if openID == event.id || voiceOver {
            open(event.item)
        } else {
            withAnimation(reduceMotion ? nil : Motion.bentoExpand) { openID = event.id }
        }
    }
}

/// One card: the event's square photo, when it starts, and the title on one line.
/// Open, the title runs in full, the time runs to the end, the place shows, and an
/// arrow says another tap goes further.
private struct AgendaCard: View {
    let event: DailyEvent
    let now: Date
    let withDay: Bool
    /// Friends Going, the Town card's faces at the right of a closed card (ticket 07); an open
    /// card's arrow takes their place (Jesse, ticket 07 Check-in 1).
    let friends: [FeedFriend]
    let open: Bool
    /// How far off it is ("In 2 days"), at the right in place of the faces: the next plan's
    /// card (ticket 11).
    var pill: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let started = event.isOn(now)
        let card = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        HStack(alignment: .top, spacing: AgendaMetric.textGap) {
            Hue.fill
                .frame(width: AgendaMetric.photo, height: AgendaMetric.photo)
                .overlay { if let url = event.photo { FeedCardURLPhoto(url: url) } }
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            // Opening only adds below: the time and the title's first line stay put.
            VStack(alignment: .leading, spacing: 0) {
                // "Now" behind the Town card's green dot while it's on (Jesse, ticket 10 Check-in 1).
                HStack(spacing: PhotoChip.dotGap) {
                    if started {
                        Circle().fill(Hue.now).frame(width: PhotoChip.dotSide, height: PhotoChip.dotSide)
                    }
                    Text(when.text)
                        .font(started ? .sansMedium(13) : .sans(13))
                        .foregroundStyle(started ? Hue.ink : Hue.inkSecondary)
                }
                title
                if open {
                    VStack(alignment: .leading, spacing: 0) {
                        if event.timed { Text("Until \(DailyEvent.clock(event.ends))") }
                        if let place = event.item.location { Text(place) }
                    }
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.trailing, AgendaMetric.arrowRoom)
                    .transition(.opacity)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, AgendaMetric.textInset)
            .frame(maxWidth: .infinity, minHeight: AgendaMetric.photo, alignment: .topLeading)
            if let pill {
                // Centred on the photo, as far in from the card's edge as the faces.
                Text(pill)
                    .font(.sansSemibold(13))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, AgendaMetric.pillSide)
                    .frame(height: AgendaMetric.pill)
                    .background(Capsule().fill(Hue.fill))
                    .frame(height: AgendaMetric.photo)
                    .padding(.trailing, AgendaMetric.textGap - AgendaMetric.photoInset)
            }
        }
        .padding(AgendaMetric.photoInset)
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.trailing, AgendaMetric.textGap)
                .opacity(open ? 1 : 0)
                .scaleEffect(open ? 1 : 0.6)
        }
        .overlay(alignment: .trailing) {
            // A read that brings other friends fades the faces over, never pops them.
            if !friends.isEmpty {
                FriendFaces(friends: friends, ring: Hue.surface)
                    .id(friends)
                    .transition(.opacity)
                    .padding(.trailing, AgendaMetric.textGap)
                    .opacity(open ? 0 : 1)
            }
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: friends)
        // The lines an opening card adds start at their final place; this keeps them
        // inside the card while it grows to reach them.
        .clipShape(card)
        .background {
            card.fill(Hue.surface)
                .modifier(CardShadow())
                .overlay { card.strokeBorder(Hue.hairline, lineWidth: 0.5) }
        }
        .contentShape(card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgendaCards.spoken(title: event.item.title,
                                               when: [when.spoken, pill].compactMap { $0 }.joined(separator: ", "),
                                               friends: friends.map(\.name), more: more))
    }

    /// What the closed title leaves on its right for the faces: their width and their inset from
    /// the card's edge. The text already stops the card's inset short of that edge, so that much
    /// is left between the title and the faces.
    private var facesRoom: CGFloat {
        guard !friends.isEmpty else { return 0 }
        // `FriendFaces`, set in from the card's edge as far as the arrow, so they sit where it comes in.
        let step = FriendFaces.side - FriendFaces.overlap
        let faces = FriendFaces.side + step * CGFloat(min(friends.count, 3) - 1)
        return faces + AgendaMetric.textGap
    }

    /// When it starts: "Now" while it's on, else its time, or with `withDay` the Town
    /// card's when line from the organizer's own time ("Tonight · 7 PM"; an all-day Event
    /// shows only its day), and how VoiceOver reads it ("Saturday, October 17 at Noon").
    /// Beside the pill it's always the date, so "Tomorrow" never shows twice.
    private var when: (text: String, spoken: String) {
        if withDay, !event.isOn(now),
           let line = FeedWhenLine(eventDate: event.item.eventDate, startTime: event.item.startTime,
                                   now: now, calendar: YouCalendar.calendar, relative: pill == nil) {
            return (line.text, line.spoken)
        }
        let time = event.startTime(now: now)
        return (time, time)
    }

    /// What the open card adds, and VoiceOver always reads: "Until 11 AM, Lake Wobegon
    /// Trailhead". "Until" is a working word, from the mockup Jesse picked; he writes
    /// the final ones.
    private var more: String {
        [event.timed ? "Until \(DailyEvent.clock(event.ends))" : nil, event.item.location]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// The title, cut to one line until the card opens. The whole title fades in over
    /// the cut one while its frame grows down from the first line. It always leaves the
    /// arrow its room, so no width changes mid-spring and the words never reflow.
    private var title: some View {
        let text = Text(event.item.title).font(.sansSemibold(15)).foregroundStyle(Hue.ink)
        return ZStack(alignment: .topLeading) {
            text.lineLimit(1).padding(.trailing, facesRoom).opacity(open ? 0 : 1)
            text.fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, AgendaMetric.arrowRoom)
                .frame(height: open ? nil : 0, alignment: .top)
                .clipped()
                .opacity(open ? 1 : 0)
        }
    }
}
