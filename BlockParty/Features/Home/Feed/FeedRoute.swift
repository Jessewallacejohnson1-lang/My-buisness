//
//  FeedRoute.swift
//  Block Party — every destination reachable from a Today feed module.
//

import SwiftUI

enum FeedRoute: Identifiable, Hashable {
    case feedDiscovery
    case civicTab
    case editInterests

    nonisolated var id: Self { self }

    @MainActor
    var destination: AnyView {
        switch self {
        case .feedDiscovery:
            AnyView(FeedDiscoveryDestination())
        case .civicTab:
            AnyView(CivicTabDestination())
        case .editInterests:
            AnyView(FeedInterestEditorDestination())
        }
    }
}
