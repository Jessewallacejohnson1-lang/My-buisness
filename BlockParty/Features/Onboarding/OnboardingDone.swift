//
//  OnboardingDone.swift
//  Block Party — onboarding's last moment (BP app docs/plans/onboarding, ticket 24): the Dynamic
//  Island opens into a pill around "Hey {first name}", grows into a new one, "Welcome to" and the
//  BlockParty. wordmark, while confetti falls from it and the phone buzzes, then closes back into
//  the island (Jesse at Check-in 1; taste.md 2026-10-30). No app can open the real island while it
//  is on screen, so this draws a black pill on the island's spot that grows out of it. A phone
//  without one gets the same pills dropping from the top, as the hello pill does.
//

import SwiftUI

struct OnboardingDone: View {
    /// The neighbour's name, as onboarding has it.
    let name: String?
    /// The island has closed, or the pills went back up.
    let ended: () -> Void

    private enum Beat { case shut, hey, welcome }

    @State private var beat = Beat.shut
    /// Drawn: from the first frame of opening (the island's size, over the island) to the last of
    /// closing. A shut pill that stayed would show round a real island its size isn't quite.
    @State private var lit = false
    /// The finger's pull, back to 0 with a spring when it lifts or iOS takes the touch.
    @GestureState(resetTransaction: Transaction(animation: Motion.card)) private var dragY: CGFloat = 0
    @State private var burst = 0
    @State private var run: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The island at rest, from the approved mock (references/onboarding-done): 124 x 36 pt, 11 pt
    /// from the screen's top.
    static let island = CGSize(width: 124, height: 36)
    static let islandTop: CGFloat = 11
    /// Open over an island, it is the onboarding mock's open island, 84 pt tall, and its words sit under the camera, which
    /// hides anything drawn on the island's own spot; at least as wide as the island plus its round
    /// ends, so the island sits inside its flat top. Dropping from the top, it is the hello pill's
    /// 58 pt. Either hugs its words with the hello pill's 24 pt either side.
    static let openHeight: CGFloat = 84
    static let openWidth = island.width + openHeight
    static let side: CGFloat = 24
    static let opensAfter: Duration = .seconds(0.42)
    /// "Hey Avery" holds as long as the hello pill's hello.
    static let holdHey = HelloDropView.holdHello
    /// 10 s with VoiceOver on, as the hello pill's message, so there's time to hear it.
    static var holdWelcome: Duration { UIAccessibility.isVoiceOverRunning ? .seconds(10) : .seconds(2.6) }
    /// Opening and growing: about 4.6% past its size and back, the mock's overshoot.
    static let grow: Animation = .spring(duration: 0.55, bounce: 0.3)
    static let close: Animation = .spring(duration: 0.45, bounce: 0)

    /// A phone with a Dynamic Island; DEBUG `-onboarding-no-island` shows the drop instead.
    private var hasIsland: Bool {
        #if DEBUG
        if LaunchFlags.has(.onboardingNoIsland) { return false }
        #endif
        return HelloDropView.safeTop > 50
    }

    /// The pill's top: on the island, or 8 pt under the status bar, as the hello pill's.
    private var top: CGFloat { hasIsland ? Self.islandTop : HelloDropView.safeTop + 8 }
    private var height: CGFloat { hasIsland ? Self.openHeight : HelloDropView.height }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                HelloConfetti(burst: burst, from: CGPoint(x: geo.size.width / 2, y: top + height / 2))
                    .allowsHitTesting(false)
                pill
                    .padding(.top, top)
                    .offset(y: dragY + (hasIsland || beat != .shut ? 0 : -(top + height + 20)))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: Self.opensAfter)
            run = Task { await play() }
        }
    }

    private var pill: some View {
        ZStack {
            switch beat {
            case .shut:
                EmptyView()
            case .hey:
                Text("Hey \(Text(YouPage.firstName(name) ?? "neighbor").foregroundStyle(Hue.brandDisc))")
                    .transition(words)
            case .welcome:
                HStack(spacing: 8) {
                    Text("Welcome to")
                    BlockPartyWordmark(height: 22)
                }
                .transition(words)
            }
        }
        .font(.sansBold(20))   // BP Body, as all of onboarding (taste.md 2026-10-25)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, beat == .shut ? 0 : Self.side)
        // Over an island, the words take the band under the camera.
        .padding(.top, beat != .shut && hasIsland ? Self.island.height : 0)
        .frame(minWidth: beat != .shut && hasIsland ? Self.openWidth : Self.island.width)
        .frame(height: beat == .shut ? Self.island.height : height)
        .background(Hue.island, in: Capsule())
        .opacity(lit ? 1 : 0)
        .contentShape(Capsule())
        .onTapGesture { end() }
        .gesture(
            // In the screen's points: the pill moves with the finger, so its own would shift under it.
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .updating($dragY) { value, pull, _ in
                    // Up follows the finger; down only stretches a little, as the hello pill.
                    let y = value.translation.height
                    pull = y < 0 ? y : y / 6
                }
                .onEnded { value in
                    // Let go raised at all: away, as the mock's.
                    if value.translation.height < -12 { end() }
                }
        )
        .allowsHitTesting(beat != .shut)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Welcome to Block Party")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { end() }
    }

    /// The words come in a hair small and settle, and leave at once, so two never show together.
    private var words: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)).animation(.easeOut(duration: 0.26).delay(0.12)),
                    removal: .opacity.animation(.easeOut(duration: 0.12)))
    }

    private func play() async {
        // One announcement for both, so the second never cuts the first off.
        AccessibilityNotification.Announcement("Hey \(YouPage.firstName(name) ?? "neighbor"). Welcome to Block Party.").post()
        if reduceMotion {
            // The words without the motion: the pill is there at once, open, and only the words fade
            // (a pill fading in would show the island grey inside it).
            lit = true
            withTransaction(Transaction(animation: nil)) { beat = .hey }
        } else {
            lit = true
            withAnimation(Self.grow) { beat = .hey }
        }
        try? await Task.sleep(for: Self.holdHey)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Self.grow) { beat = .welcome }
        if !reduceMotion { burst += 1 }
        Haptics.success()
        try? await Task.sleep(for: Self.holdWelcome)
        guard !Task.isCancelled else { return }
        end()
    }

    /// Back into the island, or up the way it came; at once from a tap or a flick, mid-spring too.
    private func end() {
        run?.cancel()
        guard beat != .shut else { return }
        if reduceMotion {
            // No motion: it goes at once.
            lit = false
            beat = .shut
            ended()
            return
        }
        withAnimation(Self.close) {
            beat = .shut
        } completion: {
            lit = false
            ended()
        }
    }
}
