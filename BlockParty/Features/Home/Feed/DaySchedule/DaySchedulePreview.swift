//
//  DaySchedulePreview.swift
//  Block Party — `-day-sheet-preview`, the day sheet with no auth and no network.
//
//  Mounts the REAL `DayScheduleSheet` over a stand-in for the Today tab, so the
//  frosted backdrop has something to blur and the sheet is framed the way it will
//  be in the app. Pair with `-day-sheet-state upcoming|inprogress|completed|empty`.
//
//  Compiles out entirely in Release.
//

#if DEBUG
import SwiftUI

struct DaySchedulePreview: View {
    @Namespace private var railNamespace
    @State private var isPresented = true
    @StateObject private var completion = DayCompletionStore()

    private let fixture = DayScheduleFixture.fromArguments()

    var body: some View {
        standInForToday
            .sheet(isPresented: $isPresented) {
                DayScheduleSheet(
                    items: fixture.items,
                    selectedID: fixture.selectedID,
                    namespace: railNamespace,
                    dates: fixture.dates,
                    onDismiss: { isPresented = false },
                    completion: completion
                )
            }
    }

    /// Not a copy of the Today tab — just enough shape behind the sheet that the
    /// backdrop material has real content to pick up.
    private var standInForToday: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Today")
                    .font(.display(30))
                    .foregroundStyle(Hue.ink)

                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Hue.fill)
                        .frame(height: 96)
                }

                Spacer()
            }
            .padding(DayScheduleMetrics.pageMargin)
            .padding(.top, 60)
        }
        .accessibilityHidden(true)
    }
}
#endif
