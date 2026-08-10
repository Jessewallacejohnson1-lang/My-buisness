// TODO: This screen will become the Civic tab for town utilities and notices,
// but it is intentionally not built yet. The utility-tile subsystem is being
// parked intact for exactly this screen: 15 files in Features/Home/Utility/,
// plus Backend/UtilityPrefsAPI.swift and Backend/TownStatusAPI.swift.
// `user_utility_prefs` still holds live per-user tile configuration, which this
// screen should re-hydrate when the Civic tab is built.

import SwiftUI

struct CivicTabDestination: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Civic updates in one place")
                    .font(.displaySemi(28))
                    .foregroundStyle(Hue.ink)

                Text("This screen isn’t built yet. Your weather, garbage, roads, and library tiles will live here, alongside road notices, city hall items, and full garbage and recycling details.")
                    .font(.sans(16))
                    .foregroundStyle(Hue.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Hue.paper.ignoresSafeArea())
            .navigationTitle("Civic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Hue.ink)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    CivicTabDestination()
}
#endif
