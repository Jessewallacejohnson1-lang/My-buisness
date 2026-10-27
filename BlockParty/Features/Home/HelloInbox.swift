//
//  HelloInbox.swift
//  Block Party — the hello pill's memory (BP app docs/plans/hello-drop, ticket 05): each new
//  thing it has to say (a contact who joined, a followed team's final, a first or a milestone),
//  kept on the phone so the pill says it once, on an open, at most 3 pills a day and an hour
//  apart, and the bell's page lists it for 7 days. The day's lines (your event today, the counts,
//  town news) are never items: the pill works them out each morning and the bell never shows them.
//

import Foundation

/// Something new for you: the pill says it once, and the bell's page keeps it 7 days.
struct HelloItem: Codable, Hashable, Identifiable {
    /// Every kind says how the pill and the bell show it (`message`, `row`), so a new kind
    /// without both doesn't build (Jesse, 2026-10-27).
    enum What: Codable, Hashable {
        /// A contact who joined (hello-drop 04), as they were when found.
        // ponytail: their relation is the one read then; a friend made since shows Add friend
        // on the row until their page is opened.
        case joined(Neighbor)
        /// A followed team's final (hello-drop 03).
        case final(Final)
        /// A first or a milestone (hello-drop 02).
        case moment(HelloMoment)
    }

    /// A final as the pill says it.
    struct Final: Codable, Hashable {
        let eventId: String
        /// "Johnnies", in bold on the bell.
        let team: String
        /// "Johnnies beat Gusties 33–23".
        let text: String
        let logo: URL?
        let tint: UInt32?
        let confetti: [UInt32]?
        /// The team's own name and id, for its page; nil for a team with none (hello-drop 03).
        let page: Page?

        struct Page: Codable, Hashable {
            let id: String
            let name: String
        }

        /// nil when it can't be worded.
        init?(_ final: TeamFinal) {
            guard let said = HelloDrop.final(final), let team = final.team else { return nil }
            eventId = final.eventId
            self.team = team.called
            text = said.text
            logo = said.logo
            tint = said.tint
            confetti = said.confetti
            page = team.hasPage ? team.id.map { Page(id: $0, name: team.name) } : nil
        }

        /// Its page, as Following opens it: the page reads the rest.
        var teamPage: Game.Team? {
            page.map { Game.Team(followed: FollowRow(targetType: .team, targetId: $0.id, name: $0.name, kind: nil,
                                                     picture: logo?.absoluteString, pictureKind: nil)) }
        }
    }

    /// The bell's round picture: their photo, the team's logo on white, or the green tick.
    enum Picture: Hashable {
        case photo(String?)
        case logo(URL?)
        case tick
    }

    let what: What
    /// When it happened, as near as the phone knows: a contact's join, else when it was found.
    // ponytail: a final is stamped when found, so after days away it reads "now"; keep the
    // game's time on the read if that matters.
    let at: Date
    /// The pill said it, or the bell's page showed it: the pill never says it again.
    var told = false

    var id: String {
        switch what {
        case .joined(let person): "joined:\(person.userId)"
        case .final(let final): "final:\(final.eventId)"
        case .moment(let moment): "moment:\(moment.rawValue)"
        }
    }

    /// Which the pill says first when two wait: firsts and milestones, finals, then who joined.
    var rank: Int {
        switch what {
        case .moment: 0
        case .final: 1
        case .joined: 2
        }
    }

    /// The pill's line; nil for a first or milestone, which the pill draws with its tick.
    var message: HelloDrop.Message? {
        switch what {
        case .joined(let person): HelloDrop.joined(person)
        case .final(let final):
            HelloDrop.Message(text: final.text, target: .town, logo: final.logo, tint: final.tint,
                              confetti: final.confetti)
        case .moment: nil
        }
    }

    /// The bell's row: who in bold, what happened, and the picture beside them.
    var row: (name: String, words: String, picture: Picture) {
        switch what {
        case .joined(let person):
            (person.displayName, "joined Block Party.", .photo(person.avatarUrl))
        case .final(let final):
            (final.team, (final.text.hasPrefix(final.team + " ") ? String(final.text.dropFirst(final.team.count + 1))
                          : final.text) + ".", .logo(final.logo))
        case .moment(let moment):
            ("You", moment.text.prefix(1).lowercased() + moment.text.dropFirst(), .tick)
        }
    }
}

/// The items found, and when the pill last dropped. The pill and the bell's page read the one.
@MainActor @Observable
final class HelloInbox {
    static let shared: HelloInbox = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // `-notice-samples`: the mock's items beside the bell's sample changes.
        if arguments.contains("-notice-samples") {
            let inbox = HelloInbox(keep: UserDefaults(suiteName: "NoticeSamples") ?? .standard)
            inbox.items = samples(now: Date())
            return inbox
        }
        // `-hello-later`: a clean phone, so the run's own pills are the only ones counted.
        if HelloDrop.later {
            UserDefaults(suiteName: "HelloLater")?.removePersistentDomain(forName: "HelloLater")
            return HelloInbox(keep: UserDefaults(suiteName: "HelloLater") ?? .standard)
        }
        #endif
        return HelloInbox()
    }()

    /// At most 3 pills a day, at least an hour apart (Jesse, 2026-10-27).
    static let perDay = 3
    static let apart: TimeInterval = 3600
    /// The bell keeps an item 7 days, its "Last 7 days".
    static let days = 7

    /// Oldest first.
    private(set) var items: [HelloItem]
    /// When the pill dropped, oldest first: the last day's.
    private var pills: [Date]
    private let keep: UserDefaults
    static let itemsKey = "helloDrop.inbox"
    static let pillsKey = "helloDrop.pills"

    /// Read back from the phone, less any past 7 days.
    // ponytail: pruned at launch and on each find; an app left open a week keeps an old one till then.
    init(keep: UserDefaults = .standard, now: Date = Date()) {
        self.keep = keep
        items = (keep.data(forKey: Self.itemsKey).flatMap { try? JSONDecoder().decode([HelloItem].self, from: $0) } ?? [])
            .filter { Town.days(from: $0.at, to: now) < Self.days }
        pills = (keep.array(forKey: Self.pillsKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    /// Something found, `at` when it happened. One already here, said or not, stays as it was;
    /// any past 7 days go.
    func add(_ what: HelloItem.What, at: Date = Date(), now: Date? = nil) {
        let now = now ?? at
        let item = HelloItem(what: what, at: at)
        items.removeAll { Town.days(from: $0.at, to: now) >= Self.days }
        if !items.contains(where: { $0.id == item.id }), Town.days(from: at, to: now) < Self.days { items.append(item) }
        save()
    }

    /// Today's contacts check: anyone kept who isn't in it any more is a friend now, asked, or
    /// blocked, so neither the pill nor the bell names them as new (taste/town.md, 2026-10-26).
    func keepJoined(_ still: Set<String>) {
        let before = items.count
        items.removeAll { if case .joined(let person) = $0.what { !still.contains(person.userId) } else { false } }
        if items.count != before { save() }
    }

    /// The one the pill says next: the highest kind, the oldest of it first.
    var next: HelloItem? {
        items.filter { !$0.told }.min { $0.rank < $1.rank }
    }

    /// The bell's rows, newest first.
    func recent(now: Date) -> [HelloItem] {
        items.filter { Town.days(from: $0.at, to: now) < Self.days }.reversed()
    }

    /// The pill said it; `false` when the app went away before it could be read.
    func tell(_ id: String, _ told: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].told = told
        save()
    }

    /// The bell's page showed them all: the pill says none of them now.
    func toldAll() {
        guard next != nil else { return }
        for index in items.indices { items[index].told = true }
        save()
    }

    /// Fewer than 3 pills today, and the last one, any day, an hour ago or more: so 11:50 PM and
    /// 12:05 AM aren't two.
    func mayDrop(now: Date) -> Bool {
        pills.filter { Town.day($0) == Town.day(now) }.count < Self.perDay
            && pills.last.map { now.timeIntervalSince($0) >= Self.apart } ?? true
    }

    func dropped(now: Date) {
        pills = (pills + [now]).filter { now.timeIntervalSince($0) < 86_400 }
        keep.set(pills.map(\.timeIntervalSince1970), forKey: Self.pillsKey)
    }

    private func save() {
        keep.set(try? JSONEncoder().encode(items), forKey: Self.itemsKey)
    }

    #if DEBUG
    /// INVENTED: the mock's items (BP app references/pill-notifications), with Saint John's real
    /// logo. Every name and score is made up.
    static func samples(now: Date) -> [HelloItem] {
        let sam = Neighbor(userId: "sample-sam", displayName: "Sam Rivera", avatarUrl: nil, since: nil,
                           relation: .stranger, mutualFriends: 0)
        var items = [HelloItem(what: .moment(.firstEvent), at: now - 26 * 3600, told: true)]
        if let final = HelloItem.Final(TeamFinal.sample(won: true)) {
            items.append(HelloItem(what: .final(final), at: now - 5 * 3600, told: true))
        }
        items.append(HelloItem(what: .joined(sam), at: now - 2 * 3600))
        return items
    }
    #endif
}
