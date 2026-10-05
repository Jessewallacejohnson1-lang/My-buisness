//
//  DailyAgenda.swift
//  Block Party — Daily's third section: today's events you're going to, saved, or your
//  clubs' (`docs/plans/daily-tab/SPEC.md` §3 in the BP app folder).
//

import SwiftUI

extension DailyEvent {
    /// Today's events you're signed up for: the ones you tapped Going on, saved, or your
    /// joined clubs'. There is no read for them yet, so a release build gets none, which
    /// hides the section, and DEBUG gets the samples. When the read exists, this is the
    /// one function that changes.
    static func agenda(now: Date) -> [DailyEvent] {
        #if DEBUG
        return agendaSamples(on: now)
        #else
        return []
        #endif
    }

    /// What the Agenda shows: the ones on now or still to come, soonest first, leaving
    /// out any that Event of the day already shows. A finished one drops off.
    static func agendaShowing(_ events: [DailyEvent], now: Date,
                              eventOfTheDay: [DailyEvent]) -> [DailyEvent] {
        let shown = Set(eventOfTheDay.map(\.id))
        return events.filter { $0.ends > now && !shown.contains($0.id) }
            .sorted { $0.starts < $1.starts }
    }

    /// The card's time: "Now" once it has started, else when it starts ("9 AM",
    /// "7:30 PM"), in the Town's time. Working words; Jesse writes the final ones.
    func startTime(now: Date) -> String {
        starts > now ? Self.clock(starts) : "Now"
    }

    /// "9 AM" or "7:30 PM" in the Town's time: minutes only when there are some.
    static func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        return townTime(calendar.component(.minute, from: date) == 0 ? "h" : "hmm", date)
    }

    /// `date` written from a date template ("EEE", "d", "h"), in English, in the Town's time.
    static func townTime(_ template: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    #if DEBUG
    /// INVENTED: four events today at real St. Joseph places, with the bundled town
    /// photos. Two titles are the Town feed's fixtures (`DailyFixtures`), one long on
    /// purpose; the knitting circle and every time are made up.
    static func agendaSamples(on date: Date) -> [DailyEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let day = calendar.startOfDay(for: date)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        return [
            sample(id: "daily-a1",
                   title: "Fire Department pancake breakfast and open house at the St. Joseph fire hall",
                   host: "St. Joseph Fire Department", photo: "downtown", place: "St. Joseph Fire Hall",
                   starts: at(7), ends: at(10), category: .food,
                   description: "Pancakes, sausage and coffee, then a look inside the trucks. Free will offering."),
            sample(id: "daily-a2", title: "Trail cleanup morning", host: "Wobegon Trail Association",
                   photo: "wobegon-trail", place: "Lake Wobegon Trailhead",
                   starts: at(9), ends: at(11), category: .service,
                   description: "Meet at the trailhead. We'll have gloves, bags, grabbers and coffee."),
            sample(id: "daily-a3", title: "Afternoon knitting circle", host: "The Local Blend",
                   photo: "the-local-blend", place: "The Local Blend",
                   starts: at(14), ends: at(15.5), category: .other,
                   description: "Bring what you're working on. Beginners welcome; there's spare yarn."),
            sample(id: "daily-a4", title: "Saint Ben's spring choral concert", host: "College of Saint Benedict",
                   photo: "sacred-heart-chapel", place: "Sacred Heart Chapel",
                   starts: at(19.5), ends: at(21), category: .musicArts,
                   description: "The college choirs sing their spring program in Sacred Heart Chapel."),
        ]
    }
    #endif
}

/// The section: its label, then today as Airbnb's day plan draws it, the day once on the
/// left with a line down beside the cards. A tap opens a card in place; a tap on the
/// open card opens its event page. One card is open at a time, and it is still open
/// when you come back from the page.
struct AgendaSection: View {
    let events: [DailyEvent]
    let now: Date
    @State private var openID: String?
    @State private var pushed: FeedCardItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// Stays in the page with no events too, empty and with no height, so an event page
    /// it opened stays open when that event ends under it.
    var body: some View {
        VStack(spacing: 0) {
            if !events.isEmpty { section }
        }
        .navigationDestination(item: $pushed) { FeedEventDetailDestination(item: $0) }
    }

    private var section: some View {
        VStack(spacing: 0) {
            DailySectionLabel(title: "Agenda", ink: Hue.ink)
            VStack(spacing: DailyMetric.agendaRowGap) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: DailyMetric.agendaRailGap) {
                        AgendaRail(day: index == 0 ? now : nil,
                                   lineIn: index > 0, lineOut: index < events.count - 1)
                        Button { tap(event) } label: {
                            AgendaCard(event: event, now: now, open: openID == event.id)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                    // The rail runs as tall as its card.
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            // A finished event closes up instead of vanishing.
            .animation(reduceMotion ? nil : Motion.bentoExpand, value: events.map(\.id))
            .padding(.top, DailyMetric.eventLabelToCard)
            .padding(.horizontal, DailyMetric.side)
        }
        .padding(.top, DailyMetric.eventSectionTop)
    }

    /// VoiceOver reads the whole card at once, so its first tap opens the page.
    private func tap(_ event: DailyEvent) {
        if openID == event.id || voiceOver {
            pushed = event.item
        } else {
            withAnimation(reduceMotion ? nil : Motion.bentoExpand) { openID = event.id }
        }
    }
}

/// The left of a row: the line joining the cards' middles and, beside the first card,
/// the day: "Fri" over the date in a grey circle.
private struct AgendaRail: View {
    /// Set on the first row only.
    let day: Date?
    let lineIn: Bool
    let lineOut: Bool

    var body: some View {
        VStack(spacing: 0) {
            line.frame(height: DailyMetric.agendaRow / 2).opacity(lineIn ? 1 : 0)
            // Down through the gap to the next card's line.
            line.padding(.bottom, -DailyMetric.agendaRowGap).opacity(lineOut ? 1 : 0)
        }
        .frame(width: DailyMetric.agendaDay)
        .overlay(alignment: .top) {
            if let day {
                VStack(spacing: DailyMetric.agendaDayToCircle) {
                    Text(DailyEvent.townTime("EEE", day))
                        .font(.sansBold(12))
                        .foregroundStyle(Hue.ink)
                    Text(DailyEvent.townTime("d", day))
                        .font(.sansMedium(14))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(width: DailyMetric.agendaDay, height: DailyMetric.agendaDay)
                        .background(Circle().fill(Hue.hairline))
                }
                .frame(height: DailyMetric.agendaRow)
            }
        }
        .accessibilityHidden(true)
    }

    private var line: some View {
        Hue.hairline.frame(width: 1)
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
        let started = event.starts <= now
        let card = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        HStack(alignment: .top, spacing: DailyMetric.agendaTextGap) {
            Hue.fill
                .frame(width: DailyMetric.agendaPhoto, height: DailyMetric.agendaPhoto)
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
                        Text("Until \(DailyEvent.clock(event.ends))")
                        if let place = event.item.location { Text(place) }
                    }
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.trailing, DailyMetric.agendaArrowRoom)
                    .transition(.opacity)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, DailyMetric.agendaTextInset)
            .frame(maxWidth: .infinity, minHeight: DailyMetric.agendaPhoto, alignment: .topLeading)
        }
        .padding(DailyMetric.agendaPhotoInset)
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.trailing, DailyMetric.agendaTextGap)
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
        ["Until \(DailyEvent.clock(event.ends))", event.item.location].compactMap { $0 }.joined(separator: ", ")
    }

    /// The title, cut to one line until the card opens. The whole title fades in over
    /// the cut one while its frame grows down from the first line. It always leaves the
    /// arrow its room, so no width changes mid-spring and the words never reflow.
    private var title: some View {
        let text = Text(event.item.title).font(.sansSemibold(15)).foregroundStyle(Hue.ink)
        return ZStack(alignment: .topLeading) {
            text.lineLimit(1).opacity(open ? 0 : 1)
            text.fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, DailyMetric.agendaArrowRoom)
                .frame(height: open ? nil : 0, alignment: .top)
                .clipped()
                .opacity(open ? 1 : 0)
        }
    }
}
