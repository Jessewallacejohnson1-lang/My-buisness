//
//  GlassShowcaseOverlay.swift
//  Block Party — the town-menu glass showcase.
//
//  Tapping Home's top-right ⋮ button frosts the WHOLE app into glass (the rest of
//  the screen fades out and recedes) and grows the town-menu panel out of the
//  top-right corner — the same narrow corner format as before (~56% width, big
//  corner radius, a mild grow from the corner), only now the panel is translucent
//  glass instead of a solid card, so the frosted app reads faintly through it.
//
//  The panel wraps its content: it sits at the top with no blank space and only
//  extends downward as menu items are added — never a fixed near-full height.
//
//  Motion is owned here so it honors Reduce Motion (grow + fade in, quick fade
//  out, plain cross-fade when the OS asks for no motion). Dismiss is a backdrop
//  tap or a row selection (both call the animated `close`). Generic: it wraps any
//  content and hands it `close`. Hosted in MainTabsView, above the tab bar.
//

import SwiftUI

struct GlassShowcaseOverlay<Content: View>: View {
    /// Owned by the host (MainTabsView). Flip true to present; the overlay flips
    /// it back to false itself once the collapse has finished.
    @Binding var isPresented: Bool
    /// The panel. Receives the animated `close` action to wire to its own chrome.
    @ViewBuilder var content: (@escaping () -> Void) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var grown = false   // uniform scale up from the corner
    @State private var shown = false   // opacity

    // Reference-matched geometry — the narrow corner format is unchanged; only the
    // height is now content-driven (no fixed full-height frame).
    private let widthFrac: CGFloat = 0.56
    private let corner: CGFloat = 40
    private let startScale: CGFloat = 0.80   // uniform, from the top-right corner

    private var growSpring: Animation { .spring(duration: 0.46, bounce: 0.16) }
    private var closeSpring: Animation { .spring(duration: 0.26, bounce: 0) }

    var body: some View {
        GeometryReader { geo in
            let topPad = geo.safeAreaInsets.top + 2
            let fullW = geo.size.width * widthFrac

            ZStack(alignment: .topTrailing) {
                if isPresented {
                    // The whole app frosts into glass and fades out behind the panel.
                    Rectangle()
                        .fill(.regularMaterial)
                        .overlay(Hue.paper.opacity(0.45))
                        .overlay(Color.black.opacity(0.04))
                        .opacity(shown ? 1 : 0)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Close menu")

                    // Content-sized glass panel, anchored top-right: it wraps the
                    // menu (no blank space) and only grows down as items are added.
                    content(close)
                        .frame(width: fullW, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.20), radius: 30, x: 0, y: 14)
                        .scaleEffect(reduceMotion ? 1 : (grown ? 1 : startScale), anchor: .topTrailing)
                        .opacity(shown ? 1 : 0)
                        .padding(.top, topPad)
                        .padding(.trailing, 8)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: isPresented, initial: true) { _, present in
            guard present else { return }
            grown = false; shown = false
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.28)) { grown = true; shown = true }
            } else {
                withAnimation(.easeOut(duration: 0.24)) { shown = true }
                withAnimation(growSpring) { grown = true }
            }
        }
    }

    /// Shrink back toward the corner, then unmount once it has settled.
    private func close() {
        Haptics.light()
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { grown = false; shown = false }
        } else {
            withAnimation(closeSpring) { grown = false }
            withAnimation(.easeOut(duration: 0.2)) { shown = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 0.27)) {
            isPresented = false
        }
    }
}
