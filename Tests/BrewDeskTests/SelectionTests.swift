import XCTest
@testable import BrewDesk

final class SelectionTests: XCTestCase {
    private func package(_ name: String, outdated: Bool = true, pinned: Bool = false) -> BrewPackage {
        BrewPackage(token: name, name: name, kind: .formula, summary: "", installed: "1", available: "2", homepage: "", tap: "", dependencies: [], outdated: outdated, autoUpdates: false, pinned: pinned)
    }
    @MainActor func testFilteredSelectAllPreservesHiddenSelectionAndClearRemovesIt() {
        let model = AppModel()
        model.packages = [package("alpha"), package("beta")]
        model.selection = [model.packages[1].id]
        model.search = "alpha"
        model.selectAllVisible()
        XCTAssertEqual(model.selection, Set(model.packages.map(\.id)))
        model.setSelected(model.packages[0].id, selected: false)
        XCTAssertEqual(model.selected.map(\.name), ["beta"])
        model.clearSelection()
        XCTAssertTrue(model.selection.isEmpty)
    }
    @MainActor func testUpdateAllReviewsEligiblePackagesAcrossFiltersWithoutExecuting() {
        let model = AppModel()
        model.environment = BrewEnvironment(executable: "/fixture/brew", prefix: "/fixture", version: "test")
        model.packages = [package("alpha"), package("beta"), package("pinned", pinned: true), package("current", outdated: false)]
        model.search = "alpha"
        model.prepareAllUpgrades()
        XCTAssertEqual(model.pending?.packages.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(model.pending?.action, .upgrade)
        XCTAssertFalse(model.busy)
        model.pending = nil
        model.busy = true
        model.prepareAllUpgrades()
        XCTAssertNil(model.pending)
    }
}
