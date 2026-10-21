//
//  EventOfTheDayPoster.swift
//  Block Party — the top of the Town feed: your Event of the day as DICE's dark poster
//  (BP app docs/plans/event-card, ticket 03; the approved Round 3 page, Jesse 2026-10-19).
//
//  The same pick Daily shows first (`EventOfTheDay`). Unlike a Town card it keeps one fixed
//  shape: the photo square on top fading into the poster's dark, a white "Event of the day"
//  chip on it, then the host, the title, the date in BP yellow, the place, the going line, and
//  Attend with the heart and ••• inside the card. Going keeps it on top, saying You're going!.
//
//  The poster is one link to the Event page, which squishes on touch-down and takes a double
//  tap on the photo as a like, as a Town card does. Its words sit over the link without taking
//  touches; the pill, the heart, the ••• and "Can't go?" sit over it as their own buttons, so
//  their taps stay theirs.
//

import SwiftUI

struct EventOfTheDayPoster: View {
    let event: DailyEvent
    let now: Date

    /// The approved Round 3 page's numbers, at 370 pt wide on a 402 pt phone.
    private enum Metric {
        /// 370 x 470: one shape for every photo.
        static let aspect: CGFloat = 370.0 / 470.0
        /// The chip from the photo's top left corner, and the words from the poster's edges.
        static let chipInset: CGFloat = 14
        static let copyInset: CGFloat = 15
        /// The photo fades into the dark from 38% of its height, 82% dark by 78%.
        static let fade: [Gradient.Stop] = [.init(color: Hue.poster.opacity(0), location: 0.38),
                                            .init(color: Hue.poster.opacity(0.82), location: 0.78),
                                            .init(color: Hue.poster, location: 1)]
        static let hostMark: CGFloat = 20
        static let hostGap: CGFloat = 8
        static let titleTop: CGFloat = 6
        static let whenTop: CGFloat = 8
        static let placeTop: CGFloat = 1
        static let goingTop: CGFloat = 10
        static let goingHeight: CGFloat = 24
        static let rowTop: CGFloat = 16
        static let rowGap: CGFloat = 10
        /// The heart and ••• sit in 30 pt black circles, as DICE's do, inside 44 pt targets.
        static let circle: CGFloat = 30
        static let target: CGFloat = 44
        static let heartGlyph: CGFloat = 18
        static let dotsGlyph: CGFloat = 18
        static let nowDot: CGFloat = 8
    }

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var linkPressed = false
    @State private var likeBurst = FeedLikeBurst()
    @State private var menuPresented = false
    /// The photo has decoded, so its credit may show.
    @State private var photoShown = false
    /// The photo couldn't load: the poster's dark shows alone.
    @State private var photoFailed = false
    /// `actions.heartFailureCount` at the last heart tap: a tap mid-shake stills it.
    @State private var heartTappedAt = 0

    private var item: FeedCardItem { event.item }

    /// The event's own photo, else its place's, credited, else its place's logo, as Daily's card
    /// and the Town card show them. One photo: the poster doesn't swipe.
    private var picture: FeedCardImageSource { photoFailed ? .fallback : item.image }

    var body: some View {
        NavigationLink(value: item) { face }
            .buttonStyle(FeedCardLinkStyle())
            .gesture(FeedTouchDownTracker(isPressed: $linkPressed))
            .accessibilityIdentifier("event-of-the-day-poster")
            .accessibilityLabel(spoken)
            .overlay(alignment: .bottom) { copy }
            .scaleEffect(FeedMotion.pressScale(isPressed: linkPressed, reduceMotion: reduceMotion))
            .opacity(FeedMotion.pressOpacity(isPressed: linkPressed, reduceMotion: reduceMotion))
            .animation(FeedMotion.pressAnimation(reduceMotion: reduceMotion), value: linkPressed)
            .padding(.horizontal, DailyFeedMetric.contentInset)
            .sheet(isPresented: $menuPresented) {
                if let why = item.why {
                    FeedCardMenu(why: why, score: item.score, report: picture.report(place: item.whereLine))
                }
            }
            // On screen, a heart or Attend that fails may shake here.
            .onAppear { actions.cardOpened(item.id) }
            .onDisappear { actions.cardClosed(item.id) }
    }

    // MARK: - The link: photo, fade, chip

    private var face: some View {
        Hue.poster
            .aspectRatio(Metric.aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { photo }
            .overlay(alignment: .top) {
                HStack(spacing: 8) {
                    PhotoChip(text: "Event of the day")
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    PhotoCredit(names: photoShown ? [picture.attribution].compactMap { $0 } : [])
                        .padding(-PhotoCredit.edgeInset)
                        .animation(reduceMotion ? nil : Motion.smooth, value: photoShown)
                }
                .frame(minHeight: PhotoChip.height)
                .padding(Metric.chipInset)
            }
            // Inside the clip: the poster's own edge takes the heart away.
            .feedCardLikeBurst(likeBurst, reduceMotion: reduceMotion)
            .clipShape(RoundedRectangle(cornerRadius: Radius.poster, style: .continuous))
            .contentShape(Rectangle())
            // The link waits for this to fail, so a single tap opens the page just after the lift
            // and a double tap likes without opening it, as on a Town card.
            .gesture(PhotoDoubleTap { performImageLike(at: $0) })
    }

    /// The square on top, faded into the dark. Called off, it goes grey, as a Town card's does.
    private var photo: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url = picture.url {
                    FeedCardURLPhoto(url: url, onReady: { photoShown = true }, onFailure: { photoFailed = true },
                                     loadingFill: Hue.poster)
                } else if let logo = picture.logo {
                    FeedCardPlaceLogo(logo: logo, topClear: Metric.chipInset + PhotoChip.height)
                }
            }
            .clipped()
            .grayscale(item.cancelled ? 1 : 0)
            .overlay { LinearGradient(stops: Metric.fade, startPoint: .top, endPoint: .bottom) }
    }

    // MARK: - The words and buttons over it

    private var copy: some View {
        let words = actions.rsvp(item, town: true)
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if !item.hostName.isEmpty {
                    HStack(spacing: Metric.hostGap) {
                        FeedAuthorAvatar(url: item.hostAvatar, name: item.hostName,
                                         side: Metric.hostMark, initialSize: 11)
                        Text(item.hostName)
                            .font(.sans(15))
                            .lineLimit(1)
                    }
                    .padding(.bottom, Metric.titleTop)
                }
                Text(item.title)
                    .font(.eventDisplay(28))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                when
                    .padding(.top, Metric.whenTop)
                if let place = item.whereLine {
                    Text(place)
                        .font(.sans(16))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .padding(.top, Metric.placeTop)
                }
            }
            // Read with the link; a touch on them reaches it, so they open the page too.
            .foregroundStyle(.white)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if let words, words.top != nil {
                goingLine(words)
                    .padding(.top, Metric.goingTop)
                    // It comes in where the place stood: it fades in once the words above have moved
                    // up to make room, and out before they come back down over it.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeInOut(duration: flip).delay(flip)),
                        removal: .opacity.animation(.easeOut(duration: flip / 2))))
            }

            HStack(spacing: Metric.rowGap) {
                if let words {
                    AttendPill(item: item, words: words,
                               onInvite: { ShareCenter.shared.present(.event(item)) })
                }
                Spacer(minLength: 0)
                if actions.canAct { heartButton }
                if item.why != nil { menuButton }
            }
            .frame(height: RSVPArea.Size.card.pillHeight)
            .padding(.top, Metric.rowTop)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.copyInset)
        .animation(.easeInOut(duration: flip), value: actions.going(item).isGoing)
    }

    /// The going words' turn: `RealLifeActions.flip`, or 0.15 s with Reduce Motion, as the pill's.
    private var flip: TimeInterval { reduceMotion ? 0.15 : RealLifeActions.flip }

    /// "Today · 2 PM", in BP yellow; while it's on, "Now" behind Apple's green dot, as a Town
    /// card's chip says it (Jesse at Check-in 1, 2026-10-21).
    @ViewBuilder
    private var when: some View {
        if item.isNow(at: now) {
            HStack(spacing: 6) {
                Circle().fill(Hue.now).frame(width: Metric.nowDot, height: Metric.nowDot)
                Text("Now")
            }
            .font(.sans(16))
            .foregroundStyle(Hue.brandDisc)
        } else if let when = item.whenLine {
            Text(when.text)
                .font(.sans(16))
                .foregroundStyle(Hue.brandDisc)
        }
    }

    /// "41 going · Sam and Marlene" (the names alone, as the Event page's bar says them), or once
    /// you're going, "You're going!" while the pill is the X that leaves; called off, with
    /// "Can't go?" beside it.
    private func goingLine(_ words: RSVPWords) -> some View {
        HStack(spacing: 8) {
            if !item.friendsGoing.isEmpty {
                FriendFaces(friends: item.friendsGoing, ring: Hue.poster)
            }
            Text(words.top ?? "")
                .font(.sansSemibold(15))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .id(words.goingLine)
                // The link reads the count, and Attend's value says Going.
                .accessibilityHidden(true)
            if words.canLeave, let leave = words.second {
                RSVPArea.leave(leave, size: .card, hint: "Takes you off the going list",
                               reduceMotion: reduceMotion, tint: .white.opacity(0.6)) {
                    actions.toggleGoing(item)
                }
            } else if let names = actions.rsvp(item, bar: true)?.second {
                Text("· \(names)")
                    .font(.sans(15))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: Metric.goingHeight)
    }

    // MARK: - Heart and •••

    private var heartButton: some View {
        let hearted = actions.heart(item).isHearted
        let failures = actions.heartFailureCount(item.id)
        return Button {
            heartTappedAt = failures
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.5)) {
                actions.toggleHeart(item)
            }
        } label: {
            circle {
                FeedActionGlyphView(glyph: .heart, size: Metric.heartGlyph, filled: hearted)
                    .foregroundStyle(hearted ? Hue.heart : .white)
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
    }

    private var menuButton: some View {
        Button { menuPresented = true } label: {
            circle {
                Image("Lucide/ellipsis")
                    .resizable()
                    .frame(width: Metric.dotsGlyph, height: Metric.dotsGlyph)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel("More options")
    }

    /// DICE's round dark button: a 30 pt black circle, the glyph white on it, a 44 pt target.
    private func circle(@ViewBuilder _ glyph: () -> some View) -> some View {
        glyph()
            .frame(width: Metric.circle, height: Metric.circle)
            .background(Circle().fill(.black))
            .frame(width: Metric.target, height: Metric.target)
            .contentShape(Circle())
            // The circles' edges line up with the words' right edge, the target reaching past it.
            .padding(.horizontal, -(Metric.target - Metric.circle) / 2)
    }

    // MARK: -

    /// What VoiceOver reads for the link: what it is, then when and where, and who's going.
    private var spoken: String {
        let when = item.isNow(at: now) ? "Happening now" : item.whenLine?.spoken
        return ["Event of the day", item.title, when, item.whereLine, item.hostName,
                actions.rsvp(item)?.top].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// No heart to mirror without an account, so no double tap either.
    private func performImageLike(at point: CGPoint?) {
        guard actions.canAct else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.snappy) {
            actions.heartOn(item)
        }
        likeBurst.fire(at: point)
    }
}
