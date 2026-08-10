//
//  DaySchedulePreview.swift
//  Block Party — `-day-sheet-preview`, the day sheet with no auth and no network.
//
//  Mounts the REAL `DayScheduleSheet` through the REAL `DayScheduleHost` over a
//  stand-in for the Today tab, so the frosted backdrop has something to blur and
//  the card is framed the way it will be in the app. Pair with
//  `-day-sheet-state upcoming|inprogress|completed|empty|cta`.
//
//  There is no rail here, so nothing morphs — this flag photographs the day's
//  CONTENT. The transition itself needs both halves of the pair and is covered by
//  `-day-sheet-demo`, which mounts the real feed.
//
//  Compiles out entirely in Release.
//

#if DEBUG
import SwiftUI

struct DaySchedulePreview: View {
    @Namespace private var railNamespace
    @StateObject private var presentation = DaySchedulePresentation()
    @StateObject private var completion = DayCompletionStore()

    private let fixture = DayScheduleFixture.fromArguments()

    var body: some View {
        standInForToday
            .dayScheduleHost(presentation, namespace: railNamespace, completion: completion)
            .task {
                presentation.open(
                    DayScheduleRequest(
                        items: fixture.items,
                        anchor: fixture.anchor,
                        dates: fixture.dates
                    )
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
