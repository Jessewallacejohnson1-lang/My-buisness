//
//  FeedRegistryTests.swift
//  BlockPartyTests — ordering, visibility, compatibility, and load isolation.
//

import SwiftUI
import XCTest
@testable import BlockParty

@MainActor
final class FeedRegistryTests: XCTestCase {
    func testOrderIsSortedAndStable() {
        let second = TestFeedModule(id: "second", order: 2, phase: .ready)
        let firstA = TestFeedModule(id: "first-a", order: 1, phase: .ready)
        let firstB = TestFeedModule(id: "first-b", order: 1, phase: .ready)

        let registry = FeedRegistry(modules: [second, firstA, firstB])

        XCTAssertEqual(registry.modules.map { $0.id }, ["first-a", "first-b", "second"])
    }

    func testEmptyModulesAreExcludedFromVisibleModules() {
        let empty = TestFeedModule(id: "empty", order: 1, phase: .empty)
        let ready = TestFeedModule(id: "ready", order: 2, phase: .ready)
        let context = makeContext()

        let visible = FeedRegistry(modules: [empty, ready]).visibleModules(in: context)

        XCTAssertEqual(visible.map { $0.id }, ["ready"])
    }

    func testUnknownModuleIDDecodesAndIsSkipped() throws {
        let unknown = try JSONDecoder().decode(
            FeedModuleID.self,
            from: Data(#""someNewerModule""#.utf8)
        )
        let known = TestFeedModule(id: "known", order: 1, phase: .ready)
        let registry = FeedRegistry(modules: [known])

        XCTAssertEqual(unknown.rawValue, "someNewerModule")
        XCTAssertNil(registry.module(for: unknown))
        XCTAssertEqual(registry.visibleModules(in: makeContext()).map { $0.id }, ["known"])
    }

    func testFailingModuleLoadLeavesOtherPhasesUntouched() async {
        let failing = ThrowingTestFeedModule(id: "failing", order: 1)
        let survivor = TestFeedModule(
            id: "survivor",
            order: 2,
            phase: .loading,
            onLoad: { module, _ in module.phase = .ready }
        )
        let untouched = TestFeedModule(id: "untouched", order: 3, phase: .empty)
        let context = makeContext()
        let controller = FeedController(
            context: context,
            registry: FeedRegistry(modules: [failing, survivor, untouched]),
            briefingLoader: { _, _ in }
        )

        await controller.load()

        XCTAssertEqual(failing.phase, .failed)
        XCTAssertEqual(survivor.phase, .ready)
        XCTAssertEqual(untouched.phase, .empty)
    }

    func testControllerLoadsAndRepublishesTheBriefingModulesRead() async {
        let context = makeContext()
        var loadedBriefingID: ObjectIdentifier?
        var moduleBriefingID: ObjectIdentifier?
        let module = TestFeedModule(
            id: "identity-reader",
            order: 1,
            phase: .loading,
            onLoad: { _, context in
                moduleBriefingID = ObjectIdentifier(context.briefing)
            }
        )
        let controller = FeedController(
            context: context,
            registry: FeedRegistry(modules: [module]),
            briefingLoader: { briefing, _ in
                loadedBriefingID = ObjectIdentifier(briefing)
            }
        )
        var didRepublishBriefingChange = false
        let observation = controller.objectWillChange.sink {
            didRepublishBriefingChange = true
        }

        await controller.load()
        controller.briefing.objectWillChange.send()

        let controllerBriefingID = ObjectIdentifier(controller.briefing)
        XCTAssertEqual(loadedBriefingID, controllerBriefingID)
        XCTAssertEqual(moduleBriefingID, controllerBriefingID)
        XCTAssertTrue(didRepublishBriefingChange)
        withExtendedLifetime(observation) {}
    }

    private func makeContext() -> FeedModuleContext {
        FeedModuleContext(
            auth: AuthStore(),
            briefing: BriefingModel(),
            displayName: "Jesse",
            navigate: { _ in }
        )
    }
}

@MainActor
private class TestFeedModule: @MainActor FeedModule {
    let id: FeedModuleID
    let order: Int
    let ownsFetch = true
    @Published var phase: FeedPhase

    private let onLoad: ((TestFeedModule, FeedModuleContext) async -> Void)?

    init(
        id: FeedModuleID,
        order: Int,
        phase: FeedPhase,
        onLoad: ((TestFeedModule, FeedModuleContext) async -> Void)? = nil
    ) {
        self.id = id
        self.order = order
        self.phase = phase
        self.onLoad = onLoad
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool { true }

    func load(_ ctx: FeedModuleContext) async {
        await onLoad?(self, ctx)
    }

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        AnyView(EmptyView())
    }
}

@MainActor
private final class ThrowingTestFeedModule: TestFeedModule {
    private enum ExpectedFailure: Error { case load }

    init(id: FeedModuleID, order: Int) {
        super.init(id: id, order: order, phase: .loading)
    }

    override func load(_ ctx: FeedModuleContext) async {
        do {
            try await operation()
            phase = .ready
        } catch {
            phase = .failed
        }
    }

    private func operation() async throws {
        throw ExpectedFailure.load
    }
}
