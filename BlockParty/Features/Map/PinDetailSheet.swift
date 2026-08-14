//
//  PinDetailSheet.swift
//  Block Party — the pin-detail sheet (map polish Phase 3, Flighty anatomy).
//
//  Tapping a pin opens THIS card over the map — it supersedes the old tab-bar
//  glass morph (removed in the same commit). The anatomy mirrors Flighty's
//  airport sheet with our content:
//    (a) small uppercase metadata pills — CATEGORY · OPEN NOW (async, Rule A
//        gated, only when true — never a placeholder) · DISTANCE (user fix only)
//    (b) large Jost display place name
//    (c) grey-caps secondary line — category glyph + street (real address data)
//        or the town
//    (d) 44pt circular close, top-right
//    (e) the status card — wash routed through Hue.statusTint; header dot + word
//        + sparkle, then hairline-divided rows built from REAL data only
//    (f) a low-emphasis "View full details" row → the full-height rich content
//        (blurb/address + VenueInfoView + happenings)
//    (g) the floating action bar — save · share · overflow · a filled circular
//        Directions primary. Shape behind ONE constant (Q4: pill ships).
//
//  Presentation: ~60% of the map container, over a subtle map dim, dragged down
//  to dismiss. The compact card never scrolls, so the dismiss drag competes with
//  nothing; the full-details presentation is a system sheet whose scroll/dismiss
//  arbitration is the system's.
//

import SwiftUI
import UIKit
import CoreLocation

// MARK: - Copy (pure, tested in PinDetailCopyTests)

/// Every sentence the status card can utter — complete plain sentences, brand
/// voice, no exclamation points, built from real signals only. `nonisolated`
/// (the module defaults to MainActor): pure string logic, unit-testable.
nonisolated enum PinDetailCopy {

    /// Spelled-out small counts read warmer in a sentence ("Three events here
    /// today."); past nine the numeral is clearer.
    static func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four",
                     "five", "six", "seven", "eight", "nine"]
        return (0...9).contains(n) ? words[n] : "\(n)"
    }

    /// The status word beside the header dot. Live wins; otherwise today's real
    /// event count decides between anticipation and quiet.
    static func statusWord(isLive: Bool, todayCount: Int) -> String {
        if isLive { return "Happening now" }
        return todayCount > 0 ? "Later today" : "Quiet today"
    }

    /// The happenings row's sentence — nil at zero (the row is omitted, never
    /// padded). Counts come from what MapModel actually holds (today's events);
    /// no week totals exist here, so none are claimed.
    static func happeningsSentence(todayCount: Int) -> String? {
        guard todayCount > 0 else { return nil }
        if todayCount == 1 { return "One event here today." }
        return "\(spelled(todayCount).capitalized) events here today."
    }

    static func statusRowLabel(isLive: Bool) -> String {
        isLive ? "Live now" : "Right now"
    }

    /// The status row's sentence. A live happening is named when one exists;
    /// forced-live states (DEBUG) with no resolvable event stay generic rather
    /// than inventing a title.
    static func statusSentence(isLive: Bool, liveTitle: String?) -> String {
        guard isLive else { return "Nothing happening yet today." }
        if let liveTitle, !liveTitle.isEmpty { return "\(liveTitle) is happening right now." }
        return "Something is happening here right now."
    }

    /// The grey-caps line under the name: the street from real address data when
    /// present, the town otherwise. Never invents a neighborhood.
    static func secondaryLine(address: String?) -> String {
        if let street = address?.split(separator: ",").first?
            .trimmingCharacters(in: .whitespaces), !street.isEmpty {
            return street
        }
        return "Saint Joseph"
    }
}

// MARK: - Sheet

struct PinDetailSheet: View {
    let detail: MapPlaceDetail
    /// Real happenings at this place today (civic spots only; always empty for
    /// POIs — events don't resolve to them).
    let happenings: [TimelineEvent]
    /// Whether one of those happenings is live right now (or DEBUG-forced).
    let isLive: Bool
    /// "0.3 mi" from the user's one-shot fix — nil without a fix, and then the
    /// pill simply doesn't render.
    let distanceLabel: String?
    /// Card height, computed by SJMapView as `heightFraction` of the map.
    let height: CGFloat
    var onClose: () -> Void

    @ObservedObject private var saved = SavedStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Google's open-now, resolved async under Rule A. Stays nil (no pill, no
    /// placeholder) unless the gate clears AND the place is open; the pill fades
    /// in without moving the rest of the header.
    @State private var openNow: Bool?
    @State private var dragOffset: CGFloat = 0
    #if DEBUG
    @State private var showingFullDetails = PinDetailSheet.debugExpandedRequested()
    #else
    @State private var showingFullDetails = false
    #endif

    /// Fraction of the map container the compact card occupies (Flighty ~60%).
    /// SJMapView also lifts the camera by this fraction so the pin stays visible
    /// above the card.
    static let heightFraction: CGFloat = 0.60

    /// Q4 — the action bar's silhouette, behind ONE constant. PILL ships: a
    /// deliberate, recorded exception to "buttons are 12pt rounded squares,
    /// never pills" (Flighty-faithful — see DECISIONS.md). Flip to
    /// `.roundedSquare` for the brand-native variant.
    static let actionBarShape: ActionBarShape = .pill

    enum ActionBarShape {
        case pill, roundedSquare

        var shape: AnyShape {
            switch self {
            case .pill:          return AnyShape(Capsule())
            case .roundedSquare: return AnyShape(RoundedRectangle(cornerRadius: Radius.tile,
                                                                  style: .continuous))
            }
        }
    }

    /// Drag-down farther than this (or flick past double it) dismisses.
    private static let dismissDistance: CGFloat = 130

    #if DEBUG
    /// `-map-detail-expanded` (with an open flag) starts straight in the
    /// full-details presentation — the headless screenshot seam. Compiles out.
    private nonisolated static func debugExpandedRequested() -> Bool {
        let a = ProcessInfo.processInfo.arguments
        return a.contains("-map-detail-expanded")
            && (a.contains("-map-open") || a.contains("-map-open-poi"))
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusCard
            Spacer(minLength: 8)
            actionBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        // The card ignores the bottom safe area (SJMapView's mount), so this
        // inset is what floats the action bar clear of the home indicator.
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        // Applied DIRECTLY to the content (the tab bar's pattern), never as a
        // `.background` layer: glass surfaces are extracted for container
        // compositing, and a background-layer glass composites OVER the card's
        // own text, frosting it out.
        .glassEffect(.regular, in: UnevenRoundedRectangle(
            topLeadingRadius: Radius.card,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Radius.card,
            style: .continuous))
        .offset(y: dragOffset)
        .gesture(dismissDrag)
        .task { await resolveOpenNow() }
        .sheet(isPresented: $showingFullDetails) {
            PinFullDetailsView(detail: detail, happenings: happenings)
        }
        .accessibilityElement(children: .contain)
        // VoiceOver treats the card as a modal: swipe order stays inside it
        // instead of walking the dimmed map behind, and the two-finger-Z
        // escape dismisses exactly like the close button.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            Haptics.light()
            onClose()
        }
    }

    // MARK: (a–d) Header — pills · name · secondary line · close

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                pillRow
                Text(detail.name)
                    .font(.display(26))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                secondaryLine
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headerAccessibilityLabel)

            Spacer(minLength: 8)

            // The 44pt circular close. Solid `fill`, not the chrome circles'
            // glass: a glass circle INSIDE the card's glass would union with it
            // in the shared GlassEffectContainer and vanish.
            Button {
                Haptics.light()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Hue.fill))
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close place details")
        }
    }

    private var pillRow: some View {
        HStack(spacing: 6) {
            pill(detail.categoryLabel.uppercased())
            // Only a POSITIVE, Rule A-cleared answer earns the pill — no
            // placeholder while resolving, nothing on closed/unknown. It fades
            // in beside its siblings without reflowing the name below.
            if openNow == true {
                pill("OPEN NOW")
                    .transition(.opacity)
            }
            if let distanceLabel {
                pill(distanceLabel.uppercased())
            }
        }
        .animation(Motion.smooth, value: openNow == true)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.mono(11).monospacedDigit())
            .tracking(0.8)
            .foregroundStyle(Hue.inkSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Hue.hairline, lineWidth: 1)
            )
    }

    private var secondaryLine: some View {
        HStack(spacing: 6) {
            Image(systemName: detail.glyph)
                .font(.system(size: 11, weight: .semibold))
            Text(PinDetailCopy.secondaryLine(address: detail.poi?.address).uppercased())
                .font(.mono(11))
                .tracking(1.2)
                .lineLimit(1)
        }
        .foregroundStyle(Hue.inkSecondary)
    }

    private var headerAccessibilityLabel: String {
        var parts = ["\(detail.name).", "\(detail.categoryLabel)."]
        if openNow == true { parts.append("Open now.") }
        if let distanceLabel { parts.append("\(distanceLabel) away.") }
        return parts.joined(separator: " ")
    }

    // MARK: (e–f) Status card

    private struct StatusRow: Identifiable {
        let icon: String
        let label: String
        let sentence: String
        var id: String { label }
    }

    private var statusRows: [StatusRow] {
        var rows: [StatusRow] = []
        // Real data only: no happenings → no row, never a filler count.
        if let sentence = PinDetailCopy.happeningsSentence(todayCount: happenings.count) {
            rows.append(StatusRow(icon: "calendar", label: "Happenings", sentence: sentence))
        }
        let liveTitle = happenings.first { DateHelpers.isLiveNow($0.startTime) }?.title
        rows.append(StatusRow(icon: "clock",
                              label: PinDetailCopy.statusRowLabel(isLive: isLive),
                              sentence: PinDetailCopy.statusSentence(isLive: isLive,
                                                                     liveTitle: liveTitle)))
        return rows
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: dot + status word + sparkle. The dot goes plum only for
            // LIVE (the accent's meaning scope); the wash stays statusTint.
            HStack(spacing: 8) {
                Circle()
                    .fill(isLive ? Hue.accent : Hue.ink)
                    .frame(width: 8, height: 8)
                Text(PinDetailCopy.statusWord(isLive: isLive, todayCount: happenings.count))
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                Spacer(minLength: 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Hue.inkSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            ForEach(statusRows) { row in
                cardDivider
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Hue.ink)
                        .frame(width: 18)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.sansSemibold(14))
                            .foregroundStyle(Hue.ink)
                        Text(row.sentence)
                            .font(.sans(14).monospacedDigit())
                            .foregroundStyle(Hue.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)
            }

            cardDivider
            Button {
                Haptics.light()
                showingFullDetails = true
            } label: {
                HStack(spacing: 4) {
                    Text("View full details")
                        .font(.sansMedium(13))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Hue.inkSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View full details for \(detail.name)")
        }
        .background(
            Hue.statusTint,
            in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        )
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Hue.hairline)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: (g) Action bar

    private var actionBar: some View {
        let isSaved = saved.isSaved(detail.saveID)
        return HStack(spacing: 6) {
            Button {
                if isSaved { Haptics.light() } else { Haptics.success() }
                saved.toggle(detail.saveID)
            } label: {
                barIcon(isSaved ? "bookmark.fill" : "bookmark",
                        tint: isSaved ? Hue.accent : Hue.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSaved
                ? "Remove \(detail.name) from saved places"
                : "Save \(detail.name)")
            .accessibilityAddTraits(isSaved ? .isSelected : [])

            Button {
                ShareCenter.shared.present(.place(
                    name: detail.name,
                    categoryLabel: detail.categoryLabel,
                    detail: detail.poi?.address ?? detail.spot?.blurb))
            } label: {
                barIcon("square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share \(detail.name)")

            Menu {
                Button {
                    showingFullDetails = true
                } label: {
                    Label("View full details", systemImage: "list.bullet.rectangle")
                }
                if let address = detail.poi?.address, !address.isEmpty {
                    Button {
                        UIPasteboard.general.string = address
                    } label: {
                        Label("Copy address", systemImage: "doc.on.doc")
                    }
                }
            } label: {
                barIcon("ellipsis")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions")

            Spacer(minLength: 8)

            // The one prominent primary: a filled circle, ink on the light bar.
            Button {
                Haptics.light()
                if let url = detail.directionsURL { openURL(url) }
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Hue.surface)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Hue.ink))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Directions to \(detail.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Self.actionBarShape.shape.fill(Hue.surface))
        .overlay(Self.actionBarShape.shape.stroke(Hue.hairline, lineWidth: 1))
        .mapFloatShadow()
    }

    private func barIcon(_ symbol: String, tint: Color = Hue.ink) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    // MARK: Dismiss drag

    /// Down follows the finger; up meets square-root resistance. The compact
    /// card has no inner scroll, so this competes with nothing (the repo rule);
    /// buttons inside win the touch as usual (child gestures take precedence).
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dy = value.translation.height
                dragOffset = dy >= 0 ? dy : -sqrt(-dy)
            }
            .onEnded { value in
                if value.translation.height > Self.dismissDistance
                    || value.predictedEndTranslation.height > Self.dismissDistance * 2 {
                    onClose()
                    // The card unmounts via its transition; reset for reuse.
                    dragOffset = 0
                } else {
                    withAnimation(reduceMotion ? Motion.smooth : Motion.card) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: Open-now (async, Rule A gated)

    private func resolveOpenNow() async {
        let resolved = await GooglePlacesService.shared.confidentDetails(
            name: detail.name,
            coordinate: detail.coordinate)
        guard !Task.isCancelled else { return }
        openNow = resolved?.openNow
    }
}

// MARK: - Full details (the "View full details" presentation)

/// The existing rich map content — blurb/address, VenueInfoView (hours · website
/// · call · confident photo) and today's happenings — full-height. A system
/// sheet, so scroll vs. drag-to-dismiss arbitration is the system's.
struct PinFullDetailsView: View {
    let detail: MapPlaceDetail
    let happenings: [TimelineEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.name)
                            .font(.display(26))
                            .foregroundStyle(Hue.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Image(systemName: detail.glyph)
                                .font(.system(size: 11, weight: .semibold))
                            Text(detail.categoryLabel.uppercased())
                                .font(.mono(11))
                                .tracking(1.2)
                        }
                        .foregroundStyle(Hue.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Hue.ink)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Hue.fill))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close full details")
                }

                if let spot = detail.spot {
                    if let blurb = spot.blurb, !blurb.isEmpty {
                        Text(blurb)
                            .font(.sans(15))
                            .foregroundStyle(Hue.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VenueInfoView(
                        query: "\(spot.name) St Joseph MN",
                        palette: .warm,
                        identity: VenueIdentity(name: spot.name, coordinate: spot.coordinate)
                    )
                    if !happenings.isEmpty {
                        happeningsList
                    }
                } else if let poi = detail.poi {
                    if let address = poi.address, !address.isEmpty {
                        Text(address)
                            .font(.sans(15))
                            .foregroundStyle(Hue.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VenueInfoView(
                        query: poi.name,
                        palette: .warm,
                        identity: VenueIdentity(name: poi.name, coordinate: poi.coordinate)
                    )
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Hue.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full details for \(detail.name)")
    }

    private var happeningsList: some View {
        VStack(spacing: 13) {
            ForEach(happenings) { happening in
                let isLive = DateHelpers.isLiveNow(happening.startTime)
                let time = happening.startTime ?? "all day"
                HStack(spacing: 8) {
                    Circle()
                        .fill(isLive ? Hue.accent : Hue.inkSecondary)
                        .frame(width: 6, height: 6)
                    Text(happening.title)
                        .font(.sansMedium(15))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(time)
                        .font(.sans(13).monospacedDigit())
                        .foregroundStyle(Hue.inkSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    isLive
                        ? "\(happening.title), live now, \(time)"
                        : "\(happening.title), \(time)"
                )
            }
        }
    }
}
