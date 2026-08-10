//
//  TownNewsAPI.swift
//  Block Party — the finite daily Town Notes read path over board_items.
//
//  This is deliberately independent of the Today briefing RPC. It follows the
//  app's hand-rolled PostgREST pattern and never rolls into another day.
//

import Foundation

struct NewsStory: Identifiable, Hashable, Sendable {
    let id: String
    let headline: String
    let summary: String
    let sourceName: String
    let sourceURL: URL?
    let publishedAt: Date
    let category: String
    let imageURL: URL?
    let fetchedAt: Date?

    /// A human-facing category label. Unknown future values are de-underscored
    /// instead of leaking a raw enum-shaped string into the interface.
    var categoryLabel: String {
        switch category.lowercased() {
        case "school": "School"
        case "campus": "Campus"
        case "business": "Business"
        case "event": "Event"
        default:
            category
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
    }

    /// Nil is the view contract for hiding the secondary browser action.
    var readActionTitle: String? {
        guard sourceURL != nil else { return nil }
        return "Read at \(sourceName) ↗"
    }

    var sourceTimeLine: String {
        "\(sourceName) · \(TownNewsDate.time(publishedAt))"
    }
}

struct TownNewsAPI {
    private static let storyCategories: Set<String> = [
        "school", "campus", "business", "event",
    ]

    let auth: AuthStore

    init(auth: AuthStore) {
        self.auth = auth
    }

    /// At most five stories published on the requested St. Joseph calendar day.
    /// The server performs the same cap/filter/order, and the client repeats the
    /// finite contract defensively so a backend regression cannot create a feed.
    func fetchDailyStories(_ date: Date) async throws -> [NewsStory] {
        let token = try await auth.validAccessToken()
        let bounds = TownNewsDate.bounds(for: date)
        let columns = [
            "id", "title", "blurb", "source_name", "source_url",
            "published_at", "category", "image_url", "fetched_at",
        ].joined(separator: ",")
        let query = [
            "select=\(columns)",
            "status=eq.published",
            "category=in.(school,campus,business,event)",
            "blurb=not.is.null",
            "published_at=gte.\(TownNewsDate.encode(bounds.start))",
            "published_at=lt.\(TownNewsDate.encode(bounds.end))",
            "order=published_at.desc",
            "limit=5",
        ].joined(separator: "&")

        let (data, _) = try await SupabaseHTTP.rest(
            "board_items",
            query: query,
            accessToken: token
        )
        let rows = try SupabaseCoding.decoder.decode([StoryRow].self, from: data)
        return Self.dailyStories(from: rows.map(NewsStory.init))
    }

    /// Real sweep provenance for the requested town day. An empty table returns
    /// nil; callers must not infer or manufacture source counts.
    func sweepMetadata(
        _ date: Date
    ) async throws -> (sourceCount: Int, lastSweptAt: Date)? {
        let token = try await auth.validAccessToken()
        let query = [
            "select=source_count,last_swept_at",
            "swept_on=eq.\(TownNewsDate.day(date))",
            "order=last_swept_at.desc",
            "limit=1",
        ].joined(separator: "&")
        let (data, _) = try await SupabaseHTTP.rest(
            "board_sweeps",
            query: query,
            accessToken: token
        )
        guard let row = try SupabaseCoding.decoder.decode([SweepRow].self, from: data).first else {
            return nil
        }
        return (sourceCount: row.sourceCount, lastSweptAt: row.lastSweptAt)
    }

    /// Pure finite-deck policy, shared by the real fetch and contract tests.
    static func dailyStories(from stories: [NewsStory]) -> [NewsStory] {
        Array(
            stories
                .filter { storyCategories.contains($0.category.lowercased()) }
                .sorted { lhs, rhs in
                    if lhs.publishedAt != rhs.publishedAt {
                        return lhs.publishedAt > rhs.publishedAt
                    }
                    return lhs.id < rhs.id
                }
                .prefix(5)
        )
    }

    fileprivate struct StoryRow: Decodable {
        let id: String
        let title: String
        let blurb: String
        let sourceName: String
        let sourceUrl: String?
        let publishedAt: Date
        let category: String
        let imageUrl: String?
        let fetchedAt: Date?
    }

    private struct SweepRow: Decodable {
        let sourceCount: Int
        let lastSweptAt: Date
    }
}

private extension NewsStory {
    init(_ row: TownNewsAPI.StoryRow) {
        self.init(
            id: row.id,
            headline: row.title,
            summary: row.blurb,
            sourceName: row.sourceName,
            sourceURL: row.sourceUrl.flatMap(URL.init(string:)),
            publishedAt: row.publishedAt,
            category: row.category,
            imageURL: row.imageUrl.flatMap(URL.init(string:)),
            fetchedAt: row.fetchedAt
        )
    }
}

enum TownNewsDate {
    static func bounds(for date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let start = calendar.startOfDay(for: date)
        return (
            start,
            calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        )
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Percent-encode a timestamp before handing it to URLComponents as an
    /// already-percent-encoded PostgREST query string.
    static func encode(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let value = formatter.string(from: date)
        return value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
