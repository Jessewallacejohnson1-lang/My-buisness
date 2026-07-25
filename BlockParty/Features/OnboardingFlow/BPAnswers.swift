//
//  BPAnswers.swift
//  Block Party — the six onboarding answers, buffered locally.
//
//  The flow runs PRE-AUTH (Jesse's Phase 0 gate decision), so for most of its life
//  there is no account to write to. Answers accumulate here and are flushed to
//  `town_profiles` on the first successful sign-in.
//
//  Buffered to UserDefaults rather than held in memory because the spec requires
//  "killing the app mid-flow resumes at the last screen" — which is only honest if the
//  answers survive too.
//
//  Keys keep the app's `hygge.` prefix. That prefix is pre-rebrand and load-bearing
//  (see CLAUDE.md: never rename the persisted identifiers); matching it keeps the
//  namespace in one place instead of starting a second one.
//
//  NOTE — the flush itself lands in Phase 3 with the rest of the wiring. Two things it
//  must respect, both confirmed against the live code:
//   • `ProfileAPI.upsert` is a FULL-ROW MERGE, not a patch — it unconditionally writes
//     display_name and avatar_url, nulling them when nil. So flush ONCE, at the end,
//     never per-screen.
//   • None of these six columns exist on `town_profiles` yet; they need a migration.
//

import Combine
import Foundation

@MainActor
final class BPAnswers: ObservableObject {

    // MARK: - The six answers

    /// S05/S06 — `profile.connection`.
    @Published var connection: String? { didSet { save(.connection, connection) } }

    /// S08 — `profile.town_level`, 1…5. Drives S20's line and the feed defaults.
    @Published var townLevel: Int? { didSet { saveInt(.townLevel, townLevel) } }

    /// S09/S10 — `profile.motivations[]`.
    @Published var motivations: Set<String> = [] { didSet { saveSet(.motivations, motivations) } }

    /// S12 — `profile.notify_cadence`. Sets the real notification default.
    @Published var notifyCadence: String? { didSet { save(.cadence, notifyCadence) } }

    /// S17/S18 — `profile.founding_member`. A free badge tier; no payment anywhere.
    @Published var foundingMember: Bool? { didSet { saveBool(.founding, foundingMember) } }

    /// S19 — `profile.landing_choice`. Routes the post-onboarding tab.
    @Published var landingChoice: String? { didSet { save(.landing, landingChoice) } }

    /// The furthest screen reached, so a mid-flow kill resumes where it left off.
    @Published var resumeIndex: Int = 0 { didSet { saveInt(.resume, resumeIndex) } }

    // MARK: - Lifecycle

    init() { load() }

    /// Wipes the buffer once the answers have been flushed to the server, so a second
    /// account on the same device never inherits the first one's answers.
    func clear() {
        for k in Key.allCases { Self.defaults.removeObject(forKey: k.rawValue) }
        connection = nil; townLevel = nil; motivations = []
        notifyCadence = nil; foundingMember = nil; landingChoice = nil
        resumeIndex = 0
    }

    /// True once every required answer has been given — the gate for a clean flush.
    var isComplete: Bool {
        connection != nil && townLevel != nil && !motivations.isEmpty
            && notifyCadence != nil && foundingMember != nil && landingChoice != nil
    }

    // MARK: - Storage

    private enum Key: String, CaseIterable {
        case connection  = "hygge.onboarding.connection"
        case townLevel   = "hygge.onboarding.townLevel"
        case motivations = "hygge.onboarding.motivations"
        case cadence     = "hygge.onboarding.notifyCadence"
        case founding    = "hygge.onboarding.foundingMember"
        case landing     = "hygge.onboarding.landingChoice"
        case resume      = "hygge.onboarding.resumeIndex"
    }

    private static let defaults = UserDefaults.standard

    /// `isLoading` suppresses the `didSet` writes while `load()` populates the
    /// published properties — without it, hydrating would rewrite every key on launch.
    private var isLoading = false

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let d = Self.defaults
        connection = d.string(forKey: Key.connection.rawValue)
        townLevel = d.object(forKey: Key.townLevel.rawValue) as? Int
        motivations = Set(d.stringArray(forKey: Key.motivations.rawValue) ?? [])
        notifyCadence = d.string(forKey: Key.cadence.rawValue)
        foundingMember = d.object(forKey: Key.founding.rawValue) as? Bool
        landingChoice = d.string(forKey: Key.landing.rawValue)
        resumeIndex = d.integer(forKey: Key.resume.rawValue)
    }

    private func save(_ k: Key, _ v: String?) {
        guard !isLoading else { return }
        if let v { Self.defaults.set(v, forKey: k.rawValue) }
        else { Self.defaults.removeObject(forKey: k.rawValue) }
    }

    private func saveInt(_ k: Key, _ v: Int?) {
        guard !isLoading else { return }
        if let v { Self.defaults.set(v, forKey: k.rawValue) }
        else { Self.defaults.removeObject(forKey: k.rawValue) }
    }

    private func saveBool(_ k: Key, _ v: Bool?) {
        guard !isLoading else { return }
        if let v { Self.defaults.set(v, forKey: k.rawValue) }
        else { Self.defaults.removeObject(forKey: k.rawValue) }
    }

    private func saveSet(_ k: Key, _ v: Set<String>) {
        guard !isLoading else { return }
        Self.defaults.set(Array(v).sorted(), forKey: k.rawValue)
    }
}
