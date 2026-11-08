//
//  FeedEventCard.swift
//  Block Party — reusable static visual for a normalized feed event.
//
//  Instagram's layout, Apple News's type (Jesse, 2026-09-19). No row above the
//  photograph: the host — the business, parish or neighbour putting the event on —
//  rides the photo's top right as its logo or photo, as Apple News marks a story with
//  its paper's (Jesse, 2026-10-29, BP app references/found-posts); the headline is set
//  OVER the photograph, ranged left off its bottom-left corner. The host's picture
//  opens its own page (follows 08); one with no page of its own opens the Event's.
//
//  The card has no container of its own: no fill, no border, no shadow. The only
//  edge on screen is the PICTURE's: it is inset by `contentInset` like everything
//  else on the card, carries a 20pt corner and takes the photo's own shape, so an
//  event reads as a cut card sunk into the page rather than a photo running off both
//  bezels. The title, when, the place and who's going stay over it (Jesse, 2026-10-19, BP app
//  docs/plans/event-card; 2026-11-07, inside-cards 24), when in plain words just under the title
//  with no chip (inside-cards 26). A card with no photo, the white card and a game's, has who's going in the
//  line under it. Nothing else is under a card: holding it opens Apple's menu, Share first
//  (`TownCardHold`). Attend is the Event page's, and the Event of the day poster's (Jesse,
//  event-card 07).
//
//  The headline face is the SYSTEM face (`.sansBold`), not the display face: Apple
//  News sets its headlines in SF, and that is the reference Jesse gave.
//

import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct FeedEventCard: View {
    let item: FeedCardItem
    /// Share in the card's hold menu.
    let onShare: (() -> Void)?
    let debugAutoplay: Bool

    private static let hostMarkSide = HostMarkDisc.side
    /// Between the photo's credit and the host's mark beside it.
    static let hostMarkGap: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// Read so the card's one-line labels can take a second line at accessibility
    /// sizes. The same trade `PostingCard`'s header already makes: a clipped line is
    /// worse than a taller card.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The photos whose bitmaps are on screen: a credit waits for its photo.
    @State private var shownPhotos: Set<URL> = []
    /// A single photo that could not be loaded (taken down, or offline): the card turns to ink.
    @State private var failedPhoto: URL?
    /// Report from the hold menu: the ••• sheet, opened at its reasons.
    @State private var menuPresented = false
    @State private var likeBurst = FeedLikeBurst()
    /// The link's press, so the photo sinks in. Set on touch-down by
    /// `FeedTouchDownTracker`, the one writer.
    @State private var linkPressed = false
    /// The photo's size, so the heart on its corner sinks in with it.
    @State private var photoSize: CGSize = .zero
    /// Going and Heart, shared with the event page, so a Join there shows here at once.
    @Environment(RealLifeActions.self) private var actions
    /// Where the host's picture is, for a Place's page to fly out of, and a tap already reading who
    /// the host is (follows 08).
    @State private var hostFrame = FrameBox()
    @State private var hostTapped = Date.distantPast
    @State private var hostRead: Task<Void, Never>?
    @Environment(\.hostOpener) private var hostOpener

    init(item: FeedCardItem, onShare: (() -> Void)? = nil, debugAutoplay: Bool = false) {
        self.item = item
        self.onShare = onShare
        self.debugAutoplay = debugAutoplay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The photo is the link to the event's page. The line under it stays outside it, so
            // "Can't go?" keeps its own tap and pressing it never squishes the card.
            NavigationLink(value: item) {
                VStack(alignment: .leading, spacing: 0) {
                    // Only the photo sinks in on a press; the line under it stays still
                    // (Jesse, 2026-10-27).
                    face
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { photoSize = $0 }
                        .scaleEffect(pressScale)
                        .opacity(FeedMotion.pressOpacity(isPressed: linkPressed, reduceMotion: motionIsReduced))
                        .animation(Press.animation(down: linkPressed, reduceMotion: motionIsReduced), value: linkPressed)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(FeedCardLinkStyle())
            .accessibilityIdentifier("event-card-link")
            // The press comes from the touch itself, not the link: the photo's double
            // tap holds the link's own press until it fails, so the photo sinks the
            // moment a finger lands.
            .gesture(FeedTouchDownTracker(isPressed: $linkPressed))
            // The heart in the card's bottom right corner, over the link as its own button: one spot on
            // the photo, the white card and the game card (event-card 06; inside-cards 24).
            .overlay(alignment: .bottomTrailing) {
                if actions.canAct {
                    // Rides the card's corner in as it sinks.
                    TownCardHeart(item: item, onWhite: item.game != nil || item.isPhotoless)
                        .padding(TownCardHeart.inset)
                        .offset(x: -photoSize.width * (1 - pressScale) / 2,
                                y: -photoSize.height * (1 - pressScale) / 2)
                        .animation(Press.animation(down: linkPressed, reduceMotion: motionIsReduced), value: linkPressed)
                }
            }
            // On the white card with no photo, its logo is the host's mark, its own button over the
            // link in the same way, at the card's left (no-photo-cards).
            .overlay(alignment: .leading) {
                if item.isPhotoless, marksHost {
                    whiteCardMark
                        .padding(.leading, NoPhotoCard.Metric.horizontal)
                        .offset(x: photoSize.width * (1 - pressScale) / 2)
                        .animation(Press.animation(down: linkPressed, reduceMotion: motionIsReduced), value: linkPressed)
                }
            }
            // The host's mark on the photo's top right, its own button over the link, as the heart is:
            // it opens the host's page (follows 08), not the Event's.
            .overlay(alignment: .topTrailing) {
                if showsHostMark {
                    // Rides the photo's corner in as it sinks.
                    hostMark
                        .padding(PhotoChip.inset)
                        .offset(x: -photoSize.width * (1 - pressScale) / 2,
                                y: photoSize.height * (1 - pressScale) / 2)
                        .animation(Press.animation(down: linkPressed, reduceMotion: motionIsReduced), value: linkPressed)
                }
            }
            // Held: Apple's menu with the card lifted as itself, its heart and host's mark included
            // (inside-cards 24).
            .modifier(TownCardHold(id: item.id, hostName: item.hostName, why: item.why, share: onShare,
                                   report: item.why == nil ? nil : $menuPresented, event: item))
            // The feed's side insets, outside the card and its buttons, so it lifts as the card alone.
            .padding(.horizontal, TownFeedMetric.contentInset)

            // The line under a card with no photo, or called off: the faces and the count, its middle
            // 24 pt under the card as Instagram's is (event-card 07); "You're going!" once you are.
            // Called off, the red Canceled 12 pt below and no count. Nothing to say, no line.
            if !item.goingOverPhoto, let rsvp = actions.rsvp(item, card: true) {
                RSVPArea(item: item, words: rsvp, onInvite: nil)
                    .frame(minHeight: MeetupPillStyle.minTarget)
                    .padding(.top, rsvp.pill == nil ? 2 : 12)
                    .padding(.horizontal, TownFeedMetric.contentInset)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(FeedCardMenuSheet(isPresented: $menuPresented, item: item,
                                    // On the white card no photo is up to report.
                                    report: item.isPhotoless ? nil : displayImage.report(place: item.whereLine)))
        // On screen: a heart or RSVP that fails may shake here. Scrolled away or covered
        // by the Event page, it turns back without a shake or a buzz.
        .onAppear { actions.cardOpened(item.id, group: item.groupID) }
        .onDisappear {
            actions.cardClosed(item.id, group: item.groupID)
            hostRead?.cancel()
        }
        .task { await runDebugAutoplay() }
        .task { await openMenuForDebug() }
    }

    // MARK: - Host

    /// Whose it is, on the photo's top right: the business's logo or the person's photo, never
    /// Block Party's (Jesse, 2026-10-29: no row above the photo). A game's teams are on the card
    /// itself, and a card showing a logo instead of a photo already says whose it is (the same
    /// school's or shop's logo twice, read 2026-10-29), so they have none.
    private var showsHostMark: Bool {
        !item.hostName.isEmpty && item.game == nil && !item.isPhotoless
    }

    /// The host's picture at the date chip's height in a white ring, so a person's photo stands off
    /// the event's, lifted off it by the credit's shadow; its touch area grown to 44 pt without
    /// moving it. Read before the title, as the row it replaced was.
    @ViewBuilder
    private var hostMark: some View {
        let mark = HostMarkDisc(picture: item.hostPicture, photo: item.hostAvatar, name: item.hostName)
            .trackFrame(hostFrame)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .contentShape(Circle().inset(by: -(MeetupPillStyle.minTarget - Self.hostMarkSide) / 2))
            .accessibilityLabel(item.hostName)
            .accessibilitySortPriority(1)
        if hostOpener != nil {
            Button(action: openHost) { mark }
                .buttonStyle(.press(.squish))
        } else {
            mark
        }
    }

    /// The host's own page (follows 08): the card's Group, else whatever `event_host` names; one
    /// with no page of its own opens the Event's. Asking who the host is waits a second at most,
    /// then opens the Event; a card scrolled away meanwhile opens nothing.
    private func openHost() {
        guard let opener = hostOpener, Date().timeIntervalSince(hostTapped) > HostOpener.again else { return }
        hostTapped = Date()
        if let id = item.groupID {
            if let group = opener.group(id) { opener.push(group) } else { opener.push(item) }
            return
        }
        let picture = hostFrame.rect
        hostRead?.cancel()
        hostRead = Task {
            let reading = Task { try? await EventHostRow.read(item) }
            let timeout = Task {
                try? await Task.sleep(for: HostOpener.readWait)
                reading.cancel()
            }
            let host = await reading.value
            timeout.cancel()
            guard !Task.isCancelled else { return }
            if let host, opener.opens(host) {
                opener.open(host, picture)
            } else {
                opener.push(item)
            }
        }
    }

    // MARK: - Image

    /// The photo, or with none the short white card (no-photo-cards).
    @ViewBuilder
    private var face: some View {
        if item.isPhotoless { whiteCard } else { imageSection }
    }

    /// No photo: the place's logo on the left, and when under the title as on a photo card (inside-cards
    /// 26), turning to Now at the start minute.
    private var whiteCard: some View {
        TimelineView(.everyMinute) { context in
            let line = item.whenLine(at: context.date)
            NoPhotoCard(logo: whiteCardLogo, photo: item.hostAvatar,
                        name: item.hostName.isEmpty ? item.title : item.hostName,
                        when: line?.text, whenSpoken: line?.spoken, now: item.isNow(at: context.date),
                        title: item.title, factsTries: item.smallLines,
                        trailingRoom: actions.canAct ? Self.whiteHeartRoom : 0, drawsMark: !marksHost)
        }
        // Called off: grey, as the photo goes (Jesse, 2026-10-15).
        .grayscale(item.cancelled ? 1 : 0)
        // A double tap likes, as on a photo; a tap opens the Event once that has failed.
        .gesture(PhotoDoubleTap { _ in performImageLike(at: nil) })
    }

    /// The white card's logo opens the host's page, as the mark on a photo does, wherever a host
    /// opener is (the Town feed); elsewhere it is drawn in the card.
    private var marksHost: Bool { hostOpener != nil && !item.hostName.isEmpty }

    /// The white card's logo as a button over the link, the host's page behind it; read before the title.
    private var whiteCardMark: some View {
        Button(action: openHost) {
            NoPhotoCardMark(logo: whiteCardLogo, photo: item.hostAvatar, name: item.hostName)
                .grayscale(item.cancelled ? 1 : 0)
                .trackFrame(hostFrame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .accessibilitySortPriority(1)
    }

    /// The place's logo the card would have shown, else the host's.
    private var whiteCardLogo: URL? {
        if case .placeLogo(let picture) = item.image { return picture.url }
        return item.hostPicture?.kind == .logo ? item.hostPicture?.url : nil
    }

    /// What the card shows: its picture, or ink once that picture has failed to load.
    private var displayImage: FeedCardImageSource {
        // A game draws its white card (`WhiteGameCard`), never its place's photo or logo.
        if item.game != nil { return .fallback }
        if let url = item.image.url, url == failedPhoto { return .fallback }
        return item.image
    }

    /// The credit for the photo on screen, in the array form `PhotoCredit` takes. Empty
    /// until the photo itself has decoded, so a credit never sits on ink.
    private var creditNames: [String] {
        guard let url = displayImage.url, PhotoPager.isShown(url, in: shownPhotos),
              let credit = displayImage.attribution
        else { return [] }
        return [credit]
    }

    private var imageSection: some View {
        shaped(GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                imageContent
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    // What a photo rubber-banding sideways shows beside it: the ink it loads on;
                    // beside the white game card, white.
                    .background(item.game == nil ? Hue.ink : Hue.surface.onLightCanvas)
                    .clipped()
                    // Called off: the photo goes grey (Jesse, 2026-10-15).
                    .grayscale(item.cancelled ? 1 : 0)

                if displayImage.isPhoto {
                    FeedCardPhotoScrim(imageHeight: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        })
        .frame(maxWidth: .infinity)
        // INSIDE the clip — the picture's own edge is what takes the heart away.
        .feedCardLikeBurst(likeBurst, reduceMotion: motionIsReduced)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // The white game card stands off the paper on the mock's hairline and soft shadow.
        .overlay {
            if item.game != nil {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(item.game == nil ? 0 : 0.07), radius: 10, y: 6)
        // Along the top, only the photo's credit, before the host's mark at the right, so the title has
        // the photo's whole width below (picked 2026-10-19: under the narrower inset card, a credit beside
        // the title cut "Plant Bingo for Angel Reins" short). When sits under the title (inside-cards 26);
        // the white game card says it under its VS (game-card 06).
        .overlay(alignment: .top) {
            HStack(alignment: .center, spacing: 8) {
                Spacer(minLength: 0)
                // Without its own edge inset, so it sits as far in as the chip and, shorter
                // than the chip, never moves the row when the photo lands and it appears.
                PhotoCredit(names: creditNames)
                    .padding(-PhotoCredit.edgeInset)
                    // Fades in with its photo, and across to the next one's on a swipe.
                    .animation(motionIsReduced ? nil : Motion.smooth, value: creditNames)
                    // The host's mark rides above the photo in its own layer (`hostMark`).
                    .padding(.trailing, showsHostMark ? Self.hostMarkSide + Self.hostMarkGap : 0)
            }
            .frame(minHeight: PhotoChip.height)
            .padding(PhotoChip.inset)
            // VoiceOver reads the title and when first, then the credit.
            .accessibilitySortPriority(-1)
            .allowsHitTesting(false)
        }
        // The white game card sets its own sport and place (game-card 06).
        .overlay(alignment: .bottom) {
            if item.game == nil {
                HStack(alignment: .bottom, spacing: 0) {
                    imageCopy
                    // Without this the HStack shrinks to its content and the overlay CENTRES
                    // it — a short headline ("Farmers Market") floated to the middle of the
                    // photograph. The copy is ranged left off the picture's bottom-left
                    // corner, always.
                    Spacer(minLength: 0)
                }
                .padding(16)
                // Clear of the heart in the bottom right corner.
                .padding(.trailing, actions.canAct ? TownCardHeart.side + TownCardHeart.inset - 8 : 0)
                // Words only: a swipe that starts on the title pages the photo under it (Jesse, 2026-10-23).
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        // The heart in the photo's corner is the double-tap's control to mirror, and
        // something on screen you can undo it with (event-card 06).
        // The link waits for this to fail before it pushes, so a single tap on the
        // photo opens the page `PhotoDoubleTap.window` after the finger lifts, and a
        // double tap likes without opening it (`EventCardPhotoTapTests`).
        .gesture(PhotoDoubleTap { performImageLike(at: $0) })
    }

    /// The photo's own shape, known before it loads (`cardAspect`), so the card never jumps when it
    /// lands. Square at accessibility sizes: the headline and where line are set over the picture, and
    /// at AX5 they outgrew a 3:2 frame and ran up over the host row (measured 2026-09-24). The event's
    /// first photo sets it, failed or not, so the card keeps its height. A game keeps the white card's
    /// 196 pt at every width (game-card 06; inside-cards 24): shrunk with a 375 pt phone, its corner
    /// heart sat on the right team's name.
    @ViewBuilder
    private func shaped(_ card: some View) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            card.aspectRatio(1, contentMode: .fit)
        } else if item.game != nil {
            card.frame(height: WhiteGameCard.Metric.height)
        } else {
            card.aspectRatio(CGFloat(item.image.cardAspect), contentMode: .fit)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let game = item.game {
            WhiteGameCard(item: item, game: game, place: item.smallLines)
        } else if let url = displayImage.url {
            // The Event page's carousel with the Event's one photo: it rubber-bands (a sideways swipe
            // used to open the Event page as if it were a tap, 2026-10-20). The place's other photos stay
            // on its page (Jesse, 2026-11-04, BP app town-feed 40). Waits on ink, and stays out of
            // VoiceOver here: the card reads as one link, and its page has the carousel.
            PhotoPager(urls: [url], page: .constant(0), shown: $shownPhotos,
                       value: "", onFailure: { failedPhoto = $0 }, skeleton: false, bounces: true)
                .accessibilityHidden(true)
        } else {
            Rectangle().fill(Hue.ink)
        }
    }

    // MARK: - Copy over the photograph

    private var imageCopy: some View {
        // Called off: the photo goes black and white and the red pill under it says so; no
        // tag over the photo (Jesse, 2026-10-17).
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                // 28, the `.title` step. 22 measured ~20% smaller than the Apple News
                // reference relative to card width, and the token scale has nothing
                // between the two (`nearestTextStyle` snaps 24–31 to `.title`).
                .font(.eventDisplay(28))
                // No `.tracking` here any more. It used to pull a system face in to
                // where Apple sets its headlines; this face carries the sheet's own
                // spacing, tuned so a set line matches the drawing, and tightening it
                // again would just double-count that.
                // A two-line headline at this size sits ~1.21em apart by default,
                // which reads airy next to the reference's ~1.1em. Negative spacing
                // is how this codebase has always tightened a heading.
                .lineSpacing(-2)
                .foregroundStyle(.white)
                // Two lines on a photo wider than 3:2: with the time under it, a third ran up into the
                // credit on a 1.91:1 photo (BP app inside-cards 26's review). A square at accessibility
                // sizes keeps three.
                .lineLimit(!dynamicTypeSize.isAccessibilitySize && item.image.cardAspect > 1.5 ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)

            // When, 4 pt under the title in plain white words, turning to Now at the start minute while
            // you look at it (Jesse, 2026-11-07, BP app inside-cards 26). It took over from the white chip
            // on the photo's top left (2026-10-19), which replaced a when line, which replaced the yellow
            // date banner (2026-09-24).
            if let when = item.whenLine {
                TimelineView(.everyMinute) { context in
                    let line = item.whenLine(at: context.date) ?? when
                    CardTime(text: line.text, spoken: line.spoken, now: item.isNow(at: context.date), color: .white)
                }
            }

            // What it is and a short place: "Lecture · Escher Auditorium".
            let lines = item.smallLines
            if !lines.isEmpty {
                SmallLine(tries: lines, wraps: true)
                    .font(.sans(13))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if item.goingOverPhoto, let top = actions.rsvp(item, card: true)?.top {
                goingLine(top)
                    .padding(.top, 4)
            }
        }
        .feedCardPhotoTypeShadow()
    }

    /// Who's going, 8 pt under the small line, as the poster says it (Jesse, 2026-11-07: "1 going sits
    /// inside cards unless if there no photo", then "yeah over photo"): friends' faces, else neighbours',
    /// in the host mark's white ring, then the count or "You're going!".
    private func goingLine(_ top: String) -> some View {
        HStack(spacing: 8) {
            if !item.friendsGoing.isEmpty {
                FriendFaces(friends: item.friendsGoing, ring: .white)
            } else if !item.goingAvatars.isEmpty {
                FeedCardFacepile(neighborAvatars: item.goingAvatars, goingCount: actions.going(item).count,
                                 reduceMotion: motionIsReduced, ring: .white)
            }
            Text(top)
                .font(.displaySemi(15))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .id(top == "You're going!")
        }
        // At least the poster's 24 pt; taller once the words grow with the phone's text size.
        .frame(minHeight: 24)
    }

    // MARK: - Actions

    /// On the white card the words keep 9 pt clear of the heart in its corner, as they did of the
    /// heart halfway down (26 pt then): it sits 8 pt further in.
    static let whiteHeartRoom: CGFloat = 34

    private var pressScale: CGFloat {
        FeedMotion.pressScale(isPressed: linkPressed, reduceMotion: motionIsReduced)
    }

    private var motionIsReduced: Bool {
        accessibilityReduceMotion
    }

    /// No heart to mirror without an account, so no double tap either.
    private func performImageLike(at point: CGPoint?) {
        guard actions.canAct else { return }
        withAnimation(motionIsReduced ? .easeInOut(duration: 0.15) : Motion.snappy) {
            actions.heartOn(item)
        }
        likeBurst.fire(at: point)
    }

    /// DEBUG-only: `-town-menu-open` opens the first sample card's Report sheet, what Report in its hold
    /// menu opens, so the phone, which nothing here can tap or hold, shows it for a screenshot.
    private func openMenuForDebug() async {
        #if DEBUG
        guard item.id == "e1", LaunchFlags.has(.townMenuOpen) else { return }
        try? await Task.sleep(for: .seconds(1))
        menuPresented = true
        #endif
    }

    /// DEBUG-only gallery driver: the double tap's like and its burst.
    private func runDebugAutoplay() async {
        #if DEBUG
        guard debugAutoplay else { return }
        try? await Task.sleep(for: .milliseconds(2_000))
        guard !Task.isCancelled else { return }
        performImageLike(at: nil)
        #endif
    }
}

extension FeedCardItem {
    /// Who's going sits over the photo, under its small line (inside-cards 24): not on the white card
    /// or a game's, which have it in the line under them, nor on a called-off card, whose line keeps
    /// the red Canceled.
    var goingOverPhoto: Bool { game == nil && !isPhotoless && !cancelled }
}

/// A touch-down the instant a finger lands, and its end, reported WITHOUT taking part
/// in who wins the touch: the feed's scroll, the link and the photo's double tap all
/// still get it. A SwiftUI `LongPressGesture` here, even as `.simultaneousGesture`,
/// stopped the feed scrolling and turned a drag into a push (measured 2026-09-25),
/// the pan-stealing `FeedMotion`'s header warns about. A slide past `slop` counts as
/// letting go, so a drag that becomes a scroll releases the squish.
struct FeedTouchDownTracker: UIGestureRecognizerRepresentable {
    @Binding var isPressed: Bool

    /// UIKit's tap slop, the distance a tap stops being a tap.
    private static let slop: CGFloat = 10

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var start: CGPoint = .zero

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            context.coordinator.start = point
            isPressed = true
        case .changed:
            let start = context.coordinator.start
            if isPressed, hypot(point.x - start.x, point.y - start.y) > Self.slop { isPressed = false }
        default:
            isPressed = false
        }
    }
}

/// A Town card's heart (event-card 06; inside-cards 24): one spot on every Town card, 12 pt in from
/// the card's bottom right corner, and the poster's at the right of its Attend row. Over a picture,
/// a 38 pt grey glass circle with the white heart; on white, the ink heart alone; red once yours.
/// It pops out to 1.3 and back, and shakes once when the server turns a heart back.
/// A host's picture on a Town card's photo, top right (Jesse, 2026-10-29): a place's logo on a white disc, as Town news
/// shows a place (2026-10-23), else a person's or the place's photo, else the first letter, in a white ring. The Event
/// card makes it a button to its host's page; a News card shows it alone (BP app town-feed 53).
struct HostMarkDisc: View {
    let picture: PlacePicture?
    var photo: URL? = nil
    let name: String

    /// The photo chip's height, as when the day's chip sat level with it (the time moved under the title,
    /// inside-cards 26). A mark, not text, so it does not scale.
    static let side: CGFloat = PhotoChip.height
    /// The white ring: Instagram's story ring, at its own 1.5 pt.
    private static let ring: CGFloat = 1.5

    var body: some View {
        Group {
            if photo == nil, let picture, picture.kind == .logo {
                LogoDisc(logo: picture.url, initial: name.first(where: \.isLetter).map { String($0).uppercased() } ?? "",
                         logoSide: Self.side * 0.875, letter: .sansSemibold(14), fits: true)
                    .frame(width: Self.side, height: Self.side)
                    .overlay(Circle().strokeBorder(Hue.hairline.onLightCanvas, lineWidth: 0.5))
            } else {
                Avatar(photo ?? picture?.url, size: Self.side, blank: .initial(name))
            }
        }
        .overlay(Circle().strokeBorder(Hue.surface, lineWidth: Self.ring))
    }
}

struct TownCardHeart: View {
    let item: FeedCardItem
    var onWhite = false

    static let side: CGFloat = 38
    static let inset: CGFloat = 12
    static let glyph: CGFloat = 20

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `actions.heartFailureCount` at the last tap: a tap mid-shake stills it.
    @State private var tappedAt = 0

    var body: some View {
        let hearted = actions.heart(item).isHearted
        let failures = actions.heartFailureCount(item.id)
        Button {
            tappedAt = failures
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.5)) {
                actions.toggleHeart(item)
            }
        } label: {
            FeedActionGlyphView(glyph: .heart, size: Self.glyph, filled: hearted)
                .foregroundStyle(hearted ? Hue.heart : onWhite ? Hue.ink.onLightCanvas : .white)
                .phaseAnimator([1, 1.3], trigger: hearted) { glyph, scale in
                    glyph.scaleEffect(reduceMotion ? 1 : scale)
                } animation: { _ in .spring(response: 0.3, dampingFraction: 0.5) }
                .frame(width: Self.side, height: Self.side)
                // Grey glass: the photo blurred through a dark tint, a line of light inside the top.
                .background {
                    if !onWhite {
                        Circle()
                            .fill(.black.opacity(0.22))
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
                            .environment(\.colorScheme, .dark)
                    }
                }
                .frame(width: MeetupPillStyle.minTarget, height: MeetupPillStyle.minTarget)
                .contentShape(Circle())
                .padding(-(MeetupPillStyle.minTarget - Self.side) / 2)
        }
        .buttonStyle(MenuPressStyle())
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .accessibilityLabel("Like, \(actions.heart(item).count) likes")
        .accessibilityValue(hearted ? "Liked" : "Not liked")
        .accessibilityAddTraits(hearted ? .isSelected : [])
    }
}

/// A neighbour's post's •••, beside its send (Jesse, 2026-10-29: the row above the photo it sat at
/// the end of is gone; a Town card's went into its hold menu, inside-cards 24): the app's Lucide
/// ellipsis at 20 pt, whose dots span 15 pt (Instagram's 14.7), in the send's 28 pt width, reaching
/// Apple's 44 pt.
struct FeedCardMenuButton: View {
    let action: () -> Void

    private static let glyph: CGFloat = 20
    private static let width: CGFloat = 28

    var body: some View {
        Button(action: action) {
            Image("Lucide/ellipsis")
                .resizable()
                .frame(width: Self.glyph, height: Self.glyph)
                .foregroundStyle(Hue.ink)
                .frame(width: Self.width, height: MeetupPillStyle.minTarget)
                .contentShape(Rectangle().inset(by: (Self.width - MeetupPillStyle.minTarget) / 2))
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel("More options")
    }
}

/// The •••'s press, as the approved Check-in 1 mock drew it: it shrinks over a faint disc on
/// touch-down and springs back the way it went.
struct MenuPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Hue.ink.opacity(configuration.isPressed ? 0.06 : 0), in: Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? Press.deepest : 1)
            .animation(Press.animation(down: configuration.isPressed, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// The link draws nothing on press: the card's squish comes from `FeedTouchDownTracker`.
struct FeedCardLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Double-tap-to-like on the photo, with a window the card owns. The link waits for
/// this to fail before it pushes, so the window IS a single tap's delay. SwiftUI's own
/// double tap waited ~0.5 s after the finger lifted (measured 2026-09-25); this one
/// fails `window` after it.
struct PhotoDoubleTap: UIGestureRecognizerRepresentable {
    let onDoubleTap: (CGPoint) -> Void

    /// Longest gap between the first lift and the second touch that still counts as a
    /// double tap. Shorter opens the page sooner, and a slower double tap reads as a
    /// tap. Jesse asked for ~0.3 s from lift to push (2026-09-25).
    static let window: TimeInterval = 0.2

    final class Recognizer: UITapGestureRecognizer {
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            super.touchesBegan(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesEnded(touches, with: event)
            if state == .possible {
                // `.common`, so the window still closes while a scroll is tracking.
                perform(#selector(windowClosed), with: nil, afterDelay: PhotoDoubleTap.window,
                        inModes: [.common])
            }
        }

        override func reset() {
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            super.reset()
        }

        @objc private func windowClosed() {
            if state == .possible { state = .failed }
        }
    }

    func makeUIGestureRecognizer(context: Context) -> Recognizer {
        let recognizer = Recognizer()
        recognizer.numberOfTapsRequired = 2
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
        if recognizer.state == .ended { onDoubleTap(context.converter.localLocation) }
    }
}
