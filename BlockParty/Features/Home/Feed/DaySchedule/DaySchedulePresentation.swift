//
//  DaySchedulePresentation.swift
//  Block Party — who is asking for the day sheet, and what they asked for.
//
//  WHY THIS EXISTS AT ALL. The day sheet was built as a `.sheet`, and a `.sheet` is
//  a SEPARATE presentation hierarchy: a `Namespace.ID` declared in the Today tab
//  does not reach into it, so `matchedGeometryEffect` between the rail card and the
//  timeline row can never run. The spec asked for both a full-height presentation
//  and the accent-bar morph, and those two are mutually exclusive through `.sheet`.
//  The owner chose the morph, so the sheet is now presented IN-HIERARCHY (see
//  `DayScheduleHost`) and everything a system sheet used to hand over — the resting
//  detent, the corner radius, drag-to-dismiss, the modal accessibility container —
//  is hand-built.
//
//  Presenting in-hierarchy means the presenter has to sit ABOVE the tab bar, which
//  puts it in `MainTabsView` — while the items that fill it are owned by the Your
//  Day module, several views below. So a request carries the day with it, and the
//  rail reaches its presenter through the environment rather than through five
//  layers of initialiser parameters.
//

import Combine
import SwiftUI

// MARK: - The request

/// Where the day comes to rest when it opens.
nonisolated enum DayScheduleAnchor: Hashable {
    /// The top of the day. Nothing was singled out.
    case top
    /// The tapped rail card's row, one third down the viewport.
    case item(String)
    /// The bottom of the day, so the "Add to today" button is what the neighbour
    /// lands on. This is what the rail's add tile asks for.
    case callToAction

    /// The row the open scroll targets, if the anchor names one.
    var itemID: String? {
        if case let .item(id) = self { return id }
        return nil
    }
}

/// One open request: the whole day, where to rest, and the clock to read it by.
///
/// The items travel WITH the request because the presenter sits above the tab bar
/// and the rail — the only thing that knows today's items — sits inside the feed.
/// Copying the array is the cheap half of that trade; the alternative is a second
/// source of truth for the day.
@MainActor
struct DayScheduleRequest {
    let items: [DayItem]
    let anchor: DayScheduleAnchor
    let dates: any DateProviding

    init(items: [DayItem], anchor: DayScheduleAnchor, dates: any DateProviding) {
        self.items = items
        self.anchor = anchor
        self.dates = dates
    }
}

// MARK: - The presenter's state

/// The one bit of shared state between the rail (which opens the day) and the host
/// (which draws it). Deliberately NOT a singleton like `ShareCenter`: the host owns
/// one and injects it, so a preview or a test can hand over its own.
@MainActor
final class DaySchedulePresentation: ObservableObject {
    @Published private(set) var request: DayScheduleRequest?

    init(request: DayScheduleRequest? = nil) {
        self.request = request
    }

    var isOpen: Bool { request != nil }

    /// Immutable update — a fresh request replaces the old one, never a mutation
    /// of it. Re-opening on a different card while open is therefore legal and
    /// simply re-anchors.
    func open(_ request: DayScheduleRequest) { self.request = request }

    func close() { request = nil }
}

// MARK: - The seam

extension EnvironmentValues {
    /// The day-sheet presenter, injected by `DayScheduleHost`. Nil everywhere the
    /// host is not mounted (galleries, the module previews), and the rail falls
    /// back to its existing navigation there rather than going dead.
    @Entry var daySchedule: DaySchedulePresentation?

    /// The matched-geometry namespace BOTH halves of the morph must share. It is
    /// declared by the host, because the host is the nearest common ancestor of the
    /// rail card and the timeline row — which is the whole reason the sheet had to
    /// stop being a `.sheet`.
    @Entry var dayScheduleNamespace: Namespace.ID?
}
