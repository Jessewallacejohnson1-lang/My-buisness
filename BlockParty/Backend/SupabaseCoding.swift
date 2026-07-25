//
//  SupabaseCoding.swift
//  Block Party — one shared JSON coder for PostgREST payloads. The older API
//  structs (SocialAPI, ProfileAPI…) each hand-roll their own decoder; new APIs
//  (TownStatusAPI, UtilityPrefsAPI) share this one instead (DRY).
//
//  snake_case ⇄ camelCase, and a dual-ISO8601 date strategy: PostgREST returns
//  timestamptz with OR without fractional seconds, so try both.
//

import Foundation

enum SupabaseCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = isoFractional.date(from: s) ?? isoPlain.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized ISO8601 date: \(s)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
