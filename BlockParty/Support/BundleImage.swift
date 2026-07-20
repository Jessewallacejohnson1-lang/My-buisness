//
//  BundleImage.swift
//  Block Party — load photos bundled as loose resources (Resources/Images).
//
//  The around-town and weather photos are copied from the Expo app's assets and
//  ride along in the app bundle. UIImage(named:) doesn't resolve loose files by
//  base name reliably, so we look them up by name + extension and cache.
//

import SwiftUI
import UIKit

enum Photo {
    private static var cache: [String: UIImage] = [:]

    /// Load a bundled image by base name (no extension). Tries jpg then png.
    static func uiImage(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        for ext in ["jpg", "png", "jpeg"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let img = UIImage(contentsOfFile: url.path) {
                cache[name] = img
                return img
            }
        }
        return nil
    }
}

/// A SwiftUI Image for a bundled photo, with a graceful linen fallback.
struct PhotoView: View {
    let name: String
    var body: some View {
        if let ui = Photo.uiImage(name) {
            Image(uiImage: ui).resizable()
        } else {
            Rectangle().fill(Hue.paper200)
        }
    }
}
