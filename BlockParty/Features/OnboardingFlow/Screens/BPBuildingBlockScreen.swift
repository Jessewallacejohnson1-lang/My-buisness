//
//  BPBuildingBlockScreen.swift
//  S07 — the "building your block" interstitial.
//
//  Centred illustration, a small-caps letterspaced grey status label, one line of copy,
//  and Continue.
//
//  ── BLOCKED: the Joetown skyline silhouette ────────────────────────────────────────
//  The spec calls for "the Joetown white skyline silhouette knocked out of a bpOrange
//  rounded shape (rebuild the silhouette as vector from the logo asset; do NOT ship the
//  full Joetown logo)".
//
//  **That logo asset does not exist anywhere I can reach** — not in this repo, not in
//  the backend repo, not on the Desktop or in Downloads. The only "joetown" in the
//  codebase is an event keyword ("Joetown Rocks") in `Interests.swift`.
//
//  I have NOT invented a skyline. A city's silhouette is a civic mark; drawing a
//  plausible one from imagination would put a fabricated identity on a real town's app.
//  `BPBuildingBlockArt` therefore renders the composition — the orange rounded shape at
//  the right size and position, with the exact Block Party app mark over it — so the
//  rest of the screen can be verified 1:1 now. Swapping the silhouette in later is a
//  one-view change confined to this file.
//  ───────────────────────────────────────────────────────────────────────────────────
//
//  ── The live count ─────────────────────────────────────────────────────────────────
//  Jesse's Phase 0 gate decision: ship the FALLBACK COPY ONLY. There is no waitlist
//  table anywhere in either repo, no count RPC, and no function granted to `anon`; and
//  the repo's standing rule is "real data only — never seeded or inflated counts".
//  Pre-launch the number would sit under the spec's own <50 threshold and fall back
//  every time regardless, so the live path would be dead code that always renders the
//  fallback.
//
//  `neighborCount` is the seam, left unwired: pass a count and the emphasised line
//  renders; leave it nil and the fallback does. One line to switch on when a real
//  source exists.
//  ───────────────────────────────────────────────────────────────────────────────────
//

import SwiftUI

struct BPBuildingBlockScreen: View {
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    /// Live waitlist/member count. Nil (today, always) → the fallback line.
    var neighborCount: Int?

    /// Below this the spec says to use the fallback rather than a thin number.
    private static let minimumCount = 50

    var body: some View {
        VStack(spacing: 0) {
            BPScreenTop(step: step, onBack: onBack)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 26) {
                BPBuildingBlockArt()
                    .frame(width: 176, height: 176)

                Text("Building your block…")
                    .font(.sansSemibold(13))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(BP.gray)

                Text(line)
                    .font(.sans(17))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BP.ink)
                    .padding(.horizontal, 32)
            }

            Spacer()

            BPButton(title: "Continue", action: onContinue)
                .padding(.horizontal, BP.Metric.pageMargin)
                .padding(.bottom, BPLayout.buttonBottomGap)
        }
        .background(BP.paper.ignoresSafeArea())
    }

    private var line: AttributedString {
        guard let n = neighborCount, n >= Self.minimumCount else {
            return BPCopy.plain("Your neighbors are already here.")
        }
        return BPCopy.emphasised("Get ready to join the ",
                                 "\(n) neighbors",
                                 " already on Block Party!",
                                 tint: BP.orange)
    }
}

/// The interstitial's illustration.
///
/// PLACEHOLDER COMPOSITION — see the file header. The orange rounded shape is real and
/// positioned; the exact Block Party app mark stands in for the Joetown skyline
/// silhouette, which has no source asset.
struct BPBuildingBlockArt: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            RoundedRectangle(cornerRadius: s * 0.24, style: BP.Metric.cornerStyle)
                .fill(BP.orange)
                .overlay {
                    BPMark(side: s * 0.46)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Building your block")
    }
}
