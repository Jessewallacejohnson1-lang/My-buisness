import SwiftUI

/// The feed's monochrome refresh mark: one small block turning once per second.
struct BlockMotifSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Hue.ink)
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
            .animation(
                reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                value: rotation
            )
            .onAppear { updateRotation() }
            .onChange(of: reduceMotion) { _, _ in updateRotation() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Refreshing feed")
    }

    private func updateRotation() {
        rotation = reduceMotion ? 0 : 360
    }
}
