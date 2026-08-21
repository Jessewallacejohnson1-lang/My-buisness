//
//  HorizonCard.swift
//  BlockParty
//
//  The "Your day" horizon card: a small window onto the sky over St. Joe
//  right now. Sky above, tinted ground below, today's agenda rising out of
//  the line between them. All text lives below the horizon — that is what
//  lets the sky run from near-black to noon-bright with no contrast hacks.
//
//  The rail is a whole-day TAPE under a permanently centered sun marker
//  (see TimeAxis). Press-and-hold lifts the card and the finger drags the
//  strip 1:1 — scrubTime is the strip time under the marker. Motion
//  contract:
//  · Minute-to-minute color drift cross-fades at 0.8 s — suppressed the
//    whole time a scrub session is live (it would smear 1:1 tracking).
//  · Text swaps polarity with a 250 ms dissolve, never a color lerp.
//  · Reduce Motion: no scale pop, glide is instant, haptics stay.
//

import SwiftUI

/// The card's user-facing strings, one place — wording is provisional by
/// design, so changing it is a one-line edit.
nonisolated enum HorizonCopy {
    /// The ruler notch's label in the hour-label row — lowercase, one of
    /// the 12a·4a·8a·12p·4p·8p family.
    static let now = "now"
    static let nothingPosted = "Nothing posted for today yet."
    static let nothingPlanned = "Nothing planned yet"

    /// Primary line — the user's own day, plain words, Apple hierarchy.
    static func primaryLine(yours: Int, open: Int) -> String {
        if yours == 0 && open == 0 { return nothingPosted }
        if yours == 0 { return nothingPlanned }
        return yours == 1 ? "1 plan today" : "\(yours) plans today"
    }

    /// Secondary line — the town's open postings. Omitted entirely at zero.
    static func secondaryLine(open: Int) -> String? {
        guard open > 0 else { return nil }
        return open == 1 ? "1 more around town" : "\(open) more around town"
    }

    /// No "Your day" prefix: the section header is its own VoiceOver
    /// element and already says it — repeating it here made the swipe
    /// order read "Your day → Your day, 5 plans…" (review finding).
    static func cardAccessibilityLabel(yours: Int, open: Int) -> String {
        let primary = primaryLine(yours: yours, open: open)
        guard let secondary = secondaryLine(open: open) else { return primary }
        return "\(primary), \(secondary)."
    }
    static let cardAccessibilityHint = "Opens your day schedule"
    /// The section header's trailing link: "See all 16 ›". Nil at zero —
    /// no postings, nothing to link.
    static func seeAllLink(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "See all \(count) ›"
    }
    static func seeAllLinkAccessibilityLabel(_ count: Int) -> String {
        "See all \(count) of today's postings"
    }
    static let loadingAccessibilityLabel = "Your day, loading"
}

struct HorizonCard: View {
    let now: Date
    let sunrise: Date?
    let sunset: Date?
    let items: [DayItem]
    /// The live scrub session, owned by YourDayHorizonSection. Nil at
    /// rest. Galleries pass `.constant(nil)`.
    @Binding var scrub: ScrubSession?
    var isLoading = false
    var onOpenDay: () -> Void = {}

    /// Copy and button scale with Dynamic Type; the sky, rail and stubs
    /// are fixed. The card may exceed its 164 pt target at AX sizes.
    @ScaledMetric(relativeTo: .body) private var primarySize: CGFloat =
        HorizonMetrics.primaryTextSize
    @ScaledMetric(relativeTo: .footnote) private var secondarySize: CGFloat =
        HorizonMetrics.secondaryTextSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizonScrub) private var host

    /// Card inner width, for the drag's points-per-hour. Width only — the
    /// full FRAME is observed by the scrub-only reporter overlay, so feed
    /// scrolling at rest never writes state here.
    @State private var cardWidth: CGFloat = 0

    private var isScrubbing: Bool { scrub != nil }

    private var liftSpring: Animation {
        .spring(
            response: HorizonMetrics.liftResponse,
            dampingFraction: HorizonMetrics.liftDamping)
    }

    var body: some View {
        let sky = SolarSky(now: now, sunrise: sunrise, sunset: sunset)
        let ground = HorizonPalette.groundStyle(for: sky)
        let day = HorizonDay(items: items, now: now)
        let counts = (yours: day.yoursCount, open: day.openCount)

        // The whole card is the single button — one obvious tap, one route.
        // While scrubbing it is a scrub surface, not a door: the only way
        // out is tapping OFF the card, so the tap route goes quiet (the
        // post-hold touch-up would otherwise also open the day sheet).
        Button {
            if scrub == nil { onOpenDay() }
        } label: {
            groundContent(ground: ground, counts: counts)
        }
        .buttonStyle(FeedCardPressStyle())
        .disabled(isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isLoading
                ? HorizonCopy.loadingAccessibilityLabel
                : HorizonCopy.cardAccessibilityLabel(yours: counts.yours, open: counts.open)
        )
        .accessibilityHint(HorizonCopy.cardAccessibilityHint)
        .background { scene(sky: sky, day: day) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        // The pill and the frame reporter live AFTER the clip shape, in
        // the unclipped lifted layer: near midday the disc rides ~14 pt
        // from the card's top edge and the pill overflows the card frame.
        .overlay(alignment: .topLeading) { timePill(sky: sky) }
        .overlay { liftReporter }
        // Lift choreography, SCOPED so the strip's own transactions (drag
        // 1:1, magnet ease, exit glide spring) never inherit this spring.
        .animation(reduceMotion ? nil : liftSpring) { content in
            content
                .scaleEffect(
                    isScrubbing && !reduceMotion ? HorizonMetrics.liftScale : 1
                )
                .shadow(
                    color: .black.opacity(
                        isScrubbing
                            ? HorizonMetrics.liftShadowOpacity
                            : HorizonMetrics.restShadowOpacity),
                    radius: isScrubbing
                        ? HorizonMetrics.liftShadowRadius
                        : HorizonMetrics.restShadowRadius,
                    x: 0,
                    y: isScrubbing
                        ? HorizonMetrics.liftShadowY
                        : HorizonMetrics.restShadowY
                )
        }
        // BOTH gestures ride .simultaneousGesture and stay attached at ALL
        // times, so neither the whole-card Button nor the feed's vertical
        // pan is ever out-competed (the ffcb384 rule), and no in-flight
        // touch is cancelled by a gesture-tree change. Ownership (in
        // ScrubSession.dragOwner) keeps them from double-driving one
        // finger.
        .simultaneousGesture(pickupGesture)
        .simultaneousGesture(resumeDragGesture)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        // The minute-drift crossfade smears 1:1 tracking — off the whole
        // time a scrub session is live. At rest it also eases the strip's
        // 0.5 pt/min creep, because `sky` carries `now`.
        .animation(
            isScrubbing || reduceMotion ? nil : .easeInOut(duration: 0.8),
            value: sky)
        #if DEBUG
        // Keyed on isLoading: the loading and ready cards are the same view
        // type in the module's AnyView switch, so their identity — and a
        // bare .task — carries across the flip with the LOADING value's
        // stale captures. Re-keying restarts the driver on the ready card.
        .task(id: isLoading) { await runScrubDemoIfRequested() }
        #endif
    }

    // MARK: Backdrop + rail (the scene behind the text)

    private func scene(sky: SolarSky, day: HorizonDay) -> some View {
        GeometryReader { geo in
            let axis = TimeAxis(now: now, width: geo.size.width)
            // The single scalar: the strip time under the centered marker.
            let offset = axis.stripOffset(centering: scrub?.scrubTime ?? now)
            ZStack(alignment: .topLeading) {
                HorizonBackdrop(
                    sky: sky, axis: axis, stripOffset: offset,
                    isScrubbing: isScrubbing)
                if !isLoading {
                    HorizonRailView(
                        sky: sky, axis: axis, day: day, now: now,
                        stripOffset: offset)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Ground content

    private func groundContent(
        ground: HorizonGroundStyle, counts: (yours: Int, open: Int)
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sky + the tick/label zone stay clear of text. Same constant
            // the contrast sweep samples — nudging one moves both.
            Spacer(minLength: 0)
                .frame(
                    height: HorizonMetrics.skyHeight
                        + HorizonMetrics.primaryTextBelowHorizon)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: HorizonMetrics.copyLineSpacing) {
                    if isLoading {
                        loadingShimmer(ground: ground)
                    } else {
                        HStack(spacing: 5) {
                            Text(HorizonCopy.primaryLine(
                                yours: counts.yours, open: counts.open))
                                .font(.sansSemibold(primarySize))
                                .foregroundStyle(Color(ground.textPrimary))
                                .monospacedDigit()
                            // The card must advertise that it opens.
                            Image(systemName: "chevron.right")
                                .font(.system(size: secondarySize, weight: .semibold))
                                .foregroundStyle(Color(ground.textSecondary))
                        }
                        if let secondary = HorizonCopy.secondaryLine(open: counts.open) {
                            Text(secondary)
                                .font(.sans(secondarySize))
                                .foregroundStyle(Color(ground.textSecondary))
                                .monospacedDigit()
                        }
                    }
                }
                .id(ground.isDark)
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25), value: ground.isDark)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, HorizonMetrics.contentInset)
            .padding(.bottom, HorizonMetrics.copyBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: HorizonMetrics.cardHeight, alignment: .top)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func loadingShimmer(ground: HorizonGroundStyle) -> some View {
        // Stubs and counts become a quiet shimmer; the sky stays live.
        // Never a spinner.
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(ground.textSecondary, opacity: 0.22))
            .frame(width: 96, height: 12)
            .shimmering()
            .accessibilityHidden(true)
    }

    // MARK: Scrub — the floating time pill

    /// 34 pt above the sun disc, digits monospaced and numericText-rolling
    /// (static styling this phase; the live roll lands with Phase 2's
    /// scrubTime-drives-everything work).
    @ViewBuilder
    private func timePill(sky: SolarSky) -> some View {
        ZStack(alignment: .topLeading) {
            if let session = scrub {
                let elevation = sky.isSunUp ? sky.solarElevation : sky.nightElevation
                let discY = HorizonMetrics.skyHeight
                    - CGFloat(elevation)
                    * (HorizonMetrics.skyHeight - HorizonMetrics.discTopMargin)
                Text(Self.pillFormatter.string(from: session.scrubTime))
                    .font(.sansSemibold(HorizonMetrics.pillTextSize))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.black.opacity(HorizonMetrics.pillBackgroundOpacity))
                    )
                    .fixedSize()
                    .position(
                        x: cardWidth / 2,
                        y: discY - HorizonMetrics.pillGapAboveDisc)
                    .transition(.opacity)
            }
        }
        .animation(
            .easeOut(duration: HorizonMetrics.scrimFadeSeconds), value: isScrubbing)
        .allowsHitTesting(false)
    }

    /// Cached — a fresh DateFormatter per scrub frame would be the most
    /// expensive thing on the card.
    private static let pillFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Town.calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    // MARK: Scrub — gestures

    /// Long-press ~0.25 s, then the SAME touch drags the strip (the spec's
    /// prescribed sequence). A press that moves early simply fails the
    /// long press and the feed's pan wins — nothing to clean up, because
    /// nothing was claimed.
    private var pickupGesture: some Gesture {
        LongPressGesture(minimumDuration: HorizonMetrics.pickupHoldSeconds)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    // Touch-down at rest: warm the Taptic engine so the
                    // pop at +0.25 s fires with zero latency.
                    if scrub == nil { ScrubHaptics.prepareAll() }
                case .second(true, nil):
                    if scrub == nil { beginScrub() }
                case .second(true, .some(let drag)):
                    guard scrub?.dragOwner == .pickup else { return }
                    dragChanged(translation: drag.translation.width, claiming: .pickup)
                default:
                    break
                }
            }
            .onEnded { _ in
                guard scrub?.dragOwner == .pickup else { return }
                dragEnded()
            }
    }

    /// Scrub mode persists after a finger lift; the NEXT touch drags the
    /// strip immediately — no second long press. Inert at rest: it only
    /// ever claims a touch while a session is live (and the feed's scroll
    /// is already disabled then), so it cannot fight the vertical pan.
    private var resumeDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard scrub != nil, scrub?.dragOwner != .pickup else { return }
                dragChanged(translation: value.translation.width, claiming: .resume)
            }
            .onEnded { _ in
                guard scrub?.dragOwner == .resume else { return }
                dragEnded()
            }
    }

    // MARK: Scrub — the state machine's view-side hooks

    private var scrubModel: ScrubModel {
        ScrubModel(
            now: now,
            pointsPerHour: cardWidth > 0
                ? cardWidth / HorizonMetrics.visibleHours
                : 0)
    }

    /// Magnetic stubs pull toward the stubs the card shows (both lanes).
    private var magnetTimes: [Date] {
        let day = HorizonDay(items: items, now: now)
        return (day.yourStubs + day.publicStubs).map(\.start)
    }

    private func beginScrub() {
        ScrubHaptics.pickup()
        scrub = ScrubSession(scrubTime: now, dragBase: now, dragOwner: .pickup)
    }

    private func dragChanged(translation: CGFloat, claiming owner: ScrubDragOwner) {
        guard var session = scrub else { return }
        if session.dragOwner == nil {
            session.dragOwner = owner
            session.dragBase = session.scrubTime
            session.hasThuddedThisContact = false
        }
        guard session.dragOwner == owner, let base = session.dragBase else { return }
        let model = scrubModel
        let raw = model.rawTime(from: base, dragTranslation: translation)
        if model.isBeyondBounds(raw) {
            if !session.hasThuddedThisContact {
                ScrubHaptics.boundThud()
                session.hasThuddedThisContact = true
            }
        } else {
            session.hasThuddedThisContact = false
        }
        session.scrubTime = model.displayTime(forRaw: raw)
        // Deliberately no animation: 1:1 with the finger, no inertia.
        scrub = session
    }

    private func dragEnded() {
        guard var session = scrub else { return }
        session.dragOwner = nil
        session.dragBase = nil
        scrub = session
        // Magnet onto a nearby stub, or ease back inside the day after a
        // rubber-banded release. Otherwise stay put — scrub persists.
        if let target = scrubModel.releaseTarget(
            for: session.scrubTime, eventTimes: magnetTimes) {
            withAnimation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: HorizonMetrics.magnetEaseSeconds)
            ) {
                scrub?.scrubTime = target
            }
        }
    }

    /// The one way out: the tap OFF the card (the scrim), routed back down
    /// by the host. The strip glides home under the marker while the lift,
    /// scrim and pill settle concurrently.
    private func exitScrub() {
        guard scrub != nil else { return }
        ScrubHaptics.settle()
        host?.lower()
        withAnimation(
            reduceMotion
                ? nil
                : .spring(
                    response: HorizonMetrics.glideResponse,
                    dampingFraction: HorizonMetrics.glideDamping)
        ) {
            scrub = nil
        }
    }

    // MARK: Scrub — the lifted frame, reported to the feed's scrim

    /// Mounted ONLY while scrubbing, so feed scrolling at rest never
    /// writes state here (global frames change every scroll frame; the
    /// card's width does not).
    @ViewBuilder
    private var liftReporter: some View {
        if isScrubbing {
            GeometryReader { geo in
                Color.clear
                    .onAppear { publishLift(geo.frame(in: .global)) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        publishLift(frame)
                    }
            }
            .allowsHitTesting(false)
        }
    }

    private func publishLift(_ frame: CGRect) {
        // Never raise once the session is over: the exit transaction keeps
        // this reporter mounted through its removal transition while the
        // ancestor scale springs home, and every one of those frames lands
        // here via onChange — an unguarded raise would re-hang the scrim
        // AFTER exitScrub lowered it (caught on the first gate recording).
        guard scrub != nil else { return }
        // geo.frame(in: .global) already reads THROUGH the ancestor
        // scaleEffect, so the reported frame is the lifted card as drawn —
        // no manual inflation (inflating again dimmed a visible ring of
        // card, also caught on the recording).
        let scale = reduceMotion ? 1 : HorizonMetrics.liftScale
        host?.raise(
            HorizonScrubHost.Lift(frame: frame, cornerRadius: Radius.card * scale),
            onExitTap: { exitScrub() })
    }
}

// MARK: - Recording lane (compiles out of Release)

#if DEBUG
extension HorizonCard {
    /// `-horizon-scrub-demo` drives the scrub through the SAME functions
    /// the gestures call — this simulator setup has no touch automation
    /// (the HorizonDebugTapDriver pattern), so this is how pickup, 1:1
    /// drag, the rubber band, the magnet, lift-persistence and the exit
    /// glide get onto a recording. It cannot prove real gesture
    /// arbitration against the feed's pan — that stays a device check.
    fileprivate func runScrubDemoIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-horizon-scrub-demo"),
              !isLoading
        else { return }
        try? await Task.sleep(for: .seconds(2))
        // Wait out first layout instead of guessing at it — the guard used
        // to one-shot against a width the reveal hadn't laid out yet.
        for _ in 0..<40 where cardWidth <= 0 {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard scrub == nil, cardWidth > 0, !Task.isCancelled else { return }

        beginScrub()
        // Synthetic finger-lift so the beats below claim as resume drags.
        scrub?.dragOwner = nil
        scrub?.dragBase = nil

        // 1 · Slow drag right = earlier, 1:1 with the "finger".
        await demoDrag(toTime: now.addingTimeInterval(-4 * 3600), over: 1.4)
        dragEnded()
        try? await Task.sleep(for: .seconds(0.6))

        // 2 · Past the day's end: rubber band + one rigid thud; the
        // release snaps back inside.
        await demoDrag(
            toTime: scrubModel.dayEnd.addingTimeInterval(2 * 3600), over: 1.6)
        dragEnded()
        try? await Task.sleep(for: .seconds(0.8))

        // 3 · Five minutes short of the nearest stub — the ±8 min magnet
        // lands it exactly on release.
        if let base = scrub?.scrubTime,
           let event = magnetTimes.min(by: {
               abs($0.timeIntervalSince(base)) < abs($1.timeIntervalSince(base))
           }) {
            await demoDrag(toTime: event.addingTimeInterval(-5 * 60), over: 1.2)
            dragEnded()
        }

        // 4 · Finger up — scrub persists…
        try? await Task.sleep(for: .seconds(1.2))
        // …until the tap off the card.
        exitScrub()
    }

    /// Steps a synthetic resume drag toward `target` at ~60 Hz. The
    /// mapping is linear, so the raw target may sit beyond the day bounds
    /// (that is how the demo reaches the rubber band).
    fileprivate func demoDrag(toTime target: Date, over seconds: Double) async {
        guard let start = scrub?.scrubTime else { return }
        let pointsPerHour = cardWidth / HorizonMetrics.visibleHours
        let translation = -CGFloat(target.timeIntervalSince(start) / 3600) * pointsPerHour
        let steps = max(Int(seconds * 60), 1)
        for step in 1...steps {
            dragChanged(
                translation: translation * CGFloat(step) / CGFloat(steps),
                claiming: .resume)
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000 / Double(steps))))
        }
    }
}
#endif
