//
//  CaughtUpFooter.swift
//  Block Party — the plain-text end of a finite daily briefing.
//

import SwiftUI

struct CaughtUpFooter: View {
    private let nextBriefingAt: Date
    /// The town day this footer belongs to, "YYYY-MM-DD". The once-per-day stamp
    /// is keyed on it, so a new edition earns one quiet text reveal.
    private let briefingDate: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textOpacity: Double = 1

    init(
        caughtUp: BriefingCaughtUp,
        briefingDateLabel _: String,
        briefingDate: String = ""
    ) {
        nextBriefingAt = caughtUp.nextBriefingAt
        self.briefingDate = briefingDate
    }

    var body: some View {
        Text(line)
            .font(.sans(16))
            .foregroundStyle(Hue.ink)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(textOpacity)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 38)
        .accessibilityLabel(line)
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            guard visible else { return }
            markReached()
        }
    }

    private var line: String {
        if !briefingDate.isEmpty {
            return SignOffCopy.line(for: briefingDate)
        }
        let editionDate = Town.calendar.date(byAdding: .day, value: -1, to: nextBriefingAt)
            ?? nextBriefingAt
        return SignOffCopy.line(for: editionDate)
    }

    private func markReached() {
        guard CaughtUpMemory.shouldCelebrate(briefingDate) else { return }
        CaughtUpMemory.remember(briefingDate)
        guard !reduceMotion else { return }
        textOpacity = 0
        withAnimation(.easeOut(duration: 0.22)) { textOpacity = 1 }
    }
}

/// Remembers which briefing day has already been celebrated.
///
/// A separate `briefing.*` key, deliberately: persisted app keys now use `bp.*`.
/// The pre-rebrand `hygge.*` values are unreachable — the new bundle id gives the
/// app a fresh container — so there is nothing to migrate.
nonisolated enum CaughtUpMemory {
    static let key = "briefing.caughtUpCelebratedOn"

    /// The store is injectable so tests can use an isolated suite rather than
    /// writing to the app's real defaults.
    static func shouldCelebrate(_ briefingDate: String,
                                store: UserDefaults = .standard) -> Bool {
        guard !briefingDate.isEmpty else { return false }
        return store.string(forKey: key) != briefingDate
    }

    static func remember(_ briefingDate: String, store: UserDefaults = .standard) {
        guard !briefingDate.isEmpty else { return }
        store.set(briefingDate, forKey: key)
    }
}
