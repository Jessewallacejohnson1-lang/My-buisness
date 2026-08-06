//
//  CaughtUpFooter.swift
//  Block Party — the quiet end of a daily briefing.
//
//  The checkmark draws itself on the first time you reach the bottom each day, with
//  one success haptic. Once per DAY, not once per launch: reaching the end of the
//  briefing is the moment worth marking, and marking it every time you scroll down
//  would make it noise.
//
//  Visibility is never gated on the animation. The stroke rests at fully drawn and
//  only rewinds when it is actually going to play, so a headless render, a Reduce
//  Motion user, and a second visit all show the finished mark.
//

import SwiftUI

struct CaughtUpFooter: View {
    let caughtUp: BriefingCaughtUp
    let briefingDateLabel: String
    /// The day this footer belongs to, "YYYY-MM-DD". The once-per-day stamp is
    /// keyed on it, so a new briefing earns a new draw-on.
    var briefingDate: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 1 = fully drawn. Starts settled; see the file comment.
    @State private var stroke: CGFloat = 1

    var body: some View {
        VStack(spacing: 9) {
            CheckmarkPath()
                .trim(from: 0, to: stroke)
                .stroke(Hue.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 18)
                .frame(width: 40, height: 40)
                .background(Hue.fill)
                .clipShape(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(briefingDateLabel)
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.ink)
                .monospacedDigit()

            Text(caughtUp.label)
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Caught up. \(briefingDateLabel). \(caughtUp.label)")
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            guard visible else { return }
            markReached()
        }
    }

    private func markReached() {
        guard CaughtUpMemory.shouldCelebrate(briefingDate) else { return }
        CaughtUpMemory.remember(briefingDate)
        // A haptic is not motion. Reduce Motion drops the draw-on, but the
        // acknowledgement — and the once-per-day stamp — still happen, so
        // turning the setting off later the same day does not re-arm it.
        Haptics.success()
        guard !reduceMotion else { return }
        stroke = 0
        withAnimation(.easeOut(duration: 0.4)) { stroke = 1 }
    }
}

/// The stroke the checkmark draws along. Drawn by hand rather than taken from an SF
/// Symbol because only a `Shape` can be trimmed.
private struct CheckmarkPath: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

/// Remembers which briefing day has already been celebrated.
///
/// A new `briefing.*` key, deliberately: the `hygge.*` and `utility.*` keys are
/// frozen — renaming or reusing one signs people out or drops their tile prefs.
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
