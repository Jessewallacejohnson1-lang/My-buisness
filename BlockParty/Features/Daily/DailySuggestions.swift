//
//  DailySuggestions.swift
//  Block Party — Daily's Suggestions and Friends are going: the day's events that match your
//  interests, and the ones friends are going to, as rows of Town cards (`DailyRows.swift`;
//  `docs/plans/daily-tab/SPEC.md` §4 and tickets 20 and 21 in the BP app folder).
//

import SwiftUI

extension DailyEvent {
    /// DEBUG `-daily-samples`: the sample Suggestions, in place of the Town feed's
    /// (`suggestions(from:…)`, daily-tab 20). nil otherwise.
    static func sampleSuggestions(now: Date) -> [DailyEvent]? {
        #if DEBUG
        return DailySamples.on ? suggestionSamples(on: now) : nil
        #else
        return nil
        #endif
    }

    /// DEBUG `-daily-samples`: three of the sample Suggestions with friends going, in place of the
    /// Town feed's (`friendsGoing(from:…)`, daily-tab 21). nil otherwise. INVENTED names.
    static func sampleFriendsGoing(now: Date) -> [DailyEvent]? {
        #if DEBUG
        guard DailySamples.on else { return nil }
        let names = [["Kim", "Tom", "Joe"], ["Ana", "Ben"], ["Sam"]]
        return zip(suggestionSamples(on: now).suffix(3), names).map { event, names in
            var event = event
            event.item.friendsGoing = names.map { FeedFriend(name: $0, photo: nil) }
            return event
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// INVENTED: seven events today at real St. Joseph places, with the bundled town
    /// photos. Titles, hosts and times are made up.
    static func suggestionSamples(on date: Date) -> [DailyEvent] {
        let calendar = Town.gregorian
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

/// The section: "For you today" over a row of the smaller Town cards (Jesse at daily-tab 20's
/// Check-in 1; it was Airbnb's "Happening today" row under a "Suggestions" label).
struct SuggestionsSection: View {
    let events: [DailyEvent]
    let now: Date

    var body: some View {
        DailyCardRow(title: "For you today", events: events, size: DailyRowMetric.suggestionSize,
                     titleSize: DailyRowMetric.suggestionTitle, showsFriends: false, now: now)
    }
}

/// Friends are going: the bigger Town cards, the friends' faces on each (daily-tab 21).
struct FriendsGoingSection: View {
    let events: [DailyEvent]
    let now: Date

    var body: some View {
        DailyCardRow(title: "Friends are going", events: events, size: DailyRowMetric.friendsSize,
                     titleSize: DailyRowMetric.friendsTitle, showsFriends: true, now: now)
    }
}
