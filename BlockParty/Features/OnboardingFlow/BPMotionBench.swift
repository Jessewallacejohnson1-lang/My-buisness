//
//  BPMotionBench.swift
//  Block Party — the Phase 4 motion bench.
//
//  The metrics bench proves geometry from stills. This proves MOTION, which stills cannot
//  show: whether the press really travels its 4pt and springs back, whether the progress
//  fill overshoots before it settles, whether the check badge pops past 1.0, and whether
//  the bubble types at the specified rate.
//
//  Why a bench and not the real screens: each mechanic renders ALONE on a plain ground at
//  a known position, so a frame-by-frame scan can track one edge without another animation
//  moving in the same frame. And each is DRIVEN programmatically, because this simulator
//  setup has no tap automation — `snapshot_ui` is available but the tap/gesture tools are
//  not, so nothing in the flow can be pressed from outside the app.
//
//  Every mechanic fires at `fireAt` (1.0s) after appear, giving a clean at-rest baseline
//  before it and a settled tail after, so a scan can find the start and end states
//  without knowing the spring's duration in advance.
//
//  Usage:
//      xcrun simctl launch <udid> Jesse.BlockParty -bp-motion press|progress|badge|typing
//      xcrun simctl io <udid> recordVideo --codec h264 out.mov     (Ctrl-C to stop)
//      swift extract_frames.swift out.mov frames/ 0.0167 f
//

import SwiftUI

enum BPMotionMechanic: String {
    case press, progress, badge, typing

    static func fromArguments() -> BPMotionMechanic? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-bp-motion"), i + 1 < args.count else { return nil }
        return BPMotionMechanic(rawValue: args[i + 1])
    }
}

struct BPMotionBench: View {
    let mechanic: BPMotionMechanic

    /// When the mechanic fires, measured from appear.
    private static let fireAt: Double = 1.0
    /// How long the press is held before release, so both edges are measurable.
    private static let holdFor: Double = 0.6

    @State private var fired = false
    @State private var pressing = false
    @State private var retypeNonce = 0

    var body: some View {
        VStack(spacing: 0) {
            // A fixed 180pt gap so every mechanic sits at the same known y and the scan
            // can hunt in one band regardless of which bench is running.
            Spacer().frame(height: 180)

            switch mechanic {
            case .press:
                BPButton(title: "Continue", debugPressed: pressing) {}
                    .padding(.horizontal, BP.Metric.pageMargin)

            case .progress:
                // 6/16 → 7/16: one screen's worth of advance, the real increment.
                BPProgressBar(progress: fired ? 7.0 / 16.0 : 6.0 / 16.0)
                    .padding(.horizontal, BP.Metric.pageMargin)

            case .badge:
                BPRow(label: "Find things to do",
                      icon: .glyph(.partyPopper),
                      selected: fired,
                      showsCheck: true) {}
                    .padding(.horizontal, BP.Metric.pageMargin)

            case .typing:
                // Fires on appear, not at `fireAt` — the type-on IS the appear animation.
                BPBubble(content: BPCopy.plain("What's your connection to St. Joe?"),
                         tail: .leading(0.43))
                    .id(retypeNonce)
                    .padding(.horizontal, BP.Metric.pageMargin)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BP.paper.ignoresSafeArea())
        // LOOPS forever rather than firing once. App launch takes a variable ~1.5-2.5s, so
        // a single fire lands at an unpredictable point in the recording — the first take
        // caught the press-down 0.3s before the video ended and missed the release
        // entirely. Looping means any window long enough for one period captures a
        // complete cycle with rest on both sides.
        .task {
            while !Task.isCancelled {
                // Typing needs a longer period than the others: a 34-char line at 30ms/char
                // plus punctuation rests runs ~1.2s, so a 1.0s period would restart the
                // reveal before it finished and no clean measurement would ever exist.
                try? await Task.sleep(for: .seconds(mechanic == .typing ? 3.0 : Self.fireAt))
                if Task.isCancelled { return }
                switch mechanic {
                case .press:
                    pressing = true
                    try? await Task.sleep(for: .seconds(Self.holdFor))
                    pressing = false
                case .typing:
                    // Re-type by swapping the bubble's identity.
                    retypeNonce += 1
                default:
                    fired.toggle()
                }
            }
        }
    }
}
