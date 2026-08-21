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
//  strip 1:1 — scrubTime is the strip time under the marker, and it is
//  THE scalar: sky, bloom, ground, pill, stubs, event line and bubble are
//  all pure functions of it, sampled through the once-per-day SolarTable.
//  Motion contract:
//  · At rest the minute drift eases at 0.8 s. The ease is injected only
//    when no scrub session is live — 1:1 tracking, the magnet ease and
//    the exit rewind all carry their own transactions untouched.
//  · The exit rewind animates scrubTime ITSELF (TimeLapseScene), so the
//    sky time-lapses back through every intermediate minute — never a
//    crossfade shortcut. Reduce Motion: crossfade, no glide.
//  · Ground polarity, ink, stub color, bloom and disc are continuous in
//    scrubTime — nothing steps, nothing keyframes independently.
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

    // The scrub's event line (spec): the bottom line swaps to the event
    // at/next-after scrubTime while scrubbing, back to counts on exit.
    static let quietHour = "Nothing at this hour"
    static let dayDone = "That's the day"
    static func eventLine(time: String, title: String, location: String?) -> String {
        guard let location, !location.isEmpty else { return "\(time) · \(title)" }
        return "\(time) · \(title) — \(location)"
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

/// Bridges scrubTime into the animation system: `animatableData` IS the
/// time, so animating a scrubTime change renders every intermediate
/// instant. The exit rewind time-lapses back through the skies between
/// here and now (the spec's hero moment — explicitly not a crossfade),
/// and the magnet ease re-lights through its 0.18 s the same way.
private struct TimeLapseScene<Content: View>: View, Animatable {
    var seconds: TimeInterval
    @ViewBuilder let content: (Date) -> Content

    var animatableData: TimeInterval {
        get { seconds }
        set { seconds = newValue }
    }

    var body: some View {
        content(Date(timeIntervalSinceReferenceDate: seconds))
    }
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
    /// Bumped only on Reduce Motion exits: the scene crossfades to the
    /// now-state through an identity swap instead of gliding the strip.
    @State private var sceneEpoch = 0

    /// A session exists — scrubbing OR the exit rewind.
    private var isSessionLive: Bool { scrub != nil }
    /// Scrubbing proper: the lift, scrim, pill, lens and bubble all key
    /// off THIS, so they settle concurrently while the rewind still runs.
    private var isActive: Bool { scrub != nil && scrub?.isEnding != true }

    /// The one scalar the whole card renders from.
    private var displaySeconds: TimeInterval {
        (scrub?.scrubTime ?? now).timeIntervalSinceReferenceDate
    }

    private var liftSpring: Animation {
        .spring(
            response: HorizonMetrics.liftResponse,
            dampingFraction: HorizonMetrics.liftDamping)
    }

    var body: some View {
        let day = HorizonDay(items: items, now: now)
        let counts = (yours: day.yoursCount, open: day.openCount)

        ZStack {
            TimeLapseScene(seconds: displaySeconds) { time in
                cardBody(at: time, day: day, counts: counts)
            }
            .id(sceneEpoch)
            .transition(.opacity)
        }
        // The resting minute drift (sky color + the strip's 0.5 pt/min
        // creep) eases at 0.8 s — injected ONLY when the transaction is
        // otherwise empty and no session is live, so it can never smear
        // 1:1 tracking, override the magnet ease, or fight the rewind.
        .transaction(value: displaySeconds) { transaction in
            if scrub == nil, !reduceMotion, transaction.animation == nil {
                transaction.animation =
                    .easeInOut(duration: HorizonMetrics.restDriftSeconds)
            }
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
        #if DEBUG
        // Keyed on isLoading: the loading and ready cards are the same view
        // type in the module's AnyView switch, so their identity — and a
        // bare .task — carries across the flip with the LOADING value's
        // stale captures. Re-keying restarts the driver on the ready card.
        .task(id: isLoading) { await runScrubDemoIfRequested() }
        #endif
    }

    /// Everything visible, as a pure function of one instant. Runs per
    /// frame during a scrub/rewind: the sky sample is an O(1) table read,
    /// the palette is arithmetic on doubles — no trig, no calendar math
    /// in the solar path.
    private func cardBody(
        at time: Date, day: HorizonDay, counts: (yours: Int, open: Int)
    ) -> some View {
        let table = SolarTableCache.table(day: now, sunrise: sunrise, sunset: sunset)
        let sky = table.sample(at: time)
        let ground = HorizonPalette.groundStyle(for: sky)
        let bubbleItem = isActive ? day.onEventItem(at: time) : nil

        // The whole card is the single button — one obvious tap, one route.
        // While scrubbing it is a scrub surface, not a door: the only way
        // out is tapping OFF the card, so the tap route goes quiet (the
        // post-hold touch-up would otherwise also open the day sheet).
        return Button {
            if scrub == nil { onOpenDay() }
        } label: {
            groundContent(ground: ground, counts: counts, day: day, at: time)
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
        .background { scene(at: time, sky: sky, day: day) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        // The pill and the frame reporter live AFTER the clip shape, in
        // the unclipped lifted layer: near midday the disc rides ~14 pt
        // from the card's top edge and the pill overflows the card frame.
        .overlay(alignment: .topLeading) { timePill(sky: sky, at: time, bubbleItem: bubbleItem) }
        .overlay { liftReporter }
        // Lift choreography, SCOPED so the strip's own transactions (drag
        // 1:1, magnet ease, exit rewind) never inherit this spring. Keys
        // off isActive: the lift settles at exit START, concurrent with
        // the rewind (spec).
        .animation(reduceMotion ? nil : liftSpring) { content in
            content
                .scaleEffect(
                    isActive && !reduceMotion ? HorizonMetrics.liftScale : 1
                )
                .shadow(
                    color: .black.opacity(
                        isActive
                            ? HorizonMetrics.liftShadowOpacity
                            : HorizonMetrics.restShadowOpacity),
                    radius: isActive
                        ? HorizonMetrics.liftShadowRadius
                        : HorizonMetrics.restShadowRadius,
                    x: 0,
                    y: isActive
                        ? HorizonMetrics.liftShadowY
                        : HorizonMetrics.restShadowY
                )
        }
    }

    // MARK: Backdrop + rail (the scene behind the text)

    private func scene(at time: Date, sky: SolarSky, day: HorizonDay) -> some View {
        GeometryReader { geo in
            let axis = TimeAxis(now: now, width: geo.size.width)
            // The single scalar: the strip time under the centered marker.
            let offset = axis.stripOffset(centering: time)
            ZStack(alignment: .topLeading) {
                HorizonBackdrop(
                    sky: sky, axis: axis, stripOffset: offset,
                    isScrubbing: isActive)
                if !isLoading {
                    HorizonRailView(
                        sky: sky, axis: axis, day: day, now: now,
                        stripOffset: offset,
                        isScrubbing: isSessionLive,
                        showsBubble: isActive)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Ground content

    private func groundContent(
        ground: HorizonGroundStyle, counts: (yours: Int, open: Int),
        day: HorizonDay, at time: Date
    ) -> some View {
        // Counts at rest → the event line while scrubbing → counts again
        // on exit. Nil = resting copy (which is also what an empty day
        // keeps through a full scrub, per spec).
        let scrubLine: String? = isActive ? scrubLineText(day: day, at: time) : nil

        return VStack(alignment: .leading, spacing: 0) {
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
                        // In-place crossfade, ONLY when the string
                        // changes: id-swapped twins overlap at partial
                        // opacity mid-transition (the burst.png rule).
                        ZStack(alignment: .topLeading) {
                            Group {
                                if let line = scrubLine {
                                    Text(line)
                                        .font(.sansSemibold(primarySize))
                                        .foregroundStyle(Color(ground.textPrimary))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .id("scrub-\(line)")
                                } else {
                                    HStack(spacing: 5) {
                                        Text(HorizonCopy.primaryLine(
                                            yours: counts.yours, open: counts.open))
                                            .font(.sansSemibold(primarySize))
                                            .foregroundStyle(Color(ground.textPrimary))
                                            .monospacedDigit()
                                        // The card must advertise that it opens.
                                        Image(systemName: "chevron.right")
                                            .font(.system(
                                                size: secondarySize, weight: .semibold))
                                            .foregroundStyle(Color(ground.textSecondary))
                                    }
                                    .id("counts")
                                }
                            }
                            .transition(.opacity)
                        }
                        if scrubLine == nil,
                           let secondary = HorizonCopy.secondaryLine(open: counts.open) {
                            Text(secondary)
                                .font(.sans(secondarySize))
                                .foregroundStyle(Color(ground.textSecondary))
                                .monospacedDigit()
                                .transition(.opacity)
                        }
                    }
                }
                .animation(
                    .easeInOut(duration: HorizonMetrics.eventLineFadeSeconds),
                    value: scrubLine)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, HorizonMetrics.contentInset)
            .padding(.bottom, HorizonMetrics.copyBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: HorizonMetrics.cardHeight, alignment: .top)
        .contentShape(Rectangle())
    }

    /// The bottom line for a scrub position, worded.
    private func scrubLineText(day: HorizonDay, at time: Date) -> String? {
        switch day.scrubLine(at: time) {
        case .event(let item):
            return HorizonCopy.eventLine(
                time: Self.eventLineTime(for: item.start),
                title: item.title,
                location: item.location)
        case .quietHour:
            return HorizonCopy.quietHour
        case .dayDone:
            return HorizonCopy.dayDone
        case .resting:
            return nil
        }
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

    /// 34 pt above the sun disc, digits monospaced and rolling
    /// (`contentTransition(.numericText())` under its own value-keyed
    /// beat, so the roll works mid-drag where no transaction exists).
    /// While the event bubble is present the pill yields upward past the
    /// bubble's top — the two share one geometry (HorizonMetrics), so
    /// they cannot collide at any solar elevation.
    @ViewBuilder
    private func timePill(sky: SolarSky, at time: Date, bubbleItem: DayItem?) -> some View {
        ZStack(alignment: .topLeading) {
            if isActive {
                let elevation = sky.isSunUp ? sky.solarElevation : sky.nightElevation
                let discY = HorizonMetrics.skyHeight
                    - CGFloat(elevation)
                    * (HorizonMetrics.skyHeight - HorizonMetrics.discTopMargin)
                let restingY = discY - HorizonMetrics.pillGapAboveDisc
                let yieldY = HorizonMetrics.bubbleBodyTop(
                    overYoursStub: bubbleItem?.source == .committed)
                    - HorizonMetrics.pillBubbleGap
                    - HorizonMetrics.pillEstimatedHeight / 2
                let label = Self.pillFormatter.string(from: time)
                Text(label)
                    .font(.sansSemibold(HorizonMetrics.pillTextSize))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(
                        .easeOut(duration: HorizonMetrics.pillDigitRollSeconds),
                        value: label)
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
                        y: bubbleItem != nil ? min(restingY, yieldY) : restingY)
                    .animation(
                        .easeInOut(duration: HorizonMetrics.eventLineFadeSeconds),
                        value: bubbleItem != nil)
                    .transition(.opacity)
            }
        }
        .animation(
            .easeOut(duration: HorizonMetrics.scrimFadeSeconds), value: isActive)
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

    /// "3 PM" on the hour, "3:15 PM" otherwise — the spec's event-line
    /// time voice.
    private static let hourOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Town.calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "h a"
        return formatter
    }()

    static func eventLineTime(for date: Date) -> String {
        Town.calendar.component(.minute, from: date) == 0
            ? hourOnlyFormatter.string(from: date)
            : pillFormatter.string(from: date)
    }

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
                guard let session = scrub, !session.isEnding,
                      session.dragOwner != .pickup
                else { return }
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

    /// Magnetic stubs pull toward the stubs the card shows (both lanes) —
    /// the same marked set the event line and bubble read.
    private var magnetTimes: [Date] {
        HorizonDay(items: items, now: now).markedItems.map(\.start)
    }

    private func beginScrub() {
        ScrubHaptics.pickup()
        scrub = ScrubSession(scrubTime: now, dragBase: now, dragOwner: .pickup)
    }

    private func dragChanged(translation: CGFloat, claiming owner: ScrubDragOwner) {
        guard var session = scrub, !session.isEnding else { return }
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
        let previous = session.scrubTime
        session.scrubTime = model.displayTime(forRaw: raw)
        // The crossing table (spec): event ·medium 0.9 outranks the sun
        // dots' soft ×2 outranks hour ·light 0.55; the 60 ms budget in
        // ScrubHaptics keeps a fling from machine-gunning.
        let solar = SolarTableCache.table(day: now, sunrise: sunrise, sunset: sunset)
        if let crossing = ScrubCrossingDetector.detect(
            from: previous, to: session.scrubTime,
            events: magnetTimes, sunrise: solar.sunrise, sunset: solar.sunset) {
            ScrubHaptics.crossing(crossing)
        }
        // Deliberately no animation: 1:1 with the finger, no inertia.
        scrub = session
    }

    private func dragEnded() {
        guard var session = scrub, !session.isEnding else { return }
        session.dragOwner = nil
        session.dragBase = nil
        scrub = session
        // Magnet onto a nearby stub, or ease back inside the day after a
        // rubber-banded release. Otherwise stay put — scrub persists.
        guard let target = scrubModel.releaseTarget(
            for: session.scrubTime, eventTimes: magnetTimes) else { return }
        // Landing ON the event is the event crossing (the ease passes it).
        if target != session.scrubTime,
           ScrubModel.magnetTarget(near: session.scrubTime, eventTimes: magnetTimes) == target {
            ScrubHaptics.eventTick()
        }
        withAnimation(
            reduceMotion
                ? nil
                : .easeOut(duration: HorizonMetrics.magnetEaseSeconds)
        ) {
            scrub?.scrubTime = target
        }
    }

    /// The one way out: the tap OFF the card (the scrim), routed back down
    /// by the host. The lift, scrim and pill settle immediately while
    /// scrubTime itself animates home — TimeLapseScene renders the glide
    /// as a time-lapse through every intermediate sky (spec hero moment).
    /// Reduce Motion: no glide — the scene crossfades to the now-state.
    private func exitScrub() {
        guard var session = scrub, !session.isEnding else { return }
        ScrubHaptics.settle()
        host?.lower()
        if reduceMotion {
            withAnimation(
                .easeInOut(duration: HorizonMetrics.reduceMotionExitFadeSeconds)
            ) {
                sceneEpoch += 1
                scrub = nil
            }
            return
        }
        session.isEnding = true
        session.dragOwner = nil
        session.dragBase = nil
        scrub = session
        withAnimation(
            .spring(
                response: HorizonMetrics.glideResponse,
                dampingFraction: HorizonMetrics.glideDamping),
            completionCriteria: .logicallyComplete
        ) {
            scrub?.scrubTime = now
        } completion: {
            scrub = nil
        }
    }

    // MARK: Scrub — the lifted frame, reported to the feed's scrim

    /// Mounted ONLY while actively scrubbing, so feed scrolling at rest
    /// never writes state here (global frames change every scroll frame;
    /// the card's width does not).
    @ViewBuilder
    private var liftReporter: some View {
        if isActive {
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
        // Never raise once the session is over or ending: the exit keeps
        // this reporter mounted through its removal transition while the
        // ancestor scale springs home, and every one of those frames lands
        // here via onChange — an unguarded raise would re-hang the scrim
        // AFTER exitScrub lowered it (caught on the first gate recording).
        guard isActive else { return }
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
    /// drag, the rubber band, the magnet, the bubble and the exit rewind
    /// get onto a recording. `-horizon-scrub-demo-script tour|sunset|
    /// fullday|events|empty` picks the beat sheet (default: tour). It
    /// cannot prove real gesture arbitration against the feed's pan —
    /// that stays a device check.
    fileprivate func runScrubDemoIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-horizon-scrub-demo"), !isLoading else { return }
        let script: String = {
            guard let i = args.firstIndex(of: "-horizon-scrub-demo-script"),
                  i + 1 < args.count
            else { return "tour" }
            return args[i + 1]
        }()
        try? await Task.sleep(for: .seconds(1.2))
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

        switch script {
        case "sunset":
            await runSunsetScript()
        case "fullday":
            await runFullDayScript()
        case "events":
            await runEventsScript()
        case "empty":
            await runEmptyScript()
        default:
            await runTourScript()
        }

        // …and out: the tap off the card — the rewind through the skies.
        try? await Task.sleep(for: .seconds(0.8))
        exitScrub()
    }

    /// The Phase 1 beat sheet: 1:1 drag, rubber band + thud, the magnet.
    fileprivate func runTourScript() async {
        await demoDrag(toTime: now.addingTimeInterval(-4 * 3600), over: 1.4)
        dragEnded()
        try? await Task.sleep(for: .seconds(0.6))

        await demoDrag(
            toTime: scrubModel.dayEnd.addingTimeInterval(2 * 3600), over: 1.6)
        dragEnded()
        try? await Task.sleep(for: .seconds(0.8))

        // Five minutes short of the nearest stub — the ±8 min magnet
        // lands it exactly on release, and the bubble names the event.
        if let base = scrub?.scrubTime,
           let event = magnetTimes.min(by: {
               abs($0.timeIntervalSince(base)) < abs($1.timeIntervalSince(base))
           }) {
            await demoDrag(toTime: event.addingTimeInterval(-5 * 60), over: 1.2)
            dragEnded()
        }
        try? await Task.sleep(for: .seconds(1.0))
    }

    /// Slow scrub across the sunset instant, both directions: the ground's
    /// 20-min crossfade, the bloom's dusk drift and the sun→moon disc
    /// swap, all with no hard cut anywhere.
    fileprivate func runSunsetScript() async {
        let table = SolarTableCache.table(day: now, sunrise: sunrise, sunset: sunset)
        await demoDrag(toTime: table.sunset.addingTimeInterval(-40 * 60), over: 1.2)
        try? await Task.sleep(for: .seconds(0.4))
        await demoDrag(toTime: table.sunset.addingTimeInterval(45 * 60), over: 5.0)
        try? await Task.sleep(for: .seconds(0.6))
        await demoDrag(toTime: table.sunset.addingTimeInterval(-45 * 60), over: 5.0)
        dragEnded()
        try? await Task.sleep(for: .seconds(0.4))
    }

    /// Fast edge-to-edge: midnight to midnight and back to afternoon — the
    /// no-visible-stepping beat.
    fileprivate func runFullDayScript() async {
        await demoDrag(toTime: scrubModel.dayStart, over: 1.2)
        try? await Task.sleep(for: .seconds(0.3))
        await demoDrag(toTime: scrubModel.dayEnd, over: 1.8)
        try? await Task.sleep(for: .seconds(0.3))
        await demoDrag(toTime: scrubModel.dayStart.addingTimeInterval(15 * 3600), over: 1.0)
        dragEnded()
        try? await Task.sleep(for: .seconds(0.4))
    }

    /// Stub to stub: the bubble appearing on each event, crossfading off
    /// through the gaps, the quiet-hour line, and "That's the day".
    fileprivate func runEventsScript() async {
        for event in magnetTimes.sorted().prefix(3) {
            await demoDrag(toTime: event.addingTimeInterval(-5 * 60), over: 1.0)
            dragEnded()  // the magnet lands it; the bubble names it
            try? await Task.sleep(for: .seconds(1.0))
        }
        // A gap: "Nothing at this hour" (bubble off), then past the last
        // event: "That's the day".
        if let last = magnetTimes.max() {
            await demoDrag(toTime: last.addingTimeInterval(35 * 60), over: 0.8)
            try? await Task.sleep(for: .seconds(0.8))
            await demoDrag(
                toTime: min(last.addingTimeInterval(90 * 60), scrubModel.dayEnd), over: 0.8)
            dragEnded()
            try? await Task.sleep(for: .seconds(0.8))
        }
    }

    /// Empty day: the sky, pill and haptics all scrub; the bottom line
    /// keeps the resting copy throughout (spec).
    fileprivate func runEmptyScript() async {
        await demoDrag(toTime: now.addingTimeInterval(-5 * 3600), over: 1.6)
        try? await Task.sleep(for: .seconds(0.4))
        await demoDrag(toTime: now.addingTimeInterval(6 * 3600), over: 2.0)
        dragEnded()
        try? await Task.sleep(for: .seconds(0.6))
    }

    /// Steps a synthetic resume drag toward `target` at ~60 Hz. The
    /// mapping is linear, so the raw target may sit beyond the day bounds
    /// (that is how the demo reaches the rubber band).
    fileprivate func demoDrag(toTime target: Date, over seconds: Double) async {
        guard let start = scrub?.scrubTime else { return }
        // Each beat is its own synthetic touch: release any prior claim so
        // the first step re-claims with a fresh dragBase at the CURRENT
        // scrubTime — otherwise a second beat's translation would compound
        // against the first beat's base and overshoot.
        scrub?.dragOwner = nil
        scrub?.dragBase = nil
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
