//
//  BasemapPalette.swift
//  Hygge — the Living Basemap's tuned cartography: TownAtmosphere → Mapbox layer
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
        switch s {
        case .winter: return .spring
        case .spring: return .summer
        case .summer: return .autumn
        case .autumn: return .winter
        }
    }

    static func make(for a: TownAtmosphere) -> BasemapPalette {
        let base = anchors[a.season]!
        let next = anchors[nextSeason(a.season)]!
        // Blend toward the next season near the boundary.
        var land     = base.land.lerp(to: next.land, a.seasonBlend)
        var green    = base.green.lerp(to: next.green, a.seasonBlend)
        var water    = base.water.lerp(to: next.water, a.seasonBlend)
        var building = base.building.lerp(to: next.building, a.seasonBlend)

        // TIME: brightness + saturation ease down toward night. Then warm light
        // (dawn/golden) pushes amber/rose, while cool light (dusk/night) tints each
        // role toward a blue-hour slate — so low light reads as an *evening*, not a
        // flat grey wash. df = 1 (noon) is an identity, so summer·noon·clear stays
        // the tuned Life360 anchor exactly.
        let df = a.dayFactor
        let bright = 0.74 + 0.26 * df          // night 0.74 → noon 1.0
        let sat    = 0.80 + 0.20 * df          // gently desaturate at night
        let warm: Double = a.phase == .golden ? 1.0 : (a.phase == .dawn ? 0.7 : 0)
        let cool: Double = a.phase == .night ? 1.0 : (a.phase == .dusk ? 0.6 : 0)
        func timeMod(_ c: HSB, nightTint: HSB, tintK: Double) -> HSB {
            var x = c.scaledBrightness(bright).scaledSaturation(sat)
            if warm > 0 {                        // amber/rose push of dawn & golden
                x = x.hueShifted(byDegrees: -8 * warm).scaledSaturation(1 + 0.12 * warm).scaledBrightness(0.99)
            }
            if cool > 0 {                        // blue-hour tint of dusk & night
                x = x.lerpHSB(to: nightTint, cool * tintK)
            }
            return x
        }
        land     = timeMod(land,     nightTint: HSB("#3A4358"), tintK: 0.24)
        green    = timeMod(green,    nightTint: HSB("#39473F"), tintK: 0.22)
        water    = timeMod(water,    nightTint: HSB("#33465F"), tintK: 0.45)
        building = timeMod(building, nightTint: HSB("#333B4E"), tintK: 0.30)

        // SKY: each condition leaves its own signature on the ground.
        switch a.sky {
        case .overcast:
            land = land.scaledSaturation(0.85); green = green.scaledSaturation(0.85)
            building = building.scaledSaturation(0.9)
        case .fog:
            // Low-visibility haze — wash the ground toward a pale grey so detail
            // softens (what the "handled as haze" note promised; fog now reads ≠ overcast).
            land     = land.scaledSaturation(0.7).lerp(to: HSB("#E7EAEC"), 0.30)
            green    = green.scaledSaturation(0.7).lerp(to: HSB("#E4E9E6"), 0.30)
            water    = water.scaledSaturation(0.7).lerp(to: HSB("#DBE2E4"), 0.26)
            building = building.lerp(to: HSB("#E7EAEC"), 0.22)
        case .snow:
            let lift = a.intensity == .heavy ? 0.22 : 0.14
            land = land.lerp(to: HSB("#FFFFFF"), lift); green = green.lerp(to: HSB("#F2F5F3"), lift)
        case .rain:
            land = land.scaledBrightness(0.95); green = green.scaledBrightness(0.95); water = water.scaledBrightness(0.95)
        case .storm:
            // The most severe sky — dim + cool the whole ground, even at midday, so a
            // daytime thunderstorm reads ≠ heavy rain.
            land     = land.scaledBrightness(0.82).lerpHSB(to: HSB("#4A5568"), 0.14)
            green    = green.scaledBrightness(0.82).lerpHSB(to: HSB("#42504A"), 0.12)
            water    = water.scaledBrightness(0.85)
            building = building.scaledBrightness(0.85)
        case .clear, .cloudy:
            break
        }

        return BasemapPalette(land: land.hex, green: green.hex, water: water.hex, building: building.hex,
                              wash: washFor(a))
    }

    // Wash: discrete per phase (the overlay animates opacity so changes cross-fade).
    private static func washFor(_ a: TownAtmosphere) -> Wash {
        switch a.phase {
        case .day:    return Wash(r: 1, g: 1, b: 1, a: 0.0)
        case .dawn:   return Wash(r: 0.98, g: 0.78, b: 0.72, a: 0.14)   // soft rose
        case .golden: return Wash(r: 1.0, g: 0.72, b: 0.44, a: 0.15)    // warm gold
        case .dusk:   return Wash(r: 0.44, g: 0.34, b: 0.56, a: 0.16)   // violet
        case .night:  return Wash(r: 0.10, g: 0.13, b: 0.26, a: 0.20)   // indigo
        }
    }
}

// Minimal HSB helper over hex — kept local to the palette (its only consumer).
private struct HSB: Equatable {
    var h: Double, s: Double, b: Double    // h in 0…360, s/b in 0…1
    init(h: Double, s: Double, b: Double) { self.h = h; self.s = s; self.b = b }
    init(_ hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(raw, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, bl = Double(v & 0xFF) / 255
        let mx = max(r, g, bl), mn = min(r, g, bl), d = mx - mn
        var hue = 0.0
        if d != 0 {
            if mx == r { hue = 60 * (((g - bl) / d).truncatingRemainder(dividingBy: 6)) }
            else if mx == g { hue = 60 * (((bl - r) / d) + 2) }
            else { hue = 60 * (((r - g) / d) + 4) }
        }
        if hue < 0 { hue += 360 }
        self.h = hue; self.s = mx == 0 ? 0 : d / mx; self.b = mx
    }
    var hex: String {
        let c = b * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = b - c
        var r = 0.0, g = 0.0, bl = 0.0
        switch h {
        case ..<60:  (r, g, bl) = (c, x, 0)
        case ..<120: (r, g, bl) = (x, c, 0)
        case ..<180: (r, g, bl) = (0, c, x)
        case ..<240: (r, g, bl) = (0, x, c)
        case ..<300: (r, g, bl) = (x, 0, c)
        default:     (r, g, bl) = (c, 0, x)
        }
        func hh(_ v: Double) -> String { String(format: "%02X", Int(((v + m) * 255).rounded().clamped(0, 255))) }
        return "#\(hh(r))\(hh(g))\(hh(bl))"
    }
    func scaledBrightness(_ f: Double) -> HSB { HSB(h: h, s: s, b: (b * f).clamped(0, 1)) }
    func scaledSaturation(_ f: Double) -> HSB { HSB(h: h, s: (s * f).clamped(0, 1), b: b) }
    func hueShifted(byDegrees d: Double) -> HSB { HSB(h: HSB.wrap(h + d), s: s, b: b) }
    /// Interpolate along the SHORTEST hue arc — a linear lerp would rotate a warm
    /// ground (hue ~37) toward the blue night-tint (hue ~220) the long way through
    /// green; the short arc keeps summer/autumn dusk·night blue, like winter.
    func lerpHSB(to o: HSB, _ t: Double) -> HSB {
        var dh = o.h - h
        if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        return HSB(h: HSB.wrap(h + dh * t), s: s + (o.s - s) * t, b: b + (o.b - b) * t)
    }
    func lerp(to o: HSB, _ t: Double) -> HSB { lerpHSB(to: o, t) }
    /// Normalize a hue into 0…360 so the `hex` angle switch never sees a negative.
    static func wrap(_ h: Double) -> Double { let m = h.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}
