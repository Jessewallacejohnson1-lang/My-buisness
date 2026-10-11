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
}

/// The cards, soonest first. A tap opens a card in place; a tap on the open card opens
/// its event page through `open`. One card is open at a time, and it is still open when
/// you come back from the page. The page owns the push, not these cards: leaving the
/// day's last Event from its page empties the day, and a push held here would close it.
struct AgendaCards: View {
    let events: [DailyEvent]
    let now: Date
    let open: (FeedCardItem) -> Void
    @State private var openID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        VStack(spacing: AgendaMetric.rowGap) {
            ForEach(events) { event in
                Button { tap(event) } label: {
                    AgendaCard(event: event, now: now, open: openID == event.id)
                }
                .buttonStyle(PressableCardStyle())
            }
        }
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
    let open: Bool

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
                Text(event.startTime(now: now))
                    .font(started ? .sansMedium(13) : .sans(13))
                    .foregroundStyle(started ? Hue.ink : Hue.inkSecondary)
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
        .accessibilityLabel([event.item.title, event.startTime(now: now), more].joined(separator: ", "))
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
            text.lineLimit(1).opacity(open ? 0 : 1)
            text.fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, AgendaMetric.arrowRoom)
                .frame(height: open ? nil : 0, alignment: .top)
                .clipped()
                .opacity(open ? 1 : 0)
        }
    }
}
