//
//  FeedEventCard.swift
//  Block Party — reusable static visual for a normalized feed event.
//
//  Instagram's layout, Apple News's type (Jesse, 2026-09-19). The host — the
//  business, parish or neighbour putting the event on — sits in a row ABOVE the
//  photograph, the way a poster's name does on Instagram; the headline is set OVER
//  the photograph, ranged left off its bottom-left corner.
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

    /// The host avatar. An avatar beside a name is a mark at a size the row is drawn
    /// around, not text, so it does not scale.
    private static let hostAvatarSide: CGFloat = 32

    /// The ••• button: a 44pt target round the app's Lucide ellipsis at 20pt, whose dots
    /// span 15pt (Instagram's span 14.7, 15pt from the edge). Its dots end at the
    /// card's inset, so the button reaches 14.5pt past it.
    private static let menuTarget: CGFloat = 44
    private static let menuGlyph: CGFloat = 20
    private static let menuDotsInset: CGFloat = 14.5
    /// Kept clear at the end of the host row so a long name stops short of the dots.
    private static let menuRoom: CGFloat = menuDots + 8
    private static let menuDots: CGFloat = 15

    /// Join beside a group's name (rsvp-and-groups 07): the Figma page's Club pill ("Meetup
    /// depth"), 30 pt tall, 16 pt in from each end, 10 pt before the •••. Its 14 pt word snaps
    /// to 15 (`.sans`), the card's RSVP word.
    private static let groupPillHeight: CGFloat = 30
    private static let groupPillSide: CGFloat = 16
    private static let groupPillGap: CGFloat = 10
    private static let groupPillWord: CGFloat = 15

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
    /// The link's press, so the whole card squishes. Set on touch-down by
    /// `FeedTouchDownTracker`, the one writer.
    @State private var linkPressed = false
    /// Going and Heart, shared with the event page, so a Join there shows here at once.
    @Environment(RealLifeActions.self) private var actions
    /// Joined from this card: it keeps saying Joined after a read that says you're in.
    @State private var joinedHere = false
    /// `actions.memberFailureCount` at the last Join: a tap mid-shake stills it (as `RSVPArea`'s).
    @State private var groupTappedAt = 0
    /// The Join pill's width, which the host's name stops short of.
    @State private var groupPillWidth: CGFloat = 0

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
            // Host and photo are one link to the event's page. The RSVP area and the
            // action row stay outside it, so their own buttons keep their own taps and
            // pressing them never squishes the card.
            NavigationLink(value: item) {
                VStack(alignment: .leading, spacing: 0) {
                    hostRow
                        .padding(.horizontal, DailyFeedMetric.contentInset)

                    imageSection
                        .padding(.top, showsHostRow ? 10 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(FeedCardLinkStyle())
            .accessibilityIdentifier("event-card-link")
            // The press comes from the touch itself, not the link: the photo's double
            // tap holds the link's own press until it fails, so the card squishes the
            // moment a finger lands, photo included.
            .gesture(FeedTouchDownTracker(isPressed: $linkPressed))

            // Under a photo that swipes, the dots that say which one is up (Instagram's).
            if swipes {
                PageDots(count: cardPhotos.count, page: pageShown)
            }

            // RSVP under the photo (rsvp-and-groups 01; Figma "Meetup depth": 12 pt below the
            // photo, 2 pt above the row), or under the dots' row. Called off, a red "Canceled"
            // pill and no count.
            if let rsvp = actions.rsvp(item) {
                RSVPArea(item: item, words: rsvp, onInvite: onShare)
                    .padding(.top, swipes ? 0 : 12)
                    .padding(.horizontal, DailyFeedMetric.contentInset)
                    .transition(.opacity)
            }

            actionRow
                .padding(.top, 2)
                .padding(.horizontal, DailyFeedMetric.contentInset)
        }
        // Over the host row's end, outside the link: pressing it neither squishes nor
        // opens the card.
        // Join first: the ••• wins where their touch areas meet, and VoiceOver reads Join first.
        .overlay(alignment: .topTrailing) { groupJoin }
        .overlay(alignment: .topTrailing) { menuButton }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // The whole card answers the link's press, action row included, so no gap
        // opens between the squished part and the row under it.
        .scaleEffect(FeedMotion.pressScale(isPressed: linkPressed, reduceMotion: motionIsReduced))
        .opacity(FeedMotion.pressOpacity(isPressed: linkPressed, reduceMotion: motionIsReduced))
        .animation(FeedMotion.pressAnimation(reduceMotion: motionIsReduced), value: linkPressed)
        .sheet(isPresented: $menuPresented) {
            if let why = item.why {
                FeedCardMenu(why: why, score: item.score, report: currentPhoto.report(place: item.whereLine))
            }
        }
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
        .onDisappear { actions.cardClosed(item.id, group: item.groupID) }
        .task { await runDebugAutoplay() }
        .task { await openMenuForDebug() }
    }

    // MARK: - Host

    /// A Town feed card always has the row, for its •••; anywhere else a card with no
    /// host has none.
    private var showsHostRow: Bool { !item.hostName.isEmpty || item.why != nil }

    /// Who is putting this on, above the photograph. A missing host draws no
    /// placeholder — the headline is still the card — only the room for the •••.
    @ViewBuilder
    private var hostRow: some View {
        if !item.hostName.isEmpty {
            HStack(spacing: 10) {
                hostAvatar

                Text(item.hostName)
                    .font(.sansSemibold(14))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                Spacer(minLength: 8)
            }
            .padding(.trailing, hostRowRoom)
            .accessibilityElement(children: .combine)
        } else if item.why != nil {
            Color.clear.frame(height: Self.hostAvatarSide)
        }
    }

    /// Kept clear at the host row's end: the •••, and Join with its gap.
    private var hostRowRoom: CGFloat {
        let menu = item.why == nil ? 0 : Self.menuRoom
        guard showsGroupJoin else { return menu }
        return (item.why == nil ? 8 : menu + Self.groupPillGap) + groupPillWidth
    }

    /// A group you weren't in when the feed read it, or joined here, or left since, once Join can
    /// work: no Join before the account exists, as no RSVP.
    private var showsGroupJoin: Bool {
        guard let groupID = item.groupID, actions.canAct else { return false }
        return !item.inGroup || joinedHere || !actions.member(groupID: groupID, inGroup: item.inGroup).isMember
    }

    /// Meetup's charcoal pill beside the group's name, outside the card's link, so pressing it
    /// never squishes the card. One tap joins: it turns white, "Joined", over the RSVP pill's
    /// 0.18 s, and the Group page agrees (one `RealLifeActions` entry). Joined only squishes:
    /// leaving stays on the Group page (Jesse, 2026-10-19). A refused join holds, turns back, then
    /// shakes.
    @ViewBuilder
    private var groupJoin: some View {
        if showsGroupJoin, let groupID = item.groupID {
            let isMember = actions.member(groupID: groupID, inGroup: item.inGroup).isMember
            let failures = actions.memberFailureCount(groupID)
            Button {
                guard !isMember else { return }
                groupTappedAt = failures
                joinedHere = true
                actions.toggleMember(groupID: groupID, inGroup: item.inGroup)
            } label: {
                Text(isMember ? "Joined" : "Join")
                    .font(.sansSemibold(Self.groupPillWord))
                    .contentTransition(.opacity)
            }
            .buttonStyle(MeetupPillStyle(height: Self.groupPillHeight, minWidth: 0, light: isMember,
                                         sidePadding: Self.groupPillSide))
            // Only the card the tap came from shakes: the group's failures are every card's.
            .turnBackShake(failures: failures, shakes: !motionIsReduced && joinedHere && groupTappedAt != failures)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { groupPillWidth = $0 }
            .animation(.easeInOut(duration: motionIsReduced ? 0.15 : RealLifeActions.flip), value: isMember)
            .accessibilityLabel("\(isMember ? "Joined" : "Join") \(item.hostName)")
            // Joined does nothing but squish, so VoiceOver doesn't offer it as a button.
            .accessibilityRemoveTraits(isMember ? .isButton : [])
            // Centred on the 32 pt host row, 10 pt before the dots.
            .padding(.top, (Self.hostAvatarSide - Self.groupPillHeight) / 2)
            .padding(.trailing, DailyFeedMetric.contentInset + (item.why == nil ? 0 : Self.menuDots + Self.groupPillGap))
        }
    }

    /// The card's ••• menu (`FeedCardMenu`), on the Town feed's own cards.
    @ViewBuilder
    private var menuButton: some View {
        if item.why != nil {
            Button { menuPresented = true } label: {
                Image("Lucide/ellipsis")
                    .resizable()
                    .frame(width: Self.menuGlyph, height: Self.menuGlyph)
                    .foregroundStyle(Hue.ink)
                    .frame(width: Self.menuTarget, height: Self.menuTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MenuPressStyle())
            .padding(.trailing, DailyFeedMetric.contentInset - Self.menuDotsInset)
            // Centred on the 32pt host row.
            .offset(y: (Self.hostAvatarSide - Self.menuTarget) / 2)
            .accessibilityLabel("More options")
        }
    }

    private var hostAvatar: some View {
        FeedAuthorAvatar(
            url: item.hostAvatar,
            name: item.hostName,
            side: Self.hostAvatarSide
        )
    }

    // MARK: - Image

    /// What the card shows: its picture, or ink once that picture has failed to load.
    private var displayImage: FeedCardImageSource {
        if let url = item.image.url, url == failedPhoto { return .fallback }
        return item.image
    }

    /// The event's own photo and its place's, each once, at most three (the Event page shows
    /// the same). Nothing leaves when it fails: it stays ink, so the card never shrinks.
    private var cardPhotos: [FeedCardImageSource] { item.photos() }

    /// Two or more photos swipe, under dots; one doesn't.
    private var swipes: Bool {
        FeedEventDetailDestination.counterText(page: 0, count: cardPhotos.count) != nil
    }

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
                    // What a photo rubber-banding sideways shows beside it: the ink it loads on.
                    .background(Hue.ink)
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
        .aspectRatio(dynamicTypeSize.isAccessibilitySize ? 1 : CGFloat(item.image.cardAspect), contentMode: .fit)
        .frame(maxWidth: .infinity)
        // INSIDE the clip — the picture's own edge is what takes the heart away.
        .feedCardLikeBurst(likeBurst, reduceMotion: motionIsReduced)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // Along the top: the day and time on the left, the photo's credit on the right, so
        // the title has the photo's whole width below (picked 2026-10-19: under the narrower
        // inset card, a credit beside the title cut "Plant Bingo for Angel Reins" short).
        .overlay(alignment: .top) {
            HStack(alignment: .center, spacing: 8) {
                if let when = item.whenLine {
                    PhotoChip(text: when.text, spoken: when.spoken)
                        .layoutPriority(1)
                }
                Spacer(minLength: 0)
                // Without its own edge inset, so it sits as far in as the chip and, shorter
                // than the chip, never moves the row when the photo lands and it appears.
                PhotoCredit(names: creditNames)
                    .padding(-PhotoCredit.edgeInset)
                    // Fades in with its photo, and across to the next one's on a swipe.
                    .animation(motionIsReduced ? nil : Motion.smooth, value: creditNames)
            }
            .frame(minHeight: PhotoChip.height)
            .padding(PhotoChip.inset)
            // VoiceOver reads the title first, then when.
            .accessibilitySortPriority(-1)
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 0) {
                imageCopy
                // Without this the HStack shrinks to its content and the overlay CENTRES
                // it — a short headline ("Farmers Market") floated to the middle of the
                // photograph. The copy is ranged left off the picture's bottom-left
                // corner, always.
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .contentShape(Rectangle())
        // Both kinds carry a heart in the row below, so the double-tap always has a
        // control to mirror — and something on screen you can undo it with.
        // The link waits for this to fail before it pushes, so a single tap on the
        // photo opens the page `PhotoDoubleTap.window` after the finger lifts, and a
        // double tap likes without opening it (`EventCardPhotoTapTests`).
        .gesture(PhotoDoubleTap { performImageLike(at: $0) })
        .padding(.horizontal, DailyFeedMetric.contentInset)
    }

    @ViewBuilder
    private var imageContent: some View {
        if swipes {
            // The Event page's carousel: it pages under the finger. Waits on ink, and stays
            // out of VoiceOver here: the card reads as one link, and its page has the carousel.
            PhotoPager(urls: cardPhotos.compactMap(\.url), page: $photoPage, shown: $shownPhotos, value: "",
                       onFailure: { _ in }, skeleton: false)
                .accessibilityHidden(true)
        } else if let url = displayImage.url {
            // One photo in the same pager, rubber-banding sideways: a sideways swipe used to
            // open the Event page as if it were a tap (seen 2026-10-20).
            PhotoPager(urls: [url], page: $photoPage, shown: $shownPhotos, value: "",
                       onFailure: { failedPhoto = $0 }, skeleton: false, bounces: true)
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

    /// Recurrence and place, under the title. Date and time ride the chip on the photo
    /// (Jesse, 2026-10-19), which replaced their line, which replaced the yellow date
    /// banner (2026-09-24).
    private var metaSummary: String {
        [item.recurrence, item.whereLine]
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
            onShare: onShare
        )
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
        guard item.id == "e1", ProcessInfo.processInfo.arguments.contains("-town-menu-open") else { return }
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
private struct FeedTouchDownTracker: UIGestureRecognizerRepresentable {
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

/// The •••'s press, as the approved Check-in 1 mock drew it: it shrinks to 0.88 over a
/// faint disc on touch-down and springs back the way it went.
private struct MenuPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Hue.ink.opacity(configuration.isPressed ? 0.06 : 0), in: Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

/// The link draws nothing on press: the card's squish comes from `FeedTouchDownTracker`.
private struct FeedCardLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Double-tap-to-like on the photo, with a window the card owns. The link waits for
/// this to fail before it pushes, so the window IS a single tap's delay. SwiftUI's own
/// double tap waited ~0.5 s after the finger lifted (measured 2026-09-25); this one
/// fails `window` after it.
private struct PhotoDoubleTap: UIGestureRecognizerRepresentable {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo \(page + 1) of \(count)")
        .accessibilityIdentifier("card-photo-dots")
    }
}
