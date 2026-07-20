//
//  ExploreSearchOverlay.swift
//  Block Party — the focused search experience. Pressing search fades the whole screen
//  (tab bar included) into a white-tinted frosted glass; one crisp white search
//  pill floats above it with a shadow, and below it a minimal, icon-less column of
//  light-grey "search guesses". Presented as a `fullScreenCover` so it sits over
//  everything, with a hand-rolled fade (the cover itself is toggled without
//  animation — see `ActivitiesView.setSearchPresented` — and this view owns the
//  fade in AND out via `visible`, so both edges are a clean cross-fade).
//
//  Motion (Emil Kowalski's framework): the glass + bar rise in on a smooth,
//  near-critically-damped spring (no overshoot — fluent, not bouncy) with a soft
//  blur that resolves to zero — blur masks the transition so it reads as one
//  fluid materialisation rather than a hard fade. It's an occasional, deliberate
//  overlay, so a real entrance is right here (unlike a per-keystroke dropdown).
//  Guesses swap instantly as you type — no per-keystroke animation. Reduce Motion
//  drops the scale/offset/blur and just cross-fades. Only per-row motion is the press "pop".
//

import SwiftUI

struct ExploreSearchOverlay: View {
    @Binding var query: String
    let suggestions: [Suggestion]
    var onPick: (Suggestion) -> Void
    var onCancel: () -> Void
    /// Commit the typed query as a plain text search (keyboard "Search" key).
    var onSubmit: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    /// Guards `dismiss` so a second tap during the fade-out can't fire a second
    /// action (e.g. open-place AND cancel).
    @State private var dismissing = false

    // Fluent, near-critically-damped spring in (damping 0.9 → no bounce); a slightly
    // quicker eased fade out. Reduce Motion collapses both to a plain cross-fade.
    private var enterAnim: Animation {
        reduceMotion ? .easeOut(duration: 0.22) : .spring(response: 0.5, dampingFraction: 0.9)
    }
    private var dismissDur: Double { reduceMotion ? 0.16 : 0.26 }
    private var exitAnim: Animation {
        reduceMotion ? .easeOut(duration: dismissDur) : .easeInOut(duration: dismissDur)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // White-tinted frosted glass over the entire screen. Tapping it (i.e.
            // anywhere outside the bar + guesses) dismisses the search.
            Rectangle()
                .fill(.ultraThinMaterial)                         // more transparent glass
                .overlay(Color.white.opacity(0.12))               // the faintest white tint
                .ignoresSafeArea()
                .opacity(visible ? 1 : 0)
                .contentShape(Rectangle())
                .allowsHitTesting(visible)                        // don't capture taps while faded out
                .onTapGesture { dismiss { onCancel() } }

            VStack(spacing: 18) {
                searchBar
                guesses
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.98, anchor: .top)
            .offset(y: visible || reduceMotion ? 0 : -8)
            .blur(radius: visible || reduceMotion ? 0 : 8)         // resolves in — softens the entrance
        }
        .onAppear {
            withAnimation(enterAnim) { visible = true }
            // Focus a beat later so the field is in the hierarchy and the keyboard
            // rises with the glass rather than before it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
        }
    }

    /// Fade the content out first, then run the real action (which removes the
    /// cover) — so dismissal reads as the same cross-fade as the entrance.
    private func dismiss(_ action: @escaping () -> Void) {
        guard !dismissing else { return }
        dismissing = true
        focused = false
        withAnimation(exitAnim) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDur) { action() }
    }

    // MARK: - The one crisp element

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Hue.inkSecondary)
                TextField("Search St. Joe", text: $query)
                    .font(.sans(17))
                    .foregroundStyle(Hue.ink)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    // "Search" commits the typed text (reference-aware filtered list),
                    // not the top row — so it never surprises by opening a Place detail.
                    .onSubmit { dismiss { onSubmit() } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Hue.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Hue.surface)                                  // crisp white
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)

            Button("Cancel") { dismiss { onCancel() } }
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .buttonStyle(.plain)
        }
    }

    // MARK: - Minimal guesses (text only, no icons, light grey)

    private var guesses: some View {
        let shown = Array(suggestions.prefix(8))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                Button { dismiss { onPick(s) } } label: {
                    Text(s.title)
                        .font(.sans(16))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                if i < shown.count - 1 {
                    Divider().overlay(Color.primary.opacity(0.06))
                }
            }
        }
        .padding(.horizontal, 8)
    }
}
