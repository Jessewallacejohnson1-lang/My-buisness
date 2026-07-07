//
//  InterestPickerView.swift
//  Hygge — "What are you into around town?" The reference's photo-card grid,
//  grouped into sections. Gentle: pick a few (min 1). Sticky coral CTA with a
//  live count. Cards fade+rise in on first appear.
//

import SwiftUI

struct InterestPickerView: View {
    @Binding var selected: Set<String>
    let name: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var heading: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "What are you into?" : "What are you into, \(n)?"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingTopBar(index: 1, total: 3, onBack: onBack).padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading)
                        .font(.display(28))
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick a few — we'll quietly surface what fits around St. Joe.")
                        .font(.sans(15))
                        .foregroundStyle(Hue.ink2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(Interests.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.sansSemibold(13))
                                .foregroundStyle(Hue.ink3)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(section.items) { interest in
                                    InterestCard(interest: interest,
                                                 selected: selected.contains(interest.id)) {
                                        toggle(interest.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 16)
            }

            footer
        }
        .background(Hue.canvas.ignoresSafeArea())
        .onAppear {
            guard !appeared else { return }
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Hue.hairline).frame(height: 1)
            ContinueButton(title: selected.isEmpty ? "Pick a few to continue" : "Continue · \(selected.count)",
                           enabled: !selected.isEmpty) {
                Haptics.selection(); onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Hue.canvas)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
