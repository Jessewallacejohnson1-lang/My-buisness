//
//  LogoPop.swift
//  Block Party — Search's logos come in together and pop. Each one waits as a shimmering
//  skeleton until every logo Search shows has loaded (or `LogoReveal.gateWait` has passed),
//  then grows from half size while it swings down from above on a soft elastic and settles,
//  one after another from the top left. A logo pops once per app open.
//
//  Reference: Jesse's mock v5 (2026-10-21, "elastic", https://claude.ai/artifact/U4wbhBW9Lks6e6jJXASAaH,
//  `BP app/references/search-bubbles/`). Its springs are stepped by hand there, so here they
//  are the same springs in closed form, driven by one linear clock: that is what lets the
//  logo stretch with its own speed.
//

import SwiftUI

/// When Search's logos may pop, and in what order.
@MainActor @Observable
final class LogoReveal {
    static let shared = LogoReveal()

    /// Every logo Search shows has loaded, or the wait ran out. Stays open for the app's life.
    private(set) var open = false
    @ObservationIgnored private var popped: Set<URL> = []
    @ObservationIgnored private var lastSlot = Date.distantPast
    @ObservationIgnored private var run = 0

    /// The longest the skeletons wait for the slowest logo; later ones pop on their own.
    static let gateWait: Duration = .seconds(2)
    /// One logo starts this long after the one before it, up to `staggerCap` of them.
    static let stagger = 0.044
    static let staggerCap = 10

    /// Opens once every one of `urls` is in the logo cache, or after `gateWait`.
    func open(after urls: [URL]) async {
        let clock = ContinuousClock(), end = clock.now + Self.gateWait
        // ponytail: polls every 50 ms; the cache's publisher if this ever shows in a profile.
        while !open, clock.now < end, !urls.allSatisfy({ POILogoCache.shared.image(for: $0) != nil }) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        open = true
    }

    /// The delay before `url` pops, or nil when it already popped this app open. Logos that
    /// ask within 0.3 s of each other are one wave, staggered in the order they asked.
    func slot(for url: URL, now: Date = .now) -> Double? {
        guard popped.insert(url).inserted else { return nil }
        if now.timeIntervalSince(lastSlot) > 0.3 { run = 0 }
        lastSlot = now
        defer { run += 1 }
        return Double(min(run, Self.staggerCap)) * Self.stagger
    }
}

/// A damped spring from `from` to 0 with no starting speed, `t` seconds in: SwiftUI's
/// `.spring(response:dampingFraction:)` for dampings under 1.
nonisolated func elasticOffset(_ t: Double, from: Double, response: Double, damping: Double) -> Double {
    let w = 2 * .pi / response, wd = w * (1 - damping * damping).squareRoot()
    return from * exp(-damping * w * t) * (cos(wd * t) + damping * w / wd * sin(wd * t))
}

extension View {
    /// Shows a shimmering `skeleton` until the logo at `url` may pop, then pops this view in.
    func logoPop(_ url: URL, skeleton: some View) -> some View {
        modifier(LogoPop(url: url, skeleton: skeleton))
    }
}

private struct LogoPop<Skeleton: View>: ViewModifier {
    let url: URL
    let skeleton: Skeleton
    @ObservedObject private var cache = POILogoCache.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seconds into the pop; `Elastic.done` once it has settled.
    @State private var t = 0.0
    @State private var shown = false

    func body(content: Content) -> some View {
        let ready = LogoReveal.shared.open && cache.image(for: url) != nil
        ZStack {
            if shown {
                content.modifier(Elastic(t: t, still: reduceMotion))
            } else {
                skeleton.shimmering().accessibilityHidden(true)
            }
        }
        .onChange(of: ready, initial: true) { _, ready in
            guard ready, !shown else { return }
            shown = true
            guard let delay = LogoReveal.shared.slot(for: url) else { t = Elastic.done; return }
            withAnimation(.linear(duration: Elastic.done).delay(delay)) { t = Elastic.done }
        }
        // The logo itself isn't drawn until it pops, so it is asked for here; one whose fetch
        // failed asks again when it is next on screen.
        .task(id: url) { cache.prefetch([url]) }
    }
}

/// The mock's pop: half size to full (response 0.61, damping 0.5) while it swings down from
/// 24 pt above (response 0.7, damping 0.42), a hair taller while it moves fastest, faded in
/// over its first 0.14 s. Reduce Motion: the fade alone.
private struct Elastic: ViewModifier, Animatable {
    var t: Double
    let still: Bool
    static let done = 1.2

    nonisolated var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        // One shape of modifiers at rest and moving, so the logo's own state never resets.
        let moving = !still && t < Self.done
        let s = moving ? 1 + elasticOffset(t, from: -0.5, response: 0.61, damping: 0.5) : 1
        let y = moving ? elasticOffset(t, from: -24, response: 0.7, damping: 0.42) : 0
        let speed = moving ? (elasticOffset(t + 0.004, from: -24, response: 0.7, damping: 0.42) - y) / 0.004 : 0
        let j = max(-0.04, min(0.04, speed * 0.0004))
        content
            .scaleEffect(x: s - j, y: s + j)
            .offset(y: y)
            .opacity(min(1, t / (still ? 0.3 : 0.14)))
    }
}
