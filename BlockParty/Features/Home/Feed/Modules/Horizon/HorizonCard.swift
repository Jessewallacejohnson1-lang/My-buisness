//
//  HorizonCard.swift
//  BlockParty
//
//  The "Your day" horizon card: a small window onto the sky over St. Joe
//  right now. Sky above, flat ground below, today's agenda rising out of
//  the line between them. Composition only — the solar math lives in
//  SolarSky/TimeAxis, the day mapping in HorizonDay, the colors in
//  HorizonPalette.
//

import SwiftUI

struct HorizonCard: View {
    let now: Date
    let sunrise: Date?
    let sunset: Date?
    let items: [DayItem]

    var body: some View {
        GeometryReader { geo in
            let sky = SolarSky(now: now, sunrise: sunrise, sunset: sunset)
            let axis = TimeAxis(now: now, sunrise: sunrise, sunset: sunset, width: geo.size.width)
            let day = HorizonDay(items: items, axis: axis, now: now)
            ZStack(alignment: .topLeading) {
                HorizonBackdrop(sky: sky, axis: axis)
                HorizonRailView(sky: sky, axis: axis, day: day, now: now)
            }
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
