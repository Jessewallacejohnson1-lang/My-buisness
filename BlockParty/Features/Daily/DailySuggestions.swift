//
//  DailySuggestions.swift
//  Block Party — Daily's fourth section: today's events that match your interests, in a
//  sideways row (`docs/plans/daily-tab/SPEC.md` §4 in the BP app folder).
//

import SwiftUI

extension DailyEvent {
    /// Today's events that match your interests. There is no read for them yet, so a
    /// release build gets none, which hides the section, and DEBUG gets the samples. When
    /// the read exists, this is the one function that changes. A quiet day's standing
    /// things (the trail, a park) wait for a real list of places (Jesse, 2026-10-05).
    static func suggestions(now: Date) -> [DailyEvent] {
        #if DEBUG
        return suggestionSamples(on: now)
        #else
        return []
        #endif
    }

    #if DEBUG
    /// INVENTED: seven events today at real St. Joseph places, with the bundled town
    /// photos. Titles, hosts and times are made up.
    static func suggestionSamples(on date: Date) -> [DailyEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let day = calendar.startOfDay(for: date)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        return [
            sample(id: "daily-s1", title: "Bird walk in the Arboretum", host: "Saint John's Arboretum",
                   photo: "sju-arboretum-trail", place: "Saint John's Arboretum",
                   starts: at(7.5), ends: at(9), category: .outdoors,
                   description: "An easy walk with binoculars to share. Meet at the Abbey parking lot."),
            sample(id: "daily-s2", title: "Kids' fishing morning at Rivers Bend", host: "St. Joseph Parks & Rec",
                   photo: "rivers-bend-park", place: "Rivers Bend Park",
                   starts: at(10), ends: at(12), category: .families,
                   description: "Poles and bait for anyone who needs them. Kids under 16 fish free."),
            sample(id: "daily-s3", title: "Yoga in Centennial Park", host: "St. Joseph Parks & Rec",
                   photo: "centennial-park", place: "Centennial Park",
                   starts: at(12), ends: at(13), category: .sports,
                   description: "An hour of gentle yoga on the grass. Bring a mat or a towel."),
            sample(id: "daily-s4", title: "Walk to Stella Maris Chapel", host: "College of Saint Benedict",
                   photo: "chapel-trail-stella-maris", place: "Stella Maris Chapel",
                   starts: at(15), ends: at(16.5), category: .outdoors,
                   description: "Across the lake and up to the chapel, about two miles there and back."),
            sample(id: "daily-s5", title: "Millstream art walk", host: "St. Joseph Arts Council",
                   photo: "millstream-arts-festival", place: "Downtown St. Joseph",
                   starts: at(17), ends: at(20), category: .musicArts,
                   description: "Local artists set up along Minnesota Street with work for sale."),
            sample(id: "daily-s6", title: "Trivia night at Bad Habit Brewing", host: "Bad Habit Brewing",
                   photo: "bad-habit-brewing", place: "Bad Habit Brewing",
                   starts: at(18.5), ends: at(20.5), category: .games,
                   description: "Teams of up to six. Three rounds, and the winners pick next week's theme."),
            sample(id: "daily-s7", title: "Sunset on the boardwalk loop", host: "Saint John's Arboretum",
                   photo: "boardwalk-loop-trail", place: "Boardwalk Loop Trail",
                   starts: at(19.5), ends: at(20.5), category: .outdoors,
                   description: "A slow walk out over the marsh as the sun goes down."),
        ]
    }
    #endif
}

/// The section: its label, then Airbnb's "Happening today" row, copied 1:1 (Jesse,
/// 2026-10-05): photo cards the finger slides sideways, each stopping at the margin.
struct SuggestionsSection: View {
    let events: [DailyEvent]
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            DailySectionLabel(title: "Suggestions", ink: Hue.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DailyMetric.suggestionGap) {
                    ForEach(events) { event in
                        SuggestionCard(event: event, now: now)
                    }
                }
                .scrollTargetLayout()
                // A finished event's card closes up instead of vanishing.
                .animation(reduceMotion ? nil : Motion.smooth, value: events.map(\.id))
            }
            .contentMargins(.horizontal, DailyMetric.side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            // The photos' shadows reach past the row; don't cut them off.
            .scrollClipDisabled()
            .padding(.top, DailyMetric.eventLabelToCard)
        }
    }
}

/// One card: the photo with when it starts and the save bookmark on it, then the title
/// on up to two lines, the place, and who hosts it.
private struct SuggestionCard: View {
    let event: DailyEvent
    let now: Date

    var body: some View {
        NavigationLink(value: event.item) {
            VStack(alignment: .leading, spacing: 0) {
                Hue.fill
                    .frame(width: DailyMetric.suggestionWidth, height: DailyMetric.suggestionPhoto)
                    .overlay { if let url = event.photo { FeedCardURLPhoto(url: url) } }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.bento, style: .continuous))
                    .modifier(CardShadow())
                    .overlay(alignment: .topLeading) { chip.padding(DailyMetric.suggestionChipInset) }
                VStack(alignment: .leading, spacing: DailyMetric.suggestionLineGap) {
                    // 13, Airbnb's title size, the same as the grey lines under it.
                    Text(event.item.title)
                        .font(.sansSemibold(13))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(2)
                    Group {
                        if let place = event.item.location { Text(place) }
                        if let host { Text("Hosted by \(host)") }
                    }
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineLimit(1)
                }
                .padding(.top, DailyMetric.suggestionTitleTop)
                .padding(.horizontal, DailyMetric.suggestionTextInset)
            }
            .multilineTextAlignment(.leading)
            .frame(width: DailyMetric.suggestionWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        // The title first; drawn, the time comes before it.
        .accessibilityLabel([event.item.title, event.startTime(now: now), event.item.location,
                             host.map { "Hosted by \($0)" }].compactMap { $0 }.joined(separator: ", "))
        // The bookmark answers its own taps, over the link, never opening the page.
        .overlay(alignment: .topTrailing) {
            SaveBookmarkButton(id: event.id).padding(DailyMetric.suggestionSaveInset)
        }
    }

    /// Who hosts it, unless that is the place again ("Saint John's Arboretum" twice).
    private var host: String? {
        let name = event.item.hostName
        return name.isEmpty || name == event.item.location ? nil : name
    }

    private var chip: some View {
        Text(event.startTime(now: now))
            .font(.sansMedium(13))
            .foregroundStyle(Hue.ink)
            .padding(.horizontal, DailyMetric.suggestionChipPadding)
            .frame(minHeight: DailyMetric.suggestionChipHeight)
            .background(Capsule().fill(Hue.surface))
    }
}
