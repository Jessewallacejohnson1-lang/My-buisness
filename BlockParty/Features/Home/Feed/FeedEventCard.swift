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
//  bezels. The day and time ride a white chip on its top left; the title and place
//  stay over it; going, Attend, the heart and send sit under it (Jesse, 2026-10-19,
//  BP app docs/plans/event-card; postings still run edge to edge).
//
//  The headline face is the SYSTEM face (`.sansBold`), not the display face: Apple
//  News sets its headlines in SF, and that is the reference Jesse gave.
//

import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct FeedEventCard: View {
    let item: FeedCardItem
    let comments: [EventComment]
    let onLoadComments: (() async throws -> [EventComment])?
    let onComment: ((String) async throws -> EventComment)?
    let onShare: (() -> Void)?
    /// Which action controls this card offers. Defaults to `.posting` so the Town
    /// pipeline and the DEBUG galleries keep the row they were built against; the
    /// Daily feed passes `.event`, which drops comments but keeps the heart.
    let actionKind: FeedActionKind
    let debugAutoplay: Bool

    /// The host's mark on the photo: the date chip's height, so the two sit level along the top.
    /// A mark, not text, so it does not scale.
    private static let hostMarkSide: CGFloat = PhotoChip.height
    /// Between the photo's credit and the host's mark beside it.
    private static let hostMarkGap: CGFloat = 8
    /// The white ring round the host's mark: Instagram's story ring, at its own 1.5 pt.
    private static let hostMarkRing: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// Read so the card's one-line labels can take a second line at accessibility
    /// sizes. The same trade `PostingCard`'s header already makes: a clipped line is
    /// worse than a taller card.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The photos whose bitmaps are on screen: a credit waits for its photo.
    @State private var shownPhotos: Set<URL> = []
    /// A single photo that could not be loaded (taken down, or offline): the card turns to ink.
    @State private var failedPhoto: URL?
    /// Which of a swiping card's photos is up (event-card 02).
    @State private var photoPage: Int? = 0
    @State private var commentState: FeedCommentState
    @State private var commentsPresented = false
    @State private var menuPresented = false
    @State private var likeBurst = FeedLikeBurst()
    @State private var autoplayStep = 0
    /// The link's press, so the photo sinks in. Set on touch-down by
    /// `FeedTouchDownTracker`, the one writer.
    @State private var linkPressed = false
    /// The photo's size, so the heart on its corner sinks in with it.
    @State private var photoSize: CGSize = .zero
    /// `actions.heartFailureCount` at the last tap on the photo's heart: a tap mid-shake stills it.
    @State private var heartTappedAt = 0
    /// Going and Heart, shared with the event page, so a Join there shows here at once.
    @Environment(RealLifeActions.self) private var actions
    /// Where the host's picture is, for a Place's page to fly out of, and a tap already reading who
    /// the host is (follows 08).
    @State private var hostFrame = FrameBox()
    @State private var hostTapped = Date.distantPast
    @State private var hostRead: Task<Void, Never>?
    @Environment(\.hostOpener) private var hostOpener

    init(
        item: FeedCardItem,
        comments: [EventComment] = [],
        onLoadComments: (() async throws -> [EventComment])? = nil,
        onComment: ((String) async throws -> EventComment)? = nil,
        onShare: (() -> Void)? = nil,
        actionKind: FeedActionKind = .posting,
        debugAutoplay: Bool = false
    ) {
        self.item = item
        self.comments = comments
        self.onLoadComments = onLoadComments
        self.onComment = onComment
        self.onShare = onShare
        self.actionKind = actionKind
        self.debugAutoplay = debugAutoplay
        _commentState = State(initialValue: FeedCommentState(comments: comments))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The photo is the link to the event's page. The RSVP area and the action row
            // stay outside it, so their own buttons keep their own taps and pressing them
            // never squishes the card.
            NavigationLink(value: item) {
                VStack(alignment: .leading, spacing: 0) {
                    // Only the photo sinks in on a press; the line under it stays still
                    // (Jesse, 2026-10-27).
                    face
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { photoSize = $0 }
                        .scaleEffect(pressScale)
                        .opacity(FeedMotion.pressOpacity(isPressed: linkPressed, reduceMotion: motionIsReduced))
                        .animation(FeedMotion.pressAnimation(reduceMotion: motionIsReduced), value: linkPressed)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(FeedCardLinkStyle())
            .accessibilityIdentifier("event-card-link")
            // Which photo is up, read with the card: the pager and its dots stay out of VoiceOver.
            .accessibilityValue(swipes ? "Photo \(pageShown + 1) of \(cardPhotos.count)" : "")
            // The press comes from the touch itself, not the link: the photo's double
            // tap holds the link's own press until it fails, so the photo sinks the
            // moment a finger lands.
            .gesture(FeedTouchDownTracker(isPressed: $linkPressed))
            // The heart on the photo's bottom right, over the link as its own button (event-card 06);
            // on the white card with no photo, at its right, halfway down (no-photo-cards).
            .overlay(alignment: item.isPhotoless ? .trailing : .bottomTrailing) {
                if actions.canAct {
                    // Rides the photo's corner in as it sinks.
                    photoHeart
                        .padding(.trailing, DailyFeedMetric.contentInset
                                 + (item.isPhotoless ? Self.whiteHeartInset : Self.photoHeartInset))
                        .padding(.bottom, item.isPhotoless ? 0 : Self.photoHeartInset)
                        .offset(x: -photoSize.width * (1 - pressScale) / 2,
                                y: item.isPhotoless ? 0 : -photoSize.height * (1 - pressScale) / 2)
                        .animation(FeedMotion.pressAnimation(reduceMotion: motionIsReduced), value: linkPressed)
                }
            }
            // The host's mark on the photo's top right, its own button over the link, as the heart is:
            // it opens the host's page (follows 08), not the Event's.
            .overlay(alignment: .topTrailing) {
                if showsHostMark {
                    // Rides the photo's corner in as it sinks.
                    hostMark
                        .padding(.trailing, DailyFeedMetric.contentInset + PhotoChip.inset)
                        .padding(.top, PhotoChip.inset)
                        .offset(x: -photoSize.width * (1 - pressScale) / 2,
                                y: photoSize.height * (1 - pressScale) / 2)
                        .animation(FeedMotion.pressAnimation(reduceMotion: motionIsReduced), value: linkPressed)
                }
            }

            // Under a photo that swipes, the dots that say which one is up (Instagram's).
            if swipes {
                PageDots(count: cardPhotos.count, page: pageShown)
            }

            // One line under the photo (event-card 06): the send, the •••, the faces, the count and
            // Attend (rsvp-and-groups 01; 12 pt below the photo), or under the dots' row. Called off,
            // a red "Canceled" pill and no count. Going, the pill turns into the X that leaves
            // (attend-x) and the send into the yellow share beside it. The heart is on the photo.
            if let rsvp = actions.rsvp(item, town: true) {
                RSVPArea(item: item, words: rsvp, onInvite: onShare, leadingSend: true, onMenu: openMenu)
                    .padding(.top, swipes ? 0 : 12)
                    .padding(.horizontal, DailyFeedMetric.contentInset)
                    .transition(.opacity)
            } else {
                // Signed out: no Attend and no heart, the send and the ••• alone.
                actionRow
                    .padding(.top, 2)
                    .padding(.horizontal, DailyFeedMetric.contentInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(FeedCardMenuSheet(isPresented: $menuPresented, item: item,
                                    report: currentPhoto.report(place: item.whereLine)))
        .sheet(isPresented: $commentsPresented) {
            FeedCommentSheet(
                commentState: $commentState,
                onLoad: onLoadComments,
                onSend: onComment
            )
        }
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
        !item.hostName.isEmpty && item.game == nil && displayImage.logo == nil && !item.isPhotoless
    }

    /// The host's picture at the date chip's height in a white ring, so a person's photo stands off
    /// the event's, lifted off it by the credit's shadow; its touch area grown to 44 pt without
    /// moving it. Read before the title, as the row it replaced was.
    @ViewBuilder
    private var hostMark: some View {
        let mark = hostAvatar
            .overlay(Circle().strokeBorder(Hue.surface, lineWidth: Self.hostMarkRing))
            .trackFrame(hostFrame)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .contentShape(Circle().inset(by: -(MeetupPillStyle.minTarget - Self.hostMarkSide) / 2))
            .accessibilityLabel(item.hostName)
            .accessibilitySortPriority(1)
        if hostOpener != nil {
            Button(action: openHost) { mark }
                .buttonStyle(PressableStyle())
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

    /// The card's ••• menu (`FeedCardMenu`), on the Town feed's own cards.
    private var openMenu: (() -> Void)? {
        item.why == nil ? nil : { menuPresented = true }
    }

    @ViewBuilder
    private var hostAvatar: some View {
        if item.hostAvatar == nil, let picture = item.hostPicture, picture.kind == .logo {
            // A place's logo on a white disc, as Town news shows a place (Jesse, 2026-10-23).
            LogoDisc(logo: picture.url, initial: item.hostName.first(where: \.isLetter).map { String($0).uppercased() } ?? "",
                     logoSide: Self.hostMarkSide * 0.875, letter: .sansSemibold(14), fits: true)
                .frame(width: Self.hostMarkSide, height: Self.hostMarkSide)
                .overlay(Circle().strokeBorder(Hue.hairline.onLightCanvas, lineWidth: 0.5))
        } else {
            Avatar(item.hostAvatar ?? item.hostPicture?.url, size: Self.hostMarkSide, blank: .initial(item.hostName))
        }
    }

    // MARK: - Image

    /// The photo, or with none the short white card (no-photo-cards).
    @ViewBuilder
    private var face: some View {
        if item.isPhotoless { whiteCard } else { imageSection }
    }

    /// No photo: the place's logo on the left and the day in a grey pill, the chip's words (Jesse at
    /// Check-in 1), turning to Now at the start minute as the chip does.
    private var whiteCard: some View {
        TimelineView(.everyMinute) { context in
            let now = item.isNow(at: context.date)
            NoPhotoCard(logo: whiteCardLogo, photo: item.hostAvatar,
                        name: item.hostName.isEmpty ? item.title : item.hostName,
                        pill: now ? "Now" : item.whenLine?.text, pillSpoken: now ? "Happening now" : item.whenLine?.spoken,
                        pillDot: now ? Hue.now : nil, title: item.title, facts: metaSummary,
                        trailingRoom: actions.canAct ? Self.whiteHeartRoom : 0)
        }
        // Called off: grey, as the photo goes (Jesse, 2026-10-15).
        .grayscale(item.cancelled ? 1 : 0)
        .padding(.horizontal, DailyFeedMetric.contentInset)
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

    /// The event's own photo and its place's, each once, at most three (the Event page shows
    /// the same). Nothing leaves when it fails: it stays ink, so the card never shrinks.
    private var cardPhotos: [FeedCardImageSource] { item.game == nil ? item.photos() : [] }

    /// Two or more photos swipe, under dots; one doesn't.
    private var swipes: Bool { cardPhotos.count > 1 }

    private var pageShown: Int { min(photoPage ?? 0, max(cardPhotos.count - 1, 0)) }

    /// The photo that's up: its credit shows, and the ••• menu reports it.
    private var currentPhoto: FeedCardImageSource {
        swipes ? cardPhotos[pageShown] : displayImage
    }

    /// The credit for the photo on screen, in the array form `PhotoCredit` takes. Empty
    /// until the photo itself has decoded, so a credit never sits on ink.
    private var creditNames: [String] {
        guard let url = currentPhoto.url, PhotoPager.isShown(url, in: shownPhotos),
              let credit = currentPhoto.attribution
        else { return [] }
        return [credit]
    }

    /// The words over the picture: white over a photo or ink, ink over a logo's light
    /// backdrop (as Search sets them).
    private var onLogo: Bool { displayImage.logo != nil }
    /// The words' height over the picture, so a logo stays in the room above them.
    @State private var copyHeight: CGFloat = 0

    private var imageSection: some View {
        GeometryReader { proxy in
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
        }
        // The photo's own shape, known before it loads (`cardAspect`), so the card never
        // jumps when it lands. Square at accessibility sizes: the headline and where line
        // are set over the picture, and at AX5 they outgrew a 3:2 frame and ran up over
        // the host row (measured 2026-09-24).
        // The event's first photo sets it, failed or not, so the card keeps its height.
        // A game keeps one shape, the white card's (game-card 06).
        .aspectRatio(dynamicTypeSize.isAccessibilitySize ? 1
                     : item.game == nil ? CGFloat(item.image.cardAspect) : WhiteGameCard.Metric.aspect,
                     contentMode: .fit)
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
        // Along the top: the day and time on the left, the photo's credit on the right, before the
        // host's mark, so the title has the photo's whole width below (picked 2026-10-19: under the
        // narrower inset card, a credit beside the title cut "Plant Bingo for Angel Reins" short).
        // The white game card says when under its VS (game-card 06).
        .overlay(alignment: .top) {
            HStack(alignment: .center, spacing: 8) {
                if item.game == nil, let when = item.whenLine {
                    // Turns to Now at the start minute while you look at it (event-card 04).
                    TimelineView(.everyMinute) { context in
                        let now = item.isNow(at: context.date)
                        // A ZStack, not a Group: a Group hands the transition to each chip, and
                        // the one coming in never sees `now` change, so it would cut.
                        ZStack(alignment: .leading) {
                            if now {
                                PhotoChip(text: "Now", spoken: "Happening now", dot: Hue.now)
                                    .transition(.opacity)
                            } else {
                                PhotoChip(text: when.text, spoken: when.spoken)
                                    .transition(.opacity)
                            }
                        }
                        .animation(motionIsReduced ? nil : Motion.smooth, value: now)
                    }
                    .layoutPriority(1)
                }
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
            // VoiceOver reads the title first, then when.
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
                .padding(.trailing, actions.canAct ? Self.photoHeartSide + Self.photoHeartInset - 8 : 0)
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
        .padding(.horizontal, DailyFeedMetric.contentInset)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let game = item.game {
            WhiteGameCard(item: item, game: game, place: metaSummary)
        } else if let url = displayImage.url {
            // The Event page's carousel: it pages under the finger, and one photo rubber-bands
            // (a sideways swipe used to open the Event page as if it were a tap, 2026-10-20).
            // Waits on ink, and stays out of VoiceOver here: the card reads as one link, and its
            // page has the carousel. A swiping card keeps a photo that fails, as ink.
            PhotoPager(urls: swipes ? cardPhotos.compactMap(\.url) : [url], page: $photoPage, shown: $shownPhotos,
                       value: "", onFailure: { if !swipes { failedPhoto = $0 } }, skeleton: false, bounces: true)
                .accessibilityHidden(true)
        } else if let logo = displayImage.logo {
            FeedCardPlaceLogo(logo: logo, topClear: PhotoChip.inset + PhotoChip.height, bottomClear: copyHeight + 16)
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
                .foregroundStyle(onLogo ? Hue.ink : .white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !metaSummary.isEmpty {
                Text(metaSummary)
                    .font(.sans(13))
                    .foregroundStyle(onLogo ? Hue.inkSecondary : .white.opacity(0.85))
                    // Unbounded at accessibility sizes, not two lines: measured
                    // 2026-09-22, "7pm · Millstream Park" still clipped at two, and
                    // it was the LAST finding left on Town at both AX3 and AX5. A
                    // meta line that runs to three lines covers a little more of the
                    // photograph; a clipped one loses the place.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // None on ink words over a logo's light backdrop.
        .feedCardPhotoTypeShadow(onLogo ? 0 : 1)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { copyHeight = $0 }
    }

    /// What it is, recurrence and place, under the title: "Lecture · Escher Auditorium". The words
    /// lead and the place gives way at the end when it runs long (Jesse, event-card 05). Date and
    /// time ride the chip on the photo (Jesse, 2026-10-19), which replaced their line, which
    /// replaced the yellow date banner (2026-09-24).
    private var metaSummary: String {
        [item.whatLine, item.game?.occasion, item.recurrence, item.whereLine]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Actions

    /// The heart and send. No bookmark: RSVP took its place on the card, and saving stays on
    /// the Event page (Jesse, 2026-10-17).
    private var actionRow: some View {
        FeedEventCardActionRow(
            kind: actionKind,
            showsHeart: actions.canAct,
            showsSave: false,
            heartFailures: actions.heartFailureCount(item.id),
            state: rowState,
            reduceMotion: motionIsReduced,
            autoplayStep: autoplayStep,
            onLike: nil,
            onSave: nil,
            onComment: { commentsPresented = true },
            onShare: onShare,
            onMenu: openMenu
        )
    }

    /// The heart on the photo (event-card 06): a 38 pt grey glass circle, the white heart in it, red
    /// once yours; on the white game card, the ink heart alone (game-card 06). Its pop and its shake
    /// on a refused write are the action row's.
    static let photoHeartSide: CGFloat = 38
    static let photoHeartInset: CGFloat = 12
    static let photoHeartGlyph: CGFloat = 20
    /// On the white card: the glyph 13 pt in from its right edge, as the mock's, and the words kept
    /// clear of it.
    static let whiteHeartInset: CGFloat = 4
    static let whiteHeartRoom: CGFloat = 26

    private var pressScale: CGFloat {
        FeedMotion.pressScale(isPressed: linkPressed, reduceMotion: motionIsReduced)
    }

    private var photoHeart: some View {
        let hearted = actions.heart(item).isHearted
        let failures = actions.heartFailureCount(item.id)
        let onWhite = item.game != nil || item.isPhotoless
        return Button {
            heartTappedAt = failures
            withAnimation(motionIsReduced ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.5)) {
                actions.toggleHeart(item)
            }
        } label: {
            FeedActionGlyphView(glyph: .heart, size: Self.photoHeartGlyph, filled: hearted)
                .foregroundStyle(hearted ? Hue.heart : onWhite ? Hue.ink.onLightCanvas : .white)
                .phaseAnimator([1, 1.3], trigger: hearted) { glyph, scale in
                    glyph.scaleEffect(motionIsReduced ? 1 : scale)
                } animation: { _ in .spring(response: 0.3, dampingFraction: 0.5) }
                .frame(width: Self.photoHeartSide, height: Self.photoHeartSide)
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
                .padding(-(MeetupPillStyle.minTarget - Self.photoHeartSide) / 2)
        }
        .buttonStyle(MenuPressStyle())
        .turnBackShake(failures: failures, shakes: !motionIsReduced && heartTappedAt != failures)
        .accessibilityLabel("Like, \(actions.heart(item).count) likes")
        .accessibilityValue(hearted ? "Liked" : "Not liked")
        .accessibilityAddTraits(hearted ? .isSelected : [])
    }

    /// The row's heart is the shared one (`RealLifeActions`), kept on the server.
    private var rowState: Binding<FeedCardActionState> {
        Binding {
            let heart = actions.heart(item)
            return FeedCardActionState(likeCount: heart.count, isLiked: heart.isHearted, isSaved: false)
        } set: { new in
            if new.isLiked != actions.heart(item).isHearted { actions.toggleHeart(item) }
        }
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

    /// DEBUG-only: `-town-menu-open` opens the first sample card's ••• sheet, so the phone,
    /// which nothing here can tap, shows it for a screenshot.
    private func openMenuForDebug() async {
        #if DEBUG
        guard item.id == "e1", LaunchFlags.has(.townMenuOpen) else { return }
        try? await Task.sleep(for: .seconds(1))
        menuPresented = true
        #endif
    }

    /// DEBUG-only gallery driver: like → image burst → save → unlike.
    private func runDebugAutoplay() async {
        #if DEBUG
        guard debugAutoplay, autoplayStep == 0 else { return }

        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        autoplayStep = 1

        try? await Task.sleep(for: .milliseconds(1_200))
        guard !Task.isCancelled else { return }
        autoplayStep = 2
        performImageLike(at: nil)

        try? await Task.sleep(for: .milliseconds(1_800))
        guard !Task.isCancelled else { return }
        autoplayStep = 3

        try? await Task.sleep(for: .milliseconds(1_400))
        guard !Task.isCancelled else { return }
        autoplayStep = 4
        #endif
    }
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

/// A card's •••, beside its send under the photo (Jesse, 2026-10-29: the row above the photo it
/// sat at the end of is gone): the app's Lucide ellipsis at 20 pt, whose dots span 15 pt
/// (Instagram's 14.7), in the send's 28 pt width, reaching Apple's 44 pt.
struct FeedCardMenuButton: View {
    let action: () -> Void

    private static let glyph: CGFloat = 20
    private static let width: CGFloat = 28
    /// Added to the row's own spacing after the send (the RSVP area's 8 pt makes 16), so neither's
    /// 44 pt reaches into the other's.
    static let gap: CGFloat = 8

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

/// The •••'s press, as the approved Check-in 1 mock drew it: it shrinks to 0.88 over a
/// faint disc on touch-down and springs back the way it went.
struct MenuPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Hue.ink.opacity(configuration.isPressed ? 0.06 : 0), in: Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
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

/// Which of a card's photos is up: Instagram's dots under its carousel, 6 pt, 4 pt apart, in a
/// 28 pt row, ink for the one up and ink at 18% for the rest (the approved Round 3 mock).
private struct PageDots: View {
    let count: Int
    let page: Int

    private static let side: CGFloat = 6
    private static let gap: CGFloat = 4
    private static let row: CGFloat = 28

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Hue.ink.opacity(index == page ? 1 : 0.18))
                    .frame(width: Self.side, height: Self.side)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.row)
        .animation(Motion.smooth, value: page)
        // The card's link says which photo is up.
        .accessibilityHidden(true)
    }
}
