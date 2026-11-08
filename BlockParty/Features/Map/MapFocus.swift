//
//  MapFocus.swift
//  Block Party — the one owner of the map's open card and where the camera goes because of it.
//
//  Codebase-health 23 (BP app). Opening a bubble lifts it into the map above its card; closing
//  the card lets the map settle level again where it is; recenter flies home and closes the
//  card without a second move; the compass levels in place. Each of those used to be worked out
//  inline in `SJMapView`; here they are one value, so the order of "what's open" and "where
//  the camera goes" is code a test can hold, not a comment. `SJMapView.fly` runs each `Move`,
//  jumping instead of flying when Reduce Motion is on.
//

import CoreGraphics
import CoreLocation
import SwiftUI
import MapboxMaps

struct MapFocus {
    /// The bubble whose card is up, nil when none is.
    private(set) var selectedID: String?
    /// The card's page, through a merged bubble's events.
    var page = 0

    /// Where the camera is now, as the map last reported it.
    nonisolated struct Camera: Equatable {
        var center: CLLocationCoordinate2D
        var zoom: Double

        static func == (a: Camera, b: Camera) -> Bool {
            a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude && a.zoom == b.zoom
        }
    }

    /// One camera move: where it lands and how it gets there.
    nonisolated struct Move: Equatable {
        enum Glide: Equatable {
            /// Ease out over 0.45 s: a card opening or closing.
            case settle
            /// Fly over 0.8 s: recenter.
            case home
            /// Ease out over 0.4 s: the compass's north and level.
            case level
            /// Fly over 0.8 s: in to an Event its page asked for (inside-cards 19).
            case arrive
        }

        var center: CLLocationCoordinate2D
        var zoom: Double
        /// Bearing and pitch to land at; nil keeps the map's own.
        var bearing: Double?
        var pitch: Double?
        /// How far the bubble is lifted above the card: the camera's bottom padding, 0 for none.
        var lift: CGFloat
        var glide: Glide

        static func == (a: Move, b: Move) -> Bool {
            a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude
                && a.zoom == b.zoom && a.bearing == b.bearing && a.pitch == b.pitch
                && a.lift == b.lift && a.glide == b.glide
        }
    }

    /// The lifted bubble clears the top chrome by this much.
    static let liftTop: CGFloat = 110

    /// Open `bubble`'s card on the first event friends are Going to, else its first, and lift the
    /// bubble above it, at today's zoom.
    mutating func open(_ bubble: TodayBubble, from camera: Camera, mapWidth: CGFloat) -> Move {
        selectedID = bubble.id
        page = TodayBubbleRules.firstPage(bubble.events)
        return Move(center: bubble.coordinate, zoom: camera.zoom, bearing: nil, pitch: nil,
                    lift: Self.lift(mapWidth: mapWidth), glide: .settle)
    }

    /// Close the card and let the map settle level where it is. Nil when no card is up: nothing
    /// to close, so no move.
    mutating func close(from camera: Camera) -> Move? {
        guard selectedID != nil else { return nil }
        selectedID = nil
        page = 0
        return Move(center: camera.center, zoom: camera.zoom, bearing: nil, pitch: nil, lift: 0, glide: .settle)
    }

    /// Where the map opens for an Event its page asked for: over its spot, 1.6 steps out from the opening zoom
    /// (the bubble's smallest, 36 pt), so it flies in a little way rather than 92 km from the Town to Ham Lake.
    static let arriveFrom: Double = SJMapView.openZoom - 1.6

    /// An Event its page or a held card asked for (inside-cards 19): its bubble's card opens on it, whoever's
    /// friends go to the others there, and the camera flies in to the opening zoom, lifting the bubble above the
    /// card. The zoom is the opening one, not the camera's: the map reports its zoom only once it has drawn.
    mutating func arrive(_ bubble: TodayBubble, on eventID: String, mapWidth: CGFloat) -> Move {
        selectedID = bubble.id
        page = bubble.events.firstIndex { $0.id == eventID } ?? 0
        return Move(center: bubble.coordinate, zoom: SJMapView.openZoom, bearing: nil, pitch: nil,
                    lift: Self.lift(mapWidth: mapWidth), glide: .arrive)
    }

    /// Recenter: the card closes as part of the one fly home, never as a move of its own.
    mutating func home() -> Move {
        selectedID = nil
        return Move(center: MapSpots.center, zoom: SJMapView.openZoom, bearing: nil, pitch: nil, lift: 0, glide: .home)
    }

    /// The card stays open on the Event it showed, in the bubble that Event is in now, however
    /// bubbles merged or split; the camera stays where it is.
    mutating func follow(_ bubble: TodayBubble, on eventID: String) {
        selectedID = bubble.id
        page = bubble.events.firstIndex { $0.id == eventID } ?? 0
    }

    /// The compass's tap: face north and level, in place. The card is left as it is.
    func level(from camera: Camera) -> Move {
        Move(center: camera.center, zoom: camera.zoom, bearing: 0, pitch: 0, lift: 0, glide: .level)
    }

    /// The card's photo is 352.7 × 198.6 at its full width; the bubble sits that, the top
    /// clearance and the card's bottom inset above the map's bottom edge.
    static func lift(mapWidth: CGFloat) -> CGFloat {
        let photo = (mapWidth - 2 * MapEventCard.sideInset) * 198.6 / 352.7
        return photo + liftTop + MapEventCard.bottomInset
    }
}

@MainActor
extension MapFocus.Move {
    /// The Mapbox camera this move lands at. A lift pads the top too, so the chrome never
    /// covers the bubble; no lift is no padding.
    var viewport: Viewport {
        var camera = Viewport.camera(center: center, zoom: CGFloat(zoom), bearing: bearing,
                                     pitch: pitch.map { CGFloat($0) })
        if lift > 0 {
            camera.padding = EdgeInsets(top: MapFocus.liftTop, leading: 0, bottom: lift, trailing: 0)
        }
        return camera
    }

    var animation: ViewportAnimation {
        switch glide {
        case .settle: .easeOut(duration: 0.45)
        case .home:   .fly(duration: 0.8)
        case .level:  .easeOut(duration: 0.4)
        case .arrive: .fly(duration: 0.8)
        }
    }
}
