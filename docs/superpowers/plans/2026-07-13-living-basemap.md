# Living Basemap Implementation Plan

> **RETIRED (2026-07-13), same day.** Everything this plan built (`AtmosphereModel`,
> `AtmosphereOverride`, `BasemapPalette.make(for:)`, the `-atmosphere` DEBUG flag) was deleted the
> same day in favor of one static basemap. See the "Living Basemap retired" entry in
> `MAP_BUILD_LOG.md`. Kept here as a historical record — do not follow these steps or treat the
> APIs below as current.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the St. Joseph town map alive before anyone touches it — the basemap, a light wash, drifting precip, and a quiet weather line all reflect the real time of day, season, and weather.

**Architecture:** One composed value `TownAtmosphere = f(time, season, sky)` computed on-device. Time (`SolarClock`, NOAA solar math) and season (`SeasonClock`) are synchronous and offline, so the map is alive on the first frame with zero network. Sky comes from Open-Meteo behind a `WeatherProvider` protocol (WeatherKit drops in later), cached in UserDefaults. `AtmosphereModel` publishes the value; `SJMapView` reads it to recolor the Mapbox basemap (`BasemapPalette`), draw a `TimeWashOverlay`, render `WeatherParticles`, and show the `AtmosphereWhisper` under the town pill. `MapModel` (events/realtime) is untouched — a clean seam.

**Tech Stack:** SwiftUI, MapboxMaps (existing SPM dep — no new deps), Foundation/CoreLocation, URLSession. Verified by `swiftc` harnesses (pure logic) + 0-warning Xcode build + simulator screenshots (visual/integration).

## Global Constraints

Every task's requirements implicitly include this section. Values copied verbatim from the spec + CLAUDE.md:

- **iOS deployment target 26.5, Swift 5.** No new SPM dependency — MapboxMaps only.
- **No Supabase schema, no backend, no edge function.** Only outbound network is Open-Meteo.
- **No CLLocation / location-permission prompt.** Atmosphere is pinned to `MapSpots.center` (lat 45.565, lon -94.317).
- **Coral is reserved.** `Hue.accent` marks live/tappable only. Weather whisper + atmosphere chrome use neutral ink + muted tones — **never coral**.
- **Real only** — weather is real; time/season are the device clock + St. Joe coordinates. Nothing seeded.
- **Reduce Motion honored** — every animated element (wash cross-fade, particles) has a static fallback (mirrors `PulseRing`).
- **Weather is swappable** — all weather access goes through `protocol WeatherProvider`. `OpenMeteoWeatherProvider` now; `WeatherKitWeatherProvider` is a one-file, one-line swap later.
- **New files auto-compile.** `BlockParty/` is an Xcode file-system-synchronized group — files created under `BlockParty/Features/Map/Atmosphere/` are picked up automatically; **no `.pbxproj` editing.** (Verify by building.) Do NOT let a `.impeccable/` dir land inside `BlockParty/` (duplicate-bundle build failure).
- **"Verified"** = builds clean with **0 warnings** AND confirmed in the running simulator via screenshots.
- **Tokens only** — no raw hex/spacing a `Hue`/metric token covers, except the basemap cartography hexes (which this feature owns and modulates).

## Test harness convention (pure units)

Pure-Foundation units are tested by compiling the **real source file** together with a throwaway `main.swift` under `scratchpad/`, so the test exercises the shipped code (no copy drift):

```bash
SP=/private/tmp/claude-501/-Users-owner-Documents-BlockParty/c4aed1e4-6c44-4c16-bae6-c04b4307c0d3/scratchpad
swiftc -D DEBUG -o "$SP/check" \
  BlockParty/Features/Map/Atmosphere/<Unit>.swift \
  BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift \
  "$SP/<unit>_main.swift" && "$SP/check"
```

`-D DEBUG` so `#if DEBUG` paths compile. A harness `main.swift` prints `PASS`/`FAIL` lines and exits nonzero on any failure. These units import only `Foundation`/`CoreLocation` — never SwiftUI — precisely so they stay harnessable.

---

### Task 1: Atmosphere vocabulary (`TownAtmosphere.swift`)

The shared value types every other unit speaks. Pure Foundation/CoreLocation.

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift`
- Test: `scratchpad/atmo_main.swift`

**Interfaces — Produces:**
- `enum TimePhase: String { case dawn, day, golden, dusk, night }`
- `enum Season: String { case winter, spring, summer, autumn }`
- `enum SkyCondition: String, Codable { case clear, cloudy, overcast, fog, rain, snow, storm; var isPrecip: Bool }`
- `enum WeatherIntensity: String, Codable { case light, moderate, heavy }`
- `struct WeatherSnapshot: Codable, Equatable { let tempF: Int; let condition: SkyCondition; let intensity: WeatherIntensity; let isDay: Bool; let capturedAt: Date }`
- `struct TownAtmosphere: Equatable` with fields `dayFactor: Double, phase: TimePhase, season: Season, seasonBlend: Double, sky: SkyCondition, intensity: WeatherIntensity, tempF: Int?, isDay: Bool, resolvedAt: Date?` plus:
  - `var conditionText: String` — "clear", "overcast", "light snow", "heavy rain", "thunderstorm", "fog", etc.
  - `var glyph: String` — SF Symbol name (respects `isDay` for clear).
  - `func whisperLine(now: Date) -> String?` — `"38° · light snow · 4:15"`, or `nil` while `resolvedAt == nil`.
  - `var accessibilityText: String?` — "Currently 38 degrees, light snow, 4:15 PM in Saint Joseph."
  - `func applying(_ overrides: [String: String]) -> TownAtmosphere` — apply DEBUG override keys.
  - `static var placeholder: TownAtmosphere` — day/summer/clear, unresolved (safe initial value).

- [ ] **Step 1: Write the failing test** — `scratchpad/atmo_main.swift`

```swift
import Foundation

func expect(_ cond: Bool, _ msg: String) {
    print(cond ? "PASS \(msg)" : "FAIL \(msg)")
    if !cond { failures += 1 }
}
var failures = 0

// conditionText + glyph
var a = TownAtmosphere.placeholder
a.sky = .snow; a.intensity = .light; a.tempF = 38; a.isDay = true; a.resolvedAt = Date()
expect(a.conditionText == "light snow", "snow+light → 'light snow'")
expect(a.glyph == "snowflake", "snow glyph")

a.sky = .clear; a.isDay = false
expect(a.glyph == "moon.stars", "clear+night glyph")
a.isDay = true
expect(a.glyph == "sun.max", "clear+day glyph")

// whisperLine formatting at 16:15 local
let cal = Calendar.current
let t = cal.date(bySettingHour: 16, minute: 15, second: 0, of: Date())!
a.sky = .snow; a.intensity = .light; a.tempF = 38
expect(a.whisperLine(now: t) == "38° · light snow · 4:15", "whisper format")

// nil until resolved
var b = TownAtmosphere.placeholder
expect(b.whisperLine(now: t) == nil, "no whisper before weather resolves")

// applying overrides
let c = TownAtmosphere.placeholder.applying(["season": "winter", "sky": "snow", "temp": "20"])
expect(c.season == .winter && c.sky == .snow && c.tempF == 20, "override applies keys")

exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `swiftc -D DEBUG -o "$SP/check" BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift "$SP/atmo_main.swift" && "$SP/check"`
Expected: FAIL — `TownAtmosphere.swift` doesn't exist / symbols undefined.

- [ ] **Step 3: Implement** — `BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift`

```swift
//
//  TownAtmosphere.swift
//  Block Party — the composed environment value for the Living Basemap.
//
//  TownAtmosphere = f(time-of-day, season, sky). Computed on-device; time+season
//  are synchronous/offline so the map is alive on the first frame, sky (weather)
//  refines it a moment later. Pure Foundation — never import SwiftUI here (keeps
//  the unit harnessable and the seam clean).
//

import Foundation

enum TimePhase: String { case dawn, day, golden, dusk, night }

enum Season: String { case winter, spring, summer, autumn }

enum SkyCondition: String, Codable {
    case clear, cloudy, overcast, fog, rain, snow, storm
    var isPrecip: Bool { self == .rain || self == .snow || self == .storm }
}

enum WeatherIntensity: String, Codable { case light, moderate, heavy }

struct WeatherSnapshot: Codable, Equatable {
    let tempF: Int
    let condition: SkyCondition
    let intensity: WeatherIntensity
    let isDay: Bool
    let capturedAt: Date
}

struct TownAtmosphere: Equatable {
    var dayFactor: Double       // 0 (deep night) … 1 (solar noon)
    var phase: TimePhase
    var season: Season
    var seasonBlend: Double      // 0…1 toward the next season
    var sky: SkyCondition
    var intensity: WeatherIntensity
    var tempF: Int?
    var isDay: Bool
    var resolvedAt: Date?        // nil until weather loads

    static let placeholder = TownAtmosphere(
        dayFactor: 1, phase: .day, season: .summer, seasonBlend: 0,
        sky: .clear, intensity: .light, tempF: nil, isDay: true, resolvedAt: nil
    )

    /// Human condition text. Intensity qualifies precip only.
    var conditionText: String {
        switch sky {
        case .clear:    return "clear"
        case .cloudy:   return "partly cloudy"
        case .overcast: return "overcast"
        case .fog:      return "fog"
        case .storm:    return "thunderstorms"
        case .rain:     return intensity == .light ? "light rain" : intensity == .heavy ? "heavy rain" : "rain"
        case .snow:     return intensity == .light ? "light snow" : intensity == .heavy ? "heavy snow" : "snow"
        }
    }

    /// SF Symbol for the whisper glyph. Muted-tinted at the call site — never coral.
    var glyph: String {
        switch sky {
        case .clear:    return isDay ? "sun.max" : "moon.stars"
        case .cloudy:   return isDay ? "cloud.sun" : "cloud.moon"
        case .overcast: return "cloud"
        case .fog:      return "cloud.fog"
        case .rain:     return "cloud.rain"
        case .snow:     return "snowflake"
        case .storm:    return "cloud.bolt.rain"
        }
    }

    private func clockLabel(_ now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm"
        return f.string(from: now)
    }

    /// "38° · light snow · 4:15" — nil until weather resolves.
    func whisperLine(now: Date) -> String? {
        guard resolvedAt != nil, let t = tempF else { return nil }
        return "\(t)° · \(conditionText) · \(clockLabel(now))"
    }

    var accessibilityText: String? {
        guard resolvedAt != nil, let t = tempF else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "h:mm a"
        return "Currently \(t) degrees, \(conditionText), \(f.string(from: Date())) in Saint Joseph."
    }

    /// DEBUG override: overlay parsed key/values onto this atmosphere.
    func applying(_ o: [String: String]) -> TownAtmosphere {
        var a = self
        if let v = o["season"], let s = Season(rawValue: v) { a.season = s }
        if let v = o["phase"], let p = TimePhase(rawValue: v) { a.phase = p }
        if let v = o["sky"], let s = SkyCondition(rawValue: v) { a.sky = s; a.resolvedAt = Date() }
        if let v = o["intensity"], let i = WeatherIntensity(rawValue: v) { a.intensity = i }
        if let v = o["temp"], let t = Int(v) { a.tempF = t; a.resolvedAt = Date() }
        if let v = o["daylight"], let d = Double(v) { a.dayFactor = min(max(d, 0), 1) }
        if let v = o["isday"] { a.isDay = (v == "1" || v == "true") }
        return a
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swiftc -D DEBUG -o "$SP/check" BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift "$SP/atmo_main.swift" && "$SP/check"`
Expected: all `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift
git commit -m "feat(map): atmosphere vocabulary — TownAtmosphere value types"
```

---

### Task 2: SolarClock (`SolarClock.swift`)

Offline sunrise/sunset + continuous `dayFactor` + `phase`, via the NOAA sunrise equation. This is the one place correctness is subtle and invisible to screenshots, so it gets an almanac-checked harness.

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/SolarClock.swift`
- Test: `scratchpad/solar_main.swift`

**Interfaces — Consumes:** `TimePhase` (Task 1). **Produces:**
- `enum SolarClock` with:
  - `struct SunTimes { let sunrise: Date; let sunset: Date; let solarNoon: Date }`
  - `static func sunTimes(on date: Date, at coord: CLLocationCoordinate2D) -> SunTimes`
  - `static func dayFactor(at date: Date, coord: CLLocationCoordinate2D) -> Double` — 0…1, `sin(π·progress)` across daylight, 0 at night.
  - `static func phase(at date: Date, coord: CLLocationCoordinate2D) -> TimePhase`

- [ ] **Step 1: Write the failing test** — `scratchpad/solar_main.swift`

```swift
import Foundation
import CoreLocation

var failures = 0
func expect(_ c: Bool, _ m: String) { print(c ? "PASS \(m)" : "FAIL \(m)"); if !c { failures += 1 } }

let stJoe = CLLocationCoordinate2D(latitude: 45.565, longitude: -94.317)
let cal = Calendar(identifier: .gregorian)
var utc = cal; utc.timeZone = TimeZone(identifier: "America/Chicago")!

func localHM(_ d: Date) -> (Int, Int) {
    var c = Calendar.current; c.timeZone = TimeZone(identifier: "America/Chicago")!
    let x = c.dateComponents([.hour, .minute], from: d); return (x.hour!, x.minute!)
}

// Almanac (timeanddate.com, St. Joseph MN, Central):
// 2026-06-21 sunrise ~05:29, sunset ~21:03 CDT
// 2026-12-21 sunrise ~07:49, sunset ~16:34 CST
func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var comp = DateComponents(); comp.year = y; comp.month = mo; comp.day = d; comp.hour = h; comp.minute = mi
    var c = Calendar.current; c.timeZone = TimeZone(identifier: "America/Chicago")!
    return c.date(from: comp)!
}

let jun = SolarClock.sunTimes(on: date(2026,6,21,12,0), at: stJoe)
let (jrh, jrm) = localHM(jun.sunrise); let (jsh, jsm) = localHM(jun.sunset)
expect(jrh == 5 && abs(jrm - 29) <= 8, "Jun 21 sunrise ≈ 05:29 (got \(jrh):\(jrm))")
expect(jsh == 21 && abs(jsm - 3) <= 8, "Jun 21 sunset ≈ 21:03 (got \(jsh):\(jsm))")

let dec = SolarClock.sunTimes(on: date(2026,12,21,12,0), at: stJoe)
let (drh, drm) = localHM(dec.sunrise); let (dsh, dsm) = localHM(dec.sunset)
expect(drh == 7 && abs(drm - 49) <= 8, "Dec 21 sunrise ≈ 07:49 (got \(drh):\(drm))")
expect(dsh == 16 && abs(dsm - 34) <= 8, "Dec 21 sunset ≈ 16:34 (got \(dsh):\(dsm))")

// dayFactor: 0 at deep night, ~1 near solar noon, 0 before sunrise
expect(SolarClock.dayFactor(at: date(2026,6,21,3,0), coord: stJoe) == 0, "3am → 0")
let noonDF = SolarClock.dayFactor(at: jun.solarNoon, coord: stJoe)
expect(noonDF > 0.98, "solar noon → ~1 (got \(noonDF))")
let midMorn = SolarClock.dayFactor(at: date(2026,6,21,9,0), coord: stJoe)
expect(midMorn > 0.3 && midMorn < 0.95, "9am mid-ramp (got \(midMorn))")

// phase: 3am night, noon day, ~sunset golden
expect(SolarClock.phase(at: date(2026,6,21,3,0), coord: stJoe) == .night, "3am night")
expect(SolarClock.phase(at: jun.solarNoon, coord: stJoe) == .day, "noon day")
expect(SolarClock.phase(at: jun.sunset.addingTimeInterval(-600), coord: stJoe) == .golden, "10min before sunset golden")

exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `swiftc -D DEBUG -o "$SP/check" BlockParty/Features/Map/Atmosphere/SolarClock.swift BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift "$SP/solar_main.swift" && "$SP/check"`
Expected: FAIL — `SolarClock` undefined.

- [ ] **Step 3: Implement** — `BlockParty/Features/Map/Atmosphere/SolarClock.swift`

```swift
//
//  SolarClock.swift
//  Block Party — offline sunrise/sunset + continuous day factor + time phase.
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
    private static func date(fromJulian j: Double) -> Date { Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }

    static func sunTimes(on date: Date, at coord: CLLocationCoordinate2D) -> SunTimes {
        let lat = coord.latitude
        let lw = -coord.longitude                    // west longitude, positive
        let jd = julian(from: date)
        let n = (jd - epoch2000 + 0.0008).rounded()   // integer days since 2000
        let Jstar = n - lw / 360.0                     // mean solar time
        let M = (357.5291 + 0.98560028 * Jstar).truncatingRemainder(dividingBy: 360)
        let Mr = deg2rad(M)
        let C = 1.9148 * sin(Mr) + 0.0200 * sin(2*Mr) + 0.0003 * sin(3*Mr)
        let lambda = (M + C + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let lr = deg2rad(lambda)
        let Jtransit = epoch2000 + Jstar + 0.0053 * sin(Mr) - 0.0069 * sin(2*lr)
        let sinDec = sin(lr) * sin(deg2rad(23.44))
        let cosDec = cos(asin(sinDec))
        let cosOmega = (sin(deg2rad(-0.833)) - sin(deg2rad(lat)) * sinDec) / (cos(deg2rad(lat)) * cosDec)
        let noon = date(fromJulian: Jtransit)
        // Clamp polar edge cases (never hit at St. Joe's latitude, but be safe).
        guard cosOmega >= -1, cosOmega <= 1 else {
            return SunTimes(sunrise: noon, sunset: noon, solarNoon: noon)
        }
        let omega = rad2deg(acos(cosOmega))
        let Jrise = Jtransit - omega / 360.0
        let Jset  = Jtransit + omega / 360.0
        return SunTimes(sunrise: date(fromJulian: Jrise), sunset: date(fromJulian: Jset), solarNoon: noon)
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
        if now >= set - golden    { return .golden }
        return .day
    }
}
```

- [ ] **Step 4: Run to verify it passes** — same command as Step 2. Expected: all `PASS`, exit 0. (If a sunrise assertion is off by more than tolerance, re-derive — do not widen tolerance past ±8 min.)

- [ ] **Step 5: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/SolarClock.swift
git commit -m "feat(map): SolarClock — offline sunrise/sunset, dayFactor, phase"
```

---

### Task 3: SeasonClock (`SeasonClock.swift`)

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/SeasonClock.swift`
- Test: `scratchpad/season_main.swift`

**Interfaces — Consumes:** `Season` (Task 1). **Produces:**
- `enum SeasonClock { struct Result { let season: Season; let blend: Double }; static func current(_ date: Date) -> Result }` — meteorological N-hemisphere seasons; `blend` ramps 0→1 over the last 15 days of the season toward the next.

- [ ] **Step 1: Write the failing test** — `scratchpad/season_main.swift`

```swift
import Foundation
var failures = 0
func expect(_ c: Bool, _ m: String) { print(c ? "PASS \(m)" : "FAIL \(m)"); if !c { failures += 1 } }
func d(_ y:Int,_ mo:Int,_ da:Int) -> Date { var c = DateComponents(); c.year=y;c.month=mo;c.day=da; return Calendar.current.date(from: c)! }

expect(SeasonClock.current(d(2026,1,15)).season == .winter, "Jan → winter")
expect(SeasonClock.current(d(2026,4,15)).season == .spring, "Apr → spring")
expect(SeasonClock.current(d(2026,7,15)).season == .summer, "Jul → summer")
expect(SeasonClock.current(d(2026,10,15)).season == .autumn, "Oct → autumn")
expect(SeasonClock.current(d(2026,7,15)).blend < 0.1, "mid-season low blend")
expect(SeasonClock.current(d(2026,8,29)).blend > 0.5, "late Aug ramps toward autumn")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails** — `swiftc -D DEBUG -o "$SP/check" BlockParty/Features/Map/Atmosphere/SeasonClock.swift BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift "$SP/season_main.swift" && "$SP/check"` → FAIL.

- [ ] **Step 3: Implement** — `BlockParty/Features/Map/Atmosphere/SeasonClock.swift`

```swift
//
//  SeasonClock.swift
//  Block Party — offline season from the local date (meteorological, N. hemisphere).
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
        // Days remaining until the next meteorological boundary (1st of next season month).
        let nextBoundaryMonth = [Season.winter: 3, .spring: 6, .summer: 9, .autumn: 12][season]!
        var comp = DateComponents(); comp.day = 1; comp.month = nextBoundaryMonth
        comp.year = cal.component(.year, from: date) + (season == .winter && m != 12 ? 0 : (nextBoundaryMonth <= m ? 1 : 0))
        // Winter spans year end; handle Dec → next-year Mar boundary.
        if season == .winter { comp.month = 3; comp.year = cal.component(.year, from: date) + (m == 12 ? 1 : 0) }
        let boundary = cal.date(from: comp) ?? date
        let daysLeft = max(0, cal.dateComponents([.day], from: date, to: boundary).day ?? 99)
        let ramp = 15.0
        let blend = daysLeft >= Int(ramp) ? 0 : (ramp - Double(daysLeft)) / ramp
        return Result(season: season, blend: min(max(blend, 0), 1))
    }
}
```

- [ ] **Step 4: Run to verify it passes** — same command. Expected: all `PASS`.

- [ ] **Step 5: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/SeasonClock.swift
git commit -m "feat(map): SeasonClock — offline season + boundary blend"
```

---

### Task 4: WeatherProvider (`WeatherProvider.swift`)

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/WeatherProvider.swift`
- Test: `scratchpad/weather_main.swift`

**Interfaces — Consumes:** `WeatherSnapshot`, `SkyCondition`, `WeatherIntensity` (Task 1). **Produces:**
- `protocol WeatherProvider { func current(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot }`
- `enum WMO { static func map(code: Int, isDay: Bool) -> (SkyCondition, WeatherIntensity) }`
- `struct OpenMeteoWeatherProvider: WeatherProvider`
- `final class CachedWeatherProvider` — wraps a base provider; `var cached: WeatherSnapshot?` (from UserDefaults, any age); `func current(...)` fetches, stores, returns. `init(base:defaults:ttl:)` (inject `UserDefaults` for the harness).

- [ ] **Step 1: Write the failing test** — `scratchpad/weather_main.swift`

```swift
import Foundation
import CoreLocation
var failures = 0
func expect(_ c: Bool, _ m: String) { print(c ? "PASS \(m)" : "FAIL \(m)"); if !c { failures += 1 } }

// WMO mapping table
expect(WMO.map(code: 0, isDay: true).0 == .clear, "0 → clear")
expect(WMO.map(code: 3, isDay: true).0 == .overcast, "3 → overcast")
expect(WMO.map(code: 48, isDay: true).0 == .fog, "48 → fog")
expect(WMO.map(code: 65, isDay: true) == (.rain, .heavy), "65 → heavy rain")
expect(WMO.map(code: 73, isDay: true).0 == .snow, "73 → snow")
expect(WMO.map(code: 95, isDay: true).0 == .storm, "95 → storm")

// Open-Meteo JSON decode → snapshot (fixture, no network)
let json = """
{"current":{"temperature_2m":37.8,"weather_code":73,"is_day":0}}
""".data(using: .utf8)!
let snap = try! OpenMeteoWeatherProvider.decode(json)
expect(snap.tempF == 38 && snap.condition == .snow && snap.isDay == false, "decode → 38°, snow, night")

// Cache round-trip via an isolated suite
let suite = UserDefaults(suiteName: "atmo.test")!
suite.removePersistentDomain(forName: "atmo.test")
let cache = CachedWeatherProvider(base: OpenMeteoWeatherProvider(), defaults: suite, ttlSeconds: 1200)
expect(cache.cached == nil, "empty cache")
cache.store(snap)
expect(cache.cached?.tempF == 38, "cache round-trips")

exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails** — `swiftc -D DEBUG -o "$SP/check" BlockParty/Features/Map/Atmosphere/WeatherProvider.swift BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift "$SP/weather_main.swift" && "$SP/check"` → FAIL.

- [ ] **Step 3: Implement** — `BlockParty/Features/Map/Atmosphere/WeatherProvider.swift`

```swift
//
//  WeatherProvider.swift
//  Block Party — the sky dimension: real weather behind a swappable protocol.
//
//  OpenMeteoWeatherProvider is a keyless URLSession GET matching the app's
//  hand-rolled backend. CachedWeatherProvider persists the last snapshot in
//  UserDefaults so the whisper is instant on open and survives offline.
//
//  WEATHERKIT SWAP (later, paid dev account): add WeatherKitWeatherProvider
//  conforming to WeatherProvider (map WeatherKit conditions → SkyCondition),
//  change the one `OpenMeteoWeatherProvider()` in AtmosphereModel, add the
//  capability/entitlement + " Weather" attribution. No other change.
//

import Foundation
import CoreLocation

protocol WeatherProvider {
    func current(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot
}

enum WMO {
    /// WMO weather interpretation code → our condition + intensity.
    static func map(code: Int, isDay: Bool) -> (SkyCondition, WeatherIntensity) {
        switch code {
        case 0:            return (.clear, .light)
        case 1, 2:         return (.cloudy, .light)
        case 3:            return (.overcast, .moderate)
        case 45, 48:       return (.fog, .moderate)
        case 51, 53, 55, 56, 57: return (.rain, .light)
        case 61, 63:       return (.rain, .moderate)
        case 65, 66, 67:   return (.rain, .heavy)
        case 71, 73, 77:   return (.snow, .moderate)
        case 75:           return (.snow, .heavy)
        case 80, 81:       return (.rain, .moderate)
        case 82:           return (.rain, .heavy)
        case 85:           return (.snow, .moderate)
        case 86:           return (.snow, .heavy)
        case 95, 96, 99:   return (.storm, .heavy)
        default:           return (.cloudy, .light)
        }
    }
}

struct OpenMeteoWeatherProvider: WeatherProvider {
    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        let current: Current
    }

    static func decode(_ data: Data) throws -> WeatherSnapshot {
        let r = try JSONDecoder().decode(Response.self, from: data)
        let isDay = r.current.is_day == 1
        let (cond, inten) = WMO.map(code: r.current.weather_code, isDay: isDay)
        return WeatherSnapshot(tempF: Int(r.current.temperature_2m.rounded()),
                               condition: cond, intensity: inten, isDay: isDay, capturedAt: Date())
    }

    func current(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(coord.latitude)),
            .init(name: "longitude", value: String(coord.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "timezone", value: "America/Chicago"),
        ]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 8
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.decode(data)
    }
}

final class CachedWeatherProvider {
    private let base: WeatherProvider
    private let defaults: UserDefaults
    private let ttl: TimeInterval
    private let key = "blockparty.atmosphere.weather"

    init(base: WeatherProvider, defaults: UserDefaults = .standard, ttlSeconds: TimeInterval = 1200) {
        self.base = base; self.defaults = defaults; self.ttl = ttlSeconds
    }

    /// Last snapshot regardless of age (for instant paint + offline). nil if none.
    var cached: WeatherSnapshot? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: d)
    }

    var isStale: Bool {
        guard let c = cached else { return true }
        return Date().timeIntervalSince(c.capturedAt) > ttl
    }

    func store(_ s: WeatherSnapshot) {
        if let d = try? JSONEncoder().encode(s) { defaults.set(d, forKey: key) }
    }

    /// Fetch fresh, store, return.
    func current(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        let s = try await base.current(at: coord)
        store(s)
        return s
    }
}
```

- [ ] **Step 4: Run to verify it passes** — same command. Expected: all `PASS`.

- [ ] **Step 5: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/WeatherProvider.swift
git commit -m "feat(map): WeatherProvider — Open-Meteo + WMO map + UserDefaults cache"
```

---

### Task 5: BasemapPalette (`BasemapPalette.swift`)

Atmosphere → Mapbox layer hexes + a wash spec. The tuned aesthetic core. Guarded so summer·noon·clear reproduces today's exact anchor (regression guard on the Life360 look).

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/BasemapPalette.swift`
- Test: `scratchpad/palette_main.swift`

**Interfaces — Consumes:** `TownAtmosphere` (Task 1). **Produces:**
- `struct BasemapPalette: Equatable { let land, green, water, building: String; let wash: Wash; struct Wash: Equatable { let r, g, b, a: Double } }`
- `static func make(for atmo: TownAtmosphere) -> BasemapPalette`

- [ ] **Step 1: Write the failing test** — `scratchpad/palette_main.swift`

```swift
import Foundation
var failures = 0
func expect(_ c: Bool, _ m: String) { print(c ? "PASS \(m)" : "FAIL \(m)"); if !c { failures += 1 } }
func lum(_ hex: String) -> Double {  // rough perceived brightness
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let v = UInt32(h, radix: 16) ?? 0
    let r = Double((v>>16)&0xFF), g = Double((v>>8)&0xFF), b = Double(v&0xFF)
    return (0.299*r + 0.587*g + 0.114*b) / 255
}

var noon = TownAtmosphere.placeholder  // summer, day, clear, dayFactor 1
noon.dayFactor = 1
let p = BasemapPalette.make(for: noon)
expect(p.land == "#F0EBE3" && p.green == "#C9E0B4" && p.water == "#A6CBE6" && p.building == "#E8E4DC",
       "summer·noon·clear == tuned anchor")
expect(p.wash.a < 0.02, "clear day → ~no wash")

var night = noon; night.dayFactor = 0; night.phase = .night; night.isDay = false
let pn = BasemapPalette.make(for: night)
expect(lum(pn.land) < lum(p.land), "night land darker than day")
expect(pn.wash.a > 0.1, "night wash present")

var winter = noon; winter.season = .winter
let pw = BasemapPalette.make(for: winter)
expect(lum(pw.green) > lum(p.green), "winter green paler/frostier than summer sage")

// all hexes valid 7-char
for hex in [p.land, p.green, p.water, p.building, pn.land, pw.green] {
    expect(hex.count == 7 && hex.hasPrefix("#"), "valid hex \(hex)")
}
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails** — `swiftc -D DEBUG -o "$SP/check" BlockParty/Features/Map/Atmosphere/BasemapPalette.swift BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift "$SP/palette_main.swift" && "$SP/check"` → FAIL.

- [ ] **Step 3: Implement** — `BlockParty/Features/Map/Atmosphere/BasemapPalette.swift`

```swift
//
//  BasemapPalette.swift
//  Block Party — the Living Basemap's tuned cartography: TownAtmosphere → Mapbox layer
//  hexes + a time wash. Summer·noon·clear reproduces the tuned Life360 anchor
//  exactly; season/time/sky modulate around it in HSB, bounded to stay tasteful.
//  Pure Foundation — the ONLY raw hexes the map is allowed (it owns cartography).
//

import Foundation

struct BasemapPalette: Equatable {
    let land: String, green: String, water: String, building: String
    let wash: Wash
    struct Wash: Equatable { let r, g, b, a: Double }

    // Seasonal anchors (first-cut; screenshot-tunable). Summer == today's MapPalette.
    private struct Roles { let land, green, water, building: HSB }
    private static let anchors: [Season: Roles] = [
        .summer: Roles(land: HSB("#F0EBE3"), green: HSB("#C9E0B4"), water: HSB("#A6CBE6"), building: HSB("#E8E4DC")),
        .autumn: Roles(land: HSB("#F1E9DC"), green: HSB("#D8CB8C"), water: HSB("#A8C6D9"), building: HSB("#E9E2D6")),
        .winter: Roles(land: HSB("#EDEEF0"), green: HSB("#DCE4DE"), water: HSB("#BCD2E0"), building: HSB("#E6E7EA")),
        .spring: Roles(land: HSB("#EFEFE6"), green: HSB("#C6E2A8"), water: HSB("#A9CFE8"), building: HSB("#E7E7DE")),
    ]
    private static func nextSeason(_ s: Season) -> Season {
        switch s { case .winter: return .spring; case .spring: return .summer; case .summer: return .autumn; case .autumn: return .winter }
    }

    static func make(for a: TownAtmosphere) -> BasemapPalette {
        let base = anchors[a.season]!
        let next = anchors[nextSeason(a.season)]!
        // Blend toward next season near the boundary.
        var land = base.land.lerp(to: next.land, a.seasonBlend)
        var green = base.green.lerp(to: next.green, a.seasonBlend)
        var water = base.water.lerp(to: next.water, a.seasonBlend)
        var building = base.building.lerp(to: next.building, a.seasonBlend)

        // TIME: brightness + saturation fall off toward night; golden adds warmth.
        let df = a.dayFactor
        let bright = 0.72 + 0.28 * df          // night 0.72 → noon 1.0
        let sat    = 0.70 + 0.30 * df          // desaturate at night
        for role in [\Roles.self] { _ = role }  // (no-op; explicit per-role below)
        func timeMod(_ c: HSB, isWater: Bool) -> HSB {
            var x = c.scaledBrightness(bright).scaledSaturation(sat)
            if a.phase == .golden {             // warm amber push
                x = x.hueShifted(byDegrees: -8).scaledSaturation(1.12).scaledBrightness(0.98)
            }
            if isWater {                         // water → deep slate-blue at night
                x = x.lerpHSB(to: HSB("#3E4E63"), (1 - df) * 0.35)
            }
            return x
        }
        land = timeMod(land, isWater: false)
        green = timeMod(green, isWater: false)
        water = timeMod(water, isWater: true)
        building = timeMod(building, isWater: false)

        // SKY: overcast/fog flatten; fresh snow lifts ground toward white; rain cools.
        switch a.sky {
        case .overcast, .fog:
            land = land.scaledSaturation(0.85); green = green.scaledSaturation(0.85)
            building = building.scaledSaturation(0.9)
        case .snow:
            let lift = a.intensity == .heavy ? 0.22 : 0.14
            land = land.lerp(to: HSB("#FFFFFF"), lift); green = green.lerp(to: HSB("#F2F5F3"), lift)
        case .rain, .storm:
            land = land.scaledBrightness(0.95); green = green.scaledBrightness(0.95); water = water.scaledBrightness(0.95)
        default: break
        }

        return BasemapPalette(land: land.hex, green: green.hex, water: water.hex, building: building.hex,
                              wash: washFor(a))
    }

    // Wash: discrete per phase (the overlay animates opacity so changes cross-fade).
    private static func washFor(_ a: TownAtmosphere) -> Wash {
        switch a.phase {
        case .day:    return Wash(r: 1, g: 1, b: 1, a: 0.0)
        case .dawn:   return Wash(r: 0.98, g: 0.80, b: 0.74, a: 0.10)   // soft rose
        case .golden: return Wash(r: 1.0, g: 0.72, b: 0.44, a: 0.14)    // warm gold
        case .dusk:   return Wash(r: 0.47, g: 0.35, b: 0.55, a: 0.12)   // violet
        case .night:  return Wash(r: 0.11, g: 0.14, b: 0.25, a: 0.16)   // indigo
        }
    }
}

// Minimal HSB helper over hex — kept local to the palette (its only consumer).
private struct HSB: Equatable {
    var h: Double, s: Double, b: Double   // h in 0…360, s/b in 0…1
    init(h: Double, s: Double, b: Double) { self.h = h; self.s = s; self.b = b }
    init(_ hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(raw, radix: 16) ?? 0
        let r = Double((v>>16)&0xFF)/255, g = Double((v>>8)&0xFF)/255, bl = Double(v&0xFF)/255
        let mx = max(r,g,bl), mn = min(r,g,bl), d = mx - mn
        var hue = 0.0
        if d != 0 {
            if mx == r { hue = 60 * (((g-bl)/d).truncatingRemainder(dividingBy: 6)) }
            else if mx == g { hue = 60 * (((bl-r)/d) + 2) }
            else { hue = 60 * (((r-g)/d) + 4) }
        }
        if hue < 0 { hue += 360 }
        self.h = hue; self.s = mx == 0 ? 0 : d/mx; self.b = mx
    }
    var hex: String {
        let c = b * s, x = c * (1 - abs((h/60).truncatingRemainder(dividingBy: 2) - 1)), m = b - c
        var r = 0.0, g = 0.0, bl = 0.0
        switch h {
        case ..<60:   (r,g,bl) = (c,x,0)
        case ..<120:  (r,g,bl) = (x,c,0)
        case ..<180:  (r,g,bl) = (0,c,x)
        case ..<240:  (r,g,bl) = (0,x,c)
        case ..<300:  (r,g,bl) = (x,0,c)
        default:      (r,g,bl) = (c,0,x)
        }
        func hh(_ v: Double) -> String { String(format: "%02X", Int(((v+m)*255).rounded().clamped(0,255))) }
        return "#\(hh(r))\(hh(g))\(hh(bl))"
    }
    func scaledBrightness(_ f: Double) -> HSB { HSB(h: h, s: s, b: (b*f).clamped(0,1)) }
    func scaledSaturation(_ f: Double) -> HSB { HSB(h: h, s: (s*f).clamped(0,1), b: b) }
    func hueShifted(byDegrees d: Double) -> HSB { HSB(h: (h+d).truncatingRemainder(dividingBy: 360), s: s, b: b) }
    func lerpHSB(to o: HSB, _ t: Double) -> HSB { HSB(h: h + (o.h-h)*t, s: s + (o.s-s)*t, b: b + (o.b-b)*t) }
    func lerp(to o: HSB, _ t: Double) -> HSB { lerpHSB(to: o, t) }
}
private extension Double { func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) } }
```

> Note: delete the stray `for role in [\Roles.self]` line — it is a placeholder artifact; the real modulation is the explicit `timeMod` calls below it. (Kept here so the reviewer notices and removes it.)

- [ ] **Step 4: Run to verify it passes** — same command. Expected: all `PASS`. If summer·noon·clear anchors don't match exactly, the modulation is altering a unit-input case it shouldn't — ensure `dayFactor 1 + phase .day + season .summer + sky .clear + seasonBlend 0` is an identity for land/green/water/building.

- [ ] **Step 5: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/BasemapPalette.swift
git commit -m "feat(map): BasemapPalette — atmosphere → tuned cartography + wash"
```

---

### Task 6: AtmosphereModel + DEBUG override (`AtmosphereModel.swift`, `AtmosphereOverride.swift`)

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/AtmosphereOverride.swift` (pure parser)
- Create: `BlockParty/Features/Map/Atmosphere/AtmosphereModel.swift` (@MainActor model)
- Test: `scratchpad/override_main.swift` (parser only; model verified in Task 10)

**Interfaces — Consumes:** all of Tasks 1–5. **Produces:**
- `enum AtmosphereOverride { static func parse(_ args: [String]) -> [String: String]? }`
- `@MainActor final class AtmosphereModel: ObservableObject { @Published private(set) var current: TownAtmosphere; func start(); func onForeground(); func stop() }`

- [ ] **Step 1: Write the failing test** — `scratchpad/override_main.swift`

```swift
import Foundation
var failures = 0
func expect(_ c: Bool, _ m: String) { print(c ? "PASS \(m)" : "FAIL \(m)"); if !c { failures += 1 } }

expect(AtmosphereOverride.parse(["app"]) == nil, "no flag → nil")
let o = AtmosphereOverride.parse(["-atmosphere", "season:winter,phase:night,sky:snow,temp:38"])!
expect(o["season"] == "winter" && o["phase"] == "night" && o["sky"] == "snow" && o["temp"] == "38", "parses k:v pairs")
let applied = TownAtmosphere.placeholder.applying(o)
expect(applied.season == .winter && applied.sky == .snow && applied.tempF == 38 && applied.phase == .night, "apply → mood")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails** — `swiftc -D DEBUG -o "$SP/check" BlockParty/Features/Map/Atmosphere/AtmosphereOverride.swift BlockParty/Features/Map/Atmosphere/TownAtmosphere.swift "$SP/override_main.swift" && "$SP/check"` → FAIL.

- [ ] **Step 3a: Implement** — `BlockParty/Features/Map/Atmosphere/AtmosphereOverride.swift`

```swift
//
//  AtmosphereOverride.swift
//  Block Party — DEBUG-only launch-arg parser to force any atmosphere for headless
//  screenshot verification: -atmosphere season:winter,phase:night,sky:snow,temp:38
//  Keys: season, phase, sky, intensity, temp, daylight (0…1), isday. Any subset.
//

import Foundation

enum AtmosphereOverride {
    /// Returns the parsed key/value map, or nil if `-atmosphere` isn't present.
    static func parse(_ args: [String]) -> [String: String]? {
        guard let i = args.firstIndex(of: "-atmosphere"), i + 1 < args.count else { return nil }
        var out: [String: String] = [:]
        for pair in args[i + 1].split(separator: ",") {
            let kv = pair.split(separator: ":", maxSplits: 1)
            if kv.count == 2 { out[String(kv[0]).lowercased()] = String(kv[1]).lowercased() }
        }
        return out.isEmpty ? nil : out
    }
}
```

- [ ] **Step 3b: Run parser test** — same command as Step 2. Expected: all `PASS`.

- [ ] **Step 3c: Implement** — `BlockParty/Features/Map/Atmosphere/AtmosphereModel.swift`

```swift
//
//  AtmosphereModel.swift
//  Block Party — owns the Living Basemap's composed atmosphere.
//
//  Time + season are computed synchronously (offline) so `current` is alive the
//  instant the map appears; cached weather fills sky immediately; a background
//  fetch refines it. Recomputes time on a 1-min heartbeat so the palette + wash
//  ease through the day. MapModel stays events/realtime — this is the clean seam.
//

import Foundation
import Combine
import CoreLocation

@MainActor
final class AtmosphereModel: ObservableObject {
    @Published private(set) var current: TownAtmosphere = .placeholder

    private let coord = MapSpots.center
    private let weather: CachedWeatherProvider
    private let forced: [String: String]?     // DEBUG override
    private var tickTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var started = false

    init(provider: WeatherProvider = OpenMeteoWeatherProvider()) {
        self.weather = CachedWeatherProvider(base: provider)
        #if DEBUG
        self.forced = AtmosphereOverride.parse(ProcessInfo.processInfo.arguments)
        #else
        self.forced = nil
        #endif
        recompute()   // publish a live v0 immediately (or the forced mood)
    }

    func start() {
        guard !started else { return }
        started = true
        if forced != nil { return }            // frozen mood; no timers/network
        applyCached()
        scheduleRefresh(initial: true)
        startTick()
    }

    func onForeground() {
        guard started, forced == nil else { return }
        recompute()
        if weather.isStale { scheduleRefresh(initial: false) }
        startTick()
    }

    func stop() {
        tickTask?.cancel(); tickTask = nil
        refreshTask?.cancel(); refreshTask = nil
    }

    // MARK: composition

    /// Recompute time + season (offline) and merge with the latest known sky.
    private func recompute() {
        let now = Date()
        let season = SeasonClock.current(now)
        var a = current
        a.dayFactor = SolarClock.dayFactor(at: now, coord: coord)
        a.phase = SolarClock.phase(at: now, coord: coord)
        a.season = season.season
        a.seasonBlend = season.blend
        if let f = forced { a = a.applying(f) }
        current = a
    }

    private func applyCached() {
        guard let s = weather.cached else { return }
        merge(s)
    }

    private func merge(_ s: WeatherSnapshot) {
        var a = current
        a.sky = s.condition; a.intensity = s.intensity; a.tempF = s.tempF; a.isDay = s.isDay
        a.resolvedAt = s.capturedAt
        if let f = forced { a = a.applying(f) }
        current = a
    }

    private func scheduleRefresh(initial: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { let s = try await self.weather.current(at: self.coord); self.merge(s) }
            catch { /* keep cached/stale; whisper never blanks */ }
        }
    }

    private func startTick() {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)   // 1 min
                guard let self, self.started, self.forced == nil else { break }
                self.recompute()
                if self.weather.isStale { self.scheduleRefresh(initial: false) }
            }
        }
    }
}
```

- [ ] **Step 4: Build the app to verify the model compiles** — see Task 10's build command (the model needs the app target). For this task, confirm no new build errors after adding both files.

- [ ] **Step 5: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/AtmosphereOverride.swift BlockParty/Features/Map/Atmosphere/AtmosphereModel.swift
git commit -m "feat(map): AtmosphereModel + DEBUG -atmosphere override"
```

---

### Task 7: TimeWashOverlay (`TimeWashOverlay.swift`)

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/TimeWashOverlay.swift`

**Interfaces — Consumes:** `TownAtmosphere`, `BasemapPalette` (Tasks 1, 5). **Produces:** `struct TimeWashOverlay: View { let atmosphere: TownAtmosphere }` — a non-interactive full-field gradient; night ≈ uniform veil, golden/dawn/dusk ≈ directional; opacity cross-fades on phase change (Reduce Motion: instant).

- [ ] **Step 1: Implement**

```swift
//
//  TimeWashOverlay.swift
//  Block Party — the atmospheric glow above the basemap. Low opacity (≤0.16) so pins
//  stay crisp; the palette (below the pins) carries most of the time feel. Night
//  is a near-uniform veil; golden/dawn/dusk are directional (light from a corner).
//

import SwiftUI

struct TimeWashOverlay: View {
    let atmosphere: TownAtmosphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let w = BasemapPalette.make(for: atmosphere).wash
        let c = Color(.sRGB, red: w.r, green: w.g, blue: w.b, opacity: w.a)
        let uniform = atmosphere.phase == .night
        Rectangle()
            .fill(
                LinearGradient(
                    colors: uniform ? [c, c]
                                    : [c, Color(.sRGB, red: w.r, green: w.g, blue: w.b, opacity: w.a * 0.15)],
                    startPoint: .topTrailing, endPoint: .bottomLeading
                )
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: atmosphere.phase)
    }
}
```

- [ ] **Step 2: Build to verify it compiles** — Task 10 build command. Expected: 0 warnings.

- [ ] **Step 3: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/TimeWashOverlay.swift
git commit -m "feat(map): TimeWashOverlay — time-of-day glow"
```

---

### Task 8: WeatherParticles (`WeatherParticles.swift`)

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/WeatherParticles.swift`

**Interfaces — Consumes:** `TownAtmosphere` (Task 1). **Produces:** `struct WeatherParticles: View { let atmosphere: TownAtmosphere }` — snow/rain/storm only; `Canvas` in `TimelineView(.animation)`; capped counts; non-interactive; `accessibilityHidden`; Reduce Motion → static frame.

- [ ] **Step 1: Implement**

```swift
//
//  WeatherParticles.swift
//  Block Party — GPU-cheap precip over the map. Snow drifts, rain streaks; fog/overcast
//  get no particles (handled as haze in the palette). Capped counts, non-
//  interactive, decorative. Reduce Motion → a still frame (no TimelineView).
//

import SwiftUI

struct WeatherParticles: View {
    let atmosphere: TownAtmosphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Particle { let x: CGFloat; let phase: CGFloat; let scale: CGFloat; let speed: CGFloat; let sway: CGFloat }

    private var kind: Kind? {
        switch atmosphere.sky {
        case .snow: return .snow
        case .rain, .storm: return .rain
        default: return nil
        }
    }
    private enum Kind { case snow, rain }

    private var count: Int {
        guard let kind else { return 0 }
        let base = kind == .snow ? 44 : 60
        switch atmosphere.intensity { case .light: return Int(Double(base) * 0.6); case .heavy: return base + 20; default: return base }
    }

    // Deterministic scatter (no Math.random at render time; stable across frames).
    private var particles: [Particle] {
        (0..<count).map { i in
            let f = CGFloat(i)
            return Particle(
                x: (f * 0.6180339).truncatingRemainder(dividingBy: 1),
                phase: (f * 0.3542).truncatingRemainder(dividingBy: 1),
                scale: 0.6 + (f * 0.271).truncatingRemainder(dividingBy: 1) * 0.8,
                speed: 0.7 + (f * 0.113).truncatingRemainder(dividingBy: 1) * 0.6,
                sway: (f * 0.197).truncatingRemainder(dividingBy: 1)
            )
        }
    }

    var body: some View {
        if kind != nil {
            if reduceMotion {
                Canvas { ctx, size in draw(ctx: ctx, size: size, t: 0.2) }
                    .allowsHitTesting(false).accessibilityHidden(true).ignoresSafeArea()
            } else {
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        draw(ctx: ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate)
                    }
                    .allowsHitTesting(false).accessibilityHidden(true).ignoresSafeArea()
                }
            }
        }
    }

    private func draw(ctx: GraphicsContext, size: CGSize, t: TimeInterval) {
        guard let kind else { return }
        let color: Color = kind == .snow ? .white.opacity(0.85) : Color(.sRGB, red: 0.7, green: 0.78, blue: 0.86, opacity: 0.55)
        for p in particles {
            let cycle = (CGFloat(t) * p.speed * (kind == .snow ? 0.05 : 0.22) + p.phase).truncatingRemainder(dividingBy: 1)
            let y = cycle * (size.height + 40) - 20
            let swayX = kind == .snow ? sin((CGFloat(t) * 0.6) + p.sway * 6) * 10 : 0
            let x = p.x * size.width + swayX
            if kind == .snow {
                let r = 1.5 * p.scale
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r*2, height: r*2)), with: .color(color))
            } else {
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x - 1.5, y: y + 12 * p.scale))
                ctx.stroke(line, with: .color(color), lineWidth: 1.1)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles** — Task 10 build command. Expected: 0 warnings.

- [ ] **Step 3: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/WeatherParticles.swift
git commit -m "feat(map): WeatherParticles — snow/rain, Reduce-Motion static"
```

---

### Task 9: AtmosphereWhisper (`AtmosphereWhisper.swift`)

**Files:**
- Create: `BlockParty/Features/Map/Atmosphere/AtmosphereWhisper.swift`

**Interfaces — Consumes:** `TownAtmosphere` (Task 1) + `Hue` tokens. **Produces:** `struct AtmosphereWhisper: View { let atmosphere: TownAtmosphere }` — the town pill's second line; muted glyph + `Hue.ink2` text; **no coral**; fades/slides in when weather resolves; a11y label from `accessibilityText`.

- [ ] **Step 1: Implement**

```swift
//
//  AtmosphereWhisper.swift
//  Block Party — the quiet "why" under the town pill: "❄ 38° · light snow · 4:15".
//  Neutral ink + a muted weather glyph — never coral (coral stays live/tappable).
//  Hidden until weather resolves; expands in with a gentle fade+slide.
//

import SwiftUI

struct AtmosphereWhisper: View {
    let atmosphere: TownAtmosphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let line = atmosphere.whisperLine(now: Date()) {
                HStack(spacing: 5) {
                    Image(systemName: atmosphere.glyph)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Hue.ink3)
                    Text(line)
                        .font(.sansMedium(12))
                        .foregroundStyle(Hue.ink2)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(atmosphere.accessibilityText ?? line)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: atmosphere.resolvedAt != nil)
    }
}
```

> If `Font.sansMedium(_:)` isn't the exact helper name, use the nearest existing `Font.sans*` helper from `BlockPartyFont.swift` (all map to the system font by weight) — check that file; do not introduce a new font.

- [ ] **Step 2: Build to verify it compiles** — Task 10 build command. Expected: 0 warnings.

- [ ] **Step 3: Commit**

```bash
git add BlockParty/Features/Map/Atmosphere/AtmosphereWhisper.swift
git commit -m "feat(map): AtmosphereWhisper — quiet weather line under the pill"
```

---

### Task 10: Integrate into SJMapView + full simulator verification (`SJMapView.swift`)

Wire the model in, recolor from the palette **on atmosphere change** (the key change — recolor currently runs once on style load), layer in the wash + particles, embed the whisper in the town pill, and verify every mood in the sim.

**Files:**
- Modify: `BlockParty/Features/Map/SJMapView.swift`
- Docs: append a `-atmosphere` bullet to `CLAUDE.md` DEBUG-flag list + a Living Basemap entry to `MAP_BUILD_LOG.md`.

**Interfaces — Consumes:** `AtmosphereModel`, `BasemapPalette`, `TimeWashOverlay`, `WeatherParticles`, `AtmosphereWhisper` (Tasks 5–9).

- [ ] **Step 1: Add the model + capture the MapboxMap.** In `SJMapView`:
  - Add `@StateObject private var atmosphere = AtmosphereModel()`.
  - Add `@State private var mapRef: MapboxMap?`.
  - In `mapLayer`, capture the map: change `.onStyleLoaded { _ in recolorBasemap(proxy.map) }` to also store it: `.onStyleLoaded { _ in mapRef = proxy.map; recolorBasemap(proxy.map) }`.

- [ ] **Step 2: Make `recolorBasemap` read the palette.** Replace the static `MapPalette` uses in `recolorBasemap(_:)` with the computed palette:

```swift
private func recolorBasemap(_ map: MapboxMap?) {
    guard let map else { return }
    let p = BasemapPalette.make(for: atmosphere.current)
    for id in ["land", "background"] {
        try? map.setLayerProperty(for: id, property: "background-color", value: p.land)
    }
    for id in ["landuse", "landcover", "national-park", "park", "pitch", "grass"] {
        try? map.setLayerProperty(for: id, property: "fill-color", value: p.green)
    }
    try? map.setLayerProperty(for: "water",    property: "fill-color", value: p.water)
    try? map.setLayerProperty(for: "waterway", property: "line-color", value: p.water)
    try? map.setLayerProperty(for: "building", property: "fill-color",         value: p.building)
    try? map.setLayerProperty(for: "building", property: "fill-outline-color", value: p.building)
}
```
  Delete the now-unused static `MapPalette` enum (its four hexes now live as `BasemapPalette`'s summer anchor).

- [ ] **Step 3: Re-color on atmosphere change + lifecycle.** In `body`, add to the `ZStack`/modifiers:
  - `.onChange(of: atmosphere.current) { _, _ in recolorBasemap(mapRef) }`
  - `.onAppear { atmosphere.start() }` (alongside `model.start`)
  - In the existing `scenePhase` `.active` branch add `atmosphere.onForeground()`; in `.onDisappear` add `atmosphere.stop()`.

- [ ] **Step 4: Layer the wash + particles.** In the top-level `ZStack(alignment: .top)`, insert directly above `topChrome` (so they sit over the map but under all chrome/sheet):

```swift
mapLayer
TimeWashOverlay(atmosphere: atmosphere.current)
WeatherParticles(atmosphere: atmosphere.current)
topChrome
floatingControls
MapSheet( ... )
```

- [ ] **Step 5: Embed the whisper in the town pill.** Change `townPill` so the name + whisper stack:

```swift
private var townPill: some View {
    VStack(spacing: 2) {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Hue.accent)
            Text(model.townLabel)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.mapInk)
                .lineLimit(1)
        }
        AtmosphereWhisper(atmosphere: atmosphere.current)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(Hue.surface, in: Capsule())
    .overlay(Capsule().stroke(Hue.mapHairline, lineWidth: 1))
    .mapFloatShadow()
    .animation(.easeInOut(duration: 0.2), value: model.townLabel)
    .accessibilityElement(children: .combine)
}
```
  (Coral `mappin` stays — it's the pill's identity marker, still "tappable/primary" semantics; the whisper glyph is the muted one. If review deems the coral pin now over-uses coral next to the neutral whisper, switch the mappin to `Hue.mapInk` — flag for the design-review pass.)

- [ ] **Step 6: Build clean (0 warnings).**

```bash
xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`, no warnings. (New files auto-included via the synchronized group.) If "Multiple commands produce": `find BlockParty -type d -name .impeccable -exec rm -rf {} +` and rebuild.

- [ ] **Step 7: Install the FRESH build (avoid the DerivedData trap) + boot sim.**

```bash
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
[ -z "$UDID" ] && UDID=$(xcrun simctl boot "iPhone 17" >/dev/null 2>&1; xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
DIR=$(xcodebuild -project BlockParty.xcodeproj -scheme BlockParty -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')
xcrun simctl install "$UDID" "$DIR/BlockParty.app"
```

- [ ] **Step 8: Screenshot the mood matrix** (each forces a mood headlessly; `-force-nonadmin` keeps chrome consistent):

```bash
for M in "season:summer,phase:day,sky:clear,temp:78,daylight:1.0,isday:1" \
         "season:autumn,phase:golden,sky:clear,temp:61,daylight:0.35,isday:1" \
         "season:winter,phase:night,sky:snow,intensity:moderate,temp:24,daylight:0.0,isday:0" \
         "season:spring,phase:dawn,sky:rain,intensity:moderate,temp:47,daylight:0.15,isday:1" \
         "season:summer,phase:day,sky:overcast,temp:66,daylight:0.8,isday:1"; do
  xcrun simctl terminate "$UDID" Jesse.Hygge 2>/dev/null
  xcrun simctl launch "$UDID" Jesse.Hygge -open-tab map -force-nonadmin -atmosphere "$M"
  sleep 3
  xcrun simctl io "$UDID" screenshot "$SP/atmo-${M%%,*}.png"
done
```
  Read each screenshot. **Acceptance:** summer·day·clear ≈ today's look; autumn·golden shows warm wash + tawny parks; winter·night·snow shows pale/dark palette + indigo veil + visible drifting snow + the whisper "24° · snow · h:mm"; spring·dawn·rain shows rose wash + rain streaks; overcast desaturates. **Pins + town pill text remain clearly legible in every shot** (especially night) — if night crushes pin contrast, raise `BasemapPalette` night `bright` floor above 0.72 and re-verify.

- [ ] **Step 9: Montage-verify motion** (snow drift + golden→night wash), per the project's established loop: record with `-atmosphere winter…snow`, extract frames, build a contact sheet, confirm the snow actually moves and the wash cross-fades. (Reduce Motion path: relaunch with the sim's Reduce Motion on and confirm particles are static + whisper still present.)

- [ ] **Step 10: Update docs + commit.** Add to `CLAUDE.md` the `-atmosphere` DEBUG bullet (mirroring the `-almanac-write` entry style) and a "Living basemap" note in the Map section; append a dated Living Basemap section to `MAP_BUILD_LOG.md` (what shipped + verified moods).

```bash
git add BlockParty/Features/Map/SJMapView.swift CLAUDE.md MAP_BUILD_LOG.md
git commit -m "feat(map): Living Basemap — time/season/weather modulate the map

Atmosphere (SolarClock + SeasonClock + Open-Meteo) drives the basemap palette,
a time wash, snow/rain particles, and a quiet weather whisper under the town
pill. Recolor now re-applies on atmosphere change. No schema, no backend, no
location permission. -atmosphere DEBUG flag forces any mood for verification."
```

---

## Self-Review

**1. Spec coverage:**
- Time-of-day (continuous + phase) → Task 2 ✓ · Season → Task 3 ✓ · Weather (Open-Meteo, cached, swappable) → Task 4 ✓ · Palette modulation → Task 5 ✓ · Model/compose/first-frame-offline → Task 6 ✓ · Time wash → Task 7 ✓ · Particles (+Reduce Motion) → Task 8 ✓ · Whisper (+coral-reserved, a11y) → Task 9 ✓ · Integration/recolor-on-change/pill/lifecycle → Task 10 ✓ · DEBUG `-atmosphere` → Tasks 6+10 ✓ · WeatherKit seam → Task 4 header ✓ · No schema/backend/permission → Global Constraints ✓ · Verification matrix + montage → Task 10 ✓.
- Anchored-to-St-Joe: `AtmosphereModel.coord = MapSpots.center` (Task 6) ✓. Town pill name still pan-follows (`model.townLabel` untouched in Task 10 Step 5) ✓.

**2. Placeholder scan:** One intentional artifact flagged in Task 5 Step 3 (the `for role in [\Roles.self]` line) with an explicit "delete this" note so it can't slip through silently. No "TBD"/"handle edge cases"/"similar to Task N". Test code is literal.

**3. Type consistency:** `TownAtmosphere` field names (`dayFactor/phase/season/seasonBlend/sky/intensity/tempF/isDay/resolvedAt`) are used identically in Tasks 5/6/7/8/9. `BasemapPalette.make(for:)` signature consistent across Tasks 5/7/10. `WeatherSnapshot` fields consistent across Tasks 4/6. `CachedWeatherProvider(base:defaults:ttlSeconds:)` matches its harness call. `AtmosphereOverride.parse(_:) -> [String:String]?` + `TownAtmosphere.applying(_:)` consistent across Tasks 1/6.

**Open follow-ups for the design-review pass (not blockers):** whisper-vs-coral-pin balance (Task 10 Step 5 note); night contrast floor (Task 10 Step 8); wash directionality per phase (Task 7) — all resolved against screenshots during verification.
