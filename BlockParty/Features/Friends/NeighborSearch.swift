//
//  NeighborSearch.swift
//  Block Party — finding a neighbour by name (BP app docs/plans/friends, ticket 02). The
//  Friends page's search and Search's People section each hold one. Only a real account
//  asks the server (`search_neighbors`); an Anonymous one is asked to log in instead.
//

import SwiftUI

/// A neighbour as search and their page show them: never Anonymous, always named.
struct Neighbor: Identifiable, Hashable, Decodable {
    /// Where the two of you stand, as the server last said (ticket 03). `blocked` is only ever
    /// yours on them (ticket 04): theirs on you reads as nobody at all.
    enum Relation: String, Decodable, Hashable {
        case stranger = "none", sent, received, friends, blocked
    }

    let userId: String
    let displayName: String
    let avatarUrl: String?
    /// When they became a neighbour, as the server stores it.
    let since: String?
    var relation: Relation
    var mutualFriends: Int
    /// When you became friends, as the server stores it; nil when you aren't (ticket 04).
    var friendsSince: String? = nil
    var id: String { userId }

    /// "Neighbor since October 2026", as the neighbour's own Profile says it.
    var sinceLine: String? { ProfileModel.since(from: since).map { "Neighbor since \($0)" } }

    /// `suggest-reason`: "1 mutual friend", "4 mutual friends", nothing at none.
    var mutualLine: String? {
        mutualFriends == 0 ? nil : mutualFriends == 1 ? "1 mutual friend" : "\(mutualFriends) mutual friends"
    }
}

@MainActor @Observable
final class NeighborSearch {
    enum State: Equatable {
        /// Nothing typed.
        case idle
        /// Asking, with nothing found yet for these words.
        case loading
        case found([Neighbor])
        case none
        /// An Anonymous account: `people-login`.
        case needsAccount
        /// The ask failed (offline); the next keystroke asks again.
        case failed

        /// Something to list: people, the line asking to log in, or the one saying the ask
        /// failed.
        var hasRows: Bool {
            switch self {
            case .found, .needsAccount, .failed: true
            default: false
            }
        }
    }

    private(set) var state = State.idle

    /// How long typing pauses before the server is asked. (guessed)
    static let pause: Duration = .milliseconds(250)

    private let find: (String) async throws -> [Neighbor]
    private let isAnonymous: () -> Bool
    @ObservationIgnored private var asking: Task<Void, Never>?

    init(find: @escaping (String) async throws -> [Neighbor], isAnonymous: @escaping () -> Bool) {
        self.find = find
        self.isAnonymous = isAnonymous
    }

    /// Asks Supabase; under DEBUG `-town-samples` the sample neighbours answer instead, and
    /// under `-town-offline` every ask fails (`RealLifeActions.backend`).
    convenience init() {
        switch RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) {
        case .live:
            // No session is no account either: offline at first launch, or a failed one.
            self.init(find: { try await CommunityAPI(auth: AuthStore.shared).searchNeighbors($0) },
                      isAnonymous: { !AuthStore.shared.isSignedIn || AuthStore.shared.isAnonymous })
        case .samples:
            self.init(find: { Self.samples(matching: $0) }, isAnonymous: { false })
        case .offline:
            self.init(find: { _ in throw URLError(.notConnectedToInternet) }, isAnonymous: { false })
        }
    }

    /// The words typed so far. Results for older words never land over newer ones.
    func search(_ words: String) {
        asking?.cancel()
        // An Anonymous account is asked to log in before it types anything.
        guard !isAnonymous() else { state = .needsAccount; return }
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { state = .idle; return }
        // What was found, or that nothing was, stays up while the next words are asked
        // about, as iOS search does, so it doesn't blink on every letter.
        switch state {
        case .found, .none: break
        default: state = .loading
        }
        asking = Task { [find] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            do {
                let people = try await find(words)
                guard !Task.isCancelled else { return }
                state = people.isEmpty ? .none : .found(people)
            } catch {
                if !Task.isCancelled { state = .failed }
            }
        }
    }

    /// The sample neighbours (`Neighbor.samples`), matched as `search_neighbors` matches: the
    /// name, or a later word, starts with the words.
    static func samples(matching words: String) -> [Neighbor] {
        let words = words.lowercased()
        return Neighbor.samples.filter { n in
            guard n.relation != .blocked else { return false }
            let name = n.displayName.lowercased()
            return name.hasPrefix(words) || name.split(separator: " ").contains { $0.hasPrefix(words) }
        }
    }
}

extension Neighbor {
    #if DEBUG
    /// INVENTED, for `-town-samples`: neighbours on bundled town photos (one without a photo),
    /// two asking you, three friends, one you asked, two you blocked.
    static let samples: [Neighbor] = [
        ("Sam Rivera", "centennial-park", Relation.friends, 1), ("Sarah Lindgren", "farmers-market", .received, 2),
        ("Ana Samuels", "saint-bens", .stranger, 1), ("Marlene Ostendorf", "memorial-park", .friends, 3),
        ("Hal Pedersen", nil, .stranger, 2), ("Heidi Vue", "sju-arboretum-trail", .sent, 0),
        ("Junie Okonkwo", "millstream-arts-festival", .received, 0), ("Dale Brunner", "wobegon-trail", .friends, 0),
        ("Hank Feldner", "rivers-bend-park", .blocked, 0), ("Tess Marrow", "rocktoberfest", .blocked, 0),
    ].map { name, photo, relation, mutual in
        Neighbor(userId: "sample:\(name)", displayName: name,
                 avatarUrl: photo.flatMap { Bundle.main.url(forResource: $0, withExtension: "jpg")?.absoluteString },
                 since: "2026-03-02T10:00:00Z", relation: relation, mutualFriends: mutual,
                 friendsSince: relation == .friends ? "2026-08-14T18:00:00Z" : nil)
    }
    #else
    static let samples: [Neighbor] = []
    #endif
}
