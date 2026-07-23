//
//  POILogoView.swift
//  Block Party — a POI's brand logo clipped to a marker circle.
//
//  Renders nothing when the POI has no resolved logo, so every call site keeps its
//  existing category glyph as the underlying fallback layer and integrating a logo
//  is a one-line addition (pin badge, selected marker, detail header).
//

import SwiftUI

struct POILogoCircle: View {
    let poi: POI
    let diameter: CGFloat
    /// Draw a 1pt hairline on the logo's own edge — for call sites whose underlying
    /// circle has no keyline of its own (the detail header). The pin badges keep
    /// their existing stroke outside the logo instead.
    var showsHairline: Bool = false

    @ObservedObject private var cache = POILogoCache.shared

    var body: some View {
        let image = cache.resolvedImage(for: poi)
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .overlay {
                        if showsHairline {
                            Circle().stroke(Hue.hairline, lineWidth: 1)
                        }
                    }
                    .transition(.opacity)
            }
        }
        // Fades in once when the prefetch lands; a cached logo is present on the
        // first frame and never animates out.
        .animation(Motion.smooth, value: image != nil)
        .allowsHitTesting(false)
    }
}
