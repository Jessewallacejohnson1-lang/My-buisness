//
//  FeedCardVenuePhoto.swift
//  Block Party — turns a feed card's `venueLookup` intent into a displayable
//  Google Places photo, through the Locked Rule A confidence gate
//  (`GooglePlacesService.confidentPhoto(forFreeText:hint:)`). It hands back a
//  `FeedCardImageSource` so the card (and the event page) keeps FeedCardURLPhoto's
//  downsampling + LRU cache instead of loading through a raw AsyncImage.
//
//  Google ToS: the photo NAME is used to build a media URL here and then dropped
//  with the view — it is never persisted (no Supabase column, no UserDefaults, no
//  disk). The author attributions ride along on `.placesPhoto` because they must
//  be displayed wherever the image appears.
//

import Foundation

@MainActor
enum FeedCardVenuePhoto {
    /// Pixel width asked of the Photo endpoint. A feed hero is the full card width
    /// (screen minus the 16pt gutters) at 3x — ~1,100 px on the widest phone. Google
    /// bills the media request, not the pixels, so asking large costs nothing extra.
    private static let heroPixelWidth = 1_200

    /// nil when the venue can't be confidently identified, or when it has no photo —
    /// the card then keeps its fallback treatment. Never throws: `GooglePlacesService`
    /// fails soft, caches per venue, and coalesces concurrent callers, so several
    /// cards sharing one venue cost a single billed round-trip.
    static func resolve(name: String, hint: String?) async -> FeedCardImageSource? {
        await GooglePlacesService.shared.confidentPhoto(forFreeText: name, hint: hint).map(source)
    }

    /// `resolve`'s answer when it is already known, with no network call: `.some(nil)`
    /// is a known "no photo", nil means only `resolve` can tell.
    static func known(name: String, hint: String?) -> FeedCardImageSource?? {
        GooglePlacesService.shared.knownConfidentPhoto(forFreeText: name, hint: hint).map { $0.map(source) }
    }

    private static func source(_ photo: ConfidentPhoto) -> FeedCardImageSource {
        .placesPhoto(
            GooglePlacesService.shared.photoURL(name: photo.photoName, maxWidth: heroPixelWidth),
            attribution: photo.attributions.joined(separator: ", ")
        )
    }
}
