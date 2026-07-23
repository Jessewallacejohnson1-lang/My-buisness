//
//  MapCompass.swift
//  Block Party — the map's north indicator.
//
//  The built-in Mapbox compass is deliberately suppressed (SJMapView's OrnamentOptions): its
//  needle is coral, which the monochrome ink-on-paper brand deletes, its fade is a fixed 0.3s,
//  and its tap resets bearing only. This is the on-brand replacement — the same 44pt chrome
//  bubble the map's other controls use (surface fill, hairline, float shadow), carrying the one
//  signature detail: a two-tone needle (ink north / grey south) that tracks the live bearing so
//  it always points to true north. Adaptive: hidden at north, fades in over 0.25s when the map
//  is turned. Tapping eases the map back to bearing 0 AND pitch 0 (handled by the owner).
//

import SwiftUI
import Combine
import CoreLocation
import MapboxMaps

/// Live camera heading fed from `SJMapView.onCameraChanged`. Held by the map view as `@State`
/// (a stable reference that does NOT subscribe the map view to this object's publisher) and
/// observed here as `@ObservedObject`, so a per-frame bearing update re-renders ONLY the
/// compass — never the whole map — which is what keeps rotation smooth at 120 Hz.
@MainActor
final class CompassHeading: ObservableObject {
    /// Map bearing in degrees (0 = north-up). Drives needle rotation + adaptive visibility.
    @Published var bearing: Double = 0
    /// Map pitch in degrees (0 = flat). Not drawn, but reset alongside bearing on tap.
    @Published var pitch: Double = 0

    /// Last camera center + zoom — plain (unpublished) so writing them every frame never
    /// churns SwiftUI. `resetNorth` reads them so "face north" rotates level in place rather
    /// than recentering.
    private(set) var center = MapSpots.center
    private(set) var zoom: Double = 13.5

    /// Fold in a camera frame. Center/zoom always update (cheap, unobserved); bearing/pitch
    /// only publish when they actually move, so a pure pan/zoom (bearing 0) never re-renders
    /// the compass.
    func update(cameraState: CameraState) {
        center = cameraState.center
        zoom = Double(cameraState.zoom)
        let newBearing = cameraState.bearing
        let newPitch = Double(cameraState.pitch)
        if newBearing != bearing { bearing = newBearing }
        if newPitch != pitch { pitch = newPitch }
    }
}

/// The compass control. Fades in when the map is turned off-north and rotates its needle to
/// keep pointing at true north; tapping asks the owner to level the camera.
struct MapCompass: View {
    @ObservedObject var heading: CompassHeading
    /// Container Reduce Motion (from `SJMapView`): drop the appear-scale, keep the fade.
    var reduceMotion: Bool
    var onReset: () -> Void

    /// Below this the map reads as north-up and the compass hides (Apple's adaptive behavior).
    private static let northThreshold: Double = 0.5

    /// Angular distance from north, 0…180 — symmetric so 359° reads as 1° off north, not 359°.
    private var northOffset: Double {
        let b = heading.bearing.truncatingRemainder(dividingBy: 360)
        let m = b < 0 ? b + 360 : b
        return min(m, 360 - m)
    }

    private var isVisible: Bool { northOffset > Self.northThreshold }

    var body: some View {
        Button(action: onReset) {
            ZStack {
                Circle()
                    .fill(Hue.surface)
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
                    .mapFloatShadow()
                CompassNeedle()
                    // Counter-rotate by the bearing so the ink half always points at true
                    // north. No implicit animation here — the value updates every camera frame,
                    // so it tracks the two-finger twist 1:1 instead of lagging behind a spring.
                    .rotationEffect(.degrees(-heading.bearing))
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.86))
        // Adaptive fade — 0.25s, scoped to the visibility flip so it never animates the needle's
        // per-frame rotation.
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        // An invisible compass must not swallow taps meant for the map or the recenter control.
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .accessibilityLabel("Point north")
        .accessibilityHint("Rotates the map to face north and level")
        .accessibilityAddTraits(.isButton)
    }
}

/// A slim compass needle: two triangles meeting at the center, tapering to points top and
/// bottom. North (up) is ink and dominant; south is a recessive grey — the same value hierarchy
/// the rest of the map uses to carry meaning without a second hue.
private struct CompassNeedle: View {
    var body: some View {
        VStack(spacing: 0) {
            NeedleHalf()
                .fill(Hue.ink)
                .frame(width: 7, height: 11)
            NeedleHalf()
                .fill(Hue.inkSecondary)
                .frame(width: 7, height: 11)
                .rotationEffect(.degrees(180))
        }
    }
}

/// One half of the needle: an isosceles triangle with its apex at the top edge and its base
/// along the bottom edge (the needle's midline). Rotated 180° for the south half.
private struct NeedleHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))   // apex (a point of the needle)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) // base corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)) // base corner
        path.closeSubpath()
        return path
    }
}
