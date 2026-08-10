//
//  FeedModule.swift
//  Block Party — one independently rendering unit in the Today feed.
//

import SwiftUI

@MainActor
protocol FeedModule: AnyObject, ObservableObject {
    var id: FeedModuleID { get }
    var order: Int { get }
    var ownsFetch: Bool { get }
    func isVisible(_ ctx: FeedModuleContext) -> Bool
    func load(_ ctx: FeedModuleContext) async
    var phase: FeedPhase { get }
    func makeView(_ ctx: FeedModuleContext) -> AnyView
}
