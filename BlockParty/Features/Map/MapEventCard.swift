//
//  MapEventCard.swift
//  Block Party — the card a bubble's tap raises on the map: Airbnb's map card, copied.
//
//  Jesse at the map-reset Check-in 1 (BP app references/map-reset, 2026-10-30): "only copy
//  their card", all four of its lines, nothing on top of the photo. Measured off Mobbin
//  (`references/map-reset/mobbin/airbnb-map-wit-0-airbnb.jpg`): 20 pt in from each side,
//  55 pt up from the bottom edge, a 352.7 × 198.6 photo (its shape kept at any width), the
//  card's 20 pt corners, two 32 pt white circles 12 pt in from the photo's top right and
//  12 pt apart, page dots 13 pt up, then four 16 pt lines 12 pt in: the title with "Now"
//  where Airbnb puts its rating, the place, the time, and the going count bold where Airbnb
//  puts its price. Airbnb's heart is our heart, a like (taste.md: the heart means like).
//  A spot with several events today pages through them on the photo, as Airbnb pages a
//  listing's photos. Tap opens the Event page; drag it down, or tap the map, to close.
//

import SwiftUI

struct MapEventCard: View {
    /// The bubble's events, in its order; never empty.
    let events: [FeedCardItem]
    @Binding var page: Int
    let onOpen: (FeedCardItem) -> Void
    let onClose: () -> Void

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pressed = false
    @State private var drag: CGFloat = 0
    @State private var scrolled: Int?
    @State private var heartTappedAt = 0
    /// VoiceOver lands on the card's words when it opens.
    @AccessibilityFocusState private var heard: Bool

    static let sideInset: CGFloat = 20
    static let bottomInset: CGFloat = 55
    private static let photoAspect: CGFloat = 352.7 / 198.6
    private static let circle: CGFloat = 32
    private static let circleInset: CGFloat = 12

    private var item: FeedCardItem { events[min(max(page, 0), events.count - 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(Self.photoAspect, contentMode: .fit)
                .overlay { photos }
                .overlay(alignment: .topTrailing) { buttons }
                .overlay(alignment: .bottom) { dots }
                .clipped()
            lines
        }
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // Squishes the moment a finger lands, and follows a drag down to close.
        .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
        .offset(y: drag)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: pressed)
        .onTapGesture { onOpen(item) }
        .simultaneousGesture(touch)
        .onChange(of: scrolled) { _, new in if let new, new != page { page = new; Haptics.selection() } }
        .onChange(of: page) { _, new in if scrolled != new { scrolled = new } }
        .onAppear {
            scrolled = page
            heard = true
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Photo

    private var photos: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { i, event in
                    photo(event)
                        .containerRelativeFrame(.horizontal)
                        .clipped()
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolled)
        .scrollDisabled(events.count < 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func photo(_ event: FeedCardItem) -> some View {
        let source = event.photos().first
        if let url = source?.url {
            FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
        } else if let logo = source?.logo {
            FeedCardPlaceLogo(logo: logo)
        } else {
            ZStack {
                Hue.fill
                Image(systemName: (event.category ?? .other).glyph)
                    .font(.glyph(30, weight: .medium))
                    .foregroundStyle(Hue.inkSecondary)
            }
        }
    }

    private var buttons: some View {
        let hearted = actions.heart(item).isHearted
        let failures = actions.heartFailureCount(item.id)
        return HStack(spacing: 44 - Self.circle) {
            Button {
                heartTappedAt = failures
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.5)) {
                    actions.toggleHeart(item)
                }
            } label: {
                circle {
                    FeedActionGlyphView(glyph: .heart, size: 18, filled: hearted)
                        .foregroundStyle(hearted ? Hue.heart : Hue.ink.onLightCanvas)
                        // The Town card's pop, out to 1.3 and back.
                        .phaseAnimator([1, 1.3], trigger: hearted) { glyph, scale in
                            glyph.scaleEffect(reduceMotion ? 1 : scale)
                        } animation: { _ in .spring(response: 0.3, dampingFraction: 0.5) }
                }
            }
            .buttonStyle(MenuPressStyle())
            .turnBackShake(failures: failures, shakes: !reduceMotion && heartTappedAt != failures)
            .accessibilityLabel("Like")
            .accessibilityValue(hearted ? "Liked" : "Not liked")
            .accessibilityAddTraits(hearted ? .isSelected : [])

            Button(action: onClose) {
                circle {
                    Image(systemName: "xmark")
                        .font(.glyph(13, weight: .bold))
                        .foregroundStyle(Hue.ink.onLightCanvas)
                }
            }
            .buttonStyle(MenuPressStyle())
            .accessibilityLabel("Close")
        }
        // The 32 pt circles sit 12 pt in; their 44 pt targets reach past them.
        .padding(Self.circleInset - (44 - Self.circle) / 2)
    }

    /// A white 32 pt circle, touchable across 44 pt.
    private func circle<Glyph: View>(@ViewBuilder _ glyph: () -> Glyph) -> some View {
        glyph()
            .frame(width: Self.circle, height: Self.circle)
            .background(Color.white, in: Circle())
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    @ViewBuilder
    private var dots: some View {
        if events.count > 1 {
            HStack(spacing: 6) {
                ForEach(events.indices, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(i == page ? 1 : 0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(i == page ? 1.15 : 1)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 2)
            .padding(.bottom, 10)
            .animation(.easeOut(duration: 0.2), value: page)
            .accessibilityHidden(true)
        }
    }

    // MARK: Words

    private var lines: some View {
        let going = actions.going(item).count
        let live = item.isNow(at: TodayBubbleClock.now())
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.sansSemibold(16))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if live {
                    HStack(spacing: 5) {
                        Circle().fill(Hue.now).frame(width: 7, height: 7)
                        Text("Now").font(.sans(16)).foregroundStyle(Hue.ink)
                    }
                    .fixedSize()
                }
            }
            if let place = item.whereLine ?? (item.hostName.isEmpty ? nil : item.hostName) {
                Text(place).lineLimit(1)
            }
            Text(Self.timeLine(item, now: TodayBubbleClock.now()))
            if going > 0 {
                Text("\(Text("\(going)").font(.sansBold(16)).foregroundStyle(Hue.ink)) going")
            }
        }
        .font(.sans(16))
        .foregroundStyle(Hue.inkSecondary)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        // The event before its heart and close.
        .accessibilitySortPriority(1)
        .accessibilityFocused($heard)
        .accessibilityHint(events.count > 1 ? "Swipe up or down for the other events here" : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(page + 1, events.count - 1)
            case .decrement: page = max(page - 1, 0)
            @unknown default: break
            }
        }
    }

    /// "Tonight, 7 – 10 PM", "Today, 10 AM – 9 PM", "Tonight, 7 PM" with no end given,
    /// "Today, all day".
    static func timeLine(_ item: FeedCardItem, now: Date) -> String {
        guard let when = item.when else { return item.shareTime ?? "Today" }
        let day = when.dayWord(now) ?? "Today"
        guard when.timed else { return "\(day), all day" }
        let start = Town.clock(when.start)
        guard let endAt = item.endAt, endAt > when.start else { return "\(day), \(start)" }
        let end = Town.clock(endAt)
        for meridiem in [" AM", " PM"] where start.hasSuffix(meridiem) && end.hasSuffix(meridiem) {
            return "\(day), \(start.dropLast(meridiem.count)) – \(end)"
        }
        return "\(day), \(start) – \(end)"
    }

    // MARK: Touch

    /// Down: squish. A drag that goes down follows the finger (resisting upward) and, far
    /// or fast enough, closes the card; anything less springs back.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !pressed { pressed = true }
                let dy = v.translation.height
                guard abs(dy) > abs(v.translation.width) else { return }
                drag = dy > 0 ? dy : -TodayBubbleRules.rubber(-dy)
            }
            .onEnded { v in
                pressed = false
                let flung = v.predictedEndTranslation.height > 180
                // Closing leaves it where the finger let go, to slide on down from there.
                if drag > 90 || (drag > 20 && flung) { return onClose() }
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 26)) { drag = 0 }
            }
    }
}
