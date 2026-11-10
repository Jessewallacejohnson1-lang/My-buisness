//
//  FeedCardMedia.swift
//  Block Party — feed-card image loading and image-source presentation helpers.
//

import Foundation
import ImageIO
import SwiftUI
import UIKit
import Vision
#if targetEnvironment(simulator)
import CoreML  // MLComputeDevice, for Vision on the simulator's CPU (`FeedCardImageLoader.focus(of:)`)
#endif

struct FeedCardURLPhoto: View {
    let url: URL
    /// Fired once the downsampled bitmap has actually decoded and is on screen. The
    /// feed card uses it to hold its fallback typography until the photo exists, so it
    /// never animates into photo-mode over an undownloaded flat-ink frame.
    var onReady: (() -> Void)? = nil
    /// Fired once when the bitmap could not be loaded at all, so a caller can drop
    /// the photo instead of holding a placeholder over it forever.
    var onFailure: (() -> Void)? = nil
    /// What shows while the photo loads. Ink suits a card whose white title already
    /// sits on top; Search's tiles keep their own lighter fill showing through instead.
    var loadingFill: Color = Hue.ink
    /// Not nil, a flyer: whole above this many points at the frame's foot, reaching two opposite edges of
    /// what's left with even gaps on the other two, over a blurred copy of itself that fills the frame
    /// (Jesse, 2026-11-05, BP app event-photos 16). Nil fills, as every other photo does.
    var whole: CGFloat? = nil
    /// With `whole`, what a flyer that reaches its frame's top rather than its sides starts under: on the
    /// Event page the clock, so the island never covers a tall poster's title (Jesse, 2026-11-05).
    var wholeTop: CGFloat = 0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            FeedCardDownsampledPhoto(
                request: FeedCardImageRequest(
                    url: url,
                    maxPixelSize: Self.pixelWidth(points: proxy.size.width, scale: displayScale)
                ),
                box: proxy.size,
                onReady: onReady,
                onFailure: onFailure,
                loadingFill: loadingFill,
                whole: whole,
                wholeTop: wholeTop
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The width to decode at, from whole points: the event page's hero measures
    /// 420.33 pt on iPhone Air, and rounding its pixels up asked for 1261 px against
    /// its card's 1260, so one photo decoded twice and took two of the cache's slots.
    static func pixelWidth(points: CGFloat, scale: CGFloat) -> Int {
        max(1, Int(points.rounded() * scale))
    }

    /// What a flyer keeps clear above it: `top` when it would reach the top and foot of its room, none
    /// when it reaches the sides, since a wide one sits with even gaps, clear of the island anyway.
    nonisolated static func flyerTop(image: CGSize, room: CGSize, top: CGFloat) -> CGFloat {
        guard image.height > 0, room.height > 0 else { return 0 }
        return image.width / image.height < room.width / room.height ? top : 0
    }

    /// How far to move a photo filling `box` so its focus sits as near the middle as the photo's
    /// edges allow: a face near a tall photo's top stays in a wide frame (Jesse, 2026-10-31: "the
    /// heads are so high up you cant see them"). The centre moves nothing, as `scaledToFill` draws it.
    nonisolated static func offset(image: CGSize, box: CGSize, focus: UnitPoint) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(box.width / image.width, box.height / image.height)
        func shift(_ length: CGFloat, _ boxLength: CGFloat, _ at: CGFloat) -> CGFloat {
            let spare = max(length - boxLength, 0) / 2
            return min(max(length * (0.5 - at), -spare), spare)
        }
        return CGSize(width: shift(image.width * scale, box.width, focus.x),
                      height: shift(image.height * scale, box.height, focus.y))
    }
}

private struct FeedCardDownsampledPhoto: View {
    let request: FeedCardImageRequest
    let box: CGSize
    var onReady: (() -> Void)? = nil
    var onFailure: (() -> Void)? = nil
    var loadingFill: Color = Hue.ink
    var whole: CGFloat? = nil
    var wholeTop: CGFloat = 0

    /// The bitmap this view loaded, tagged with its URL so a view handed a new URL never
    /// shows the old photo.
    @State private var loaded: (url: URL, image: CGImage)?
    /// It has drawn here: reading it again on the way back on screen with no signal isn't a
    /// failed photo, which its card would drop for good.
    @State private var shownOnce = false

    /// What to draw: this view's own bitmap, else the largest one already decoded for
    /// the same photo, so a photo on screen elsewhere draws here in the first frame.
    private var image: CGImage? {
        if let loaded, loaded.url == request.url { return loaded.image }
        return FeedCardImageLoader.shared.largest(for: request.url)
    }

    var body: some View {
        Group {
            if let image, let whole {
                flyer(image, clear: whole)
                    .transition(.opacity)
            } else if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .offset(FeedCardURLPhoto.offset(image: CGSize(width: image.width, height: image.height), box: box,
                                                    focus: FeedCardImageLoader.shared.focus(for: request.url)))
                    .transition(.opacity)
            } else {
                // Ink, not a light fill: the card's title is white and already sits on
                // top during this beat, so a pale placeholder would swallow it. This
                // way the load-in reads as the card's own fallback treatment.
                Rectangle().fill(loadingFill)
            }
        }
        .task(id: request) {
            let loadedImage = await FeedCardImageLoader.shared.image(for: request)
            guard !Task.isCancelled else { return }
            if let loadedImage {
                // Cross-fade the photograph in rather than hard-cutting it over the ink.
                withAnimation(.easeOut(duration: 0.2)) { loaded = (request.url, loadedImage) }
            }
            // A photo already on screen at another size has not failed.
            if image != nil {
                shownOnce = true
                onReady?()
            } else if !shownOnce {
                onFailure?()
            }
        }
        // Off screen it lets go, or a long scroll holds every photo it passed: 473 MB on Town at
        // 40 swipes, and iOS shuts the biggest apps down first (BP app backlog 21). On the way back
        // the loader's newest draw at once.
        .onDisappear { loaded = nil }
    }

    /// One bitmap drawn twice, so a flyer costs one download and one decode: blurred to fill the frame, as
    /// Instagram's wash behind a whole post, and whole over it. Opaque, so the blur's edges don't fade.
    private func flyer(_ image: CGImage, clear: CGFloat) -> some View {
        let bitmap = Image(decorative: image, scale: 1).resizable()
        let room = max(box.height - clear, 0)
        let top = FeedCardURLPhoto.flyerTop(image: CGSize(width: image.width, height: image.height),
                                            room: CGSize(width: box.width, height: room), top: wholeTop)
        return ZStack(alignment: .top) {
            bitmap
                .scaledToFill()
                .frame(width: box.width, height: box.height)
                .clipped()
                .blur(radius: Self.flyerBlur, opaque: true)
            bitmap
                .scaledToFit()
                .frame(width: box.width, height: max(room - top, 0))
                .padding(.top, top)
        }
    }

    /// PICKED on the mock (BP app `references/whole-flyer-frames/`): the flyer's words are gone from the wash.
    private static let flyerBlur: CGFloat = 30
}

private nonisolated struct FeedCardImageRequest: Hashable, Sendable {
    let url: URL
    let maxPixelSize: Int
}

/// Downsampled photos, the 24 used last, keyed by URL and pixel size, and beside them the 48
/// small ones used last (round faces: `Avatar`). On the main actor, so a view can draw a photo already decoded in the frame it appears; the
/// download and the decode run off it. Emptied on a memory warning. A photo shown
/// at another size (a venue photo on the page after its card) starts from
/// `largest(for:)`, never from a skeleton.
@MainActor
final class FeedCardImageLoader {
    static let shared = FeedCardImageLoader()

    private static let maxCachedImages = 24
    /// Faces keep their own room, so the feed's dozen big photos never push a face out and faces
    /// never push a photo out; 48 more faces than that still do. A 96 pt profile photo is 288 px.
    private static let maxCachedSmall = 48
    private static let smallPixels = 300
    private var cache: [FeedCardImageRequest: CGImage] = [:]
    private var cacheOrder: [FeedCardImageRequest] = []
    /// Where the eye goes in each photo, found once per URL and kept when its bitmap is dropped.
    private var focuses: [URL: UnitPoint] = [:]

    private init() {
        focuses = Self.keptFocuses()
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { FeedCardImageLoader.shared.letGo() }
        }
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                FeedCardImageLoader.shared.trimForLeaving()
                FeedCardImageLoader.shared.keepFocuses()
            }
        }
    }

    private func letGo() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    /// Leaving, it keeps the newest few photos and every face: cards on screen hold their own bitmaps,
    /// but those behind an Event page or another tab have let go, and these are what coming back draws.
    private static let keptOnLeaving = 6

    private func trimForLeaving() {
        for index in Self.droppedOnLeaving(cacheOrder.map(\.maxPixelSize)).sorted(by: >) {
            cache.removeValue(forKey: cacheOrder.remove(at: index))
        }
    }

    /// Which entries leaving drops, given each one's pixel size, oldest first.
    static func droppedOnLeaving(_ sizes: [Int]) -> [Int] {
        var photos = 0, drop: [Int] = []
        for index in sizes.indices.reversed() where sizes[index] > smallPixels {
            photos += 1
            if photos > keptOnLeaving { drop.append(index) }
        }
        return drop
    }

    /// Past this it starts over: a photo looked at again costs a moment, hundreds of old ones every launch.
    private static let maxKeptFocuses = 1000

    /// Kept on the phone, or after a restart each photo waits on Vision again with ink showing.
    private static func keptFocuses() -> [URL: UnitPoint] {
        guard let data = TownFeedCache.load(.photoFocus),
              let kept = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: kept.compactMap { key, spot in
            guard let url = URL(string: key), spot.count == 2 else { return nil }
            return (url, UnitPoint(x: spot[0], y: spot[1]))
        })
    }

    private func keepFocuses() {
        if focuses.count > Self.maxKeptFocuses { focuses.removeAll() }
        let kept = Dictionary(uniqueKeysWithValues: focuses.map { ($0.key.absoluteString, [Double($0.value.x), Double($0.value.y)]) })
        if let data = try? JSONEncoder().encode(kept) { TownFeedCache.save(data, .photoFocus) }
    }

    /// The largest bitmap decoded for this photo at any size. Largest, so a host's
    /// 96 px avatar cut from the same file never stands in for a full-width photo.
    func largest(for url: URL) -> CGImage? {
        cache.filter { $0.key.url == url }.values.max { $0.width < $1.width }
    }

    /// Where to centre this photo in a frame of another shape; the middle until it has been looked at.
    func focus(for url: URL) -> UnitPoint {
        focuses[url] ?? .center
    }

    fileprivate func image(for request: FeedCardImageRequest) async -> CGImage? {
        if let cached = cache[request] {
            touch(request)
            return cached
        }
        guard let thumbnail = await Self.decode(request) else { return nil }
        // Before it shows, so it never jumps. A small square one (a face in its circle) has nothing to cut.
        if focuses[request.url] == nil, request.maxPixelSize > Self.smallPixels || thumbnail.width != thumbnail.height,
           let spot = await Self.focus(of: thumbnail) {
            focuses[request.url] = spot
        }
        insert(thumbnail, for: request)
        return thumbnail
    }

    /// Where the eye goes, from the top left (0...1): the middle of the photo's faces, else of
    /// what Vision's attention saliency picks, else the middle; nil when Vision failed or was
    /// cancelled, so the next decode looks again. The place-photos skill's `focus.swift` draws
    /// the approval sheet with the same rule; change both together.
    @concurrent
    nonisolated static func focus(of image: CGImage) async -> UnitPoint? {
        // Closures, not `\.boundingBox` key paths: a key path links the setter iOS 27 added, and the
        // app then wouldn't launch on iOS 26.5 (2026-10-31).
        var faces = DetectFaceRectanglesRequest(), saliency = GenerateAttentionBasedSaliencyImageRequest()
        #if targetEnvironment(simulator)
        // The simulator gives Vision no Neural Engine or GPU ("Could not create inference context"):
        // its CPU, so a screenshot there shows what a phone does.
        let cpu = MLComputeDevice.allComputeDevices.first { if case .cpu = $0 { true } else { false } }
        faces.setComputeDevice(cpu, for: .main)
        saliency.setComputeDevice(cpu, for: .main)
        #endif
        guard var boxes = try? await faces.perform(on: image).map({ $0.boundingBox.cgRect }) else { return nil }
        if boxes.isEmpty {
            guard let salient = try? await saliency.perform(on: image) else { return nil }
            boxes = salient.salientObjects.map { $0.boundingBox.cgRect }
        }
        guard let first = boxes.first else { return .center }
        let box = boxes.dropFirst().reduce(first) { $0.union($1) }
        return UnitPoint(x: box.midX, y: 1 - box.midY)  // Vision measures from the bottom left
    }

    @concurrent
    private nonisolated static func decode(_ request: FeedCardImageRequest) async -> CGImage? {
        let source: CGImageSource?
        if request.url.isFileURL {
            source = CGImageSourceCreateWithURL(request.url as CFURL, nil)
        } else {
            guard let data = await remoteData(from: request.url) else { return nil }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }

        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: request.maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Its own cache on the phone, so photos are there after a restart: the default holds 10 MB and
    /// nothing over 500 KB, so each one came down again, fading in over ink (BP app backlog 21).
    private nonisolated static let photos: URLSession = {
        let config = URLSessionConfiguration.default
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("feed-photos")
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 300 << 20, directory: folder)
        return URLSession(configuration: config)
    }()

    private nonisolated static func remoteData(from url: URL) async -> Data? {
        do {
            let (data, response) = try await photos.data(from: url)
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                return nil
            }
            return data
        } catch {
            // No signal: the copy on the phone, however old, rather than a card losing its photo.
            return try? await photos.data(for: URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad)).0
        }
    }

    private func touch(_ request: FeedCardImageRequest) {
        cacheOrder.removeAll { $0 == request }
        cacheOrder.append(request)
    }

    private func insert(_ image: CGImage, for request: FeedCardImageRequest) {
        cache[request] = image
        touch(request)

        for index in Self.overflow(cacheOrder.map(\.maxPixelSize)).sorted(by: >) {
            cache.removeValue(forKey: cacheOrder.remove(at: index))
        }
    }

    /// Which entries to drop, given each one's pixel size, oldest first: all but the 24 newest
    /// photos and the 48 newest small ones.
    static func overflow(_ sizes: [Int]) -> [Int] {
        var photos = 0, small = 0, drop: [Int] = []
        for index in sizes.indices.reversed() {
            if sizes[index] <= smallPixels {
                small += 1
                if small > maxCachedSmall { drop.append(index) }
            } else {
                photos += 1
                if photos > maxCachedImages { drop.append(index) }
            }
        }
        return drop
    }
}

/// The scrim that keeps a card's overlaid white title legible on a real photograph.
///
/// The title had only ever been seen against flat ink, where a single 0 → 0.55 ramp
/// over the bottom 40% was plenty; a bright frame (a noon sky, a sunlit lawn) washed
/// it out. This covers more of the image so the ramp starts well above the copy, and
/// leans a little deeper at the very bottom — but it stays a shadow, not a black bar.
/// The last of the contrast is carried by `feedCardPhotoTypeShadow()` on the copy
/// itself, which is cheaper visually than blanketing the photograph.
struct FeedCardPhotoScrim: View {
    /// Height of the image this scrim sits on; the scrim covers `coverage` of it.
    let imageHeight: CGFloat
    /// Which edge the copy sits against. `.top` is the posting header floating over
    /// the photograph; it is a shorter, lighter ramp than the title's, because it
    /// carries one line of chrome rather than a headline.
    var edge: VerticalEdge = .bottom

    private static let coverage: CGFloat = 0.58
    private static let topCoverage: CGFloat = 0.3
    private static let stops: [Gradient.Stop] = [
        .init(color: .black.opacity(0), location: 0),
        .init(color: .black.opacity(0.18), location: 0.45),
        .init(color: .black.opacity(0.68), location: 1),
    ]
    private static let topStops: [Gradient.Stop] = [
        .init(color: .black.opacity(0.45), location: 0),
        .init(color: .black.opacity(0.14), location: 0.55),
        .init(color: .black.opacity(0), location: 1),
    ]

    var body: some View {
        LinearGradient(stops: edge == .bottom ? Self.stops : Self.topStops, startPoint: .top, endPoint: .bottom)
            .frame(height: imageHeight * (edge == .bottom ? Self.coverage : Self.topCoverage))
            // Shade only: a swipe or tap on it reaches the photo under it (Jesse, 2026-10-23).
            .allowsHitTesting(false)
    }
}

extension View {
    /// Soft ink halo for white type sitting directly on a photograph. The scrim does
    /// most of the work; this catches what a scrim can't — a bright patch landing
    /// exactly under a letterform.
    func feedCardPhotoTypeShadow(_ strength: Double = 1) -> some View {
        shadow(color: .black.opacity(0.35 * strength), radius: 6, y: 1)
    }
}

extension FeedCardImageSource {
    /// The photograph's address; nil for a logo and for ink.
    var url: URL? {
        switch self {
        case .eventPhoto(let url), .placePhoto(let url, _, _): url
        case .placeLogo, .fallback: nil
        }
    }

    /// Whether a photograph is on screen.
    var isPhoto: Bool { url != nil }

    /// The chip a place's photo carries wherever it shows: the site it came from, or a
    /// free photo's author and licence (MEMORY.md, 2026-11-01). nil when there is none, so
    /// no empty capsule renders.
    var attribution: String? {
        guard case .placePhoto(_, let credit?, _) = self, !credit.isEmpty else { return nil }
        return credit
    }

    /// Report photo, for a photo Block Party saved of a place (BP app place-photos 06); nil
    /// for the event's own photo, a logo and ink.
    func report(place: String?) -> PhotoReport? {
        guard case .placePhoto(let url, _, _) = self else { return nil }
        return PhotoReport(place: place, photo: url)
    }

    /// The card's shape, width over height: the photo's own, inside Instagram's limits (4:5
    /// tall to 1.91:1 wide; Jesse, 2026-10-19, BP app docs/plans/event-card); 3:2 for a photo
    /// of unknown size, a logo and ink.
    var cardAspect: Double {
        guard case .placePhoto(_, _, let aspect?) = self, aspect.isFinite, aspect > 0 else { return 3.0 / 2.0 }
        return min(max(aspect, 4.0 / 5.0), 1.91)
    }

    /// A whole flyer's room on a Town card or the poster, width over height: its own shape, at most 4:5 tall and
    /// never cut wide, so a 3:1 banner runs full width and short, and a taller one shrinks inside it (Jesse,
    /// 2026-11-10, BP app town-feed 57); square for one of unknown size.
    var flyerAspect: Double { max(ownAspect, 4.0 / 5.0) }

    /// The photo's own shape, width over height, uncut; square for one of unknown size.
    var ownAspect: Double {
        guard case .placePhoto(_, _, let aspect?) = self, aspect.isFinite, aspect > 0 else { return 1 }
        return aspect
    }

    /// A place's logo as Search draws it, on its backdrop with ink words over it.
    var logo: SearchLogo? {
        guard case .placeLogo(let picture) = self else { return nil }
        // A grey logo gets Search's studio hue, as on the logo wall.
        let row = SearchLogo.Row(url: picture.url, hue: picture.hue ?? Hue.searchStudioHue, chroma: picture.hue != nil)
        return SearchLogo(placeId: picture.url.absoluteString, row: row)
    }
}

/// A place we have no photo of, where its photo would be: its logo on its Search backdrop,
/// the logo's own shadow cast on it, centred in the room above the words over it, so a long
/// title never runs over it (Jesse, 2026-10-16: B). Sizes are picked, not measured: at most
/// half the frame's height and 40% of its width; the event page passes its own, so the logo
/// clears the clock and the round buttons above it.
struct FeedCardPlaceLogo: View {
    let logo: SearchLogo
    /// Share of the frame's height kept clear above the logo.
    var topShare: CGFloat = 0.06
    /// Share of the frame's height the logo is tall at most.
    var sideShare: CGFloat = 0.5
    /// How much of the frame's top a chip over it takes, kept clear.
    var topClear: CGFloat = 0
    /// How much of the frame's bottom the words over it take, kept clear.
    var bottomClear: CGFloat = 0

    /// Under this the logo would be a smudge, so the backdrop shows alone.
    private static let smallest: CGFloat = 40
    private static let gap: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let top = max(proxy.size.height * topShare, topClear)
            let room = proxy.size.height - top - bottomClear - Self.gap
            let side = min(proxy.size.height * sideShare, proxy.size.width * 0.4, room)
            ZStack(alignment: .top) {
                SearchBackdrop(colors: logo.backdrop)
                SearchFloor()
                if side >= Self.smallest {
                    CastLogo(logo: logo, side: side)
                        .padding(.top, top + (room - side) / 2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}
