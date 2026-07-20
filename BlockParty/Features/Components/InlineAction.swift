//
//  InlineAction.swift
//  Block Party — a self-contained "do one async thing, then confirm it" action.
//
//  Ported from a React/Motion component the app liked, rebuilt natively and
//  re-skinned onto the ink-on-paper system: an icon chip + label on the left,
//  and a right-hand control that runs idle → loading (indeterminate ink bar) →
//  success (collapses to an ink disc with a shimmer sweep + checkmark).
//
//  Unlike the source, success is TERMINAL here (it settles into "done" instead of
//  auto-resetting) — a calendar-add shouldn't invite an accidental second tap.
//  A failure surfaces briefly, then returns to idle so the user can retry.
//

import SwiftUI

struct InlineAction: View {
    let icon: String                 // SF Symbol for the left chip
    let label: String                // resting description ("Add to your calendar")
    let doneLabel: String            // after success ("Added to your calendar")
    let actionText: String           // the verb on the button ("Add")
    let perform: () async throws -> Void

    @State private var phase: Phase = .idle
    @State private var failureNote: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case idle, loading, success, error }
    private var collapsed: Bool { phase == .success || phase == .error }

    private var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.16)
                     : .spring(response: 0.32, dampingFraction: 0.86)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: 46, height: 46)
                .background(Hue.fill)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(phase == .success ? doneLabel : label)
                    .font(.sansBold(16))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .contentTransition(.opacity)
                if let failureNote {
                    Text(failureNote)
                        .font(.sansBold(11))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 8)

            control
                .frame(width: collapsed ? 46 : 118, height: 46)
                .background(moduleFill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity)
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .modifier(CardShadow())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(phase == .idle ? .isButton : [])
        .accessibilityAction { if phase == .idle { trigger() } }
    }

    @ViewBuilder private var control: some View {
        ZStack {
            switch phase {
            case .idle:
                Button(action: trigger) {
                    Text(actionText)
                        .font(.sansBold(14))
                        .foregroundStyle(Hue.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.blurFade)

            case .loading:
                LoadingBar(reduceMotion: reduceMotion)
                    .padding(.horizontal, 12)
                    .transition(.blurFade)

            case .success:
                SuccessDisc(reduceMotion: reduceMotion)
                    .transition(.blurFade)

            case .error:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.blurFade)
            }
        }
    }

    private var moduleFill: Color {
        switch phase {
        case .idle, .loading: return Hue.fill
        case .success:        return Hue.ink
        case .error:          return Hue.ink
        }
    }

    private var accessibilityValue: String {
        switch phase {
        case .idle:    return actionText
        case .loading: return "Adding…"
        case .success: return "Added"
        case .error:   return failureNote ?? "Couldn't add these events"
        }
    }

    private func trigger() {
        guard phase == .idle else { return }
        Haptics.light()
        withAnimation(spring) {
            failureNote = nil
            phase = .loading
        }
        Task {
            do {
                try await perform()
                Haptics.success()
                withAnimation(spring) { phase = .success }
            } catch {
                Haptics.error()
                let note = (error as? LocalizedError)?.errorDescription ?? "Couldn't add these events. Try again."
                withAnimation(spring) {
                    failureNote = note
                    phase = .error
                }
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(spring) {
                    failureNote = nil
                    phase = .idle
                }
            }
        }
    }
}

// MARK: - Loading: an indeterminate ink bar sliding left ↔ right

private struct LoadingBar: View {
    let reduceMotion: Bool
    @State private var animating = false

    var body: some View {
        if reduceMotion {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Hue.ink)
                .scaleEffect(0.72)
                .frame(maxWidth: .infinity)
        } else {
            GeometryReader { geo in
                let trackW = geo.size.width
                let pillW = max(18, trackW * 0.34)
                Capsule()
                    .fill(Hue.fill)
                    .frame(height: 6)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Hue.ink)
                            .frame(width: pillW, height: 6)
                            .offset(x: animating ? trackW - pillW : 0)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: animating
                            )
                    }
            }
            .onAppear { animating = true }
        }
    }
}

// MARK: - Success: ink disc, a one-shot shimmer sweep, a checkmark that pops in

private struct SuccessDisc: View {
    let reduceMotion: Bool
    @State private var sweep = false
    @State private var checkIn = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                GeometryReader { geo in
                    let w = geo.size.width
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.85)
                        .rotationEffect(.degrees(-22))
                        .offset(x: sweep ? w * 1.1 : -w * 1.1)
                }
                .mask(Circle())
            }
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(checkIn ? 1 : 0.4)
                .opacity(checkIn ? 1 : 0)
        }
        .frame(width: 46, height: 46)
        .onAppear {
            if reduceMotion {
                checkIn = true
                return
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.58).delay(0.06)) {
                checkIn = true
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { sweep = true }
        }
    }
}

// MARK: - A soft blur-and-fade transition for swapping the control's contents

private struct BlurFade: ViewModifier {
    var blur: CGFloat
    var opacity: Double
    func body(content: Content) -> some View {
        content.blur(radius: blur).opacity(opacity)
    }
}

private extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(blur: 4, opacity: 0),
                  identity: BlurFade(blur: 0, opacity: 1))
    }
}
