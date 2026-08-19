//
//  SplashView.swift
//  Block Party — the launch splash.
//
//  Frame zero mirrors LaunchScreen.storyboard: the approved LaunchMark raster at the
//  same proportional frame and the existing Jost wordmark on #0D0F0D. LaunchHost
//  keeps the real RootView alive underneath this overlay, then cross-fades the two.
//

import SwiftUI

private enum SplashLayout {
    static let background = Color(hex: 0x0D0F0D)

    /// LaunchMark starts at 40% of screen width, capped well below its 880 px source.
    /// Its SwiftUI layout frame is divided by 1.05 so the initial motion scale lands
    /// on the storyboard's exact 40%-wide first frame.
    static let markInitialWidthRatio: CGFloat = 0.40
    /// The 1.08 exit scale is the largest phase, so cap frame zero slightly lower
    /// to guarantee the rendered mark never exceeds the requested 293 pt ceiling.
    static let markInitialSideMaximum: CGFloat = 293 * (1.05 / 1.08)
    static let markInitialScale: CGFloat = 1.05
    static let markCenterYRatio: CGFloat = 0.48

    static let wordmarkWidthRatio: CGFloat = 0.46
    static let wordmarkBaselineYRatio: CGFloat = 0.88
    static let wordmarkSourceWidth: CGFloat = 187.1255849609375
    static let wordmarkCenterAboveBaseline: CGFloat = 12.857635498046875
}

private enum SplashTiming {
    static let wordmarkStagger = Duration.milliseconds(120)
    static let exitDuration = 0.28
    static let reducedExitDuration = 0.20

    /// Starting the 280 ms exit by 620 ms keeps the common path within the 900 ms
    /// motion budget. Starting by 920 ms guarantees the overlay is gone at 1.2 s.
    static let earliestExitStart = Duration.milliseconds(620)
    static let hardExitStart = Duration.milliseconds(920)
    static let reducedEarliestExitStart = Duration.milliseconds(500)
    static let reducedHardExitStart = Duration.seconds(1)
}

/// The application shell is mounted immediately and remains stable while the launch
/// overlay plays. Only compositor-friendly opacity/scale/offset values animate; no
/// geometry or constraints are changed per frame.
struct LaunchHost<Content: View>: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let content: Content

    @State private var settleMark = false
    @State private var revealWordmark = false
    @State private var earliestExitReached = false
    @State private var hardExitReached = false
    @State private var exitStarted = false
    @State private var splashVisible = true

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var holdsFirstFrame: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-launch-splash-hold")
        #else
        false
        #endif
    }

    private var skipsSplash: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-launch-splash-skip")
        #else
        false
        #endif
    }

    private var shouldStartExit: Bool {
        !holdsFirstFrame && !skipsSplash && !exitStarted
            && (hardExitReached || (earliestExitReached && !auth.booting))
    }

    private var exitSeconds: Double {
        reduceMotion ? SplashTiming.reducedExitDuration : SplashTiming.exitDuration
    }

    var body: some View {
        ZStack {
            // Plain state-driven animation, NOT `phaseAnimator(_:trigger:)`: a
            // trigger-based phase animator cycles through its phases and settles
            // back on the FIRST one, so the root ended at opacity 0 — a black app
            // forever after the splash left (found on the 2026-08-19 integration
            // pass). These booleans flip once per launch and must rest flipped.
            content
                .allowsHitTesting(!splashVisible || skipsSplash)
                .opacity(skipsSplash || exitStarted ? 1 : 0)
                .scaleEffect(reduceMotion || skipsSplash || exitStarted ? 1 : 0.98)
                .animation(.easeOut(duration: exitSeconds), value: exitStarted)

            if splashVisible && !skipsSplash {
                SplashView(
                    settleMark: settleMark,
                    revealWordmark: revealWordmark,
                    exitStarted: exitStarted
                )
                .zIndex(1)
            }
        }
        .background(SplashLayout.background.ignoresSafeArea())
        .task {
            guard !holdsFirstFrame, !skipsSplash else { return }
            await Task.yield()
            if !reduceMotion {
                settleMark = true
                try? await Task.sleep(for: SplashTiming.wordmarkStagger)
                guard !Task.isCancelled else { return }
                revealWordmark = true
            }
        }
        .task {
            guard !holdsFirstFrame, !skipsSplash else { return }
            let delay = reduceMotion
                ? SplashTiming.reducedEarliestExitStart
                : SplashTiming.earliestExitStart
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            earliestExitReached = true
        }
        .task {
            guard !holdsFirstFrame, !skipsSplash else { return }
            let delay = reduceMotion
                ? SplashTiming.reducedHardExitStart
                : SplashTiming.hardExitStart
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hardExitReached = true
        }
        .onChange(of: shouldStartExit, initial: true) { _, ready in
            guard ready else { return }
            exitStarted = true
        }
        .task(id: exitStarted) {
            guard exitStarted else { return }
            try? await Task.sleep(for: .seconds(exitSeconds))
            guard !Task.isCancelled else { return }
            splashVisible = false
        }
    }
}

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var settleMark = false
    var revealWordmark = false
    var exitStarted = false

    var body: some View {
        ZStack {
            SplashLayout.background
                .opacity(exitStarted ? 0 : 1)
                .animation(.easeOut(duration: exitSeconds), value: exitStarted)

            GeometryReader { geometry in
                let size = geometry.size
                let initialMarkSide = min(
                    size.width * SplashLayout.markInitialWidthRatio,
                    SplashLayout.markInitialSideMaximum
                )
                let settledMarkSide = initialMarkSide / SplashLayout.markInitialScale
                let wordmarkWidth = size.width * SplashLayout.wordmarkWidthRatio

                ZStack {
                    Image("LaunchMark")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: settledMarkSide, height: settledMarkSide)
                        .scaleEffect(reduceMotion || settleMark
                            ? 1
                            : SplashLayout.markInitialScale)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: settleMark)
                        .opacity(exitStarted ? 0 : 1)
                        .scaleEffect(reduceMotion || !exitStarted ? 1 : 1.08)
                        .animation(.easeOut(duration: exitSeconds), value: exitStarted)
                        .position(
                            x: size.width / 2,
                            y: size.height * SplashLayout.markCenterYRatio
                        )

                    // Keep the launch-screen copy present on frame zero, then hand it
                    // to the requested rising copy in place. This avoids a one-frame
                    // blink while the animated wordmark still moves 8 pt and fades in.
                    wordmark(width: wordmarkWidth)
                        .opacity(reduceMotion || !revealWordmark ? 1 : 0)
                        .animation(.easeOut(duration: 0.32), value: revealWordmark)
                        .opacity(exitStarted ? 0 : 1)
                        .animation(.easeOut(duration: exitSeconds), value: exitStarted)
                        .position(
                            x: size.width / 2,
                            y: wordmarkCenterY(screenHeight: size.height, width: wordmarkWidth)
                        )

                    if !reduceMotion {
                        wordmark(width: wordmarkWidth)
                            .opacity(revealWordmark ? 1 : 0)
                            .offset(y: revealWordmark ? 0 : 8)
                            .animation(.easeOut(duration: 0.32), value: revealWordmark)
                            .opacity(exitStarted ? 0 : 1)
                            .animation(.easeOut(duration: exitSeconds), value: exitStarted)
                            .position(
                                x: size.width / 2,
                                y: wordmarkCenterY(screenHeight: size.height, width: wordmarkWidth)
                            )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Block Party")
    }

    private var exitSeconds: Double {
        reduceMotion ? SplashTiming.reducedExitDuration : SplashTiming.exitDuration
    }

    private func wordmarkCenterY(screenHeight: CGFloat, width: CGFloat) -> CGFloat {
        let baseline = screenHeight * SplashLayout.wordmarkBaselineYRatio
        let scale = width / SplashLayout.wordmarkSourceWidth
        return baseline - (SplashLayout.wordmarkCenterAboveBaseline * scale)
    }

    private func wordmark(width: CGFloat) -> some View {
        Image("LaunchWordmark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: width)
    }
}

#Preview("Launch frame") { SplashView() }
