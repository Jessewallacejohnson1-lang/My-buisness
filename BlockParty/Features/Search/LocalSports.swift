//
//  LocalSports.swift
//  Block Party — the sports on Search's Sports pill (BP app school-search 10): the sports the local schools play, each
//  with every team from high school up, read off the schools' activities. Jesse, 2026-11-16: "i want sports on top then
//  when you click into them you see teams", "any teams highschool and up". Mock: `references/sports-first/mock.html`.
//

import Foundation

/// One sport on the Sports pill: its name, Apple's symbol for it, and its teams, colleges first.
struct SportShelf: Hashable, Identifiable {
    let name: String
    let symbol: String
    let teams: [SportTeam]

    var id: String { name }
}

/// A team on a sport's page: its activity's row (opens the school's page, its star follows the activity) and what tells
/// it from the school's other teams of the sport ("Boys", "Girls", "Adapted"), empty when the school has one.
struct SportTeam: Hashable, Identifiable {
    let item: SearchItem
    let school: String
    let variant: String

    var id: String { item.id }
}

enum LocalSports {
    enum Season: Int, CaseIterable {
        case fall, winter, spring

        /// Minnesota's school seasons: fall to the end of October, winter to the end of February, spring after.
        static func of(_ date: Date, calendar: Calendar = Town.calendar) -> Season {
            switch calendar.component(.month, from: date) {
            case 3...6: .spring
            case 7...10: .fall
            default: .winter
            }
        }
    }

    struct Sport {
        let name: String
        let symbol: String
        let season: Season
        /// The words in an activity's name that make it this sport, each matched whole ("ski", never "Skills").
        let words: [String]
    }

    /// Every sport at least 5 local schools play (2026-11-16), in each season's order. A sport shows only with a team.
    static let all: [Sport] = [
        Sport(name: "Basketball", symbol: "figure.basketball", season: .winter, words: ["basketball"]),
        Sport(name: "Hockey", symbol: "figure.hockey", season: .winter, words: ["hockey"]),
        Sport(name: "Wrestling", symbol: "figure.wrestling", season: .winter, words: ["wrestling"]),
        Sport(name: "Swim & Dive", symbol: "figure.pool.swim", season: .winter, words: ["swim", "swimming"]),
        Sport(name: "Skiing", symbol: "figure.skiing.downhill", season: .winter, words: ["ski", "skiing"]),
        Sport(name: "Gymnastics", symbol: "figure.gymnastics", season: .winter, words: ["gymnastics"]),
        Sport(name: "Football", symbol: "figure.american.football", season: .fall, words: ["football"]),
        Sport(name: "Volleyball", symbol: "figure.volleyball", season: .fall, words: ["volleyball"]),
        Sport(name: "Soccer", symbol: "figure.soccer", season: .fall, words: ["soccer"]),
        Sport(name: "Cross Country", symbol: "figure.run", season: .fall, words: ["cross country"]),
        Sport(name: "Baseball", symbol: "figure.baseball", season: .spring, words: ["baseball"]),
        Sport(name: "Softball", symbol: "figure.softball", season: .spring, words: ["softball"]),
        Sport(name: "Track & Field", symbol: "figure.track.and.field", season: .spring, words: ["track"]),
        Sport(name: "Golf", symbol: "figure.golf", season: .spring, words: ["golf"]),
        Sport(name: "Tennis", symbol: "figure.tennis", season: .spring, words: ["tennis"]),
        Sport(name: "Lacrosse", symbol: "figure.lacrosse", season: .spring, words: ["lacrosse"]),
    ]

    /// The sports in the order the pill shows them: this season's first, then the next, then the one after.
    static func ordered(now: Date) -> [Sport] {
        let first = Season.of(now).rawValue, count = Season.allCases.count
        func after(_ sport: Sport) -> Int { (sport.season.rawValue - first + count) % count }
        // Stable: each season keeps the order it is written in.
        return all.enumerated().sorted { a, b in
            (after(a.element), a.offset) < (after(b.element), b.offset)
        }.map(\.element)
    }

    /// The sport an activity's name is, if any: the first in `all` with a word of the name, whole.
    static func sport(of activity: String) -> Sport? {
        let words = activity.lowercased().split { !$0.isLetter }.map(String.init)
        let joined = words.joined(separator: " ")
        return all.first { sport in
            sport.words.contains { word in
                word.contains(" ") ? (" " + joined + " ").contains(" " + word + " ") : words.contains(word)
            }
        }
    }

    /// The words that tell a team from its school's others: the name without the sport, Boys or Girls first.
    /// "Alpine Skiing - Boys" is "Boys Alpine"; "Volleyball (girls)" is "Girls"; Saint Ben's "Basketball" is "".
    static func variant(of activity: String, sport: Sport) -> String {
        let dropped: Set = ["and", "dive", "diving", "field", "racing", "sports", "sju", "fastpitch", "country"]
        var seen = Set<String>()
        let kept = activity.split { !$0.isLetter }.map(String.init).filter { word in
            let low = word.lowercased()
            guard !dropped.contains(low), !sport.words.flatMap({ $0.split(separator: " ").map(String.init) }).contains(low),
                  seen.insert(low).inserted else { return false }
            return true
        }
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let gender = kept.filter { ["Boys", "Girls"].contains($0) }
        return (gender + kept.filter { !gender.contains($0) }).joined(separator: " ")
    }

    /// Each sport with a team, this season's first; its teams are the activities of schools from high school up,
    /// colleges first, then A to Z by the school's short name, then by what tells them apart.
    /// - Parameters:
    ///   - activities: the schools' activity rows (`SearchModel.schools`), each with its team.
    ///   - level: each school's level by its team's id, nil for a school that is neither college nor high school.
    static func shelves(_ activities: [SearchItem], level: (String) -> SearchModel.DiscLevel?, now: Date) -> [SportShelf] {
        var teams: [String: [(level: SearchModel.DiscLevel, team: SportTeam)]] = [:]
        for item in activities where item.activity != nil {
            guard let team = item.team, let id = team.id, let at = level(id), at != .other, let sport = sport(of: item.name) else { continue }
            teams[sport.name, default: []].append((at, SportTeam(item: item, school: team.short,
                                                                  variant: variant(of: item.name, sport: sport))))
        }
        return ordered(now: now).compactMap { sport in
            guard let found = teams[sport.name], !found.isEmpty else { return nil }
            let sorted = found.sorted { a, b in
                if a.level != b.level { return a.level < b.level }
                let school = a.team.school.localizedStandardCompare(b.team.school)
                if school != .orderedSame { return school == .orderedAscending }
                return a.team.variant.localizedStandardCompare(b.team.variant) == .orderedAscending
            }
            return SportShelf(name: sport.name, symbol: sport.symbol, teams: sorted.map(\.team))
        }
    }
}
