import Foundation
import Testing

@testable import ZivletShelfCore

@Suite("Auto-clear plans and the storage warning (P2-141, OWN-APP-3)")
struct AutoClearTests {
    @Test func offClearsNothing() throws {
        let shelf = try ShelfFixtures.shelf(names: ["a"])
        let plan = AutoClearPlan.items(
            in: shelf, policy: .off, now: .t0.addingTimeInterval(1e6), left: [shelf.items[0].id])
        #expect(plan.isEmpty)
    }

    @Test func afterLeavingPicksOnlyItemsThatLeftAndAreInTheBox() throws {
        let shelf = try ShelfFixtures.shelf(names: ["a", "b"])
        let plan = AutoClearPlan.items(in: shelf, policy: .afterLeaving, now: .t0, left: [shelf.items[1].id, UUID()])
        #expect(plan == [shelf.items[1].id])
    }

    @Test func after24HoursPicksOnlyOldItems() throws {
        let old = try ShelfFixtures.item("old", addedAt: .t0)
        let young = try ShelfFixtures.item("young", addedAt: .t0.addingTimeInterval(23 * 3600))
        let exact = try ShelfFixtures.item("exact", addedAt: .t0.addingTimeInterval(1))
        let shelf = try ShelfFixtures.shelf(old, young, exact)
        let plan = AutoClearPlan.items(
            in: shelf, policy: .after24Hours, now: .t0.addingTimeInterval(24 * 3600 + 1), left: [])
        #expect(plan == [old.id])
    }

    @Test func theWarningStartsAt2GB() {
        #expect(!StorageBudget.isOverWarning(1_999_999_999) && StorageBudget.isOverWarning(2_000_000_000))
        #expect(StorageBudget.warnBytes == 2_000_000_000)
    }
}
