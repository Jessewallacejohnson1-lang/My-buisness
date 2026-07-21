//
//  LoaderBlockPartyMark.swift
//  Block Party — the framed wordmark used as the launch loader's centre mark.
//
//  Recreates the app-icon lockup as a vector so it scale-pulses crisply: an ink
//  square frame (square-cornered, per the brand's "square-framed marks, not
//  circles") holding "Block / Party" in Jost. On the paper loader field the frame's
//  interior is left open (paper shows through), exactly as the icon reads.
//

import SwiftUI

struct BlockPartyMark: View {
    /// Outer side length of the square frame, in points.
    let side: CGFloat

    var body: some View {
        let stroke = side * 0.072
        let radius = side * 0.045          // barely rounded — essentially square
        let inset = side * 0.155
        let fontSize = side * 0.225

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Hue.ink, lineWidth: stroke)

            Text("Block\nParty")
                .font(.logo(fontSize))                 // Jost SemiBold
                .foregroundStyle(Hue.ink)
                .kerning(fontSize * 0.005)
                .lineSpacing(-fontSize * 0.14)          // tight, like the icon
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset)
                .minimumScaleFactor(0.5)
        }
        .frame(width: side, height: side)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("Block Party")
    }
}

#Preview {
    ZStack {
        Hue.paper.ignoresSafeArea()
        BlockPartyMark(side: 160)
    }
}
