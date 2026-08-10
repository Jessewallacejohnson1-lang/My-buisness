//
//  ForYouPreview.swift
//  Block Party — DEBUG-only full-screen coverage for all For You states.
//

#if DEBUG
import SwiftUI

struct ForYouPreview: View {
    @StateObject private var module = ForYouModule()

    private var context: FeedModuleContext {
        FeedModuleContext(
            auth: .shared,
            briefing: BriefingModel(),
            displayName: "DEBUG neighbor",
            navigate: { _ in },
            revealed: true,
            contentRevealed: true,
            revealAnimated: false
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(debugLabel)
                    .font(.monoMedium(10))
                    .tracking(1)
                    .foregroundStyle(Hue.inkSecondary)

                if module.phase == .empty {
                    hiddenStateProof
                } else {
                    module.makeView(context)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(Hue.paper.ignoresSafeArea())
        .task { await module.load(context) }
    }

    private var debugLabel: String {
        switch module.contentState {
        case .needsInterests:
            "DEBUG FIXTURE · NO INTEREST TAGS"
        case .noMatches:
            "DEBUG FIXTURE · TAGS WITH NO MATCHES"
        case .recommendations:
            "DEBUG FIXTURE · THREE MATCHED POSTINGS"
        case .failed:
            "DEBUG FIXTURE · FAILED"
        case .loading:
            "DEBUG FIXTURE · LOADING"
        }
    }

    private var hiddenStateProof: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The module is hidden.")
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
            Text("The profile has interests, but no upcoming posting maps to them. Production phase: empty.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .blockPartyCard(padding: nil)
        .padding(.horizontal, 18)
    }
}
#endif
