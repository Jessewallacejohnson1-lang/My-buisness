//
//  MapSheet.swift
//  Hygge — the always-visible bottom sheet on the map (Life360-style).
//
//  A draggable white sheet that sits above the tab bar and floats over the map.
//  Three content states, all backed by REAL data (no invented counts):
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

/// How far the sheet is pulled up. Two detents; the grabber drags between them.
private enum SheetDetent { case peek, expanded }

/// The two list faces of the sheet (a spot detail temporarily overrides both).
private enum SheetMode { case today, places }

struct MapSheet: View {
    // Data (owned by MapModel / SJMapView; the sheet only reads)
    let events: [TimelineEvent]
    let state: MapModel.LoadState
    let spots: [Spot]                          // already filtered by the map's chip
    @Binding var selected: Spot?               // non-nil → show that spot's detail

    // Callbacks up to SJMapView
    let happenings: (Spot) -> [TimelineEvent]  // events resolving to a spot
    let spotFor: (TimelineEvent) -> Spot?      // an event's pin, if any
    let onSelectSpot: (Spot) -> Void           // fly camera + select
    let onRetry: () -> Void

    /// Cleared from behind the tab bar so the last row / Directions never hide.
    static let tabBarClearance: CGFloat = 56
    /// Collapsed height — grabber + header + ~2 rows. The map's floating controls
    /// sit just above this.
    static let peekHeight: CGFloat = 244

    @State private var mode: SheetMode = MapSheet.initialMode()
    @State private var detent: SheetDetent = .peek

    /// DEBUG-only: `-map-sheet places` opens the sheet on the Places list so it can
    /// be screenshotted headlessly. No effect in release / without the flag.
    private static func initialMode() -> SheetMode {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-sheet"), i + 1 < a.count, a[i + 1] == "places" { return .places }
        #endif
        return .today
    }
    @GestureState private var drag: CGFloat = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            let peek = Self.peekHeight
            let expanded = max(peek, H * 0.62)
            let resting = detent == .peek ? peek : expanded
            // Drag up → negative translation → taller sheet.
            let height = min(max(resting - drag, peek), expanded)

            VStack(spacing: 0) {
                grabber
                if let spot = selected {
                    detailContent(spot)
                } else {
                    listHeader
                    listBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: height, alignment: .top)
            .background(sheetBackground)
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: Radius.xl,
                                       topTrailingRadius: Radius.xl,
                                       style: .continuous)
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, Self.tabBarClearance)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: detent)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selected?.id)
        // A tapped pin expands the sheet to show its detail.
        .onChange(of: selected?.id) { _, id in if id != nil { detent = .expanded } }
    }

    // MARK: Grabber (the drag target)

    private var grabber: some View {
        Capsule()
            .fill(Hue.mapHairline)
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        let projected = value.translation.height + value.predictedEndTranslation.height * 0.25
                        let next: SheetDetent = projected < -60 ? .expanded
                                              : projected > 60 ? .peek
                                              : detent
                        if next != detent { Haptics.light() }
                        detent = next
                    }
            )
            .accessibilityLabel(detent == .peek ? "Expand sheet" : "Collapse sheet")
    }

    private var sheetBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: Radius.xl,
                               topTrailingRadius: Radius.xl,
                               style: .continuous)
            .fill(Hue.surface)
            .mapSheetShadow()
    }

    // MARK: List header — title + coral toggle pill (Today ⇄ Places)

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .today ? "Today" : "Places")
                    .font(.displaySemi(22))
                    .foregroundStyle(Hue.mapInk)
                subtitle
            }
            Spacer()
            toggleButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch mode {
        case .places:
            Text("\(spots.count) places in town")
                .font(.sans(13)).foregroundStyle(Hue.grayLight)
        case .today:
            switch state {
            case .loading:
                Text("Loading…").font(.sans(13)).foregroundStyle(Hue.grayLight)
            case .loaded, .empty:
                if events.isEmpty {
                    Text("A quiet day so far").font(.sans(13)).foregroundStyle(Hue.grayLight)
                } else {
                    Text("^[\(events.count) happening](inflect: true) today")
                        .font(.mono(13)).foregroundStyle(Hue.gray).monospacedDigit()
                }
            case .offline:
                retryLabel("Offline — tap to retry", icon: "wifi.slash")
            case .error:
                retryLabel("Couldn't load — tap to retry", icon: "arrow.clockwise")
            }
        }
    }

    private func retryLabel(_ text: String, icon: String) -> some View {
        Button(action: onRetry) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(text)
            }
            .font(.sans(13)).foregroundStyle(Hue.accent)
        }
        .buttonStyle(.plain)
    }

    private var toggleButton: some View {
        Button {
            Haptics.light()
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = (mode == .today) ? .places : .today
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode == .today ? "building.2.fill" : "calendar")
                    .font(.system(size: 12, weight: .semibold))
                Text(mode == .today ? "Places" : "Today")
                    .font(.sansSemibold(14))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Hue.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .today ? "Show places" : "Show today")
    }

    // MARK: List body

    @ViewBuilder
    private var listBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch mode {
                case .today:  todayRows
                case .places: placeRows
                }
            }
            .padding(.bottom, Self.tabBarClearance + 12)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var todayRows: some View {
        switch state {
        case .loading:
            ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
        case .loaded, .empty:
            if events.isEmpty {
                emptyState(icon: "moon.stars", text: "Nothing on the map yet today.")
            } else {
                ForEach(events) { ev in
                    TodayEventRow(event: ev, live: DateHelpers.isLiveNow(ev.startTime))
                        .contentShape(Rectangle())
                        .onTapGesture { if let s = spotFor(ev) { onSelectSpot(s) } }
                    rowDivider
                }
            }
        case .offline, .error:
            emptyState(icon: "wifi.slash", text: "Couldn't load today's happenings.")
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
        Rectangle().fill(Hue.mapHairline).frame(height: 1).padding(.leading, 20)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(Hue.grayLight)
            Text(text).font(.sans(14)).foregroundStyle(Hue.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    // MARK: Detail — one spot (replaces the old MapBottomCard)

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
                            .foregroundStyle(Hue.mapInk)
                            .frame(width: 32, height: 32)
                            .background(Hue.bgSubtle, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to list")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(spot.name).font(.displaySemi(20)).foregroundStyle(Hue.mapInk).lineLimit(1)
                        if let blurb = spot.blurb {
                            Text(blurb).font(.sans(13)).foregroundStyle(Hue.grayLight).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                VenueInfoView(query: "\(spot.name) St Joseph MN",
                              palette: .map,
                              identity: (name: spot.name, coordinate: spot.coordinate))
                    .padding(.top, 16)

                if !items.isEmpty {
                    VStack(spacing: 13) {
                        ForEach(items) { h in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(DateHelpers.isLiveNow(h.startTime) ? Hue.accent : Hue.grayLight)
                                    .frame(width: 6, height: 6)
                                Text(h.title).font(.sansMedium(15)).foregroundStyle(Hue.mapInk).lineLimit(1)
                                Spacer()
                                Text(h.startTime ?? "all day").font(.sans(13)).foregroundStyle(Hue.gray)
                            }
                        }
                    }
                    .padding(.top, 18)
                }

                Button {
                    let lat = spot.coordinate.latitude, lon = spot.coordinate.longitude
                    if let url = URL(string: "maps://?daddr=\(lat),\(lon)&dirflg=d") { openURL(url) }
                } label: {
                    Text("Directions")
                        .font(.sansSemibold(16)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(CoralPillStyle())
                .padding(.top, 20)
                .accessibilityLabel("Directions to \(spot.name)")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Self.tabBarClearance + 12)
        }
        .scrollIndicators(.hidden)
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
                Circle().fill(live ? Hue.accentSoft : Hue.bgSubtle).frame(width: 38, height: 38)
                Image(systemName: live ? "dot.radiowaves.left.and.right" : "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(live ? Hue.accent : Hue.gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.sansMedium(15)).foregroundStyle(Hue.mapInk).lineLimit(1)
                if let loc = event.location ?? event.clubName {
                    Text(loc).font(.sans(13)).foregroundStyle(Hue.grayLight).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if live {
                Text("Now")
                    .font(.sansSemibold(12)).foregroundStyle(Hue.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Hue.accentSoft, in: Capsule())
            } else if let t = event.startTime {
                Text(t).font(.mono(13)).foregroundStyle(Hue.gray).monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// A curated place: category icon, name, blurb, live-today count, chevron.
private struct PlaceRow: View {
    let spot: Spot
    let liveCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(liveCount > 0 ? Hue.accentSoft : Hue.bgSubtle).frame(width: 38, height: 38)
                Image(systemName: spot.category.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(liveCount > 0 ? Hue.accent : Hue.gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name).font(.sansMedium(15)).foregroundStyle(Hue.mapInk).lineLimit(1)
                if let blurb = spot.blurb {
                    Text(blurb).font(.sans(13)).foregroundStyle(Hue.grayLight).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if liveCount > 0 {
                Text("^[\(liveCount) live](inflect: true)")
                    .font(.sansSemibold(12)).foregroundStyle(Hue.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Hue.accentSoft, in: Capsule())
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Hue.grayLight)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// Calm placeholder row while today's happenings load.
private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Hue.bgSubtle).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Hue.bgSubtle).frame(width: 150, height: 11)
                Capsule().fill(Hue.bgSubtle).frame(width: 90, height: 9)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Coral primary pill (Directions)

private struct CoralPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Hue.accentPressed : Hue.accent, in: Capsule())
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
