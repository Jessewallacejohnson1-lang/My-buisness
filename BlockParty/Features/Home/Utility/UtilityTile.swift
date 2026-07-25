//
//  UtilityTile.swift
//  Block Party — Today "Utility Row": core data model + the provider contract.
//
//  Pure data + the provider protocol; NO SwiftUI here so it stays testable and
//  provider-agnostic. The row UI and the customize sheet render entirely from the
//  registry (see UtilityTileRegistry, Phase 2). Adding a future tile touches ONLY:
//  one provider (implementing UtilityTileProvider), one registry entry, one
//  gradient token — never the row or sheet views.
//

import Foundation

// MARK: - Identity

/// A tile id. String-backed (NOT a closed enum) so prefs written by a NEWER app
/// version decode fine here and unknown ids are simply ignored (forward compat —
/// see UtilityPrefsStore.reconcile). Codes to/from a plain JSON string.
struct UtilityTileID: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    let rawValue: String
    // Pure value type — nonisolated so the id can be built/read from any context
    // (e.g. the nonisolated prefs sanitize/mapSettings helpers), not just MainActor.
    nonisolated init(rawValue: String) { self.rawValue = rawValue }
    nonisolated init(stringLiteral value: StringLiteralType) { self.rawValue = value }
    nonisolated var description: String { rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    // V1 catalog (fixed ids). Adding a future tile adds a constant here + a
    // registry entry — never an edit to the row or sheet.
    nonisolated static let weather: UtilityTileID = "weather"
    nonisolated static let garbage: UtilityTileID = "garbage"
    nonisolated static let roads:   UtilityTileID = "roads"
    nonisolated static let library: UtilityTileID = "library"

    /// The V1 default set, in default order (all four enabled).
    nonisolated static let defaults: [UtilityTileID] = [.weather, .garbage, .roads, .library]
}

// MARK: - Rendered content (what a tile shows, in BOTH states)

/// Compact + expanded content for one tile. Produced by a provider, rendered by
/// the row. No SwiftUI — glyphs are SF Symbol names, colours come from the token
/// layer at render time.
struct UtilityTileContent: Equatable, Sendable {
    /// Label-row SF Symbol (condition symbol, "trash.fill", "road.lanes", "book.fill"); nil = no glyph.
    var symbol: String?
    /// Bold value line ("72° feels 78°", "Tonight", "1 notice", "Open").
    var primary: String
    /// ~12pt 80%-white secondary line, 2-line max ("Rain 60% by 3 PM", "Recycling week"). nil = none.
    var secondary: String?
    /// Optional badge beside the label (roads active → warning triangle).
    var badge: UtilityTileBadge?
    /// Rows revealed on tap-to-expand (matches the Calendar bento's compact⇄expanded).
    var expanded: [UtilityDetailRow]
    /// Optional per-value gradient override (hex pairs [top, bottom]) — lets a
    /// provider drive its tile's colour dynamically (weather → live condition)
    /// while the tile view stays generic. nil = use the registry's static token.
    var gradientHex: [UInt32]?

    init(symbol: String? = nil, primary: String, secondary: String? = nil,
         badge: UtilityTileBadge? = nil, expanded: [UtilityDetailRow] = [],
         gradientHex: [UInt32]? = nil) {
        self.symbol = symbol; self.primary = primary; self.secondary = secondary
        self.badge = badge; self.expanded = expanded; self.gradientHex = gradientHex
    }
}

/// One row inside an expanded tile.
struct UtilityDetailRow: Equatable, Identifiable, Sendable {
    var id: String { label }
    var symbol: String?
    var label: String
    var value: String
    init(symbol: String? = nil, label: String, value: String) {
        self.symbol = symbol; self.label = label; self.value = value
    }
}

/// White 90% "exclamationmark.triangle.fill" beside the label (roads active notice).
enum UtilityTileBadge: Equatable, Sendable { case warning }

// MARK: - Value + state

/// A provider's output: content + when the underlying data was produced. `updatedAt`
/// drives the stale note (a `.live` tile older than its `staleAfter` shows "Updated 2d ago").
struct UtilityTileValue: Equatable, Sendable {
    var content: UtilityTileContent
    var updatedAt: Date
    init(content: UtilityTileContent, updatedAt: Date = Date()) {
        self.content = content; self.updatedAt = updatedAt
    }
}

/// Row-facing state. `.failed` renders an em-dash value — never a crash.
enum UtilityTileState: Equatable, Sendable {
    case loading
    case loaded(UtilityTileValue)
    case failed
}

// MARK: - Refresh policy

/// How a tile keeps itself current. The row uses this to decide when to re-fetch
/// on appear and whether to open a live subscription.
enum UtilityRefreshPolicy: Equatable, Sendable {
    /// Pure local math; recompute on every appear (garbage, library). Always fresh.
    case computed
    /// The provider caches internally; re-fetch on appear when its own TTL is stale (weather: 900s).
    case cached(ttl: TimeInterval)
    /// Realtime + fallback fetch; show "Updated Nd ago" once data is older than `staleAfter` (roads: 86400s).
    case live(staleAfter: TimeInterval)

    /// Age past which a value is shown as stale, or nil if staleness isn't surfaced.
    var staleAfter: TimeInterval? {
        if case let .live(staleAfter) = self { return staleAfter }
        return nil
    }
}

// MARK: - Provider contract

enum UtilityTileError: Error { case unavailable }

/// Everything a tile needs to produce a value. One provider per data pattern; the
/// registry owns the instances. `@MainActor` to match the app's default isolation
/// and let realtime/auth-touching providers update state directly.
@MainActor
protocol UtilityTileProvider: AnyObject {
    var id: UtilityTileID { get }
    var refreshPolicy: UtilityRefreshPolicy { get }

    /// One-shot fetch/compute for the current per-tile settings. Throwing → `.failed`.
    func fetch(settings: TileSettings) async throws -> UtilityTileValue

    /// Optional live updates (roads). Fire `onChange` when the underlying data
    /// changes and the row re-fetches. Return nil if there's no live source.
    func subscribe(settings: TileSettings, onChange: @escaping () -> Void) -> UtilitySubscription?
}

extension UtilityTileProvider {
    // Default: no live source.
    func subscribe(settings: TileSettings, onChange: @escaping () -> Void) -> UtilitySubscription? { nil }
}

/// Opaque cancel handle returned by `subscribe`.
final class UtilitySubscription {
    private let onCancel: () -> Void
    init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() { onCancel() }
}

// MARK: - Settings (the per-tile jsonb blob)

/// One tile's settings — the value stored under its id in `user_utility_prefs.settings`
/// jsonb (e.g. garbage → {"day": 3}). Loosely typed via JSONValue so a future tile can
/// add keys with NO schema/migration change.
struct TileSettings: Codable, Equatable, Sendable {
    var values: [String: JSONValue]
    init(_ values: [String: JSONValue] = [:]) { self.values = values }

    init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }

    var isEmpty: Bool { values.isEmpty }
    func int(_ key: String) -> Int? { values[key]?.intValue }
    func string(_ key: String) -> String? { values[key]?.stringValue }
    func bool(_ key: String) -> Bool? { values[key]?.boolValue }

    /// Return a copy with `key` set to `value` (immutable update).
    func setting(_ key: String, _ value: JSONValue) -> TileSettings {
        var next = values
        next[key] = value
        return TileSettings(next)
    }
}

/// A minimal Codable JSON value — the bridge between Swift and the jsonb `settings`
/// column so future tiles need no new Swift types to persist a setting.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        // Order matters: Bool before Int (JSON true/false), Int before Double (whole numbers).
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:            try c.encodeNil()
        case .bool(let b):     try c.encode(b)
        case .int(let i):      try c.encode(i)
        case .double(let d):   try c.encode(d)
        case .string(let s):   try c.encode(s)
        case .array(let a):    try c.encode(a)
        case .object(let o):   try c.encode(o)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let i):    return i
        case .double(let d): return Int(d)
        default:             return nil
        }
    }
    var stringValue: String? { if case let .string(s) = self { return s }; return nil }
    var boolValue: Bool? { if case let .bool(b) = self { return b }; return nil }
}
