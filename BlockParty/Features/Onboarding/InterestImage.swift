//
//  InterestImage.swift
//  Block Party — resolves an interest card's photo. A real local photo wins if present;
//  otherwise the bundled seed art; otherwise nil so the card draws a calm tinted
//  fallback (no gradient slop) and never crashes. Drop a real St. Joe photo named
//  the same and it takes over with zero code changes (hybrid imagery — see spec).
//

import SwiftUI

enum InterestImage {
    static func image(for id: String) -> Image? {
        let name = "interest-\(id)"
        // A real-photo override ("LocalPhotos/interest-<id>") wins if added.
        if UIImage(named: "LocalPhotos/\(name)") != nil { return Image("LocalPhotos/\(name)") }
        if UIImage(named: name) != nil { return Image(name) }
        return nil
    }
}
