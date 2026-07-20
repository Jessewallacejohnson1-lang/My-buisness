//
//  MapIntroView.swift
//  Block Party — the onboarding crescendo: an introduction to the town Map.
//
//  The last first-run beat (Welcome → Interests → this). Blooms back into the
//  coral brand field of the splash, then a real Mapbox porthole of downtown Saint
//  Joseph — centered on Minnesota St & College Ave, by the Church of St. Joseph
//  and Local Blend — assembles itself. Life360-style teardrop pins drop onto the
//  real venues by name, and one glows "live," teaching the map's single most
//  important idea (coral = happening right now) before the user reaches the tab.
//
//  Faithful to the Life360 "create your Circle" composition (title · circular map
//  · supporting line · pill button), in Block Party's coral+white system. The map is the
//  real thing (same cartography as SJMapView); the pins are art-directed overlays
//  — spread for legibility like the reference, not GPS-exact — so the download
//  reads clean. Motion mirrors the app's house rules: ease-out springs, a coral
//  pulse identical to the map's, and a full Reduce-Motion path (everything renders
//  in its final state, no pulse, no drift).
//

import SwiftUI
import CoreLocation
import MapboxMaps

/// Downtown: Minnesota St W at College Ave — the corner by the Church of St.
/// Joseph, Local Blend, and Bad Habit. Mirrors the "downtown" spot in MapSpots.
private let DOWNTOWN_CENTER = CLLocationCoordinate2D(latitude: 45.5647, longitude: -94.3184)

struct MapIntroView: View {
    /// The button label — "Explore the map" as the onboarding finale, "Got it"
    /// when it's reopened as a help sheet from the Map's "?" button.
    var ctaTitle: String = "Explore the map"
    /// When true (the Map's "?" help sheet), skip the staggered assemble-in and
    /// present the content at once — a reference shouldn't make you wait a second
    /// and re-watch the first-run bloom on every open.
    var instant: Bool = false
    /// Finishes onboarding, or dismisses the help sheet. (Trailing-closure call
    /// sites — `MapIntroView { … }` — bind here, so it stays the last parameter.)
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // One flag drives the assemble-in cascade; each element carries its own delayed
    // animation so the screen builds top-to-bottom (title → map → pins → text).
    // `pulseOn` starts the live heartbeat once its pin has landed; `breathe` is the
    // slow halo behind the disc. `ctaHittable` gates the button's touch target so
    // it's never tappable while it's still invisible (opacity 0 mid-reveal).
    @State private var revealed = false
    @State private var pulseOn = false
    @State private var breathe = false
    @State private var ctaHittable = false

    private let discSize: CGFloat = 264

    var body: some View {
        ZStack {
            // The field: brand coral across the top (matches the splash hand-off),
            // deepening toward the bottom so the support line + button clear a
            // legible contrast without leaving the coral identity.
            LinearGradient(
                stops: [
                    .init(color: Hue.ink, location: 0.0),
                    .init(color: Hue.ink, location: 0.45),
                    .init(color: Hue.ink, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                title
                    .padding(.top, 8)

                Spacer(minLength: 20)
                    .frame(maxHeight: 34)

                porthole

                Spacer(minLength: 20)

                supportLine
                    .padding(.horizontal, 34)
                    .padding(.bottom, 22)

                continueButton
                    .padding(.horizontal, 24)
            }
            .padding(.top, 12)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: runIntro)
    }

    // MARK: Title

    private var title: some View {
        Text("Everything in town,\non one map")
            .font(.display(34))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.55).delay(0.05), value: revealed)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Porthole (real map disc + pins + halo)

    private var porthole: some View {
        ZStack {
            // Slow breathing halo — keeps the disc from ever feeling static. Static
            // (and dimmer) under Reduce Motion.
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.30), .clear],
                    center: .center, startRadius: 8, endRadius: discSize * 0.72))
                .frame(width: discSize * 1.55, height: discSize * 1.55)
                .scaleEffect(breathe ? 1.06 : 0.92)
                // Gated on `revealed` like every sibling, so it fades in with the
                // disc instead of floating alone on the first frame.
                .opacity(revealed ? (breathe ? 0.9 : 0.55) : 0)
                .animation(reduceMotion || instant ? nil : .easeOut(duration: 0.5).delay(0.15), value: revealed)
                .allowsHitTesting(false)

            PortholeMap(size: discSize)
                .scaleEffect(revealed ? 1 : 0.96)
                .opacity(revealed ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.15), value: revealed)

            ForEach(pins) { pin in
                PinWithLabel(model: pin, pulseOn: pulseOn, reduceMotion: reduceMotion)
                    .scaleEffect(revealed ? 1 : 0.3, anchor: .center)
                    .opacity(revealed ? 1 : 0)
                    // Drops in from a touch above its resting spot, like a map pin
                    // landing.
                    .offset(x: pin.dx, y: revealed ? pin.dy : pin.dy - 22)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6).delay(pin.delay), value: revealed)
            }
        }
        .frame(width: 342, height: 360)
    }

    // MARK: Support line + button

    private var supportLine: some View {
        Text("Cafés, trails, and gatherings across St. Joe — all in one place. When a pin pulses, it's happening right now.")
            .font(.sansMedium(16))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.9), value: revealed)
    }

    private var continueButton: some View {
        Button {
            Haptics.success()
            onContinue()
        } label: {
            Text(ctaTitle)
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
        }
        .buttonStyle(WhitePillButtonStyle())
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(1.05), value: revealed)
        // Not tappable until it has actually faded in — an opacity-0 button still
        // hit-tests, so without this a blind tap in the first second would fire it.
        .allowsHitTesting(ctaHittable)
    }

    // MARK: Choreography

    private func runIntro() {
        // Reduce Motion, or the help sheet (`instant`): everything in its final
        // state at once — no staggered assemble-in.
        guard !reduceMotion && !instant else {
            revealed = true
            ctaHittable = true
            // The help sheet still gets gentle life (halo + heartbeat); Reduce
            // Motion stays fully still.
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathe = true }
                withAnimation(.easeOut(duration: 0.4)) { pulseOn = true }
            }
            return
        }
        // Onboarding finale: toggling `revealed` fires each element's own delayed
        // animation, building the screen top-to-bottom.
        revealed = true
        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathe = true }
        // Arm the button's touch target as it fades in (delay 1.05), and start the
        // live heartbeat once the Local Blend pin has landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { ctaHittable = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.4)) { pulseOn = true }
        }
    }

    // MARK: Pins — the real downtown Saint Joseph venues, art-directed around the
    // map so their names stay legible. Offsets are from the porthole center; icons
    // match the live map's `SpotCategory`. Local Blend is live.

    private var pins: [IntroPinModel] {
        [
            IntroPinModel(name: "Local Blend",   icon: "cup.and.saucer.fill", live: true,  dx: -32, dy: -88, delay: 0.55),
            IntroPinModel(name: "Bad Habit",     icon: "mug.fill",            live: false, dx:  94, dy: -34, delay: 0.68),
            IntroPinModel(name: "Krewe",         icon: "fork.knife",          live: false, dx:  46, dy:  72, delay: 0.81),
            IntroPinModel(name: "St. Joe Church", icon: "building.columns.fill", live: false, dx: -90, dy: 22, delay: 0.94),
        ]
    }
}

// MARK: - Pin model

private struct IntroPinModel: Identifiable {
    let name: String
    let icon: String
    let live: Bool
    let dx: CGFloat
    let dy: CGFloat
    let delay: Double
    var id: String { name }
}

// MARK: - Real map porthole
//
// A live Mapbox map of downtown Saint Joseph clipped into a white-rimmed disc,
// styled with the same neutral cartography as SJMapView. Non-interactive — it's a
// preview, not a control.

private struct PortholeMap: View {
    let size: CGFloat

    @State private var viewport: Viewport = .camera(
        center: DOWNTOWN_CENTER, zoom: 15.7, bearing: 0, pitch: 0)

    var body: some View {
        MapReader { proxy in
            Map(viewport: $viewport)
                .mapStyle(MapStyle(uri: StyleURI(rawValue: "mapbox://styles/mapbox/light-v11")!))
                .onStyleLoaded { _ in BasemapPalette.recolor(proxy.map) }
        }
        // Render taller than the clip circle so Mapbox's bottom-edge logo +
        // attribution fall outside the porthole (attribution lives on the real
        // map tab); the circle stays clean.
        .frame(width: size, height: size + 96)
        .clipShape(Circle())
        .frame(width: size, height: size)
        .overlay(
            // A soft inner vignette for depth, then the crisp white porthole rim.
            Circle()
                .fill(RadialGradient(colors: [.clear, .black.opacity(0.05)],
                                     center: .center, startRadius: size * 0.36, endRadius: size * 0.5))
                .allowsHitTesting(false)
        )
        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        .overlay(Circle().strokeBorder(Hue.hairline.opacity(0.7), lineWidth: 1).padding(3))
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 10)
    }
}

// MARK: - Teardrop pin + name label (Life360 lockup)

private struct PinWithLabel: View {
    let model: IntroPinModel
    let pulseOn: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 3) {
            TeardropPin(icon: model.icon, live: model.live,
                        pulseOn: pulseOn, reduceMotion: reduceMotion)
            label
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.live ? "\(model.name), happening now" : model.name)
    }

    private var label: some View {
        HStack(spacing: 4) {
            if model.live {
                Circle().fill(Hue.ink).frame(width: 5, height: 5)
            }
            Text(model.name)
                .font(.sansSemibold(11))
                .foregroundStyle(model.live ? Hue.ink : Hue.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(Hue.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 1)
        .fixedSize()
    }
}

/// A rounded map pin — a white (or coral, when live) head with a pointed tail,
/// built from a circle over a 45°-rotated rounded square so the point stays soft.
/// The live head is solid coral with a white glyph and carries the same pulse ring
/// the map uses.
private struct TeardropPin: View {
    let icon: String
    let live: Bool
    let pulseOn: Bool
    let reduceMotion: Bool

    private let head: CGFloat = 42

    var body: some View {
        ZStack {
            if live && pulseOn && !reduceMotion {
                IntroPulseRing()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill)
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(45))
                    .offset(y: 15)
                Circle()
                    .fill(fill)
                    .frame(width: head, height: head)
            }
            .compositingGroup()
            .mapFloatShadow()
            .overlay(
                // Hairline keeps the white pin crisp against pale map tiles.
                Circle()
                    .stroke(live ? Color.clear : Hue.hairline, lineWidth: 1)
                    .frame(width: head, height: head)
            )

            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(live ? .white : Hue.ink)
        }
        .frame(width: 48, height: 58, alignment: .center)
    }

    private var fill: Color { live ? Hue.ink : Hue.surface }
}

/// The live heartbeat — coral 0.35 → 0, scale 1 → 2.2, 1.5s loop. Identical to the
/// map's `PulseRing`. Only mounted when motion is allowed.
private struct IntroPulseRing: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Hue.ink.opacity(pulsing ? 0 : 0.35))
            .frame(width: 42, height: 42)
            .scaleEffect(pulsing ? 2.2 : 1.0)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Button style
//
// White rounded-square button on the ink field, ink label, soft lift.

private struct WhitePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.white,
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    MapIntroView(onContinue: {})
}
