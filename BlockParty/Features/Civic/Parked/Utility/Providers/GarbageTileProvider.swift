//
//  GarbageTileProvider.swift
//  Block Party — the garbage/recycling Utility Row tile. Pure local date math via
//  GarbageSchedule; no network.
//

import Foundation

@MainActor
final class GarbageTileProvider: UtilityTileProvider {
    let id: UtilityTileID = .garbage
    let refreshPolicy: UtilityRefreshPolicy = .computed

    func fetch(settings: TileSettings) async throws -> UtilityTileValue {
        let weekday = settings.int("day") ?? GarbageSchedule.defaultWeekday
        let pickup = GarbageSchedule.nextPickup(pickupWeekday: weekday)

        let primary: String
        switch pickup.daysFromToday {
        case 0:  primary = "Tonight"
        case 1:  primary = "Tomorrow"
        default: primary = UtilityFormat.weekdayName(pickup.date)
        }
        let secondary = pickup.isRecyclingWeek ? "Recycling week" : "Trash only"

        let expanded: [UtilityDetailRow] = [
            UtilityDetailRow(symbol: "calendar", label: "Next pickup", value: UtilityFormat.mediumDate(pickup.date)),
            UtilityDetailRow(symbol: pickup.isRecyclingWeek ? "arrow.3.trianglepath" : "trash",
                             label: "This week",
                             value: pickup.isRecyclingWeek ? "Trash + recycling" : "Trash only"),
        ]

        let content = UtilityTileContent(symbol: "trash.fill", primary: primary,
                                         secondary: secondary, expanded: expanded)
        return UtilityTileValue(content: content)
    }
}
