//
//  EventLook.swift
//  Block Party — the Event page's look, Apple Invites' top (BP app docs/plans/inside-cards, ticket 17; Jesse,
//  2026-11-06: "copy apples invites top", "copy all of it", "copy there discription font and color"): the
//  picture melts into its own colour, near-black at the foot, under a big centred title, with the facts in
//  a light tint of that colour and two big round-ended buttons. Measured off Apple Invites' birthday screen
//  (`references/inside-cards/mobbin/page-apple-invites-birthday.jpg`, 393 pt) and the mock Jesse approved
//  (`references/inside-cards/pieces/`, 402 pt); SPEC.md has every number.
//
//  A game's page keeps its own look (ticket 21) and a business page stays white: nothing here draws on them.
//

import SwiftUI
import MapboxMaps

/// The page's sizes, on a 402 pt phone; the picture's scale with the width.
enum EventLook {
    /// The mock's phone, which the picture's sizes scale from.
    static let mockWidth: CGFloat = 402
    /// A photo: edge to edge from the screen's top, this tall.
    static let photoHeight: CGFloat = 410
    /// The sharp photo is whole to 96 pt above its foot and gone 6 pt above it.
    static let sharpFrom: CGFloat = 96
    static let sharpTo: CGFloat = 6
    /// The blurred copy, mirrored past the foot, carries the photo into the page's colour: whole to 50 pt
    /// above the foot, gone 112 pt below it (46 for a pale picture, so the white buttons stay readable).
    static let meltFrom: CGFloat = 50
    static let meltTo: CGFloat = 112
    static let meltToPale: CGFloat = 46
    static let blur: CGFloat = 26
    static let saturation: Double = 1.25
    /// A picture whose mean brightness is over this is pale.
    static let pale: Double = 0.6
    /// A flyer never crops: full width, at most this tall, starting under the clock, this much melt under it.
    static let flyerMax: CGFloat = 420
    static let flyerTop: CGFloat = 62
    static let flyerBottom: CGFloat = 24
    /// Logo only: a white disc this far from the top, the logo this share of it, the hero this tall.
    static let disc: CGFloat = 148
    static let discTop: CGFloat = 96
    static let discLogo: CGFloat = 0.76
    static let logoHero: CGFloat = 290
    /// Round glass buttons, measured: 34 pt, 4.5 under the safe area, back 19 in and calendar 20 in.
    static let glass: CGFloat = 34
    static let glassTop: CGFloat = 4.5
    static let backInset: CGFloat = 19
    static let calendarInset: CGFloat = 20
    static let glassGlyph: CGFloat = 17
    /// The heart: 16 in and 96 above a photo's foot; 12 from a flyer's corner.
    static let heartInset: CGFloat = 16
    static let heartAboveFoot: CGFloat = 96
    static let heartFlyerInset: CGFloat = 12
    /// The words: 16 pt from the sides, the title 34 on 41, the lines 17 on 24.5 starting 10 under it.
    static let side: CGFloat = 16
    static let title: CGFloat = 34
    static let titleLine: CGFloat = 41
    /// What `lineSpacing` adds to BP Event Heading's own line to make 41 at 34 pt and 48 at the yellow page's 42
    /// (measured on the simulator: 41.3 and 48).
    static let titleSpacing: CGFloat = 8
    static let sunTitleSpacing: CGFloat = 11
    static let linesTop: CGFloat = 10
    static let line: CGFloat = 17
    static let lineHeight: CGFloat = 24.5
    /// A one-line SF Pro 17 `Text`'s frame (20.33 pt on the simulator, measured: tighter than the body style's
    /// 22 pt line), which the 24.5 pt lines space from.
    static let lineNatural: CGFloat = 20.33
    /// The title's caps start this far under the picture's foot: the mock's half-leading (41 less 34, halved).
    static let titleTop: CGFloat = 3.5
    /// A photo's credit chip, level with the heart: its bottom 68 pt above the foot, so its top sits about 86 up.
    static let creditAboveFoot: CGFloat = 68
    /// A flyer's credit sits under it at the right, 12 pt, in a 29 pt line.
    static let creditLine: CGFloat = 29
    static let credit: CGFloat = 12
    /// The two big buttons: 73 pt with full round ends, 14 apart, 20 under the lines, a 22 pt glyph over the word.
    static let button: CGFloat = 73
    static let buttonGap: CGFloat = 14
    static let buttonsTop: CGFloat = 20
    static let buttonGlyph: CGFloat = 22
    static let buttonWord: CGFloat = 16
    static let buttonGlyphGap: CGFloat = 4
    /// The small map under Map (inside-cards 19), off the mock's CSS: 150 pt tall, 14 under the buttons, 20 pt corners,
    /// a white hairline at 14% inside; the Event's photo 46 pt in a 2.5 pt white ring at its middle; a 30 pt white
    /// expand button 10 pt in from the top right with a 15 pt glyph. Opening, the page scrolls so it ends 12 pt
    /// above the bar. It grows and shrinks on a spring with no bounce, the mock's 0.36 s.
    static let smallMap: CGFloat = 150
    static let smallMapTop: CGFloat = 14
    static let smallMapCorner: CGFloat = 20
    static let smallMapPin: CGFloat = 46
    static let smallMapRing: CGFloat = 2.5
    static let smallMapGrow: CGFloat = 30
    static let smallMapGrowInset: CGFloat = 10
    static let smallMapGrowGlyph: CGFloat = 15
    static let smallMapClear: CGFloat = 12
    /// Mapbox's ⓘ credit on the still (their terms ask for one on every map; Jesse 2026-11-08): an 11 pt glyph in a
    /// 28 pt tap square at the bottom right corner.
    static let smallMapCreditGlyph: CGFloat = 11
    static let smallMapCredit: CGFloat = 28
    static let smallMapSpring: Animation = .spring(duration: 0.36, bounce: 0)
    /// Follow: a row 18 under the buttons, 12 pt tall at each end, the host's logo in a 40 pt white circle,
    /// Instagram's 70 x 32 Follow with 8 pt corners.
    static let hostTop: CGFloat = 18
    static let hostPad: CGFloat = 12
    static let hostGap: CGFloat = 12
    static let hostLogo: CGFloat = 40
    static let hostName: CGFloat = 16
    static let hostKind: CGFloat = 15
    static let followWidth: CGFloat = 70
    static let followCorner: CGFloat = 8
    /// The Schedule (happening-now 06), off mock A's CSS: 26 under the buttons, its heading as About's, 6 to the rows;
    /// rows 48 tall, the time in a 96 pt column (the mock's 78 wrapped "Tue 3:50 PM"), 12 to the name; a part ended today
    /// at 40%. Its words' sizes are at the call (BP Body, `Font.sans`): 15, 16, "See all" 15.
    static let scheduleTop: CGFloat = 26
    static let scheduleHeadingGap: CGFloat = 6
    static let scheduleRow: CGFloat = 48
    static let scheduleTime: CGFloat = 96
    static let scheduleGap: CGFloat = 12
    static let schedulePast: Double = 0.4
    /// About: 18 under the row, Inter Tight Bold 20, 8 to its words at 17 on 22.
    static let aboutTop: CGFloat = 18
    static let aboutHeading: CGFloat = 20
    static let aboutGap: CGFloat = 8
    static let aboutWords: CGFloat = 17
    /// The Attend bar (inside-cards 18), off the approved mock's CSS: faces 14 pt in (words alone 24, today's), 8 pt
    /// from the words; the words Inter Tight Bold 15 over BP Body 13; a 46 pt see-through send with a 20 pt glyph,
    /// 6 pt from Attend, folding 60 pt right into Invite as it shrinks to 40% and fades.
    static let barFacesInset: CGFloat = 14
    static let barFacesGap: CGFloat = 8
    static let barWords: CGFloat = 15
    static let barTime: CGFloat = 13
    static let send: CGFloat = 46
    static let sendGlyph: CGFloat = 20
    static let sendGap: CGFloat = 6
    static let sendFold: CGFloat = 60
    /// Once the page scrolls, the top colour fades in under the clock: whole to 45% of 118 pt, gone at its end.
    static let topFade: CGFloat = 118
    static let topFadeSolid: CGFloat = 0.45
    /// No picture and no logo: the exact yellow, the title 42 on 48 starting 158 pt down, the heart 110 down
    /// at the right.
    static let sunTitleTop: CGFloat = 158
    static let sunTitle: CGFloat = 42
    static let sunTitleLine: CGFloat = 48
    static let sunHeartTop: CGFloat = 110
    static let sunHeartInset: CGFloat = 12
    /// White on the page: a button's fill at 10% with a 16% line, dimmed words at 66%, a hairline at 14%.
    /// Ink on the yellow: 7% and 10%, 68%, the lines' tint 78%, a glass circle 10%.
    static let fill: Double = 0.10
    static let fillLine: Double = 0.16
    /// Map while its small map is open: white at 20%, ink at 14% on the yellow (the mock's).
    static let fillLit: Double = 0.20
    static let sunFillLit: Double = 0.14
    static let dim: Double = 0.66
    static let hairline: Double = 0.14
    static let glassFill: Double = 0.22
    static let glassLine: Double = 0.18
    static let sunFill: Double = 0.07
    static let sunFillLine: Double = 0.10
    static let sunDim: Double = 0.68
    static let sunTint: Double = 0.78
    static let sunGlass: Double = 0.10
    /// The white disc's shadow under a logo.
    static let discShadow: Double = 0.34
    static let discShadowRadius: CGFloat = 17
    static let discShadowY: CGFloat = 10

    // MARK: The page's colour (EventPageTests)

    /// Grey: a picture with no colourful hue, and a called-off one, whose photo is black and white.
    static let grey: UInt32 = 0x808080
    /// The picture is read at this many pixels a side.
    static let sample = 72

    /// The page's colours, from the picture's own: the top at 30% lightness, darkened until white reads on
    /// it at 5 to 1 or better (Apple's own measures 2.7; Jesse agreed to darker); 21% at 62% of the way down,
    /// 11% at 82%, `Hue.gameNight` at the foot. `tint` is the lines' colour, the hue at 92% lightness (Apple's
    /// #D6FDFF on #63818B). A grey stays grey throughout.
    struct Wash: Equatable {
        let top: UInt32
        let mid: UInt32
        let low: UInt32
        let tint: UInt32

        /// Where each colour sits down the screen.
        static let topEnds = 0.45
        static let midAt = 0.62
        static let lowAt = 0.82

        var stops: [Gradient.Stop] {
            [.init(color: Color(hex: top), location: 0), .init(color: Color(hex: top), location: Self.topEnds),
             .init(color: Color(hex: mid), location: Self.midAt), .init(color: Color(hex: low), location: Self.lowAt),
             .init(color: Hue.gameNight, location: 1)]
        }
    }

    /// Two colours mixed, `t` of the way from `a` to `b`: the page's colour while the hero swipes from the
    /// Event's own photo to its flyer (town-feed 59).
    static func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UInt32 {
        let t = min(max(t, 0), 1)
        return [16, 8, 0].reduce(UInt32(0)) { mixed, shift in
            let x = CGFloat((a >> shift) & 0xFF), y = CGFloat((b >> shift) & 0xFF)
            return mixed | (UInt32((x + (y - x) * t).rounded()) << shift)
        }
    }

    static func wash(_ rgb: UInt32) -> Wash {
        var lightness = 0.30
        while lightness > 0.12, contrastWithWhite(tone(rgb, lightness)) < 5 { lightness -= 0.01 }
        return Wash(top: tone(rgb, lightness), mid: tone(rgb, min(lightness, 0.21)), low: tone(rgb, 0.11),
                    tint: GameMatchup.tone(rgb, lightness: 0.92, saturationFloor: 1))
    }

    /// The colour at that lightness, its hue kept and its saturation held between 60% and 82%, as a game's
    /// page deepens its teams' colours.
    private static func tone(_ rgb: UInt32, _ lightness: Double) -> UInt32 {
        GameMatchup.tone(rgb, lightness: lightness, saturationCap: 0.82)
    }

    /// WCAG's contrast of white on the colour.
    static func contrastWithWhite(_ rgb: UInt32) -> Double {
        1.05 / (luminance(rgb) + 0.05)
    }

    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ c: UInt32) -> Double {
            let v = Double(c & 0xFF) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb >> 16) + 0.7152 * channel(rgb >> 8) + 0.0722 * channel(rgb)
    }

    /// The picture's own colour: the most common colourful hue, by count times saturation squared, ignoring
    /// saturation under 25% and lightness outside 12% to 85%, and see-through pixels (a logo's edge). Grey
    /// for none. `pixels` are RGBA bytes, as `pixels(of:)` reads them.
    static func dominant(pixels: [UInt8]) -> UInt32 {
        var bins: [Int: (weight: Double, r: Double, g: Double, b: Double)] = [:]
        var i = 0
        while i + 3 < pixels.count {
            defer { i += 4 }
            guard pixels[i + 3] >= 128 else { continue }
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            let (hue, lightness, saturation) = hls(r / 255, g / 255, b / 255)
            guard saturation >= 0.25, (0.12...0.85).contains(lightness) else { continue }
            let k = saturation * saturation
            let key = min(Int(hue * 24), 23)
            let bin = bins[key, default: (0, 0, 0, 0)]
            bins[key] = (bin.weight + k, bin.r + r * k, bin.g + g * k, bin.b + b * k)
        }
        guard let best = bins.values.max(by: { $0.weight < $1.weight }) else { return grey }
        func channel(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v / best.weight).rounded()))) }
        return channel(best.r) << 16 | channel(best.g) << 8 | channel(best.b)
    }

    /// Mean brightness, 0 to 1, of the pixels that show: over `pale` the picture is pale.
    static func brightness(pixels: [UInt8]) -> Double {
        var sum = 0.0, count = 0.0
        var i = 0
        while i + 3 < pixels.count {
            defer { i += 4 }
            guard pixels[i + 3] >= 128 else { continue }
            sum += 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
            count += 1
        }
        return count > 0 ? sum / count / 255 : 0
    }

    /// The picture at `sample` pixels a side, as RGBA bytes.
    static func pixels(of image: CGImage) -> [UInt8] {
        let n = sample
        var data = [UInt8](repeating: 0, count: n * n * 4)
        data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                          bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        }
        return data
    }

    /// Hue (0 to 1), lightness and saturation, as Python's colorsys gives them (the mock's rule).
    static func hls(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let high = max(r, g, b), low = min(r, g, b), l = (high + low) / 2, d = high - low
        guard d > 0 else { return (0, l, 0) }
        let s = l > 0.5 ? d / (2 - high - low) : d / (high + low)
        let h = high == r ? (g - b) / d + (g < b ? 6 : 0) : high == g ? (b - r) / d + 2 : (r - g) / d + 4
        return (h / 6, l, s)
    }
}

// MARK: - Pictures

/// A photo melting into the page: sharp from the screen's top, gone just above its foot, while a blurred
/// copy of it, mirrored past the foot, carries it down into the page's colour. The one bitmap is drawn
/// three times, so it costs one download and one decode (`FeedCardImageLoader`).
struct EventMeltHero: View {
    let url: URL
    let height: CGFloat
    /// A pale picture's melt ends sooner, so the white buttons under it stay readable.
    let pale: Bool
    /// Called off: black and white, as on its card (Jesse, 2026-10-17).
    let cancelled: Bool
    /// The bitmap is on screen: the melt draws it too. Before, it waits, so the one decode isn't three.
    let ready: Bool
    let onReady: () -> Void
    let onFailure: () -> Void

    var body: some View {
        Color.clear
            .frame(height: height)
            .background(alignment: .top) { EventMelt(url: url, height: height, pale: pale, ready: ready) }
            .overlay(alignment: .top) {
                // Near-black while it loads, never the dark ramp's near-white ink (the page is dark).
                FeedCardURLPhoto(url: url, onReady: onReady, onFailure: onFailure, loadingFill: Hue.gameNight)
                    .frame(height: height)
                    .clipped()
                    .mask(alignment: .top) {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black, location: (height - EventLook.sharpFrom) / height),
                                               .init(color: .clear, location: (height - EventLook.sharpTo) / height)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .grayscale(cancelled ? 1 : 0)
    }
}

/// The blurred copy under a picture and, mirrored, past its foot: whole to `meltFrom` above the foot and
/// gone `meltTo` below it. Drawn as a background, so it takes no room and the words sit over its tail.
private struct EventMelt: View {
    let url: URL
    let height: CGFloat
    let pale: Bool
    let ready: Bool

    var body: some View {
        let reach = pale ? EventLook.meltToPale : EventLook.meltTo
        VStack(spacing: 0) {
            if ready {
                copy
                copy.scaleEffect(x: 1, y: -1)
            } else {
                Hue.gameNight.frame(height: 2 * height)
            }
        }
        .animation(Motion.smooth, value: ready)
        .saturation(EventLook.saturation)
        // Opaque, so the blur's edges stay solid; the mask alone fades it.
        .blur(radius: EventLook.blur, opaque: true)
        .frame(height: height + reach, alignment: .top)
        .clipped()
        .mask(alignment: .top) {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: (height - EventLook.meltFrom) / (height + reach)),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var copy: some View {
        FeedCardURLPhoto(url: url, loadingFill: Hue.gameNight)
            .frame(height: height)
            .clipped()
    }
}

/// A flyer whole over its own melt: never cropped, full width, at most 420 pt tall, starting under the clock
/// so the island never covers its title (taste/event-page.md, 2026-11-05).
struct EventFlyerHero: View {
    let url: URL
    /// Width over height.
    let aspect: CGFloat
    let width: CGFloat
    let pale: Bool
    let cancelled: Bool
    let ready: Bool
    let onReady: () -> Void
    let onFailure: () -> Void

    /// The flyer's size at this width.
    static func size(aspect: CGFloat, width: CGFloat) -> CGSize {
        let height = min(width / aspect, EventLook.flyerMax * width / EventLook.mockWidth)
        return CGSize(width: height * aspect, height: height)
    }

    /// The hero's height: the clock's band, the flyer, and the melt's start under it.
    static func height(aspect: CGFloat, width: CGFloat) -> CGFloat {
        EventLook.flyerTop + size(aspect: aspect, width: width).height + EventLook.flyerBottom
    }

    var body: some View {
        let size = Self.size(aspect: aspect, width: width)
        let height = Self.height(aspect: aspect, width: width)
        Color.clear
            .frame(height: height)
            .background(alignment: .top) { EventMelt(url: url, height: height, pale: pale, ready: ready) }
            .overlay(alignment: .top) {
                FeedCardURLPhoto(url: url, onReady: onReady, onFailure: onFailure, loadingFill: Hue.gameNight)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .padding(.top, EventLook.flyerTop)
            }
            .grayscale(cancelled ? 1 : 0)
    }
}

/// Logo only: the place's logo on a white disc, in the room above the words; the page takes the logo's colour.
struct EventLogoHero: View {
    let logo: SearchLogo
    /// The logo's bitmap, once it's here, for the page's colour.
    let onImage: (CGImage) -> Void

    @ObservedObject private var cache = POILogoCache.shared

    var body: some View {
        let image = cache.image(for: logo.url)
        Circle()
            .fill(.white)
            .frame(width: EventLook.disc, height: EventLook.disc)
            .shadow(color: .black.opacity(EventLook.discShadow), radius: EventLook.discShadowRadius, y: EventLook.discShadowY)
            .overlay { CastLogo(logo: logo, side: EventLook.disc * EventLook.discLogo, strength: 0) }
            .padding(.top, EventLook.discTop)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: EventLook.logoHero, alignment: .top)
            .accessibilityHidden(true)
            .onChange(of: image != nil, initial: true) { _, _ in
                if let cgImage = image?.cgImage { onImage(cgImage) }
            }
    }
}

// MARK: - Buttons

/// Apple Invites' round glass button at the top of the page, Town's heart's glass (`TownCardHeart`): 34 pt
/// with a white glyph, in a 44 pt tap box. On the yellow page, ink on a faint ink circle.
struct EventGlassButton: View {
    let glyph: String
    let label: String
    var sun = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.sansSemibold(EventLook.glassGlyph))
                .foregroundStyle(tint ?? (sun ? Hue.onBrandDisc : .white))
                .frame(width: EventLook.glass, height: EventLook.glass)
                .background {
                    if sun {
                        Circle().fill(Hue.onBrandDisc.opacity(EventLook.sunGlass))
                    } else {
                        Circle()
                            .fill(.black.opacity(EventLook.glassFill))
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(.white.opacity(EventLook.glassLine), lineWidth: 0.5) }
                            .environment(\.colorScheme, .dark)
                    }
                }
                .frame(width: MeetupPillStyle.minTarget, height: MeetupPillStyle.minTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(label)
    }
}

/// One of the two big buttons under the lines, Apple Invites' measured: 73 pt with full round ends, white
/// at 10% with a hairline, a 22 pt glyph over Inter Tight SemiBold 16. Each takes half the row; alone, all of it.
struct EventBigButton: View {
    let glyph: String
    let word: String
    var sun = false
    /// Map while its small map is open: a brighter fill.
    var lit = false
    let action: () -> Void

    var body: some View {
        let ink: Color = sun ? Hue.onBrandDisc : .white
        Button(action: action) {
            VStack(spacing: EventLook.buttonGlyphGap) {
                Image(systemName: glyph)
                    .font(.sans(EventLook.buttonGlyph))
                    .frame(height: EventLook.buttonGlyph)
                Text(word)
                    .font(.displaySemi(EventLook.buttonWord))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: EventLook.button)
            .background(ink.opacity(lit ? (sun ? EventLook.sunFillLit : EventLook.fillLit) : sun ? EventLook.sunFill : EventLook.fill),
                        in: Capsule())
            .animation(Motion.smooth, value: lit)
            .overlay { Capsule().strokeBorder(ink.opacity(sun ? EventLook.sunFillLine : EventLook.fillLine), lineWidth: 0.5) }
            .contentShape(Capsule())
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(word)
    }
}

/// The small map under Map (inside-cards 19; Jesse, 2026-11-06: "when you click the map it opens up right below and if
/// you click you can see it on the map"): a still of Block Party's map over the Event's spot, the Event's photo in a
/// white ring at its middle (the mock's bubble) and a white expand button in its corner. A tap opens the full map.
struct EventSmallMap: View {
    let item: FeedCardItem
    /// The still, once made (`SmallMapShot`); the map's ground until then.
    let shot: UIImage?
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EventLook.smallMapCorner, style: .continuous)
        Button(action: action) {
            ZStack {
                Hue.mapLand
                if let shot {
                    Image(uiImage: shot)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
                pin
            }
            .frame(maxWidth: .infinity)
            .frame(height: EventLook.smallMap)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.white.opacity(EventLook.hairline), lineWidth: 0.5) }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.glyph(EventLook.smallMapGrowGlyph, weight: .semibold))
                    .foregroundStyle(Hue.ink.onLightCanvas)
                    .frame(width: EventLook.smallMapGrow, height: EventLook.smallMapGrow)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)
                    .padding(EventLook.smallMapGrowInset)
            }
            .contentShape(shape)
        }
        .buttonStyle(.press(.squish))
        .animation(Motion.smooth, value: shot != nil)
        .accessibilityLabel("See it on the map")
        .overlay(alignment: .bottomTrailing) { credit }
    }

    /// The map's credits, as the full map's ⓘ lists them.
    private var credit: some View {
        Menu {
            Link("© Mapbox", destination: Self.mapbox)
            Link("© OpenStreetMap", destination: Self.openStreetMap)
            Link("Improve this map", destination: Self.improve)
        } label: {
            Image(systemName: "info.circle")
                .font(.glyph(EventLook.smallMapCreditGlyph))
                .foregroundStyle(Hue.ink.onLightCanvas.opacity(0.55))
                .frame(width: EventLook.smallMapCredit, height: EventLook.smallMapCredit)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Map credits")
    }

    private static let mapbox = URL(string: "https://www.mapbox.com/about/maps/")!
    private static let openStreetMap = URL(string: "https://www.openstreetmap.org/copyright")!
    private static let improve = URL(string: "https://apps.mapbox.com/feedback/")!

    /// The Event's photo, else its place's, else its logo, as its bubble on the map; the yellow with none.
    private var pin: some View {
        let source = item.photos().first
        return ZStack {
            if let url = source?.url {
                FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
            } else if let logo = source?.logo {
                FeedCardPlaceLogo(logo: logo)
            } else {
                Hue.brandDisc
            }
        }
        .frame(width: EventLook.smallMapPin, height: EventLook.smallMapPin)
        .clipShape(Circle())
        .background { Circle().fill(.white).padding(-EventLook.smallMapRing) }
        .shadow(color: .black.opacity(0.3), radius: 7, x: 0, y: 6)
        .accessibilityHidden(true)
    }
}

/// One still of Block Party's map for the small map (inside-cards 19): Mapbox's snapshotter on the map's own style and
/// palette, at the map's opening zoom, so it reads as the map it opens. No wordmark (Jesse's 2026-08-14 call) and no
/// attribution line on a 150 pt still: the full map it opens keeps its ⓘ.
@MainActor
final class SmallMapShot {
    private let snapshotter: Snapshotter
    private var waits: [AnyCancelable] = []
    private var done: CheckedContinuation<UIImage?, Never>?

    private init(size: CGSize, scale: CGFloat) {
        snapshotter = Snapshotter(options: MapSnapshotOptions(size: size, pixelRatio: scale,
                                                              showsLogo: false, showsAttribution: false))
    }

    /// The still, or nil when the style or the tiles couldn't load.
    static func make(at spot: CLLocationCoordinate2D, size: CGSize, scale: CGFloat) async -> UIImage? {
        guard size.width > 0 else { return nil }
        let shot = SmallMapShot(size: size, scale: scale)
        return await withCheckedContinuation { shot.start(at: spot, then: $0) }
    }

    /// Recoloured once its style is in, then drawn. Each wait holds this object until it's done.
    private func start(at spot: CLLocationCoordinate2D, then done: CheckedContinuation<UIImage?, Never>) {
        self.done = done
        waits.append(snapshotter.onStyleLoaded.observeNext { [self] _ in
            BasemapPalette.recolor(snapshotter)
            snapshotter.start(overlayHandler: nil) { [self] in finish(try? $0.get()) }
        })
        // A style that never loads would leave the still waiting for good; a tile or a sprite missing still draws.
        waits.append(snapshotter.onMapLoadingError.observe { [self] in if $0.type == .style { finish(nil) } })
        snapshotter.setCamera(to: CameraOptions(center: spot, zoom: SJMapView.openZoom))
        snapshotter.styleURI = BasemapPalette.style
    }

    private func finish(_ image: UIImage?) {
        done?.resume(returning: image)
        done = nil
        waits.removeAll()
    }
}

/// Instagram's dots under a photo set (town-feed 59), white on the hero: the one on show full, the rest at 40%,
/// following the finger's `page` (0 the first, 1 the second).
struct EventPageDots: View {
    let count: Int
    let page: CGFloat
    /// Instagram's 6 pt dots, 4 pt apart (guessed from the Mobbin still, `references/one-flyer-many-events/`).
    static let side: CGFloat = 6
    static let gap: CGFloat = 4

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: Self.side, height: Self.side)
                    .opacity(0.4 + 0.6 * max(0, 1 - abs(page - CGFloat(index))))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// "About" over all of its words, Apple's font in white (Jesse: "copy there discription font and color").
struct EventAbout: View {
    let text: String
    var sun = false

    var body: some View {
        let ink: Color = sun ? Hue.onBrandDisc : .white
        VStack(alignment: .leading, spacing: EventLook.aboutGap) {
            Text("About")
                .font(.display(EventLook.aboutHeading))
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.apple(EventLook.aboutWords))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An Event page's Attend bar (inside-cards 18; Jesse, 2026-11-06: "remove the share buttion but it on the bottem next
/// to attend", "change attends button to more neatrual color your pick", "show friends that are going on the left of
/// bottem pill and if you join it shows your profile too"). At the left the friends' faces and the count, the count
/// alone with no friend going, and with nobody going the day over its time (`RSVPWords`, `look`). Your own face joins
/// the row at the front on a spring the instant you Attend, and leaves the same way, a refused Attend's turn back too.
/// At the right the send, then Attend in white; the send folds into Invite as the pill turns. Inside today's capsule
/// (`EventPage.rsvpBar`); a game's page keeps `RSVPArea` (inside-cards 21).
struct EventBar: View {
    let item: FeedCardItem
    let words: RSVPWords
    var sun = false
    /// The send's tap and Invite's: what the top share opened (`ShareCenter`).
    let onShare: () -> Void

    @Environment(RealLifeActions.self) private var actions
    /// Your photo for your face; nil (a preview) or none is Instagram's blank.
    @Environment(ProfileModel.self) private var profile: ProfileModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink: Color = sun ? Hue.onBrandDisc : .white
        let dim: Color = sun ? Hue.onBrandDisc.opacity(EventLook.sunDim) : .white.opacity(EventLook.dim)
        // Faces only beside words: called off and not going, the red Canceled alone.
        let friends = words.top == nil ? [] : item.friendsGoing
        let you = words.top != nil && actions.going(item).isGoing
        let faces = you || !friends.isEmpty
        HStack(spacing: 0) {
            HStack(spacing: -FriendFaces.overlap) {
                if you {
                    Avatar(avatarUrl: profile?.avatarUrl, size: FriendFaces.side)
                        .overlay(Circle().strokeBorder(Hue.paper, lineWidth: 1.5))
                        .zIndex(1)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                }
                if !friends.isEmpty { FriendFaces(friends: friends) }
            }
            .accessibilityHidden(true)
            .padding(.trailing, faces ? EventLook.barFacesGap : 0)

            // "You're going!" and the day cross-fade in over what was there; a count rolls.
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 0) {
                    if let top = words.top {
                        Text(top)
                            .font(.display(EventLook.barWords))
                            .foregroundStyle(ink)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    if let second = words.second {
                        if words.canLeave {
                            RSVPArea.leave(second, size: .card, hint: "Takes you off the going list", tint: dim) {
                                actions.toggleGoing(item)
                            }
                        } else {
                            Text(second)
                                .font(.sans(EventLook.barTime))
                                .foregroundStyle(dim)
                        }
                    }
                }
                .lineLimit(1)
                .id(words.goingLine ? 0 : words.top?.hasSuffix(" going") == true ? 1 : 2)
                .transition(.opacity.animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip)))
            }
            .layoutPriority(1)

            Spacer(minLength: EventLook.barFacesGap)

            AttendPill(item: item, words: words, size: .page, onInvite: onShare, white: true,
                       send: EventSendButton(sun: sun, action: onShare))
        }
        .padding(.leading, faces ? EventLook.barFacesInset : EventPage.Metric.barWordsInset)
        // Your face springs in and out, the friends and words making room with it (the mock's spring: a little past).
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.62),
                   value: you)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.smooth, value: actions.going(item).count)
    }
}

/// The send beside Attend in an Event page's bar (inside-cards 18): a 46 pt see-through circle as the big buttons are,
/// white at 10% with a line of light inside its top, the card's send in white; ink on the yellow page. It opens what
/// Invite opens.
struct EventSendButton: View {
    var sun = false
    let action: () -> Void

    var body: some View {
        let ink: Color = sun ? Hue.onBrandDisc : .white
        Button(action: action) {
            FeedActionGlyphView(glyph: .send, size: EventLook.sendGlyph)
                .foregroundStyle(ink)
                .frame(width: EventLook.send, height: EventLook.send)
                .background {
                    Circle().fill(ink.opacity(sun ? EventLook.sunFill : EventLook.fill)
                        .shadow(.inner(color: ink.opacity(sun ? EventLook.sunFillLine : EventLook.fillLine), radius: 0, x: 0, y: 0.5)))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel("Share")
    }
}
