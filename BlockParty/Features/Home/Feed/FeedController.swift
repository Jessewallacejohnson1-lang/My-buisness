//
//  FeedController.swift
//  Block Party — coordinates the shared briefing and independently fetched modules.
//

import Combine

@MainActor
final class FeedController: ObservableObject {
    typealias BriefingLoader = @MainActor (BriefingModel, AuthStore) async -> Void

    let briefing: BriefingModel
    let registry: FeedRegistry

    private var context: FeedModuleContext
    private let briefingLoader: BriefingLoader
    private var briefingObservations: [AnyCancellable] = []
    /// A newer load supersedes an older one. BriefingModel retains its own matching
    /// response guard, so an old RPC can never overwrite a newer refresh.
    private var generation = 0

    init(
        context: FeedModuleContext,
        registry: FeedRegistry? = nil,
        briefingLoader: BriefingLoader? = nil
    ) {
        self.context = context
        briefing = context.briefing
        self.registry = registry ?? FeedRegistry(briefing: context.briefing)
        self.briefingLoader = briefingLoader ?? { model, auth in
            await model.load(BriefingAPI(auth: auth))
        }
        briefing.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &briefingObservations)
    }

    func updateContext(_ context: FeedModuleContext) {
        self.context = context
    }

    func load() async {
        generation += 1
        let mine = generation
        let context = context
        let briefing = briefing
        let briefingLoader = briefingLoader
        let independentModules = registry.modules.filter { $0.ownsFetch }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard self?.generation == mine else { return }
                await briefingLoader(briefing, context.auth)
            }

            for module in independentModules {
                group.addTask { @MainActor [weak self] in
                    guard self?.generation == mine else { return }
                    await module.load(context)
                }
            }
        }
    }

    func refreshBriefing() async {
        await briefing.refresh(BriefingAPI(auth: context.auth))
    }
}
