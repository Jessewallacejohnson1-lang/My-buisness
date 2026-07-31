//
//  LibraryTileProvider.swift
//  Block Party — the library-hours Utility Row tile. Static hours table via
//  LibraryHours; pure, no network.
//

import Foundation

@MainActor
final class LibraryTileProvider: UtilityTileProvider {
    let id: UtilityTileID = .library
    let refreshPolicy: UtilityRefreshPolicy = .computed

    func fetch(settings: TileSettings) async throws -> UtilityTileValue {
        let content: UtilityTileContent
        switch LibraryHours.status() {
        case let .open(closesAt, _):
            content = UtilityTileContent(symbol: "book.fill", primary: "Open",
                                         secondary: "Closes \(UtilityFormat.clock(closesAt))",
                                         expanded: weekRows())
        case let .closed(opensAt, weekday):
            var secondary: String?
            if let opensAt, let weekday {
                let today = Calendar.current.component(.weekday, from: Date())
                let when = weekday == today ? "today" : UtilityFormat.weekdayName(weekday, short: true)
                secondary = "Opens \(UtilityFormat.clock(opensAt)) \(when)"
            }
            content = UtilityTileContent(symbol: "book.fill", primary: "Closed",
                                         secondary: secondary, expanded: weekRows())
        }
        return UtilityTileValue(content: content)
    }

    /// One row per weekday for the expanded tile.
    private func weekRows() -> [UtilityDetailRow] {
        (1...7).map { weekday in
            let day = UtilityFormat.weekdayName(weekday, short: true)
            guard let range = LibraryHours.table[weekday]?.first else {
                return UtilityDetailRow(label: day, value: "Closed")
            }
            return UtilityDetailRow(label: day,
                                    value: "\(UtilityFormat.clock(range.lowerBound)) – \(UtilityFormat.clock(range.upperBound))")
        }
    }
}
