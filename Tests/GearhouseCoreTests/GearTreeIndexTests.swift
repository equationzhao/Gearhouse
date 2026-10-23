import XCTest
@testable import GearhouseCore

final class GearTreeIndexTests: XCTestCase {
    private let gears: [Value] = [
        ["id":"bike", "name":"Tarmac"], ["id":"wheel", "name":"CL II"],
        ["id":"front", "name":"IRC Front"], ["id":"rear", "name":"IRC Rear"],
        ["id":"other", "name":"Propel"], ["id":"hidden", "name":"Hidden", "hidden":true],
        ["id":"retired", "name":"Retired", "retired":true],
        ["id":"deleted", "name":"Deleted", "deletedAt":"2026-01-01"]
    ]
    private let events: [Value] = [
        ["gearId":"front", "parentId":"wheel", "at":"2024-01-01T00:00:00"],
        ["gearId":"rear", "parentId":"wheel", "at":"2024-01-01T00:00:00"],
        ["gearId":"wheel", "parentId":"bike", "at":"2024-01-01T00:00:00"],
        ["gearId":"wheel", "parentId":"other", "at":"2026-01-01T00:00:00"]
    ]
    func testSnapshotTimeStableOrderAndPendingDoNotMutateHistory() {
        let tree = GearTreeIndex(gears: gears, events: events, at: "2025-01-01T00:00:00")
        XCTAssertEqual(tree.parents["wheel"], "bike")
        XCTAssertEqual(tree.nextEventAt, "2026-01-01T00:00:00")
        let rows = tree.rows()
        XCTAssertEqual(rows.map(\.id), ["bike", "wheel", "front", "rear", "other"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 2, 0])
        XCTAssertEqual(Set(rows.filter(\.hasChildren).map(\.id)), ["bike", "wheel"])
        let moved = tree.rows(pending: ["wheel":"other"])
        XCTAssertEqual(moved.map(\.id), ["bike", "other", "wheel", "front", "rear"])
        XCTAssertEqual(tree.parents["wheel"], "bike")
        XCTAssertEqual(tree.rows(collapsed: ["wheel"]).map(\.id), ["bike", "wheel", "other"])
        XCTAssertEqual(tree.rows(pending: ["wheel":""]).map(\.depth), [0, 0, 1, 1, 0])
    }
    func testSearchHiddenParentsAndTrashKeepExistingDisplayRules() {
        let tree = GearTreeIndex(gears: gears, events: events, at: "2025-01-01T00:00:00")
        let matches = tree.rows(collapsed: ["bike"], query: "irc")
        XCTAssertEqual(matches.map(\.id), ["front", "rear"])
        XCTAssertEqual(matches.map(\.depth), [0, 0])
        XCTAssertEqual(tree.rows(showRetired: true, showHidden: true).count, 7)
        XCTAssertEqual(tree.rows(trash: true).map(\.id), ["deleted"])
        let orphan = tree.rows(pending: ["wheel":"hidden"])
        XCTAssertEqual(orphan.first(where: { $0.id == "wheel" })?.depth, 0)
    }
    func testUnsortedEventsAndSameInstantUseLastSavedEvent() {
        let tied: Value = ["gearId":"wheel", "parentId":.null, "at":"2026-01-01T00:00:00"]
        let tree = GearTreeIndex(gears: gears, events: [events[3], events[2], tied], at: "2026-02-01T00:00:00")
        XCTAssertEqual(tree.parents["wheel"], "")
        XCTAssertNil(tree.nextEventAt)
    }
}
