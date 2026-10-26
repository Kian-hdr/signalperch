import XCTest
@testable import Signalperch

final class PriorityTests: XCTestCase {
    func testSavedOrderSanitizesAndIncludesNewServices() {
        let order = ServicePriority.normalized(["claude", "unknown", "claude", "openai"])
        XCTAssertEqual(Array(order.prefix(2)), ["claude", "openai"])
        XCTAssertEqual(Set(order), Set(Provider.all.map(\.id)))
        XCTAssertEqual(order.count, Provider.all.count)
    }
    func testDragToFirstSelectsServiceWithoutLosingOthers() {
        let moved = ServicePriority.reordered(["claude", "github", "openai"], moving: ["openai"], before: "claude")
        XCTAssertEqual(moved, ["openai", "claude", "github"])
        XCTAssertEqual(ServicePriority.firstEnabled(in: moved, enabled: Set(moved)), "openai")
        XCTAssertEqual(ServicePriority.firstEnabled(in: moved, enabled: ["claude", "github"]), "claude")
    }
    func testMovingToEndAndMultipleRowsPreservesSourceOrder() {
        XCTAssertEqual(ServicePriority.reordered(["openai", "claude", "github"], moving: ["openai"], before: nil), ["claude", "github", "openai"])
        XCTAssertEqual(ServicePriority.reordered(["openai", "claude", "github", "vercel"], moving: ["github", "openai"], before: nil), ["claude", "vercel", "openai", "github"])
    }
    func testDropOnSelfAndInvalidSourceKeepOrder() {
        let ids = ["openai", "claude", "github"]
        XCTAssertEqual(ServicePriority.reordered(ids, moving: ["claude"], before: "claude"), ids)
        XCTAssertEqual(ServicePriority.reordered(ids, moving: ["unknown"], before: nil), ids)
    }
    func testLegacyListOffsetsMoveBothDirections() {
        let ids = ["openai", "claude", "github"]
        XCTAssertEqual(ServicePriority.moved(ids, from: [0], to: 3), ["claude", "github", "openai"])
        XCTAssertEqual(ServicePriority.moved(ids, from: [2], to: 0), ["github", "openai", "claude"])
        XCTAssertEqual(ServicePriority.moved(ids, from: [0, 1], to: 3), ["github", "openai", "claude"])
    }
    @MainActor func testStoreRestoresOrderAndSkipsDisabledPrimary() {
        let suite = "SignalperchPriorityTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = MonitorStore(defaults: defaults)
        first.reorderProviders(moving: ["claude"], before: "openai")
        XCTAssertEqual(first.primaryProvider?.id, "claude")
        let restored = MonitorStore(defaults: defaults)
        XCTAssertEqual(restored.primaryProvider?.id, "claude")
        defaults.set(["openai", "github"], forKey: "enabledProviders")
        let disabledPrimary = MonitorStore(defaults: defaults)
        XCTAssertEqual(disabledPrimary.primaryProvider?.id, "openai")
        XCTAssertEqual(disabledPrimary.providers.map(\.id), ["openai", "github"])
    }

}
