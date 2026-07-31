//
//  WeatherBar.swift
//  Block Party — weather bar: live current conditions over a WeatherBackground.
//
//  Honest data only: the temperature comes from open-meteo (no key, no auth).
//  If the fetch fails we keep the place + a matched gradient, never a fake number.
//

import SwiftUI

// MARK: - Model

struct Weather {
    let tempF: Int
    let feelsLikeF: Int          // apparent_temperature — the Utility Row weather tile's "feels 78°"
    let highF: Int
    let lowF: Int
    let label: String
    let state: WeatherState
    let windGustMph: Int?        // wind_gusts_10m (current); nil if unavailable
    let precipProbNext2h: Int?   // max precipitation_probability over the next 2 hourly buckets
    let precipPeakTime: Date?    // time of that peak — powers "Rain 60% by 3 PM"
    let aqi: Int?                // US AQI (air-quality endpoint); nil if that best-effort call fails
    let sunrise: Date?           // today's sunrise, read in the town's timezone; nil if unavailable
    let sunset: Date?            // today's sunset, ditto — powers the Daily Almanac nudge
}

// MARK: - Service (open-meteo, St. Joseph, MN)

// The module builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so this enum
// is already main-actor isolated: `cached` is only ever read/written from the
// single main-actor `.task` caller, so no extra guarding is needed.
enum WeatherService {
    private static var cached: (weather: Weather, at: Date)?
    private static let ttl: TimeInterval = 15 * 60  // 15 minutes

    private static let lat = "45.565", lon = "-94.3186"   // St. Joseph, MN

    /// The town's timezone. Open-Meteo is pinned to it (see the URL), so the
    /// sunrise/sunset strings come back as Chicago wall-clock with no offset —
    /// parse and display in this zone so the Almanac always speaks in St. Joe time.
    static let townTZ = TimeZone(identifier: "America/Chicago") ?? .current

    private static var inFlight: Task<Weather?, Never>?

    static func current() async -> Weather? {
        if let c = cached, Date().timeIntervalSince(c.at) < ttl { return c.weather }
        // Coalesce concurrent callers (weather tile + almanac + hero) into ONE
        // fetch, instead of a cache stampede of duplicate open-meteo calls.
        if let inFlight { return await inFlight.value }
        let task = Task<Weather?, Never> { await fetchWeather() }
        inFlight = task
        let weather = await task.value
        inFlight = nil
        return weather
    }

    private static func fetchWeather() async -> Weather? {
        // Two independent Open-Meteo calls (both free, no key): the forecast API
        // and the air-quality API. They overlap across the network wait. AQI is
        // best-effort — its failure just drops AQI, never the whole readout.
        async let forecastTask = fetchForecast()
        async let aqiTask = fetchAQI()
        guard let f = await forecastTask else { return cached?.weather }
        let aqi = await aqiTask

        let isDay = f.current.is_day == 1
        let precip = precipNext2h(f.hourly)
        let weather = Weather(
            tempF: Int(f.current.temperature_2m.rounded()),
            feelsLikeF: Int((f.current.apparent_temperature ?? f.current.temperature_2m).rounded()),
            highF: Int((f.daily.temperature_2m_max.first ?? f.current.temperature_2m).rounded()),
            lowF: Int((f.daily.temperature_2m_min.first ?? f.current.temperature_2m).rounded()),
            label: label(code: f.current.weather_code, isDay: isDay),
            state: WeatherState.from(code: f.current.weather_code, isDay: isDay),
            windGustMph: f.current.wind_gusts_10m.map { Int($0.rounded()) },
            precipProbNext2h: precip?.prob,
            precipPeakTime: precip?.at,
            aqi: aqi,
            sunrise: parseLocalTime(f.daily.sunrise?.first),
            sunset: parseLocalTime(f.daily.sunset?.first)
        )
        cached = (weather, Date())
        return weather
    }

    private static func fetchForecast() async -> Response? {
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_gusts_10m"
            + "&hourly=precipitation_probability"
            + "&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset"
            + "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America%2FChicago&forecast_days=2"
        guard let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(Response.self, from: data)
    }

    private static func fetchAQI() async -> Int? {
        let s = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=us_aqi&timezone=America%2FChicago&forecast_days=1"
        guard let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(AirQualityResponse.self, from: data) else { return nil }
        return currentHourValue(times: r.hourly.time, values: r.hourly.us_aqi)
    }

    /// Max precipitation probability over the next two hourly buckets (the current
    /// hour + the next), and the time of that peak. nil if hourly data is absent.
    private static func precipNext2h(_ hourly: Response.Hourly?) -> (prob: Int, at: Date)? {
        guard let hourly, let probs = hourly.precipitation_probability else { return nil }
        let times = hourly.time.compactMap { localTimeParser.date(from: $0) }
        guard times.count == probs.count else { return nil }
        let now = Date()
        // First bucket whose hour hasn't fully passed, then look at up to 2 buckets.
        guard let start = times.firstIndex(where: { $0 >= now.addingTimeInterval(-3600) }) else { return nil }
        var best: (prob: Int, at: Date)?
        for i in start..<min(start + 2, probs.count) {
            guard let p = probs[i] else { continue }
            if best == nil || p > best!.prob { best = (p, times[i]) }
        }
        return best
    }

    /// The hourly value for the current hour (latest bucket at/before now).
    private static func currentHourValue(times: [String], values: [Int?]) -> Int? {
        let parsed = times.compactMap { localTimeParser.date(from: $0) }
        guard parsed.count == values.count, !parsed.isEmpty else { return nil }
        let now = Date()
        var idx = 0
        for (i, t) in parsed.enumerated() where t <= now { idx = i }
        return values[idx]
    }

    /// Parse Open-Meteo's offset-less local ISO ("2026-07-05T20:58") into an
    /// absolute Date, read in the town's timezone. nil is fine — the Almanac
    /// degrades to a number-free nudge rather than inventing a time.
    private static let localTimeParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = townTZ
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    private static func parseLocalTime(_ s: String?) -> Date? {
        guard let s else { return nil }
        return localTimeParser.date(from: s)
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double?
            let weather_code: Int
            let is_day: Int
            let wind_gusts_10m: Double?
        }
        struct Hourly: Decodable {
            let time: [String]
            let precipitation_probability: [Int?]?
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let sunrise: [String]?
            let sunset: [String]?
        }
        let current: Current
        let hourly: Hourly?
        let daily: Daily
    }

    private struct AirQualityResponse: Decodable {
        struct Hourly: Decodable { let time: [String]; let us_aqi: [Int?] }
        let hourly: Hourly
    }

    /// WMO weather code → human label (day-aware).
    static func label(code: Int, isDay: Bool) -> String {
        switch code {
        case 0:                return isDay ? "Clear" : "Clear night"
        case 1, 2:             return "Partly cloudy"
        case 3:                return "Overcast"
        case 45, 48:           return "Foggy"
        case 51...67, 80...82: return "Rain"
        case 71...77, 85, 86:  return "Snow"
        case 95, 96, 99:       return "Storms"
        default:               return isDay ? "Clear" : "Clear night"
        }
    }
}

// MARK: - View

struct WeatherBar: View {
    @State private var weather: Weather?

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("St. Joseph, Minnesota")
                    .font(.sansSemibold(14))
                    .foregroundStyle(Hue.surface)
                Text(weather?.label ?? "—")
                    .font(.sans(12))
                    .foregroundStyle(Hue.surface)
            }
            Spacer()
            if let w = weather {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(w.tempF)°")
                        .font(.monoMedium(30))
                        .monospacedDigit()
                        .foregroundStyle(Hue.surface)
                    Text("H \(w.highF)°  L \(w.lowF)°")
                        .font(.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Hue.surface)
                }
            }
        }
        .padding(14)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 75)
        // The sky rides in as a `.background`, so it always fills the whole bar.
        // Pinned to a fixed height and bottom-aligned (as it was), the backdrop
        // left a hairline strip at the top whenever the readout ran a touch taller
        // than 75pt — the old solid-ink block had hidden it; without that block the
        // strip showed the page through. `.background` matches the bar's frame
        // exactly, so the sky reaches every edge and there is no gap to expose.
        .background {
            WeatherBackground(state: weather?.state)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.45)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .task { weather = await WeatherService.current() }
    }
}
