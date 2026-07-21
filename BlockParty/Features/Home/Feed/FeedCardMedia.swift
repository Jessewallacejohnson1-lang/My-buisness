//
//  FeedCardMedia.swift
//  Block Party — feed-card image loading and image-source presentation helpers.
//

import SwiftUI
import UIKit

struct FeedCardURLPhoto: View {
    let url: URL

    var body: some View {
        if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
            configured(Image(uiImage: image))
        } else {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    configured(image)
                } else {
                    Rectangle().fill(Hue.fill)
                }
            }
        }
    }

    private func configured(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
    }
}

extension FeedCardImageSource {
    var isPhoto: Bool {
        switch self {
        case .eventPhoto, .placesPhoto: true
        case .fallback: false
        }
    }

    var attribution: String? {
        if case .placesPhoto(_, let attribution) = self { attribution } else { nil }
    }

    var isFallback: Bool {
        if case .fallback = self { true } else { false }
    }
}
