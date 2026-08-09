//
//  FeedRegistry.swift
//  Block Party — the one catalog and running order for the Today feed.
//
//  Adding a module means adding its implementation and one entry to the literal
//  below. FeedView remains generic and does not change.
//

import Combine

@MainActor
final class FeedRegistry: ObservableObject {
    let modules: [any FeedModule]

    private var moduleObservations: [AnyCancellable] = []

    init(briefing: BriefingModel? = nil, modules: [any FeedModule]? = nil) {
        let entries: [any FeedModule]
        if let modules {
            entries = modules
        } else {
            let sharedBriefing = briefing ?? BriefingModel()
            entries = [
                AlmanacModule(briefing: sharedBriefing),
                YourDayModule(briefing: sharedBriefing),
                TriviaModule(briefing: sharedBriefing),
                SpotlightModule(briefing: sharedBriefing),
                SignOffModule(briefing: sharedBriefing),
            ]
        }

        // The offset tie-break makes equal-order modules deterministic and stable.
        self.modules = entries.enumerated().sorted { lhs, rhs in
            if lhs.element.order != rhs.element.order {
                return lhs.element.order < rhs.element.order
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        observeModuleChanges()
    }

    func visibleModules(in context: FeedModuleContext) -> [any FeedModule] {
        modules.filter { $0.phase != .empty && $0.isVisible(context) }
    }

    func module(for id: FeedModuleID) -> (any FeedModule)? {
        modules.first { $0.id == id }
    }

    private func observeModuleChanges() {
        for module in modules {
            observe(module)
        }
    }

    private func observe<Module: FeedModule>(_ module: Module) {
        module.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &moduleObservations)
    }
}
