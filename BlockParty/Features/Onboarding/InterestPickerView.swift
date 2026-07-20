//
//  InterestPickerView.swift
//  Block Party — "What are you into around town?" The reference's photo-card grid,
//  grouped into sections. Gentle: pick a few (min 1). Sticky coral CTA with a
//  live count. Cards fade+rise in on first appear.
//

import SwiftUI

struct InterestPickerView: View {
    @Binding var selected: Set<String>
    let name: String
    let onBack: () -> Void
    let onContinue: () -> Void
    /// Onboarding shows the 3-step progress bar + "Continue"; the profile editor
    /// reuses this grid with a plain back row + a "Done" CTA (`showsProgress: false`).
    var showsProgress: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var ctaTitle: String {
        if selected.isEmpty { return showsProgress ? "Pick a few to continue" : "Choose a few" }
        return showsProgress ? "Continue · \(selected.count)" : "Done · \(selected.count)"
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var heading: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "What are you into?" : "What are you into, \(n)?"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if showsProgress {
                    OnboardingTopBar(index: 1, total: 3, onBack: onBack).padding(.top, 8)
                } else {
                    HStack { OnboardingBackButton(action: onBack); Spacer() }.padding(.top, 8)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading)
                        .font(.display(28))
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick a few. We'll show events, clubs, and trails that match.")
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
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
                                .foregroundStyle(Hue.inkSecondary)
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
        .background(Hue.paper.ignoresSafeArea())
        .onAppear {
            guard !appeared else { return }
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Hue.hairline).frame(height: 1)
            ContinueButton(title: ctaTitle, enabled: !selected.isEmpty) {
                Haptics.selection(); onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Hue.paper)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
