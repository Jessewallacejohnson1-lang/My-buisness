//
//  MapSheet.swift
//  Block Party — the always-visible bottom sheet on the map (Life360-style).
//
//  The sheet IS the surface here: a draggable white sheet that sits above the tab
//  bar and floats over the map. Three detents the grabber snaps between:
//    • peek   (~120pt) — ONE ambient line: what's live right now (not a list)
//    • medium (~50%)   — the working list (Today ⇄ Places)
//    • full   (~85%)   — the same list, immersive; stops just below the chrome
//
//  Peek shows a single glanceable status line; as you pull up it cross-fades into
//  the list. All content is REAL (no invented counts):
//    • today  — today's happenings from MapModel.todayEvents (coral dot = live now)
//    • places — the curated MapSpots catalogue, with each spot's live count today
//    • detail — one spot: blurb, its happenings, Directions (set by tapping a pin)
//
//  Mirrors Life360's "People / Places" sheet: a title + a coral toggle pill on the
//  right, a scrollable list, and a spot detail that replaces the list when a pin is
//  tapped (so nothing stacks). The old pop-up MapBottomCard is subsumed here.
//

import SwiftUI
import CoreLocation

/// How far the sheet is pulled up. Three detents; the grabber snaps between them.
private enum SheetDetent: CaseIterable { case peek, medium, full }

/// The two list faces of the sheet (a spot detail temporarily overrides both).
private enum SheetMode { case today, places }

/// A vertical gesture belongs to exactly one surface at a time. `scroll` may hand
/// off to `sheet` when a downward drag reaches the active ScrollView's top.
private enum SheetDragOwner { case undecided, scroll, sheet }

struct MapSheet: View {
    // Data (owned by MapModel / SJMapView; the sheet only reads)
    let events: [TimelineEvent]
    let state: MapModel.LoadState
    let spots: [Spot]                          // already filtered by the map's chip
    @Binding var selected: Spot?               // non-nil → show that spot's detail
    /// A tapped food/business POI (mutually exclusive with `selected`). Its detail now
    /// renders INSIDE this bar too, instead of the old swipe-up Apple modal.
    @Binding var selectedPOI: POI?

    // Callbacks up to SJMapView
    let happenings: (Spot) -> [TimelineEvent]  // events resolving to a spot
    let spotFor: (TimelineEvent) -> Spot?      // an event's pin, if any
    let onSelectSpot: (Spot) -> Void           // fly camera + select
    let onRetry: () -> Void

    /// Vertical space the unified tab bar occupies at the very bottom. The sheet's
    /// glass sits flush on top of it; both live in one `GlassEffectContainer` (see
    /// `MainTabsView`) so they read/merge as a single continuous Liquid Glass shape.
    static let tabBarReserve: CGFloat = 66
    /// Collapsed height — grabber + the single live-now line, sized to sit right on
    /// top of the tab bar (no floating gap). The map's floating ?/locate controls
    /// rest just above this and fade out as the sheet grows.
    static let peekHeight: CGFloat = 96
    /// Breathing room under the last row, above the sheet's bottom edge (the tab bar
    /// sits below the sheet now, so content no longer needs to clear a 56pt gap).
    static let contentBottomInset: CGFloat = 18
    /// Corner radius of the unified glass — matches `HyggeTabBar`'s shell (26) so the
    /// sheet reads as the tab bar stretching upward, not a second panel.
    static let glassRadius: CGFloat = 26
    /// Peak opacity of the content frost veil at full expansion. Near-opaque so the
    /// dark map cluster bubbles can't bleed through the body as smudges; not 1.0 so a
    /// whisper of glass depth survives (and the grabber/join bands stay fully glassy).
    static let frostMax: CGFloat = 0.94
    /// Floor of that veil at the PEEK rest state. Was 0, i.e. pure glass — and pure glass over
    /// this basemap bleaches the warm cream ground while transmitting park green, so the
    /// collapsed sheet picked up green blotches whose polygon SHAPES were readable through the
    /// panel. Deliberately low: enough to flatten that chroma, not enough to stop the peek band
    /// reading as the same glass as the tab bar it merges into.
    static let frostMin: CGFloat = 0.30

    /// The unified glass silhouette: rounded top (like the tab bar), square bottom so
    /// it blends straight down into the tab bar it sits on.
    static let sheetShape = UnevenRoundedRectangle(
        topLeadingRadius: glassRadius, bottomLeadingRadius: 0,
        bottomTrailingRadius: 0, topTrailingRadius: glassRadius, style: .continuous)

    @State private var mode: SheetMode = MapSheet.initialMode()
    @State private var detent: SheetDetent = MapSheet.initialDetent()
    /// Namespace for the Today ⇄ Places segmented control's sliding selection pill.
    @Namespace private var segment

    /// DEBUG-only: `-map-sheet places` opens the sheet on the Places list so it can
    /// be screenshotted headlessly. No effect in release / without the flag.
    private static func initialMode() -> SheetMode {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-sheet"), i + 1 < a.count, a[i + 1] == "places" { return .places }
        #endif
        return .today
    }

    /// DEBUG-only: `-map-detent peek|medium|full` opens the sheet at a given detent
    /// so each rest state (and the peek line ⇄ list cross-fade) can be screenshotted
    /// headlessly. No effect in release / without the flag.
    private static func initialDetent() -> SheetDetent {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-detent"), i + 1 < a.count {
            switch a[i + 1] {
            case "medium": return .medium
            case "full":   return .full
            default:       return .peek
            }
        }
        // `-map-sheet <mode>` targets the LIST, which only shows from medium up — open
        // there so that flag surfaces its list without also needing `-map-detent`.
        if a.contains("-map-sheet") { return .medium }
        #endif
        return .peek
    }

    /// Finger translation applied to the sheet. Unlike the old grabber-only
    /// GestureState, this is driven by a whole-sheet gesture whose ownership is
    /// coordinated with the active inner ScrollView.
    @State private var drag: CGFloat = 0
    @State private var dragOwner: SheetDragOwner = .undecided
    /// Unlike `onEnded`, GestureState resets when the recognizer is cancelled.
    /// Observing that reset prevents stale drag ownership from disabling scrolling.
    @GestureState private var dragGestureActive = false
    /// If content reaches its top during a downward drag, the sheet begins at zero
    /// from that exact point instead of jumping by the distance already scrolled.
    @State private var dragHandoffTranslation: CGFloat = 0
    @State private var listScrollAtTop = true
    @State private var spotDetailScrollAtTop = true
    @State private var poiDetailScrollAtTop = true
    /// Latest laid-out container height, so the drag-end snap can reason about the
    /// actual detent heights (they're derived from it). Updated off the layout pass.
    @State private var containerH: CGFloat = 0
    /// This is a hand-rolled sheet, so §11 doesn't get honored for free — it self-gates:
    /// detent/select springs drop to a non-bouncy crossfade under Reduce Motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    /// The device-local saved set (shared with Explore). Observed so the detail
    /// header's bookmark reflects saves live; also the source of the map's Saved pin.
    @ObservedObject private var saved = SavedStore.shared

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            let m = metrics(H)
            let resting = restHeight(detent, m)
            // Drag up → negative translation → taller sheet.
            let height = min(max(resting - drag, m.peek), m.full)
            // 0 at peek → 1 by the time we reach medium: drives the line⇄list fade.
            let p = min(max((height - m.peek) / max(1, m.medium - m.peek), 0), 1)
            // Content frost: 0 at peek (pure glass), ramps to near-opaque by medium so the
            // expanded content reads as a clean frosted surface — the map's dark cluster
            // bubbles can't bleed through the empty middle as smudges. Faded out at the
            // grabber + the tab-bar join (below), so the continuous-glass morph still reads.
            let frost = Self.frostMin + p * (Self.frostMax - Self.frostMin)

            VStack(spacing: 0) {
                grabber
                if let spot = selected {
                    detailContent(spot)
                } else if let poi = selectedPOI {
                    poiDetailContent(poi)
                } else {
                    ZStack(alignment: .top) {
                        // Bias the two curves off the shared `p` so one layer is always
                        // dominant — no muddy 50/50 crossing when you scrub slowly. The
                        // outgoing line also blurs a touch to soften the handoff seam.
                        let peekOut = 1 - min(1, p * 1.7)            // gone by p≈0.59
                        let listIn = max(0, (p - 0.3) / 0.7)         // in from p≈0.3
                        listStack
                            .opacity(listIn)
                            .allowsHitTesting(p > 0.5)
                            .accessibilityHidden(p <= 0.5)
                        peekLine
                            .opacity(peekOut)
                            .blur(radius: (1 - peekOut) * 2)
                            .allowsHitTesting(p <= 0.5)
                            .accessibilityHidden(p > 0.5)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: height, alignment: .top)
            // Frost veil between the content and the glass. Transparent at the grabber
            // (top) and the tab-bar join (bottom) so those bands stay glassy and the
            // continuous morph reads; near-opaque in the body once expanded so content
            // sits on a clean surface. Whole veil scales with `frost` (0 at peek).
            .background {
                LinearGradient(
                    stops: [
                        .init(color: Hue.surface.opacity(0),     location: 0.00),
                        .init(color: Hue.surface.opacity(frost), location: 0.05),
                        .init(color: Hue.surface.opacity(frost), location: 0.90),
                        .init(color: Hue.surface.opacity(0),     location: 1.00)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipShape(Self.sheetShape)
            // Real Liquid Glass — the SAME material + radius as BlockPartyTabBar. Both sit
            // in one GlassEffectContainer (MainTabsView), so the sheet's glass and the
            // tab bar merge into a single continuous bottom shape.
            .glassEffect(.regular, in: Self.sheetShape)
            // Observe the same vertical gesture across the whole sheet. The active
            // ScrollView remains enabled only while it owns that gesture.
            .simultaneousGesture(sheetDragGesture)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 20)                 // match the tab bar's side insets
            .padding(.bottom, Self.tabBarReserve)      // rest flush on top of the tab bar
            // Publish how far the sheet has grown past peek (0 = collapsed) so the map's
            // floating ?/locate controls can fade out before the sheet reaches them.
            .preference(key: SheetExpansionKey.self,
                        value: min(1, max(0, (height - m.peek) / 64)))
            .onChange(of: H, initial: true) { _, h in containerH = h }
        }
        .animation(reduceMotion ? Motion.smooth : Motion.sheet, value: detent)
        .animation(reduceMotion ? Motion.smooth : Motion.sheet, value: selected?.id)
        .animation(reduceMotion ? Motion.smooth : Motion.sheet, value: selectedPOI?.id)
        // A tapped pin lifts the sheet to MEDIUM (Apple-Maps feel): the card rises to ~half
        // while the map stays the hero and the camera lifts the pin above it (see SJMapView).
        // Full is a drag-up away. A POI opens into the same in-bar detail, so it lifts too.
        .onChange(of: selected?.id) { _, id in if id != nil { detent = .medium } }
        .onChange(of: selectedPOI?.id) { _, id in if id != nil { detent = .medium } }
        .onChange(of: dragGestureActive) { wasActive, isActive in
            if wasActive && !isActive { resetDrag() }
        }
        // onChange only fires on a transition; a spot/POI preselected at mount (e.g. the
        // `-map-open` / `-map-open-poi` debug flags, or a deep link) needs the same lift.
        .onAppear { if selected != nil || selectedPOI != nil { detent = .medium } }
    }

    /// The three rest heights, derived from the container height. peek is fixed
    /// (one line); medium is half-ish; full stops just below the map's floating
    /// chrome so the town pill / filter / compose stay clear (never half-clipped)
    /// and a band of the live map is always visible — the sheet doesn't swallow it.
    private func metrics(_ H: CGFloat) -> (peek: CGFloat, medium: CGFloat, full: CGFloat) {
        let peek = Self.peekHeight
        let medium = max(peek + 120, H * 0.5)
        // full is H−132, but `.padding(.bottom, tabBarReserve)` is applied AFTER this
        // height frame, so the sheet's real top clearance is 132 − tabBarReserve ≈ 66pt
        // (measured 68) — still clear of the floating chrome. The H*0.9 arm only binds on
        // iPad-class heights (H > 1320).
        let full = max(medium + 80, min(H * 0.9, H - 132))
        return (peek, medium, full)
    }

    private func restHeight(_ d: SheetDetent, _ m: (peek: CGFloat, medium: CGFloat, full: CGFloat)) -> CGFloat {
        switch d {
        case .peek:   return m.peek
        case .medium: return m.medium
        case .full:   return m.full
        }
    }

    // MARK: Grabber + coordinated sheet drag

    private var grabber: some View {
        Capsule()
            .fill(Hue.hairline)
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .accessibilityLabel("Adjust sheet height")
            .accessibilityValue(detentA11yValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(up: true)
                case .decrement: step(up: false)
                @unknown default: break
                }
            }
    }

    /// The grabber's rendered band is 19pt tall (8 + 5 + 6). Keep the historical
    /// grabber behavior even when full-height content is scrolled away from its top.
    private static let grabberDragRegionHeight: CGFloat = 19
    /// The outer recognizer begins at 1pt for immediate tracking, but movement below
    /// this distance remains a tap and must never participate in detent projection.
    private static let tapSlop: CGFloat = 8

    /// A single vertical gesture arbitrates between the sheet and its active
    /// ScrollView. At non-full detents the sheet always wins. At full, content
    /// scrolls normally unless a downward drag begins (or arrives) at the top.
    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragGestureActive) { _, active, _ in active = true }
            .onChanged(updateDrag)
            .onEnded(finishDrag)
    }

    private var activeScrollAtTop: Bool {
        if selected != nil { return spotDetailScrollAtTop }
        if selectedPOI != nil { return poiDetailScrollAtTop }
        if isCenteredEmptyState { return true }
        return listScrollAtTop
    }

    private var innerScrollDisabled: Bool {
        detent != .full || dragOwner == .sheet
    }

    private func updateDrag(_ value: DragGesture.Value) {
        let vertical = value.translation.height

        if dragOwner == .undecided {
            // Ignore a horizontal start instead of stealing taps/segment movement.
            guard abs(vertical) > abs(value.translation.width) else { return }

            let beganOnGrabber = value.startLocation.y <= Self.grabberDragRegionHeight
            if beganOnGrabber || detent != .full || (vertical > 0 && activeScrollAtTop) {
                dragOwner = .sheet
                dragHandoffTranslation = 0
            } else {
                dragOwner = .scroll
            }
        } else if dragOwner == .scroll, vertical > 0, activeScrollAtTop {
            // The ScrollView consumed the portion above its top. Continue this same
            // finger movement from zero so the sheet handoff has no positional jump.
            dragOwner = .sheet
            dragHandoffTranslation = vertical
        }

        guard dragOwner == .sheet else { return }
        let sheetTranslation = vertical - dragHandoffTranslation
        withAnimation(reduceMotion ? Motion.smooth : Motion.interactive) {
            drag = sheetTranslation
        }
    }

    private func finishDrag(_ value: DragGesture.Value) {
        guard dragOwner == .sheet else {
            resetDrag()
            return
        }
        let sheetTranslation = value.translation.height - dragHandoffTranslation
        guard abs(sheetTranslation) >= Self.tapSlop else {
            resetDrag()
            return
        }
        snap(value, handoffTranslation: dragHandoffTranslation)
    }

    /// Snap to the nearest of the three detents, carried by drag momentum
    /// (predicted end translation), so a quick flick can skip a stop. A decisive
    /// downward flick always collapses fully, including after reversing mid-drag.
    private func snap(_ value: DragGesture.Value, handoffTranslation: CGFloat) {
        let m = metrics(containerH)
        let resting = restHeight(detent, m)
        let projected = value.predictedEndTranslation.height - handoffTranslation
        let targetHeight = min(max(resting - projected, m.peek), m.full)
        let stops: [(SheetDetent, CGFloat)] = [(.peek, m.peek), (.medium, m.medium), (.full, m.full)]
        // Points/second. Above this, direction is a stronger signal than distance:
        // a fast close gesture should never get caught at the medium stop.
        let isFastDismiss = value.velocity.height >= 1_200
        let next = isFastDismiss
            ? SheetDetent.peek
            : stops.min { abs($0.1 - targetHeight) < abs($1.1 - targetHeight) }?.0 ?? detent
        if next != detent { Haptics.selection() }   // detent snap = a segmented tick (§10)
        withAnimation(reduceMotion ? Motion.smooth : Motion.sheet) {
            detent = next
            drag = 0
        }
        dragOwner = .undecided
        dragHandoffTranslation = 0
    }

    private func resetDrag() {
        drag = 0
        dragOwner = .undecided
        dragHandoffTranslation = 0
    }

    /// Transform scroll geometry to a Bool so state only changes when a scroller
    /// crosses the top boundary, not on every pixel (important during 60fps scroll).
    private nonisolated static func scrollIsAtTop(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentOffset.y + geometry.contentInsets.top <= 0.5
    }

    /// Spoken by VoiceOver after each adjustable step, so the landed detent is announced.
    private var detentA11yValue: String {
        switch detent {
        case .peek:   return "Peek"
        case .medium: return "Half open"
        case .full:   return "Full"
        }
    }

    /// VoiceOver adjustable: step one detent up/down.
    private func step(up: Bool) {
        let order: [SheetDetent] = [.peek, .medium, .full]
        guard let i = order.firstIndex(of: detent) else { return }
        let j = min(max(i + (up ? 1 : -1), 0), order.count - 1)
        if j != i { Haptics.selection(); detent = order[j] }   // detent step = a segmented tick (§10)
    }

    // MARK: Peek — one line: what's live right now

    /// The single glanceable line shown at the peek detent. Tapping it lifts the
    /// sheet to the working list (or retries when offline/errored).
    private var peekLine: some View {
        Button {
            switch state {
            case .offline, .error: onRetry()
            default:               Haptics.selection(); detent = .medium   // detent change (§10)
            }
        } label: {
            HStack(spacing: 12) {
                StatusDot(live: !liveEvents.isEmpty)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peekPrimary)
                        .font(.sansSemibold(16))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    if let secondary = peekSecondary {
                        Text(secondary)
                            .font(.sans(13))
                            .foregroundStyle(peekSecondaryColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                peekAccessory
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PeekLineStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(peekA11yLabel)
        .accessibilityHint(peekIsRetry ? "Retries loading today's happenings" : "Opens the map list")
    }

    /// Today's events that are happening right now.
    private var liveEvents: [TimelineEvent] {
        events.filter { DateHelpers.isLiveNow($0.startTime) }
    }

    private var peekIsRetry: Bool {
        switch state { case .offline, .error: return true; default: return false }
    }

    private var peekPrimary: String {
        switch state {
        case .loading: return "Checking what's on…"
        case .offline: return "You're offline"
        case .error:   return "Couldn't load today's happenings"
        case .loaded, .empty:
            let live = liveEvents
            if live.count == 1 { return live[0].title }
            if live.count > 1  { return "\(live.count) happening now" }
            if events.isEmpty  { return "Nothing happening yet today" }
            return "Nothing happening right now"
        }
    }

    private var peekSecondary: String? {
        switch state {
        case .loading: return nil
        case .offline, .error: return "Tap to retry"
        case .loaded, .empty:
            let live = liveEvents
            if live.count == 1 {
                if let where0 = live[0].location ?? live[0].clubName { return "Live now · \(where0)" }
                return "Live now"
            }
            if live.count > 1 { return "Happening across town right now" }
            if events.isEmpty { return "Use + to share the first event" }
            return "\(events.count) today — pull up to see"
        }
    }

    private var peekSecondaryColor: Color {
        if peekIsRetry { return Hue.ink }
        return liveEvents.isEmpty ? Hue.inkSecondary : Hue.ink   // secondary ink stays legible on frosted material
    }

    @ViewBuilder
    private var peekAccessory: some View {
        if peekIsRetry {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: 30, height: 30)
                .background(Hue.fill, in: Circle())
        } else {
            // A quiet "pull up" affordance — a soft chevron that hints there's more.
            Image(systemName: "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Hue.inkSecondary)
                .frame(width: 30, height: 30)
                .background(Hue.paper, in: Circle())
        }
    }

    private var peekA11yLabel: String {
        [peekPrimary, peekSecondary].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: List (medium / full) — header + scrollable body

    private var listStack: some View {
        VStack(spacing: 0) {
            listHeader
            listBody
        }
    }

    // MARK: List header — Today | Places segmented control + context subtitle

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            segmentedControl
            subtitle
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch mode {
        case .places:
            Text("\(spots.count) places in town")
                .font(.sans(13)).foregroundStyle(Hue.inkSecondary)
        case .today:
            switch state {
            case .loading:
                Text("Loading…").font(.sans(13)).foregroundStyle(Hue.inkSecondary)
            case .loaded, .empty:
                if events.isEmpty {
                    Text("Nothing happening yet today").font(.sans(13)).foregroundStyle(Hue.inkSecondary)
                } else {
                    Text("^[\(events.count) happening](inflect: true) today")
                        .font(.mono(13)).foregroundStyle(Hue.inkSecondary).monospacedDigit()
                }
            case .offline:
                retryLabel("Offline — tap to retry", icon: "wifi.slash")
            case .error:
                retryLabel("Couldn't load today's happenings — tap to retry", icon: "arrow.clockwise")
            }
        }
    }

    private func retryLabel(_ text: String, icon: String) -> some View {
        Button(action: onRetry) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(text)
            }
            .font(.sans(13)).foregroundStyle(Hue.ink)
        }
        .buttonStyle(.plain)
    }

    /// A visible two-segment switch — both destinations always shown — replacing the old
    /// blind flip-button (you had to read the label to know where it'd take you). The
    /// SELECTED segment takes the brand accent; "selected state" is one of the accent's
    /// meaning-scoped seams. Mirrors `BlockPartyTabBar`'s sliding matchedGeometry pill.
    private var segmentedControl: some View {
        HStack(spacing: 4) {
            segmentButton(.today, "Today")
            segmentButton(.places, "Places")
        }
        .padding(4)
        .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.button + 2, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func segmentButton(_ target: SheetMode, _ title: String) -> some View {
        let isSelected = mode == target
        return Button {
            guard mode != target else { return }
            Haptics.selection()   // a segmented Today⇄Places choice → selection tick (§10)
            withAnimation(reduceMotion ? Motion.smooth : Motion.snappy) { mode = target }
        } label: {
            Text(title)
                .font(.sansSemibold(14))
                .foregroundStyle(isSelected ? .white : Hue.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.button - 2, style: .continuous)
                            .fill(Hue.accent)
                            .matchedGeometryEffect(id: "segmentPill", in: segment)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: List body

    /// A non-scrolling state (nothing to scroll): center its block in the available
    /// height so full-over-empty reads as a composed screen, never a top-clinging void.
    private var isCenteredEmptyState: Bool {
        guard mode == .today else { return false }   // Places always has the catalogue
        switch state {
        case .loaded, .empty:  return events.isEmpty
        case .offline, .error: return true
        default:               return false          // loading shows skeletons (scroll)
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if isCenteredEmptyState {
            emptyStateBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // fill + center
                .padding(.bottom, Self.contentBottomInset)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    switch mode {
                    case .today:  todayRows
                    case .places: placeRows
                    }
                }
                .padding(.bottom, Self.contentBottomInset)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(innerScrollDisabled)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                Self.scrollIsAtTop(geometry)
            } action: { _, isAtTop in
                listScrollAtTop = isAtTop
            }
        }
    }

    /// The centered empty/error content (routed here by `isCenteredEmptyState`).
    @ViewBuilder
    private var emptyStateBlock: some View {
        switch state {
        case .offline, .error:
            emptyState(icon: "wifi.slash", text: "Couldn't load today's happenings.")
        default:
            emptyState(icon: "moon.stars",
                       text: "No events or activity posted yet today — but all your local spots are on the map. Tap a pin to explore.")
        }
    }

    @ViewBuilder
    private var todayRows: some View {
        switch state {
        case .loading:
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
            }
            .shimmering()
        case .loaded, .empty:
            // Empty is handled by the centered path (isCenteredEmptyState); here we only
            // reach the populated list.
            ForEach(events) { ev in
                TodayEventRow(event: ev, live: DateHelpers.isLiveNow(ev.startTime))
                    .contentShape(Rectangle())
                    .onTapGesture { if let s = spotFor(ev) { onSelectSpot(s) } }
                rowDivider
            }
        case .offline, .error:
            EmptyView()   // handled by the centered path
        }
    }

    private var placeRows: some View {
        ForEach(spots) { spot in
            PlaceRow(spot: spot, liveCount: happenings(spot).filter { DateHelpers.isLiveNow($0.startTime) }.count)
                .contentShape(Rectangle())
                .onTapGesture { onSelectSpot(spot) }
            rowDivider
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Hue.hairline).frame(height: 1).padding(.leading, 20)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(Hue.inkSecondary)
            Text(text).font(.sans(14)).foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)   // centered block; keep the copy off the glass edges
    }

    // MARK: Detail — one spot (replaces the old MapBottomCard)

    /// Save/unsave this place. Saved takes the brand accent ("saved state" is one of the
    /// accent's meaning-scoped seams) — this is a tappable control in the SHEET, so accent
    /// is fine here; the map *pin's* saved mark stays ink so accent keeps meaning "live" on
    /// the canvas. Powers the map's Saved pin via SavedStore.
    private func saveButton(_ spot: Spot) -> some View {
        let isSaved = saved.isSaved(spot.id)
        return Button {
            // Saving a place is a positive milestone → success notification; un-saving is
            // a light tap (spec §10 — success marks the save, not the removal).
            if isSaved { Haptics.light() } else { Haptics.success() }
            withAnimation(reduceMotion ? Motion.smooth : Motion.select) { saved.toggle(spot.id) }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSaved ? Hue.accent : Hue.ink)
                .symbolEffect(.bounce, value: isSaved)
                .frame(width: 36, height: 36)
                .background(Hue.paper, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove \(spot.name) from saved places" : "Save \(spot.name)")
    }

    private func detailContent(_ spot: Spot) -> some View {
        let items = happenings(spot)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        selected = nil
                        detent = .peek
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Hue.ink)
                            .frame(width: 32, height: 32)
                            .background(Hue.paper, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to list")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(spot.name).font(.display(20)).foregroundStyle(Hue.ink).lineLimit(1)  // §9: card title 20pt bold
                        if let blurb = spot.blurb {
                            Text(blurb).font(.sans(15)).foregroundStyle(Hue.inkSecondary).lineLimit(1)       // §9: subtitle 15pt
                        }
                    }
                    Spacer(minLength: 0)
                    saveButton(spot)
                }
                .staggeredAppear(0)

                VenueInfoView(query: "\(spot.name) St Joseph MN",
                              palette: .map,
                              identity: VenueIdentity(name: spot.name, coordinate: spot.coordinate))
                    .padding(.top, 16)
                    .staggeredAppear(1)

                if !items.isEmpty {
                    VStack(spacing: 13) {
                        ForEach(items) { h in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(DateHelpers.isLiveNow(h.startTime) ? Hue.accent : Hue.inkSecondary)
                                    .frame(width: 6, height: 6)
                                Text(h.title).font(.sansMedium(15)).foregroundStyle(Hue.ink).lineLimit(1)
                                Spacer()
                                Text(h.startTime ?? "all day").font(.sans(13)).foregroundStyle(Hue.inkSecondary)
                            }
                        }
                    }
                    .padding(.top, 18)
                    .staggeredAppear(2)
                }

                Button {
                    let lat = spot.coordinate.latitude, lon = spot.coordinate.longitude
                    if let url = URL(string: "maps://?daddr=\(lat),\(lon)&dirflg=d") { openURL(url) }
                } label: {
                    Text("Directions")
                        .font(.sansSemibold(16)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(AccentPillStyle())
                .padding(.top, 20)
                .staggeredAppear(3)
                .accessibilityLabel("Directions to \(spot.name)")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Self.contentBottomInset)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(innerScrollDisabled)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            Self.scrollIsAtTop(geometry)
        } action: { _, isAtTop in
            spotDetailScrollAtTop = isAtTop
        }
    }

    // MARK: Detail — one POI (food / business), rendered IN the bar (no more modal)

    /// The tapped-POI detail, hosted inside the bar exactly like a spot's — replacing the
    /// old swipe-up Apple modal (POIDetailSheet). Back-chevron returns to the list; the
    /// accent primary CTA opens the venue in Maps. `VenueInfoView` adds live Google
    /// hours/website/phone/photo when they resolve, and nothing when they don't.
    private func poiDetailContent(_ poi: POI) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        selectedPOI = nil
                        detent = .peek
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Hue.ink)
                            .frame(width: 32, height: 32)
                            .background(Hue.paper, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to list")

                    ZStack {
                        Circle().fill(poi.family.tint).frame(width: 40, height: 40)
                        Image(systemName: poi.glyph)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(poi.name).font(.display(20)).foregroundStyle(Hue.ink).lineLimit(1)   // §9: card title
                        Text(poi.family.label.uppercased())
                            .font(.mono(11)).tracking(1.2).foregroundStyle(Hue.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .staggeredAppear(0)

                if let address = poi.address, !address.isEmpty {
                    Text(address)
                        .font(.sans(15)).foregroundStyle(Hue.inkSecondary)   // §9: 15pt subtitle
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .staggeredAppear(1)
                }

                VenueInfoView(query: poi.name,
                              palette: .map,
                              identity: VenueIdentity(name: poi.name, coordinate: poi.coordinate))
                    .padding(.top, 16)
                    .staggeredAppear(2)

                Button {
                    let q = poi.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "http://maps.apple.com/?q=\(q)&ll=\(poi.lat),\(poi.lon)") { openURL(url) }
                } label: {
                    Text("Open in Maps")
                        .font(.sansSemibold(16)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(AccentPillStyle())
                .padding(.top, 20)
                .staggeredAppear(3)
                .accessibilityLabel("Open \(poi.name) in Maps")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Self.contentBottomInset)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(innerScrollDisabled)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            Self.scrollIsAtTop(geometry)
        } action: { _, isAtTop in
            poiDetailScrollAtTop = isAtTop
        }
    }
}

// MARK: - Status dot (peek line)

/// A small dot that reads as "live" (accent, with a slow breathing ring) or "quiet"
/// (soft gray). The ring is gated by Reduce Motion — calm by default, alive on live.
/// Accent = "live" here, matching the live pins on the map canvas.
private struct StatusDot: View {
    let live: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if live && !reduceMotion {
                Circle()
                    .stroke(Hue.accent, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulsing ? 2.2 : 1)
                    .opacity(pulsing ? 0 : 0.5)
            }
            Circle()
                .fill(live ? Hue.accent : Hue.inkSecondary)
                .frame(width: 9, height: 9)
        }
        .frame(width: 26, height: 26)          // stable slot so text never shifts
        .onChange(of: live, initial: true) { _, isLive in
            if isLive && !reduceMotion {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            } else {
                pulsing = false
            }
        }
    }
}

/// Press feedback for the whole peek line — the subtle scale that tells the user
/// the sheet heard the tap before it springs up.
private struct PeekLineStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Rows

/// Today's happening: live dot / clock, title, venue, time.
private struct TodayEventRow: View {
    let event: TimelineEvent
    let live: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(live ? Hue.fill : Hue.paper).frame(width: 38, height: 38)
                Image(systemName: live ? "dot.radiowaves.left.and.right" : "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(live ? Hue.accent : Hue.inkSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.sansMedium(15)).foregroundStyle(Hue.ink).lineLimit(1)
                if let loc = event.location ?? event.clubName {
                    Text(loc).font(.sans(13)).foregroundStyle(Hue.inkSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if live {
                Text("Now")
                    .font(.sansSemibold(12)).foregroundStyle(Hue.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Hue.fill, in: Capsule())
            } else if let t = event.startTime {
                Text(t).font(.mono(13)).foregroundStyle(Hue.inkSecondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// A curated place: a confidently-identified photo thumbnail (else the category
/// icon), name, blurb, live-today count, chevron.
private struct PlaceRow: View {
    let spot: Spot
    let liveCount: Int

    @State private var photoURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name).font(.sansMedium(15)).foregroundStyle(Hue.ink).lineLimit(1)
                if let blurb = spot.blurb {
                    Text(blurb).font(.sans(13)).foregroundStyle(Hue.inkSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if liveCount > 0 {
                Text("^[\(liveCount) live](inflect: true)")
                    .font(.sansSemibold(12)).foregroundStyle(Hue.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Hue.fill, in: Capsule())
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Hue.inkSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .task(id: spot.id) {
            photoURL = nil
            if let cp = await GooglePlacesService.shared.confidentPhoto(name: spot.name, coordinate: spot.coordinate) {
                photoURL = GooglePlacesService.shared.photoURL(name: cp.photoName, maxWidth: 160)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photoURL {
            AsyncImage(url: photoURL) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    iconCircle
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            iconCircle
        }
    }

    private var iconCircle: some View {
        ZStack {
            Circle().fill(liveCount > 0 ? Hue.fill : Hue.paper).frame(width: 38, height: 38)
            Image(systemName: spot.category.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(liveCount > 0 ? Hue.ink : Hue.inkSecondary)
        }
    }
}

/// Calm placeholder row while today's happenings load.
private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Hue.paper).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Hue.paper).frame(width: 150, height: 11)
                Capsule().fill(Hue.paper).frame(width: 90, height: 9)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Accent primary button (Directions / Open in Maps)

/// The detail's primary CTA. Takes the brand accent — "primary CTAs" is one of the
/// accent's meaning-scoped seams — rather than the old ink fill.
private struct AccentPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Hue.accent.opacity(0.85) : Hue.accent,
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Sheet expansion preference

/// How far `MapSheet` has grown past its peek detent (0 = collapsed, 1 = at/above
/// medium). Read by `SJMapView` to fade the floating ?/locate controls before the
/// sheet reaches them, and to keep them out of the way as it expands.
struct SheetExpansionKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
