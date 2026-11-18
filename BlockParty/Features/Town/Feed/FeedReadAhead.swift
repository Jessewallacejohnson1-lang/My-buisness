//
//  FeedReadAhead.swift
//  Block Party — a list asks for the pictures of the cards below the screen before they scroll on, so a card
//  comes on with its photo, logos and faces already drawn (Jesse, 2026-11-17: "before you scroll, everything is
//  already preloaded for the next like 2 chunks"; BP app tab-lag 03).
//

import Network
import SwiftUI

/// What one card draws from the network: photos with the frame each fills (points), logos (`POILogoCache`) and
/// round faces.
struct FeedPictures: Equatable {
    struct Photo: Equatable {
        let url: URL
        let box: CGSize
        var fit = false
    }

    var photos: [Photo] = []
    var logos: [URL] = []
    var faces: [URL] = []
    /// About how tall the card stands, for how many cards make two screens.
    var height: CGFloat = 140

    /// The largest face a card draws (the white card's 56 pt mark): one read serves every smaller one.
    static let face = CGSize(width: 56, height: 56)

    /// An Event card `width` points wide: its photo at the card's own shape (a flyer whole, over its wash), else a
    /// game's two logos or its place's logo; the host's and its collaborators' logos; the faces going.
    static func of(_ item: FeedCardItem, width: CGFloat, aspect: Double? = nil) -> FeedPictures {
        var pictures = FeedPictures()
        if let game = item.game {
            pictures.logos += game.teams.compactMap(\.logo)
            pictures.height = 196 + 60
        } else if let url = item.image.url {
            // A flyer shows whole, and its blurred wash draws that same bitmap at once.
            let box = item.whole ? CGSize(width: width, height: width / CGFloat(item.image.flyerAspect))
                : CGSize(width: width, height: width / CGFloat(aspect ?? item.image.cardAspect))
            pictures.photos.append(Photo(url: url, box: box, fit: item.whole))
            pictures.height = box.height + 60
        } else if case .placeLogo(let picture) = item.image {
            pictures.logos.append(picture.url)
        }
        for picture in [item.hostPicture] + item.collabs.map(\.picture) {
            guard let picture else { continue }
            if picture.kind == .logo { pictures.logos.append(picture.url) } else { pictures.faces.append(picture.url) }
        }
        pictures.faces += [item.hostAvatar].compactMap { $0 } + item.friendsGoing.compactMap(\.photo)
            + item.goingAvatars.prefix(3)
        return pictures
    }
}

extension TownFeedItem {
    /// The pictures this Town card draws in a column `width` points wide.
    func pictures(width: CGFloat) -> FeedPictures {
        let inset = width - 2 * TownFeedMetric.contentInset
        switch self {
        case .event(let item), .again(.event(let item), _):
            return .of(item, width: inset)
        case .eventOfTheDay(let event):
            // The poster's photo is square (a flyer whole, as on a card).
            return .of(event.item, width: inset, aspect: 1)
        case .news(let news), .again(.news(let news), _):
            var pictures = FeedPictures()
            if let photo = news.photoSource, let url = photo.url {
                let box = CGSize(width: inset, height: inset / CGFloat(photo.cardAspect))
                pictures.photos.append(.init(url: url, box: box))
                pictures.height = box.height + 60
            }
            if let picture = news.picture, picture.kind == .logo { pictures.logos.append(picture.url) }
            return pictures
        case .post(let post), .again(.post(let post), _):
            var pictures = FeedPictures()
            let box = CGSize(width: inset, height: inset / CGFloat(post.photoAspect))
            // The first photo only: the rest wait for a swipe.
            pictures.photos = post.photos.prefix(1).map { .init(url: $0, box: box) }
            pictures.faces = [post.posterPhoto].compactMap { $0 }
            if !post.photos.isEmpty { pictures.height = box.height + 120 }
            return pictures
        case .posting(let posting):
            var pictures = FeedPictures()
            let box = CGSize(width: width, height: width * 5 / 4)
            if let url = posting.image.url { pictures.photos.append(.init(url: url, box: box)) }
            pictures.faces = [posting.authorAvatar].compactMap { $0 }
            pictures.height = box.height + 120
            return pictures
        case .place(let place, _):
            return FeedPictures(logos: [place.logo?.url].compactMap { $0 })
        case .caughtUp:
            return FeedPictures()
        }
    }
}

/// Asks for the pictures of the cards after the one that just came on, down to two screens below it: one
/// with Low Data Mode on (Jesse, 2026-11-17). Each is asked for once; the loaders skip what they already have.
@MainActor
enum FeedReadAhead {
    /// A screen's height over its width on every iPhone this app runs on (19.5:9).
    static let screen: CGFloat = 2.17

    /// The cards after `index`, of `count`, whose pictures to ask for: as many as fill `screens` screens of a
    /// `width`-point column, `height` saying how tall each stands. Only those cards are looked at.
    nonisolated static func ahead(count: Int, after index: Int, width: CGFloat, screens: CGFloat,
                                  height: (Int) -> CGFloat) -> Range<Int> {
        let start = min(max(index + 1, 0), count)
        var end = start, room = screens * screen * width
        while end < count, room > 0 {
            room -= height(end)
            end += 1
        }
        return start..<end
    }

    static func read(_ items: [TownFeedItem], after index: Int, width: CGFloat, scale: CGFloat) {
        guard width > 0 else { return }
        var cards: [Int: FeedPictures] = [:]
        let range = ahead(count: items.count, after: index, width: width, screens: screens) { at in
            let card = items[at].pictures(width: width)
            cards[at] = card
            return card.height
        }
        for card in range.compactMap({ cards[$0] }) {
            for photo in card.photos {
                FeedCardImageLoader.shared.readAhead(photo.url, box: photo.box, scale: scale, fit: photo.fit)
            }
            for face in card.faces { FeedCardImageLoader.shared.readAhead(face, box: FeedPictures.face, scale: scale) }
            // A logo that failed (a missing file) isn't asked again on every card that comes on.
            POILogoCache.shared.prefetch(card.logos.filter { !POILogoCache.shared.failed.contains($0) })
        }
    }

    /// Two screens, one with Low Data Mode on.
    static var screens: CGFloat { network.currentPath.isConstrained ? 1 : 2 }

    private static let network: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "feed-read-ahead.network"))
        return monitor
    }()
}

