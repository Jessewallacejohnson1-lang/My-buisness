//
//  EventOfTheDayPoster.swift
//  Block Party — the top of the Town feed: your Event of the day as DICE's dark poster
//  (BP app docs/plans/event-card, ticket 03; the approved Round 3 page, Jesse 2026-10-19).
//
//  The same pick Daily shows first (`EventOfTheDay`). Unlike a Town card it keeps one fixed
//  shape, but for a flyer, shown whole and uncovered under the chip with the poster grown to fit
//  (town-feed 57): the photo square on top fading into the poster's dark, a white "Event of the day"
//  chip on it, then the title, when in BP yellow, and one small line, what it is and a short place
//  ("Meat raffle · Sal's Bar and Grill"), in a photo card's look (Jesse, 2026-11-07, BP app
//  inside-cards 26), the going line, and Attend with the heart inside the card,
//  the heart in Town's glass at the row's right (inside-cards 24); the host is on the Event page
//  (event-card 05). Going keeps it on top, saying You're going!. Held, it opens a Town card's menu,
//  Share first (`TownCardHold`), which took its send and •••.
//
//  The poster is one link to the Event page, which squishes on touch-down and takes a double
//  tap on the photo as a like, as a Town card does. Its words sit over the link without taking
//  touches; the pill, the heart and "Can't go?" sit over it as their own buttons, so their taps
//  stay theirs.
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
        /// When 4 pt under the title and the small line 4 pt under it, as on a photo card (inside-cards 26).
        static let whenTop: CGFloat = 4
        static let lineTop: CGFloat = 4
        static let goingTop: CGFloat = 10
        static let goingHeight: CGFloat = 24
        static let rowTop: CGFloat = 16
        static let rowGap: CGFloat = 10
        /// The credit's soft shadow under the "Event of the day" chip, so it keeps its edge on a pale sky:
        /// without it the white chip's edge measured 1.3 to 1 on Nov 6's photo (inside-cards 25).
        static let chipShadow: Double = 0.25
        static let chipShadowRadius: CGFloat = 4
        /// A flyer keeps this far from the chip above it and the words below it, over its own blur, the Event
        /// page's 30 pt (PICKED, BP app town-feed 57).
        static let flyerGap: CGFloat = 8
        static let washBlur: CGFloat = 30
    }

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var linkPressed = false
    /// Two fingers have lifted the poster (`pinchToZoom`): its squish lets go at once.
    @State private var lifted = false
    @State private var likeBurst = FeedLikeBurst()
    /// Report from the hold menu: the ••• sheet, opened at its reasons.
    @State private var menuPresented = false
    /// The photo has decoded, so its credit may show.
    @State private var photoShown = false
    /// The photo couldn't load: the poster's dark shows alone.
    @State private var photoFailed = false
    /// The words and buttons' height: under a whole flyer the poster grows by it, so pressing Attend grows it
    /// downward and never moves the flyer.
    @State private var copyHeight: CGFloat = 0

    private var item: FeedCardItem { event.item }

    /// The event's own photo, else its place's, credited, else its place's logo, as the Town card
    /// shows them. One photo: the poster doesn't swipe.
    private var picture: FeedCardImageSource { photoFailed ? .fallback : item.image }

    var body: some View {
        NavigationLink(value: item) { face }
            .buttonStyle(FeedCardLinkStyle())
            .gesture(FeedTouchDownTracker(isPressed: $linkPressed))
            .accessibilityIdentifier("event-of-the-day-poster")
            .accessibilityLabel(spoken)
            // Over a flyer, the words wait for their first measure, so they never land on its foot for a frame.
            .overlay(alignment: .bottom) { copy.opacity(item.whole && copyHeight == 0 ? 0 : 1) }
            // Two fingers lift the poster, its words too, where it sits (BP app photo-zoom).
            .pinchToZoom(corner: Radius.poster, slot: Hue.paper, lifted: $lifted)
            // Held: Apple's menu with the poster lifted as itself, words and buttons included
            // (inside-cards 24).
            .modifier(TownCardHold(id: item.id, hostName: item.hostName, why: item.why,
                                   share: { ShareCenter.shared.present(.event(item)) },
                                   report: item.why == nil ? nil : $menuPresented, event: item))
            .scaleEffect(lifted ? 1 : FeedMotion.pressScale(isPressed: linkPressed, reduceMotion: reduceMotion))
            .opacity(lifted ? 1 : FeedMotion.pressOpacity(isPressed: linkPressed, reduceMotion: reduceMotion))
            .animation(Press.animation(down: linkPressed, reduceMotion: reduceMotion), value: linkPressed)
            .modifier(FeedCardMenuSheet(isPresented: $menuPresented, item: item,
                                        report: picture.report(place: item.whereLine)))
            // On screen, a heart or Attend that fails may shake here.
            .onAppear { actions.cardOpened(item.id) }
            .onDisappear { actions.cardClosed(item.id) }
    }

    // MARK: - The link: photo, fade, chip

    @ViewBuilder
    private var shape: some View {
        if item.whole && !photoFailed {
            // A flyer full width at its own shape, the words under it: the poster grows to fit (Jesse picked B,
            // 2026-11-10, BP app town-feed 57).
            VStack(spacing: 0) {
                flyer
                Color.clear.frame(height: copyHeight + Metric.flyerGap)
            }
            .background { flyerWash }
        } else {
            Hue.poster
                .aspectRatio(Metric.aspect, contentMode: .fit)
                .overlay(alignment: .top) { photo }
        }
    }

    private var face: some View {
        shape
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                HStack(spacing: 8) {
                    PhotoChip(text: "Event of the day")
                        // One shadow round the chip's edge, not one under each of its words.
                        .compositingGroup()
                        .shadow(color: .black.opacity(Metric.chipShadow), radius: Metric.chipShadowRadius, y: 1)
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

    /// A flyer whole and uncovered, as on its Event page: at its own shape (at most 4:5 tall), rounded, inside the
    /// poster's sides and under the "Event of the day" chip (Jesse, 2026-11-10, BP app town-feed 57).
    private var flyer: some View {
        Color.clear
            .aspectRatio(CGFloat(item.image.flyerAspect), contentMode: .fit)
            .overlay {
                if let url = picture.url {
                    FeedCardURLPhoto(url: url, onReady: { photoShown = true }, onFailure: { photoFailed = true },
                                     loadingFill: Hue.poster)
                        .aspectRatio(CGFloat(item.image.ownAspect), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                }
            }
            .grayscale(item.cancelled ? 1 : 0)
            .padding(.top, Metric.chipInset + PhotoChip.height + Metric.flyerGap)
            .padding(.horizontal, Metric.copyInset)
    }

    /// Behind a flyer: itself blurred to fill the poster, melting into the poster's dark by the words.
    @ViewBuilder
    private var flyerWash: some View {
        ZStack {
            Hue.poster
            if let url = picture.url {
                // Clipped before the blur, or the filled photo runs past the poster.
                FeedCardURLPhoto(url: url, loadingFill: Hue.poster)
                    .clipped()
                    .blur(radius: Metric.washBlur, opaque: true)
                    .grayscale(item.cancelled ? 1 : 0)
            }
            LinearGradient(colors: [Hue.poster.opacity(0.2), Hue.poster.opacity(0.85), Hue.poster],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - The words and buttons over it

    private var copy: some View {
        let words = actions.rsvp(item, town: true)
        return VStack(alignment: .leading, spacing: 0) {
            // A stack, not a Group: measured as a Group, its lines would land on top of each other.
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.eventDisplay(28))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                when
                    .padding(.top, Metric.whenTop)
                // What it is and a short place in one line, a photo card's own (`smallLines`).
                let lines = item.smallLines
                if !lines.isEmpty {
                    SmallLine(tries: lines, wraps: true)
                        .font(.sans(13))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, Metric.lineTop)
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
                    // Going, the yellow share pops up right of the X (event-card 06). Attend is yellow on the dark
                    // (attend-yellow).
                    AttendPill(item: item, words: words,
                               onInvite: { ShareCenter.shared.present(.event(item)) }, showsShare: true,
                               yellow: true)
                }
                Spacer(minLength: 0)
                // Town's glass heart, level with Attend: its circle's edge on the words' right edge.
                if actions.canAct { TownCardHeart(item: item) }
            }
            .frame(height: RSVPArea.Size.card.pillHeight)
            .padding(.top, Metric.rowTop)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.copyInset)
        // The first read lands as it is; a going line coming or going grows the poster with the words' turn.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if copyHeight == 0 { copyHeight = height } else { withAnimation(.easeInOut(duration: flip)) { copyHeight = height } }
        }
        .animation(.easeInOut(duration: flip), value: actions.going(item).isGoing)
    }

    /// The going words' turn: `RealLifeActions.flip`, or 0.15 s with Reduce Motion, as the pill's.
    private var flip: TimeInterval { reduceMotion ? 0.15 : RealLifeActions.flip }

    /// "Today · 2 PM" in every Town card's type, in BP yellow (Jesse, 2026-11-07, BP app inside-cards
    /// 26); while it's on, "Now" behind Apple's green dot, as a Town card says it (Jesse at Check-in 1,
    /// 2026-10-21). Another day's, on Daily, says the day short, "Sat · 4 PM" (`DailyEvent.dayLine`).
    @ViewBuilder
    private var when: some View {
        let on = item.isNow(at: now)
        let text = item.isOpen(at: now) ? item.whenLine(at: now)?.text : event.dayLine(now: now) ?? item.whenLine?.text
        if on || text != nil {
            CardTime(text: text ?? "", now: on, color: Hue.brandDisc)
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
                .font(.displaySemi(15))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .id(words.goingLine)
                // The link reads the count, and Attend's value says Going.
                .accessibilityHidden(true)
            if words.canLeave, let leave = words.second {
                RSVPArea.leave(leave, size: .card, hint: "Takes you off the going list",
                               tint: .white.opacity(0.6)) {
                    actions.toggleGoing(item)
                }
            } else if let bar = actions.rsvp(item, bar: true), !bar.canLeave, let names = bar.second {
                Text("· \(names)")
                    .font(.sans(15))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: Metric.goingHeight)
    }

    // MARK: -

    /// What VoiceOver reads for the link, in the order the poster shows it: its name, when, what it is
    /// ("Lecture") and where, and who's going.
    private var spoken: String {
        let when = item.isNow(at: now) ? "Happening now" : item.whenLine(at: now)?.spoken
        return ["Event of the day", item.title, when, item.whatLine, item.whereLine,
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
