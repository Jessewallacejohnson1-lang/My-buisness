//
//  BPProgressBar.swift
//  Block Party — the textured capsule.
//
//  Signature mechanic #2.
//
//  MEASURED off the reference (S16, long fill, x=550 vertical scan): a 16pt capsule.
//  Track #E7E4E7 (≈ `Hue.hairline`). The fill carries a LIGHTER stripe along its top —
//  sampled #5ACD05 → #7ED733, i.e. white at ~20%, sitting 4pt down from the fill's top
//  and 5pt tall. That stripe is the "texture" that makes the bar read as Duolingo's
//  rather than a stock ProgressView.
//
//  The fill is a capsule in its own right, not a clipped rectangle: at low progress it
//  must stay a rounded lozenge (S06 shows a 17pt-wide fill that is still fully round),
//  so the fill width is floored at the bar height.
//
//  Advance carries a spring overshoot — the pulse the acceptance checklist asks for
//  comes free from the spring rather than a separate scale animation.
//

import SwiftUI

struct BPProgressBar: View {
    /// 0…1.
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let h = BP.Metric.progressHeight
            let clamped = min(max(progress, 0), 1)
            let full = geo.size.width
            // Floor at `h` so a barely-started bar is still a round lozenge, and never
            // let it exceed the track.
            let w = clamped <= 0 ? 0 : min(max(full * clamped, h), full)

            ZStack(alignment: .leading) {
                Capsule(style: BP.Metric.cornerStyle)
                    .fill(BP.hairline)

                Capsule(style: BP.Metric.cornerStyle)
                    .fill(BP.orange)
                    .overlay(alignment: .top) {
                        // The highlight stripe. Inset from the fill's ends so it never
                        // pokes through the capsule's rounded caps.
                        Capsule(style: BP.Metric.cornerStyle)
                            .fill(BP.fillHighlight)
                            .frame(height: BP.Metric.progressStripeHeight)
                            .padding(.horizontal, BP.Metric.progressStripeInset)
                            .padding(.top, BP.Metric.progressStripeTop)
                    }
                    .frame(width: w)
                    .opacity(w > 0 ? 1 : 0)
            }
            .frame(height: h)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : BP.Motion.progress, value: clamped)
        }
        .frame(height: BP.Metric.progressHeight)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(max(progress, 0), 1)) * 100)) percent")
    }
}

/// Back arrow + progress bar, laid out as the reference has them: the arrow at the
/// left margin, the bar filling the rest of the row to a 16pt right margin.
///
/// MEASURED (S06): the bar starts at x=60.3pt and ends at x=377pt — 317pt wide on a
/// 393.3pt screen, with the arrow occupying the space to its left.
struct BPTopBar: View {
    var progress: Double?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button {
                    Haptics.selection()
                    onBack()
                } label: {
                    // A full arrow, not a chevron — measured off S05, where the glyph
                    // has a visible shaft.
                    Image(systemName: "arrow.left")
                        .font(.system(size: BP.Metric.backArrowSize, weight: .medium))
                        .foregroundStyle(BP.gray)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            if let progress {
                BPProgressBar(progress: progress)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(height: 32)
        .padding(.horizontal, BP.Metric.pageMargin)
    }
}
