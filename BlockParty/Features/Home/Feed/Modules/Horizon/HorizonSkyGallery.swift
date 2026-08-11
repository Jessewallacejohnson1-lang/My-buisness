//
//  HorizonSkyGallery.swift
//  BlockParty
//
//  DEBUG-only strip of the horizon card's sky at the eight spec test times,
//  for headless verification: `-horizon-sky-gallery` (page 1: 4:30a–10:00a)
//  and `-horizon-sky-gallery-page 2` (1:00p–10:45p). Sky, horizon line,
//  solar dots and flat ground only — no rail, no stubs, no text.
//

#if DEBUG
import SwiftUI

struct HorizonSkyGallery: View {
    /// Mock sun times from the spec: sunrise 06:13, sunset 21:02.
    private static let sunTimes = (rise: (6, 13), set: (21, 2))
    private static let testTimes: [(label: String, hour: Int, minute: Int)] = [
        ("4:30a night", 4, 30),
        ("6:05a dawn", 6, 5),
        ("7:15a early day", 7, 15),
        ("10:00a morning", 10, 0),
        ("1:00p midday", 13, 0),
        ("6:30p late day", 18, 30),
        ("8:25p dusk", 20, 25),
        ("10:45p night", 22, 45),
    ]

    private let page: Int

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-horizon-sky-gallery-page"), i + 1 < args.count,
           let parsed = Int(args[i + 1]) {
            page = parsed
        } else {
            page = 1
        }
    }

    var body: some View {
        let entries = page == 2
            ? Array(Self.testTimes[4...])
            : Array(Self.testTimes[..<4])
        VStack(spacing: 14) {
            ForEach(entries, id: \.label) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.label)
                        .font(.sansMedium(11))
                        .foregroundStyle(Hue.inkSecondary)
                    card(hour: entry.hour, minute: entry.minute)
                }
            }
        }
        .padding(.horizontal, YourDayRailMetrics.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Hue.paper)
    }

    private func card(hour: Int, minute: Int) -> some View {
        let calendar = Town.calendar
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        let now = calendar.date(from: components) ?? Date()

        var riseComponents = components
        riseComponents.hour = Self.sunTimes.rise.0
        riseComponents.minute = Self.sunTimes.rise.1
        var setComponents = components
        setComponents.hour = Self.sunTimes.set.0
        setComponents.minute = Self.sunTimes.set.1
        let sunrise = calendar.date(from: riseComponents)
        let sunset = calendar.date(from: setComponents)

        let sky = SolarSky(now: now, sunrise: sunrise, sunset: sunset)
        return GeometryReader { geo in
            HorizonBackdrop(
                sky: sky,
                axis: TimeAxis(now: now, sunrise: sunrise, sunset: sunset, width: geo.size.width)
            )
        }
        .frame(height: HorizonMetrics.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        .modifier(CardShadow())
    }
}
#endif
