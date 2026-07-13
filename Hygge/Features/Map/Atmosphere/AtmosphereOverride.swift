//
//  AtmosphereOverride.swift
//  Hygge — DEBUG-only launch-arg parser to force any atmosphere for headless
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
