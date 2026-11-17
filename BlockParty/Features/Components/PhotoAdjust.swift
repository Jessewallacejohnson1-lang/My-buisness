//
//  PhotoAdjust.swift
//  Block Party — Adjust: move and zoom a picked photo inside the frame it will show in, before it goes up (BP app
//  backlog 32; Jesse, 2026-11-17: yes to the mock https://claude.ai/artifact/VNkvCwR1n8jmAUc1DbhtbY,
//  `references/photo-adjust/`). One screen for a post's photos (the post's own shape or square, a tap on the photo in
//  New post), the profile photo (a circle) and the cover (the profile's shape), the last two opening by themselves
//  right after a pick. Apple's own zooming scroll view does the moving: it follows the finger, flings, stretches past
//  the edge and springs back so the frame stays filled, as Photos' crop does.
//

import SwiftUI
import UIKit

// MARK: - The arithmetic

/// Where a photo sits in its frame, as a part of the photo from 0 to 1 each way. Pure, so a test reads it.
nonisolated enum PhotoCrop {
    /// Zoom goes this far past filling the frame (the mock's 5x).
    static let maxZoom: CGFloat = 5

    /// The middle of the photo at the frame's shape: what every photo got before Adjust.
    static func middle(of image: CGSize, aspect: CGFloat) -> CGRect {
        guard image.width > 0, image.height > 0, aspect > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let wide = image.width / image.height
        if wide > aspect {
            let w = aspect / wide
            return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        }
        let h = wide / aspect
        return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
    }

    /// The zoom at which the photo just fills the frame.
    static func fill(_ image: CGSize, frame: CGSize) -> CGFloat {
        guard image.width > 0, image.height > 0 else { return 1 }
        return max(frame.width / image.width, frame.height / image.height)
    }

    /// The part of the photo inside the frame, for a scroll at `offset` and `zoom` whose content inset puts the frame's
    /// edges at the content's edges.
    static func crop(image: CGSize, frame: CGSize, zoom: CGFloat, offset: CGPoint, inset: UIEdgeInsets) -> CGRect {
        guard image.width > 0, image.height > 0, zoom > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let r = CGRect(x: (offset.x + inset.left) / zoom / image.width, y: (offset.y + inset.top) / zoom / image.height,
                       width: frame.width / zoom / image.width, height: frame.height / zoom / image.height)
        return clamp(r)
    }

    /// The zoom and offset that show `crop` in the frame: the crop's width sets the zoom (never under filling), and
    /// its middle stays where it was, kept inside the photo.
    static func place(_ crop: CGRect, image: CGSize, frame: CGSize, inset: UIEdgeInsets) -> (zoom: CGFloat, offset: CGPoint) {
        let least = fill(image, frame: frame)
        let byWidth = crop.width > 0 ? frame.width / (crop.width * image.width) : least
        let byHeight = crop.height > 0 ? frame.height / (crop.height * image.height) : least
        let zoom = min(max(min(byWidth, byHeight), least), least * maxZoom)
        let shownW = frame.width / zoom, shownH = frame.height / zoom
        let x = min(max(crop.midX * image.width - shownW / 2, 0), image.width - shownW)
        let y = min(max(crop.midY * image.height - shownH / 2, 0), image.height - shownH)
        return (zoom, CGPoint(x: x * zoom - inset.left, y: y * zoom - inset.top))
    }

    /// `crop` at another shape (the shape button changed after a photo was left): its middle kept, as wide as it was
    /// where the photo allows, else as large as fits.
    static func fit(_ crop: CGRect, image: CGSize, aspect: CGFloat) -> CGRect {
        let frame = CGSize(width: aspect * 100, height: 100)
        let at = place(crop, image: image, frame: frame, inset: .zero)
        return self.crop(image: image, frame: frame, zoom: at.zoom, offset: at.offset, inset: .zero)
    }

    /// Inside the photo: a crop never reaches past an edge.
    static func clamp(_ r: CGRect) -> CGRect {
        let w = min(max(r.width, 0), 1), h = min(max(r.height, 0), 1)
        return CGRect(x: min(max(r.minX, 0), 1 - w), y: min(max(r.minY, 0), 1 - h), width: w, height: h)
    }

    /// The photo cut to `crop`, drawn (not cropped as a bitmap) so a photo taken with the phone turned stays upright.
    static func cut(_ image: UIImage, to crop: CGRect) -> UIImage {
        let r = clamp(crop)
        let size = CGSize(width: (image.size.width * r.width).rounded(.down), height: (image.size.height * r.height).rounded(.down))
        guard size.width >= 1, size.height >= 1 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: CGPoint(x: -image.size.width * r.minX, y: -image.size.height * r.minY))
        }
    }

    /// At most `side` px on the long side, so a 48 MP photo never sits whole on the Adjust screen.
    static func shrunk(_ image: UIImage, side: CGFloat = 2400) async -> UIImage {
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let k = side / max(px.width, px.height, 1)
        guard k < 1 else { return image }
        return await image.byPreparingThumbnail(ofSize: CGSize(width: px.width * k, height: px.height * k)) ?? image
    }
}

// MARK: - The screen

/// The frame a photo is adjusted in.
enum PhotoAdjustShape: Equatable {
    /// A post: its first photo's own shape (4:5 to 1.91:1), or square after the shape button.
    case post(own: CGFloat)
    /// The profile photo.
    case circle
    /// The cover, at the profile's shape.
    case wide(CGFloat)
}

enum PhotoAdjustCopy {
    static let cancel = "Cancel"
    static let done = "Done"
    static let hint = "Drag to move · Pinch to zoom"
}

/// Full screen on black, Instagram's and Photos' crop: Cancel and Done over the photo, the frame clear and the rest of
/// the photo dimmed, a grid while a finger is down, one hint that fades at the first touch. A post's several photos
/// sit in a strip under it, a tap choosing which to adjust; each keeps where it was left.
struct PhotoAdjustView: View {
    let images: [UIImage]
    let shape: PhotoAdjustShape
    /// Each photo's crop, and whether the post went square.
    let onDone: (_ crops: [CGRect], _ square: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on: Int
    @State private var isSquare: Bool
    @State private var touching = false
    @State private var touched = false
    @State private var stage: PhotoAdjustStage

    init(images: [UIImage], shape: PhotoAdjustShape, crops: [CGRect?] = [], square: Bool = false, start: Int = 0,
         onDone: @escaping (_ crops: [CGRect], _ square: Bool) -> Void) {
        self.images = images
        self.shape = shape
        self.onDone = onDone
        _on = State(initialValue: min(max(start, 0), max(images.count - 1, 0)))
        _isSquare = State(initialValue: square)
        _stage = State(initialValue: PhotoAdjustStage(crops: images.indices.map { crops.indices.contains($0) ? crops[$0] : nil }))
    }

    private enum Metric {
        /// The post's frame starts here from the screen's top (the mock's 130 pt), the bar above it.
        static let postTop: CGFloat = 130
        /// The circle leaves 20 pt each side.
        static let circleInset: CGFloat = 20
        static let hintGap: CGFloat = 18
        static let shapeButton: CGFloat = 36
        static let shapeInset: CGFloat = 12
        static let thumb: CGFloat = 56
        static let thumbGap: CGFloat = 8
        static let stripBottom: CGFloat = 10
        static let barSide: CGFloat = 20
        static let dim: Double = 0.62
    }

    var body: some View {
        GeometryReader { geo in
            let screen = CGSize(width: geo.size.width, height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            let frame = frameRect(in: screen)
            ZStack(alignment: .topLeading) {
                Color.black
                PhotoAdjustScroll(image: images[on], index: on, frame: frame, crop: stage.crop(on),
                                  stage: stage, touching: $touching, animate: !reduceMotion)
                    .accessibilityLabel("Your photo")
                    .accessibilityHint(PhotoAdjustCopy.hint)
                dimmer(frame, in: screen)
                grid(frame)
                Text(PhotoAdjustCopy.hint)
                    .font(.sans(13))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: screen.width)
                    .offset(y: frame.maxY + Metric.hintGap)
                    .opacity(touched ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if case .post = shape { shapeButton(frame) }
                bar.padding(.top, geo.safeAreaInsets.top)
                if images.count > 1 {
                    strip
                        .frame(width: screen.width)
                        .offset(y: screen.height - geo.safeAreaInsets.bottom - Metric.stripBottom - Metric.thumb)
                }
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : Motion.smooth, value: isSquare)
            .animation(.easeOut(duration: 0.25), value: touching)
            .animation(.easeOut(duration: 0.4), value: touched)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onChange(of: touching) { _, now in if now { touched = true } }
    }

    private func frameRect(in screen: CGSize) -> CGRect {
        switch shape {
        case .post(let own):
            let aspect = isSquare ? 1 : max(own, 0.1)
            return CGRect(x: 0, y: Metric.postTop, width: screen.width, height: screen.width / aspect)
        case .circle:
            let side = screen.width - Metric.circleInset * 2
            return CGRect(x: Metric.circleInset, y: (screen.height - side) / 2, width: side, height: side)
        case .wide(let aspect):
            let h = screen.width / max(aspect, 0.1)
            return CGRect(x: 0, y: (screen.height - h) / 2, width: screen.width, height: h)
        }
    }

    /// Everything outside the frame darkened, the frame cut out (a circle for the profile photo). Drawn as shapes so
    /// the hole moves with the shape button.
    private func dimmer(_ frame: CGRect, in screen: CGSize) -> some View {
        let edge = shape == .circle ? AnyShape(Circle()) : AnyShape(Rectangle())
        return Rectangle()
            .fill(.black.opacity(Metric.dim))
            .mask {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                    edge
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .frame(width: screen.width, height: screen.height)
            .allowsHitTesting(false)
    }

    /// Thirds and the frame's edge, while a finger is down.
    private func grid(_ frame: CGRect) -> some View {
        let edge = shape == .circle ? AnyShape(Circle()) : AnyShape(Rectangle())
        return ZStack {
            Path { p in
                for k in [1.0 / 3, 2.0 / 3] {
                    p.move(to: CGPoint(x: frame.width * k, y: 0)); p.addLine(to: CGPoint(x: frame.width * k, y: frame.height))
                    p.move(to: CGPoint(x: 0, y: frame.height * k)); p.addLine(to: CGPoint(x: frame.width, y: frame.height * k))
                }
            }
            .stroke(.white.opacity(0.45), lineWidth: 1)
            .clipShape(edge)
            edge.stroke(.white.opacity(0.7), lineWidth: 1)
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(touching ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var bar: some View {
        HStack {
            Button(PhotoAdjustCopy.cancel) { dismiss() }
                .font(.display(17))
                .foregroundStyle(.white)
            Spacer()
            Button(PhotoAdjustCopy.done) {
                Haptics.light()
                // Each at the frame's shape now, a photo left before the shape button changed included.
                let all = images.indices.map { i in
                    let left = (i == on ? stage.current() : nil) ?? stage.crop(i)
                    return left.map { PhotoCrop.fit($0, image: images[i].size, aspect: aspect) }
                        ?? PhotoCrop.middle(of: images[i].size, aspect: aspect)
                }
                onDone(all, isSquare)
                dismiss()
            }
            .font(.displaySemi(17))
            .foregroundStyle(Hue.brandDisc)
        }
        .buttonStyle(.press(.dim))
        .padding(.horizontal, Metric.barSide)
        .frame(height: 44)
    }

    /// The frame's shape, width over height.
    private var aspect: CGFloat {
        switch shape {
        case .post(let own): isSquare ? 1 : own
        case .circle: 1
        case .wide(let a): a
        }
    }

    /// Instagram's shape button at the frame's lower left: the post's own shape or square.
    private func shapeButton(_ frame: CGRect) -> some View {
        Button {
            Haptics.light()
            stage.keep(on)
            isSquare.toggle()
        } label: {
            Image(systemName: isSquare ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                .font(.glyph(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Metric.shapeButton, height: Metric.shapeButton)
                .background(.black.opacity(0.55), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(isSquare ? "Use the photo's own shape" : "Make it square")
        .offset(x: frame.minX + Metric.shapeInset - 4, y: frame.maxY - Metric.shapeInset - 40)
    }

    private var strip: some View {
        HStack(spacing: Metric.thumbGap) {
            ForEach(images.indices, id: \.self) { i in
                Button {
                    guard i != on else { return }
                    Haptics.selection()
                    stage.keep(on)
                    on = i
                } label: {
                    Image(uiImage: images[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: Metric.thumb, height: Metric.thumb)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.adjustThumb, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.adjustThumb, style: .continuous)
                                .strokeBorder(.white, lineWidth: i == on ? 2 : 0)
                        }
                        .opacity(i == on ? 1 : 0.6)
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("Photo \(i + 1) of \(images.count)")
                .accessibilityAddTraits(i == on ? .isSelected : [])
            }
        }
    }
}

/// What the scroll and the screen share: the scroll on show, and where each photo was left.
@MainActor
final class PhotoAdjustStage {
    /// Where each photo sat last time, else nil for its middle.
    private(set) var crops: [CGRect?]
    weak var scroll: PhotoAdjustScroll.Coordinator?

    init(crops: [CGRect?]) { self.crops = crops }

    func crop(_ i: Int) -> CGRect? { crops.indices.contains(i) ? crops[i] : nil }

    /// The photo on show, as it sits now.
    func current() -> CGRect? { scroll?.crop() }

    /// Keep where photo `i` sits before the screen moves on from it.
    func keep(_ i: Int) {
        guard crops.indices.contains(i), let now = current() else { return }
        crops[i] = now
    }
}

/// Apple's zooming scroll view over the whole screen, its content inset putting the frame's edges at the photo's, so
/// the photo can go no further than to fill the frame, and stretches past it under the finger.
struct PhotoAdjustScroll: UIViewRepresentable {
    let image: UIImage
    let index: Int
    let frame: CGRect
    let crop: CGRect?
    let stage: PhotoAdjustStage
    @Binding var touching: Bool
    let animate: Bool

    func makeCoordinator() -> Coordinator { Coordinator(touching: $touching) }

    func makeUIView(context: Context) -> AdjustScrollView {
        let scroll = AdjustScrollView()
        scroll.delegate = context.coordinator
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.alwaysBounceHorizontal = true
        scroll.bouncesZoom = true
        scroll.decelerationRate = .fast
        scroll.backgroundColor = .clear
        scroll.addSubview(context.coordinator.photo)
        // The first layout gives it a size: what was asked for before then shows now.
        scroll.laidOut = { [weak coordinator = context.coordinator] in coordinator?.apply() }
        context.coordinator.scroll = scroll
        stage.scroll = context.coordinator
        return scroll
    }

    func updateUIView(_ scroll: AdjustScrollView, context: Context) {
        let c = context.coordinator
        c.touching = $touching
        stage.scroll = c
        c.want = (image, index, frame, crop, animate)
        c.apply()
    }

    /// A scroll view that says when it's laid out.
    final class AdjustScrollView: UIScrollView {
        var laidOut: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            laidOut?()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let photo = UIImageView()
        weak var scroll: UIScrollView?
        var touching: Binding<Bool>
        private var shown: Int?
        private var frame: CGRect = .zero
        /// What SwiftUI last asked for: the photo, its index, the frame, where it was left, and whether to animate.
        var want: (image: UIImage, index: Int, frame: CGRect, crop: CGRect?, animate: Bool)?

        func apply() {
            guard let want else { return }
            show(want.image, index: want.index, frame: want.frame, crop: want.crop, animated: want.animate)
        }

        init(touching: Binding<Bool>) {
            self.touching = touching
            photo.contentMode = .scaleToFill
        }

        /// Photo `index` in `frame`: a new photo lands where it was left (else its middle); a new frame (the shape
        /// button) keeps the photo's middle where it is and zooms only as far as filling the new frame needs.
        func show(_ image: UIImage, index: Int, frame: CGRect, crop: CGRect?, animated: Bool) {
            guard let scroll, scroll.bounds.width > 0 else { return }
            guard index != shown || frame != self.frame else { return }
            let sameFrame = frame == self.frame
            let keep = sameFrame ? nil : self.crop()
            let size = image.size
            let inset = UIEdgeInsets(top: frame.minY, left: frame.minX,
                                     bottom: scroll.bounds.height - frame.maxY, right: scroll.bounds.width - frame.maxX)
            let target = index != shown ? (crop ?? PhotoCrop.middle(of: size, aspect: frame.width / frame.height))
                                        : (keep ?? PhotoCrop.middle(of: size, aspect: frame.width / frame.height))
            let least = PhotoCrop.fill(size, frame: frame.size)
            let place = PhotoCrop.place(target, image: size, frame: frame.size, inset: inset)
            let isNew = index != shown
            let apply = {
                if isNew {
                    self.photo.image = image
                    scroll.minimumZoomScale = 1
                    scroll.maximumZoomScale = 1
                    scroll.zoomScale = 1
                    self.photo.frame = CGRect(origin: .zero, size: size)
                    scroll.contentSize = size
                }
                scroll.contentInset = inset
                scroll.minimumZoomScale = least
                scroll.maximumZoomScale = least * PhotoCrop.maxZoom
                scroll.zoomScale = place.zoom
                scroll.contentOffset = place.offset
            }
            let first = shown == nil
            let fresh = index != shown && !first
            shown = index
            self.frame = frame
            if fresh && animated {
                UIView.transition(with: scroll, duration: 0.2, options: .transitionCrossDissolve, animations: apply)
            } else if animated && !sameFrame && !first {
                UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: apply)
            } else {
                apply()
            }
        }

        /// The part of the photo in the frame now.
        func crop() -> CGRect? {
            guard let scroll, let size = photo.image?.size, frame.width > 0 else { return nil }
            return PhotoCrop.crop(image: size, frame: frame.size, zoom: scroll.zoomScale,
                                  offset: scroll.contentOffset, inset: scroll.contentInset)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { touching.wrappedValue = true }
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { touching.wrappedValue = true }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate && !scrollView.isZooming { touching.wrappedValue = false }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { touching.wrappedValue = false }
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            if !scrollView.isDragging { touching.wrappedValue = false }
        }
    }
}

// MARK: - Opening it after a pick

extension View {
    /// Adjust over everything once `image` is set (the profile photo, the cover): Done hands back the photo cut to the
    /// frame, Cancel hands back nothing and the pick is dropped.
    func photoAdjust(_ image: Binding<UIImage?>, shape: PhotoAdjustShape, done: @escaping (UIImage) -> Void) -> some View {
        fullScreenCover(isPresented: Binding { image.wrappedValue != nil } set: { if !$0 { image.wrappedValue = nil } }) {
            if let picked = image.wrappedValue {
                PhotoAdjustView(images: [picked], shape: shape) { crops, _ in
                    if let crop = crops.first { done(PhotoCrop.cut(picked, to: crop)) }
                }
            }
        }
    }
}
