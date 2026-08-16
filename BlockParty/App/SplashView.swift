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
            content
                .allowsHitTesting(!splashVisible || skipsSplash)
                .phaseAnimator([false, true], trigger: exitStarted) { root, revealed in
                    root
                        .opacity(skipsSplash || revealed ? 1 : 0)
                        .scaleEffect(reduceMotion || skipsSplash || revealed ? 1 : 0.98)
                } animation: { revealed in
                    revealed ? .easeOut(duration: exitSeconds) : nil
                }

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
                .phaseAnimator([false, true], trigger: exitStarted) { background, exiting in
                    background.opacity(exiting ? 0 : 1)
                } animation: { exiting in
                    exiting ? .easeOut(duration: exitSeconds) : nil
                }

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
                        .phaseAnimator([false, true], trigger: settleMark) { mark, settled in
                            mark.scaleEffect(reduceMotion || settled
                                ? 1
                                : SplashLayout.markInitialScale)
                        } animation: { settled in
                            settled
                                ? .spring(response: 0.5, dampingFraction: 0.8)
                                : nil
                        }
                        .phaseAnimator([false, true], trigger: exitStarted) { mark, exiting in
                            mark
                                .opacity(exiting ? 0 : 1)
                                .scaleEffect(reduceMotion || !exiting ? 1 : 1.08)
                        } animation: { exiting in
                            exiting ? .easeOut(duration: exitSeconds) : nil
                        }
                        .position(
                            x: size.width / 2,
                            y: size.height * SplashLayout.markCenterYRatio
                        )

                    // Keep the launch-screen copy present on frame zero, then hand it
                    // to the requested rising copy in place. This avoids a one-frame
                    // blink while the animated wordmark still moves 8 pt and fades in.
                    wordmark(width: wordmarkWidth)
                        .phaseAnimator([false, true], trigger: revealWordmark) { text, handedOff in
                            text.opacity(reduceMotion || !handedOff ? 1 : 0)
                        } animation: { handedOff in
                            handedOff ? .easeOut(duration: 0.32) : nil
                        }
                        .phaseAnimator([false, true], trigger: exitStarted) { text, exiting in
                            text.opacity(exiting ? 0 : 1)
                        } animation: { exiting in
                            exiting ? .easeOut(duration: exitSeconds) : nil
                        }
                        .position(
                            x: size.width / 2,
                            y: wordmarkCenterY(screenHeight: size.height, width: wordmarkWidth)
                        )

                    if !reduceMotion {
                        wordmark(width: wordmarkWidth)
                            .phaseAnimator([false, true], trigger: revealWordmark) { text, revealed in
                                text
                                    .opacity(revealed ? 1 : 0)
                                    .offset(y: revealed ? 0 : 8)
                            } animation: { revealed in
                                revealed ? .easeOut(duration: 0.32) : nil
                            }
                            .phaseAnimator([false, true], trigger: exitStarted) { text, exiting in
                                text.opacity(exiting ? 0 : 1)
                            } animation: { exiting in
                                exiting ? .easeOut(duration: exitSeconds) : nil
                            }
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
