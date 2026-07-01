//
//  WeatherBar.swift
//  Hygge — real-photo weather backdrop with live current conditions.
//
//  Honest data only: the temperature comes from open-meteo (no key, no auth).
//  If the fetch fails we still show the place + a calm photo, never a fake number.
//

import SwiftUI

// MARK: - Model

struct Weather {
    let tempF: Int
    let highF: Int
    let lowF: Int
    let label: String
    let photo: String
}

// MARK: - Service (open-meteo, St. Joseph, MN)

enum WeatherService {
    static func current() async -> Weather? {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=45.565&longitude=-94.3186&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=America%2FChicago&forecast_days=1")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(Response.self, from: data)
            let (label, photo) = describe(code: r.current.weather_code, isDay: r.current.is_day == 1)
            return Weather(
                tempF: Int(r.current.temperature_2m.rounded()),
                highF: Int((r.daily.temperature_2m_max.first ?? r.current.temperature_2m).rounded()),
                lowF: Int((r.daily.temperature_2m_min.first ?? r.current.temperature_2m).rounded()),
                label: label,
                photo: photo
            )
        } catch {
            return nil
        }
    }

    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
        struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
        let current: Current
        let daily: Daily
    }

    /// WMO weather code → (label, bundled photo base name).
    static func describe(code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0: return (isDay ? "Clear" : "Clear night", isDay ? "clear-day" : "clear-night")
        case 1, 2: return ("Partly cloudy", "clouds")
        case 3: return ("Overcast", "overcast")
        case 45, 48: return ("Foggy", "fog")
        case 51...67, 80...82: return ("Rain", "rain")
        case 71...77, 85, 86: return ("Snow", "snow")
        case 95, 96, 99: return ("Storms", "storm")
        default: return (isDay ? "Clear" : "Clear night", isDay ? "clear-day" : "clear-night")
        }
    }
}

// MARK: - View

struct WeatherBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var weather: Weather?
    @State private var drift = false

    private var photoName: String { weather?.photo ?? "clear-day" }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoView(name: photoName)
                .scaledToFill()
                .scaleEffect(drift ? 1.08 : 1.0)
                .frame(height: 132)
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
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .task { weather = await WeatherService.current() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
