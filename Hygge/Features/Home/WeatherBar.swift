//
//  WeatherBar.swift
//  Hygge — weather bar: live current conditions over a WeatherBackground.
//
//  Honest data only: the temperature comes from open-meteo (no key, no auth).
//  If the fetch fails we keep the place + a matched gradient, never a fake number.
//

import SwiftUI

// MARK: - Model

struct Weather {
    let tempF: Int
    let highF: Int
    let lowF: Int
    let label: String
    let state: WeatherState
    let sunrise: Date?   // today's sunrise, read in the town's timezone; nil if unavailable
    let sunset: Date?    // today's sunset, ditto — powers the Daily Almanac nudge
}

// MARK: - Service (open-meteo, St. Joseph, MN)

// The module builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so this enum
// is already main-actor isolated: `cached` is only ever read/written from the
// single main-actor `.task` caller, so no extra guarding is needed.
enum WeatherService {
    private static var cached: (weather: Weather, at: Date)?
    private static let ttl: TimeInterval = 30 * 60  // 30 minutes

    /// The town's timezone. Open-Meteo is pinned to it (see the URL), so the
    /// sunrise/sunset strings come back as Chicago wall-clock with no offset —
    /// parse and display in this zone so the Almanac always speaks in St. Joe time.
    static let townTZ = TimeZone(identifier: "America/Chicago") ?? .current

    static func current() async -> Weather? {
        if let c = cached, Date().timeIntervalSince(c.at) < ttl { return c.weather }

        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=45.565&longitude=-94.3186&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&temperature_unit=fahrenheit&timezone=America%2FChicago&forecast_days=1")!
        // Retry a few times so a transient first-launch network blip self-heals in
        // place — the widget resolves on its own and never needs a pull-to-refresh.
        for attempt in 0..<4 {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let r = try JSONDecoder().decode(Response.self, from: data)
                let isDay = r.current.is_day == 1
                let weather = Weather(
                    tempF: Int(r.current.temperature_2m.rounded()),
                    highF: Int((r.daily.temperature_2m_max.first ?? r.current.temperature_2m).rounded()),
                    lowF: Int((r.daily.temperature_2m_min.first ?? r.current.temperature_2m).rounded()),
                    label: label(code: r.current.weather_code, isDay: isDay),
                    state: WeatherState.from(code: r.current.weather_code, isDay: isDay),
                    sunrise: parseLocalTime(r.daily.sunrise?.first),
                    sunset: parseLocalTime(r.daily.sunset?.first)
                )
                cached = (weather, Date())
                return weather
            } catch {
                if attempt < 3 { try? await Task.sleep(nanoseconds: 1_200_000_000) }
            }
        }
        return cached?.weather   // last real reading, or nil — never a fake number
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
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let sunrise: [String]?
            let sunset: [String]?
        }
        let current: Current
        let daily: Daily
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
        ZStack(alignment: .bottomLeading) {
            WeatherBackground(state: weather?.state)
                .frame(height: 75)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("St. Joseph, Minnesota")
                        .font(.sansSemibold(14))
                        .foregroundStyle(.white)
                    Text(weather?.label ?? "—")
                        .font(.sans(12))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if let w = weather {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(w.tempF)°")
                            .font(.monoMedium(30))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("H \(w.highF)°  L \(w.lowF)°")
                            .font(.mono(11))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(14)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
        }
        .frame(height: 75)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .task { weather = await WeatherService.current() }
    }
}
