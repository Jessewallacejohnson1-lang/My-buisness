//
//  SolarClock.swift
//  Hygge — offline sunrise/sunset + continuous day factor + time phase.
//
//  NOAA "sunrise equation" (the Wikipedia Julian-day formulation), so golden hour
//  lands at St. Joe's REAL hour — sunset swings ~9:03pm (late June) to ~4:34pm
//  (late Dec). Pure math: no network, no location permission. Pinned by callers
//  to MapSpots.center.
//

import Foundation
import CoreLocation

enum SolarClock {
    struct SunTimes { let sunrise: Date; let sunset: Date; let solarNoon: Date }

    private static let epoch2000 = 2451545.0
    private static func deg2rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func rad2deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func julian(from date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2440587.5 }
    private static func dateFromJulian(_ j: Double) -> Date { Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }

    static func sunTimes(on date: Date, at coord: CLLocationCoordinate2D) -> SunTimes {
        let lat = coord.latitude
        let lon = coord.longitude                      // signed, east-positive (St. Joe ≈ −94.32)
        // Anchor the day count to LOCAL noon of the input's local day. Without this,
        // an evening local time (already the next UTC day at western longitudes)
        // rounds `n` to tomorrow and returns tomorrow's sun times — which would
        // misclassify dusk/golden. TimeZone.current matches the app + St. Joe.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let anchor = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let jd = julian(from: anchor)
        let n = (jd - epoch2000 + 0.0008).rounded()    // integer days since 2000
        let jStar = n - lon / 360.0                     // mean solar time (west longitude ⇒ later)
        let m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        let mr = deg2rad(m)
        let c = 1.9148 * sin(mr) + 0.0200 * sin(2 * mr) + 0.0003 * sin(3 * mr)
        let lambda = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let lr = deg2rad(lambda)
        let jTransit = epoch2000 + jStar + 0.0053 * sin(mr) - 0.0069 * sin(2 * lr)
        let sinDec = sin(lr) * sin(deg2rad(23.44))
        let cosDec = cos(asin(sinDec))
        let cosOmega = (sin(deg2rad(-0.833)) - sin(deg2rad(lat)) * sinDec) / (cos(deg2rad(lat)) * cosDec)
        let noon = dateFromJulian(jTransit)
        // Clamp polar edge cases (never hit at St. Joe's latitude, but be safe).
        guard cosOmega >= -1, cosOmega <= 1 else {
            return SunTimes(sunrise: noon, sunset: noon, solarNoon: noon)
        }
        let omega = rad2deg(acos(cosOmega))
        let jRise = jTransit - omega / 360.0
        let jSet  = jTransit + omega / 360.0
        return SunTimes(sunrise: dateFromJulian(jRise), sunset: dateFromJulian(jSet), solarNoon: noon)
    }

    /// Smooth 0→1→0 across daylight (peak at midday); 0 at night. sin(π·progress).
    static func dayFactor(at date: Date, coord: CLLocationCoordinate2D) -> Double {
        let s = sunTimes(on: date, at: coord)
        let rise = s.sunrise.timeIntervalSince1970
        let set  = s.sunset.timeIntervalSince1970
        let now  = date.timeIntervalSince1970
        guard set > rise else { return 0 }
        if now <= rise || now >= set { return 0 }
        let progress = (now - rise) / (set - rise)
        return sin(.pi * progress)
    }

    static func phase(at date: Date, coord: CLLocationCoordinate2D) -> TimePhase {
        let s = sunTimes(on: date, at: coord)
        let rise = s.sunrise.timeIntervalSince1970
        let set  = s.sunset.timeIntervalSince1970
        let now  = date.timeIntervalSince1970
        let golden = 40.0 * 60      // warm-light window around rise/set
        let twilight = 30.0 * 60    // civil twilight approximation
        if now < rise - twilight || now >= set + twilight { return .night }
        if now < rise            { return .dawn }
        if now <= rise + golden  { return .golden }
        if now >= set            { return .dusk }
        if now >= set - golden   { return .golden }
        return .day
    }
}
