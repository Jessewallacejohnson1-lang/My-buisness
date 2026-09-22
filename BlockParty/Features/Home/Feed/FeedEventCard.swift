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
//  else on the card and carries a real corner, so an event reads as a cut card sunk
//  into the page rather than a photo running off both bezels (Jesse, 2026-09-19 —
//  postings still run edge to edge, which is what now tells the two kinds apart).
//
//  The headline face is the SYSTEM face (`.sansBold`), not the display face: Apple
//  News sets its headlines in SF, and that is the reference Jesse gave.
//

import SwiftUI
import UIKit

struct FeedEventCard: View {
    let item: FeedCardItem
    let comments: [EventComment]
    let onLike: ((Bool) -> Void)?
    let onSave: ((Bool) -> Void)?
    let onLoadComments: (() async throws -> [EventComment])?
    let onComment: ((String) async throws -> EventComment)?
    let onShare: (() -> Void)?
    /// Which action controls this card offers. Defaults to `.posting` so the Town
    /// pipeline and the DEBUG galleries keep the row they were built against; the
    /// Daily feed passes `.event`, which drops comments but keeps the heart.
    let actionKind: FeedActionKind
    let debugAutoplay: Bool

    /// The photo's shape. Apple News runs its lead image at roughly 3:2; this card
    /// used to be 5:4, which is most of a phone screen per event.
    private static let mediaAspect: CGFloat = 3.0 / 2.0

    /// The host avatar. An avatar beside a name is a mark at a size the row is drawn
    /// around, not text, so it does not scale.
    private static let hostAvatarSide: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// Read so the card's one-line labels can take a second line at accessibility
    /// sizes. The same trade `PostingCard`'s header already makes: a clipped line is
    /// worse than a taller card.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var resolvedVenuePhoto: ResolvedVenuePhoto?
    @State private var venuePhotoDecoded = false
    @State private var actionState: FeedCardActionState
    @State private var commentState: FeedCommentState
    @State private var commentsPresented = false
    @State private var likeBurst = FeedLikeBurst()
    @State private var autoplayStep = 0

    init(
        item: FeedCardItem,
        comments: [EventComment] = [],
        onLike: ((Bool) -> Void)? = nil,
        onSave: ((Bool) -> Void)? = nil,
        onLoadComments: (() async throws -> [EventComment])? = nil,
        onComment: ((String) async throws -> EventComment)? = nil,
        onShare: (() -> Void)? = nil,
        actionKind: FeedActionKind = .posting,
        debugAutoplay: Bool = false
    ) {
        self.item = item
        self.comments = comments
        self.onLike = onLike
        self.onSave = onSave
        self.onLoadComments = onLoadComments
        self.onComment = onComment
        self.onShare = onShare
        self.actionKind = actionKind
        self.debugAutoplay = debugAutoplay
        _actionState = State(initialValue: FeedCardActionState(item: item))
        _commentState = State(initialValue: FeedCommentState(comments: comments))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hostRow
                .padding(.horizontal, DailyFeedMetric.contentInset)

            imageSection
                .padding(.top, item.hostName.isEmpty ? 0 : 10)

            socialRow
                .padding(.top, 10)
                .padding(.horizontal, DailyFeedMetric.contentInset)

            actionRow
                .padding(.top, 2)
                .padding(.horizontal, DailyFeedMetric.contentInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .sheet(isPresented: $commentsPresented) {
            FeedCommentSheet(
                commentState: $commentState,
                onLoad: onLoadComments,
                onSend: onComment
            )
        }
        .onChange(of: item) { _, updatedItem in
            actionState.sync(with: updatedItem)
        }
        .task(id: item.image) { await resolveVenuePhoto() }
        .task { await runDebugAutoplay() }
    }

    // MARK: - Host

    /// Who is putting this on, above the photograph. A missing host draws nothing
    /// rather than a placeholder — the headline is still the card.
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
            .accessibilityElement(children: .combine)
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

    /// A resolved venue photo, tagged with the lookup that produced it — so a card
    /// whose item changed under it can tell "already resolved" from "someone else's
    /// photo" without ever flashing the wrong venue.
    private struct ResolvedVenuePhoto {
        let lookup: FeedCardImageSource
        let image: FeedCardImageSource
    }

    /// The source whose bitmap the hero LOADS. As soon as the venue resolves the
    /// download starts here — even while the typography still shows the fallback (see
    /// `displayImage`), so the photo decodes behind the flat-ink beat, not after it.
    private var loadedSource: FeedCardImageSource {
        guard case .venueLookup = item.image else { return item.image }
        guard let resolved = resolvedVenuePhoto, resolved.lookup == item.image
        else { return .fallback }
        return resolved.image
    }

    /// What the card's TYPOGRAPHY and scrim reflect. A resolved venue photo only
    /// counts once its bitmap has actually decoded (`venuePhotoDecoded`), so the card
    /// never sits in the half-state the 0.25 s ease was meant to prevent: a scrim
    /// gradient over an undownloaded flat-ink frame. Every non-`venueLookup` source
    /// is already final and shows immediately.
    private var displayImage: FeedCardImageSource {
        guard case .venueLookup = item.image else { return item.image }
        guard venuePhotoDecoded, let resolved = resolvedVenuePhoto, resolved.lookup == item.image
        else { return .fallback }
        return resolved.image
    }

    /// The photographer credit for the photo currently on screen, in the array form
    /// `PhotoCredit` takes. Empty unless a Places photo is actually displayed, so the
    /// credit can never render over the ink fallback.
    private var creditNames: [String] {
        guard let attribution = displayImage.attribution else { return [] }
        return [attribution]
    }

    /// The one place the feed spends a billed Google call. It runs from `.task`, so a
    /// card that never scrolls into view never costs anything, and `GooglePlacesService`
    /// caches + coalesces, so cards sharing a venue share one round-trip. A venue that
    /// can't be confidently identified simply stays on the fallback — no gray box, no
    /// spinner, no retry loop.
    private func resolveVenuePhoto() async {
        guard case .venueLookup(let name, let hint) = item.image else { return }
        // Same venue as the last appearance — displayImage is already showing it, so
        // don't drop it and re-render the fallback for a frame on the way back in.
        guard resolvedVenuePhoto?.lookup != item.image else { return }

        // A genuinely new venue — its photo hasn't decoded yet, so the card holds the
        // fallback until this lookup's bitmap is ready (see markVenuePhotoDecoded).
        venuePhotoDecoded = false

        let lookup = item.image
        let resolved = await FeedCardVenuePhoto.resolve(name: name, hint: hint)
        guard !Task.isCancelled, let resolved else { return }

        // No animation here: this only starts the download — imageContent shows the same
        // flat ink meanwhile. The single visible transition runs on decode, below.
        resolvedVenuePhoto = ResolvedVenuePhoto(lookup: lookup, image: resolved)
    }

    /// The resolved photo's bitmap has decoded and is on screen: flip the card's
    /// typography + scrim to photo-mode in one animation, joined to the cross-fade the
    /// image itself runs (`FeedCardDownsampledPhoto`) — so there is no hard cut and no
    /// undesigned half-state on the way in.
    private func markVenuePhotoDecoded() {
        guard !venuePhotoDecoded else { return }
        withAnimation(motionIsReduced ? nil : .easeOut(duration: 0.25)) {
            venuePhotoDecoded = true
        }
    }

    private var imageSection: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                imageContent
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if displayImage.isPhoto {
                    FeedCardPhotoScrim(imageHeight: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(Self.mediaAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        // INSIDE the clip — the picture's own edge is what takes the heart away.
        .feedCardLikeBurst(likeBurst, reduceMotion: motionIsReduced)
        .clipShape(RoundedRectangle(cornerRadius: DailyFeedMetric.mediaRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            // Copy and the ToS credit share ONE bottom-aligned row, so the copy's
            // available width is derived from the credit's measured width instead of a
            // hard-coded inset. They used to be two independent bottom overlays whose
            // fixed insets guaranteed they overlapped ("Karry Rood" landing on the meta
            // line).
            HStack(alignment: .bottom, spacing: 8) {
                imageCopy
                if creditNames.isEmpty {
                    // Without this the HStack shrinks to its content and the overlay
                    // CENTRES it — a short headline ("Farmers Market") floated to the
                    // middle of the photograph. The copy is ranged left off the
                    // picture's bottom-left corner, always.
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 8)
                    PhotoCredit(names: creditNames)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .topLeading) { dateBanner }
        .contentShape(Rectangle())
        // Both kinds carry a heart in the row below, so the double-tap always has a
        // control to mirror — and something on screen you can undo it with.
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { performImageLike(at: $0.location) }
        )
    }

    @ViewBuilder
    private var imageContent: some View {
        switch loadedSource {
        case .eventPhoto(let url), .placesPhoto(let url, _):
            FeedCardURLPhoto(url: url, onReady: markVenuePhotoDecoded)
        case .venueLookup, .fallback:
            Rectangle().fill(Hue.ink)
        }
    }

    // MARK: - Date banner

    /// When it is, floating at the top of the picture (Jesse, 2026-09-20).
    ///
    /// The app's one accent, `Hue.brandYellowHex`, at full strength — not the 68%
    /// wash the map disc carries, because this sits on a photograph and a translucent
    /// yellow would take its hue from whatever happened to be behind it. Ink on
    /// yellow, which is the logo's own pairing.
    ///
    /// It hugs its text rather than running the full width: DESIGN.md scopes yellow
    /// to small accents, and a full-bleed yellow strip would make the accent the
    /// loudest thing in the feed. Same reason it carries no shadow — the card is
    /// meant to sit IN the page, so nothing on it gets lifted off the picture.
    @ViewBuilder
    private var dateBanner: some View {
        if !item.dateChip.isEmpty {
            Text(item.dateChip.uppercased())
                .font(.sansBold(12))
                .tracking(0.6)
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: Hue.brandYellowHex))
                )
                .padding(12)
                .accessibilityLabel(item.dateChip)
        }
    }

    // MARK: - Copy over the photograph

    private var imageCopy: some View {
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
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !metaSummary.isEmpty {
                Text(metaSummary)
                    .font(.sans(13))
                    .foregroundStyle(.white.opacity(0.85))
                    // Unbounded at accessibility sizes, not two lines: measured
                    // 2026-09-22, "7pm · Millstream Park" still clipped at two, and
                    // it was the LAST finding left on Town at both AX3 and AX5. A
                    // meta line that runs to three lines covers a little more of the
                    // photograph; a clipped one loses the time and the place.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .feedCardPhotoTypeShadow()
    }

    /// Date, recurrence and time/place as one line — what used to be a chip floating
    /// in the photograph's top corner plus a meta line under the title.
    private var metaSummary: String {
        // No `dateChip` — the date is the banner at the top of the picture now
        // (Jesse, 2026-09-20), and printing it twice on one photograph read as a
        // mistake rather than as emphasis.
        [item.recurrence, item.metaLine]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Social

    private var socialRow: some View {
        HStack(spacing: 8) {
            if !item.goingAvatars.isEmpty {
                FeedCardFacepile(
                    neighborAvatars: item.goingAvatars,
                    goingCount: item.goingCount,
                    reduceMotion: motionIsReduced
                )
            }

            Text(item.goingSummary)
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .layoutPriority(1)
        }
        .frame(minHeight: 24)
    }

    private var actionRow: some View {
        FeedEventCardActionRow(
            kind: actionKind,
            state: $actionState,
            reduceMotion: motionIsReduced,
            autoplayStep: autoplayStep,
            onLike: onLike,
            onSave: onSave,
            onComment: { commentsPresented = true },
            onShare: onShare
        )
    }

    private var motionIsReduced: Bool {
        accessibilityReduceMotion
    }

    private func performImageLike(at point: CGPoint?) {
        let changed = !actionState.isLiked

        withAnimation(motionIsReduced ? .easeInOut(duration: 0.15) : Motion.snappy) {
            _ = actionState.like()
        }
        likeBurst.fire(at: point)

        if changed { onLike?(true) }
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
