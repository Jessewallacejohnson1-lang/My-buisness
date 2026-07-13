//
//  SeasonClock.swift
//  Hygge — offline season from the local date (meteorological, N. hemisphere).
//  blend eases the palette into the next season over the season's final 15 days.
//

import Foundation

enum SeasonClock {
    struct Result { let season: Season; let blend: Double }

    static func current(_ date: Date = Date()) -> Result {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let m = cal.component(.month, from: date)
        let season: Season
        switch m {
        case 12, 1, 2: season = .winter
        case 3, 4, 5:  season = .spring
        case 6, 7, 8:  season = .summer
        default:       season = .autumn
        }
        // First day of the next meteorological season, then blend over the last 15 days.
        var comp = DateComponents()
        comp.day = 1
        switch season {
        case .winter: comp.month = 3;  comp.year = cal.component(.year, from: date) + (m == 12 ? 1 : 0)
        case .spring: comp.month = 6;  comp.year = cal.component(.year, from: date)
        case .summer: comp.month = 9;  comp.year = cal.component(.year, from: date)
        case .autumn: comp.month = 12; comp.year = cal.component(.year, from: date)
        }
        let boundary = cal.date(from: comp) ?? date
        let daysLeft = max(0, cal.dateComponents([.day], from: date, to: boundary).day ?? 99)
        let ramp = 15.0
        let blend = Double(daysLeft) >= ramp ? 0 : (ramp - Double(daysLeft)) / ramp
        return Result(season: season, blend: min(max(blend, 0), 1))
    }
}
