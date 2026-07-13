//
//  Masthead.swift
//  Hygge — Home header: wordmark, today's date, and the one menu button.
//
//  The menu button carries a small vertical three-dot affordance (⋮), ported
//  from the reference: on tap the button gives a little bounce, the dots fade
//  away, and — a beat later — the town menu drawer unfolds out of the corner.
//  The dots fade back once the drawer closes.
//

import SwiftUI

struct Masthead: View {
    var onMenu: (() -> Void)?      // the one top-right button → the town menu drawer
    /// Mirrors the drawer's presented state so the dots restore on close.
    var menuOpen: Bool = false

    /// Tapped → dots gone (stays gone while the drawer is open).
    @State private var activated = false
    /// One-shot scale pulse on tap.
    @State private var bounce = false

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hygge")
                    .font(.display(34))
                    .foregroundStyle(Hue.ink)
                // The personal hello now lives in the Almanac's daily greeting just
                // below; the masthead keeps only the wordmark + today's date.
                Text(dateLine)
                    .font(.mono(13))
                    .monospacedDigit()
                    .foregroundStyle(Hue.ink2)
            }
            Spacer()
            menuButton.padding(.top, 4)
        }
        // Restore the dots when the drawer closes.
        .onChange(of: menuOpen) { _, open in
            if !open { withAnimation(.easeOut(duration: 0.28)) { activated = false } }
        }
        .onAppear(perform: debugAutoTap)
    }

    /// DEBUG-only: `-tap-menu` fires the button's tap ~1.2s after Home appears so
    /// the bounce + dots-leave + drawer hand-off can be recorded headlessly.
    private func debugAutoTap() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-tap-menu") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { tap() }
        #endif
    }

    // MARK: - Menu button (⋮ dots + avatar-style circle)

    private var menuButton: some View {
        HStack(spacing: 9) {
            // Vertical three dots — the "menu" affordance. Fades + shrinks toward
            // the button as it's tapped, then restores on close.
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Hue.ink3).frame(width: 4, height: 4)
                }
            }
            .opacity(activated ? 0 : 1)
            .scaleEffect(activated ? 0.4 : 1, anchor: .trailing)
            .blur(radius: activated ? 1.5 : 0)

            Button(action: tap) {
                Image(systemName: "person")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .scaleEffect(bounce ? 1.12 : 1)
            .accessibilityLabel("Menu")
        }
    }

    /// The little reaction, then hand off to the drawer a beat later (matches the
    /// reference: the button bounces + the dots leave before the panel unfolds).
    private func tap() {
        guard let onMenu else { return }
        let s = slowTap
        Haptics.light()
        withAnimation(.easeOut(duration: 0.18 * s)) { activated = true }
        withAnimation(.spring(response: 0.26 * s, dampingFraction: 0.42)) { bounce = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13 * s) {
            withAnimation(.spring(response: 0.34 * s, dampingFraction: 0.62)) { bounce = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * s) { onMenu() }
    }

    /// DEBUG-only: `-slow-tap` stretches the tap reaction ~4× so it can be
    /// captured frame-by-frame. 1× (no-op) otherwise.
    private var slowTap: Double {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-slow-tap") ? 4 : 1
        #else
        return 1
        #endif
    }
}
