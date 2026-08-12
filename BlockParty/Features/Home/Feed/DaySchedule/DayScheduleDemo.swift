//
//  DayScheduleDemo.swift
//  Block Party — `-day-sheet-demo`, the day sheet driven without a finger.
//
//  This setup has NO simulator scroll or tap automation (CLAUDE.md), so the one
//  thing the in-hierarchy rewrite exists to produce — the accent bar morphing out
//  of a rail card and back into it — is unrecordable by hand. The house answer to
//  exactly this problem is already in the codebase: `-speeddial-loop`, `-bp-motion`
//  and `-menu-autoclose` all drive a motion sequence programmatically so it can be
//  filmed. This is the same thing for the day.
//
//  It drives the REAL views: the real rail (seeded through `-yourday-count`'s own
//  fixtures, so the ids the morph pairs on are the shipping ones), the real tap
//  seam, the real host, the real sheet. Nothing here is a mock of the transition.
//
//  The sequence, repeated so a recording started at any moment catches a whole one:
//
//      open on the first rail card  →  scroll to the end of the day
//        →  tick a checkbox  →  dismiss (the morph in reverse)
//
//  THREE WAYS TO RUN IT, in rising order of fidelity:
//
//    -day-sheet-demo                       the Today feed + the host, no tab shell
//    -show-home -day-sheet-demo            the REAL tab shell — this is the one that
//                                          proves the sheet clears the tab bar
//    …either, plus -day-sheet-hold         opens once and stays, for a screenshot or
//                                          an accessibility dump of the OPEN state
//
//  (`-show-home` is matched earlier in `RootView`'s chain, so it wins and mounts
//  `MainTabsView`; this file's flag then only seeds and drives.)
//
//  Everything in this file compiles out of Release; the two modifiers keep their
//  types there and become pass-throughs.
//

import SwiftUI

// MARK: - Timing

#if DEBUG
/// One place for the beats, so the opener's loop and the driver inside the sheet
/// cannot drift apart.
private enum DayScheduleDemoBeat {
    static let flag = "-day-sheet-demo"
    /// `-day-sheet-hold` opens once and stops there, so the OPEN state can be
    /// screenshotted and its accessibility tree read without racing the loop.
    /// Same idea as `-bp-hold`.
    static let holdFlag = "-day-sheet-hold"

    /// Before the first open, and between cycles.
    static let settle: Duration = .milliseconds(1300)
    /// Between each step inside the sheet.
    static let step: Duration = .milliseconds(1400)
    /// How long the opener waits after opening, before starting the next cycle.
    /// Must outlast the driver's three steps plus the dismiss spring.
    static let cycle: Duration = .milliseconds(5000)
    static let cycles = 3

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    static var holds: Bool {
        ProcessInfo.processInfo.arguments.contains(holdFlag)
    }
}
#endif

// MARK: - Opening (the rail's side)

/// Taps the first rail card, on a loop. Attached to the hosted rail so the open
/// runs through the same closure a finger would.
struct DayScheduleDemoOpener: ViewModifier {
    let items: [DayItem]
    let open: (DayScheduleAnchor) -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            guard DayScheduleDemoBeat.isRequested, let first = items.first else { return }

            if DayScheduleDemoBeat.holds {
                try? await Task.sleep(for: DayScheduleDemoBeat.settle)
                guard !Task.isCancelled else { return }
                open(.item(first.id))
                return
            }

            for _ in 0..<DayScheduleDemoBeat.cycles {
                try? await Task.sleep(for: DayScheduleDemoBeat.settle)
                guard !Task.isCancelled else { return }
                open(.item(first.id))

                try? await Task.sleep(for: DayScheduleDemoBeat.cycle)
                guard !Task.isCancelled else { return }
            }
        }
        #else
        content
        #endif
    }
}

// MARK: - Driving (the sheet's side)

/// Scroll, tick, leave. Attached inside the sheet's `ScrollViewReader` so it drives
/// the real scroll proxy and the real completion store rather than a stand-in.
struct DayScheduleDemoDriver: ViewModifier {
    let proxy: ScrollViewProxy
    let items: [DayItem]
    let completion: DayCompletionStore
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            guard DayScheduleDemoBeat.isRequested,
                  !DayScheduleDemoBeat.holds,
                  let last = items.last
            else { return }

            // 1. Scroll the day, so the recording shows the timeline moving under
            //    the pinned header rather than a static screenshot.
            try? await Task.sleep(for: DayScheduleDemoBeat.step)
            guard !Task.isCancelled else { return }
            withAnimation(DayScheduleMotion.open) {
                proxy.scrollTo(last.id, anchor: .center)
            }

            // 2. Tick the row that is now on screen.
            try? await Task.sleep(for: DayScheduleDemoBeat.step)
            guard !Task.isCancelled else { return }
            let isComplete = completion.isComplete(last)
            withAnimation(DayScheduleMotion.check) {
                completion.setComplete(!isComplete, for: last.id)
            }

            // 3. Leave the way the × does — and the morph runs backwards.
            try? await Task.sleep(for: DayScheduleDemoBeat.step)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        #else
        content
        #endif
    }
}

// MARK: - The demo root

#if DEBUG
/// `-day-sheet-demo` mounts the real Today feed with a day-sheet host over it,
/// bypassing the auth gate the way every other preview flag does. `YourDayModule`
/// recognises the same flag and seeds its rail, so no second argument is needed.
struct DayScheduleDemoView: View {
    @Namespace private var dayNamespace
    @StateObject private var presentation = DaySchedulePresentation()
    @StateObject private var completion = DayCompletionStore()

    var body: some View {
        FeedView(auth: .shared)
            .dayScheduleHost(presentation, namespace: dayNamespace, completion: completion)
            .environmentObject(AuthStore.shared)
    }
}
#endif
