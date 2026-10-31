import XCTest
@testable import GearhouseCore

final class GearTreeDragTests: XCTestCase {
    private let parents = ["tarmac":"", "propel":"", "wheel":"tarmac", "front":"tarmac", "rear":"tarmac", "chain":"tarmac"]

    func testDragPayloadRoundTripAndValidation() throws {
        let payload = try GearTreeDrag(gearIDs: ["front","rear","front"])
        XCTAssertEqual(try GearTreeDrag.decode(payload.encoded()).gearIDs, ["front","rear"])
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: []))
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: [""]))
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: Array(repeating: "wheel", count: 500)))
        for json in ["{}", "[]", "{\"version\":2,\"gearIDs\":[\"wheel\"]}", "{\"version\":1,\"gearIDs\":[]}"] {
            XCTAssertThrowsError(try GearTreeDrag.decode(Data(json.utf8)))
        }
        XCTAssertThrowsError(try GearTreeDrag.decode(Data(repeating: 32, count: 65537)))
    }
    func testIRCFrontAndRearMoveTogetherWithoutCommittingHistory() throws {
        let pending = try GearTreeDrag(gearIDs: ["front","rear"]).staging(onto: "wheel", originalParents: parents, pending: [:])
        XCTAssertEqual(pending, ["front":"wheel", "rear":"wheel"])
        XCTAssertEqual(parents["front"], "tarmac")
        XCTAssertEqual(parents["rear"], "tarmac")
    }
    func testMovingSelectionWithParentKeepsChildrenAttached() throws {
        var tree = parents; tree["front"] = "wheel"; tree["rear"] = "wheel"
        let pending = try GearTreeDrag(gearIDs: ["front","wheel","rear"]).staging(onto: "propel", originalParents: tree, pending: [:])
        XCTAssertEqual(pending, ["wheel":"propel"])
    }
    func testCycleChecksUsePendingTreePosition() throws {
        let moved = try GearTreeDrag(gearIDs: ["wheel"]).staging(onto: "propel", originalParents: parents, pending: [:])
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: ["propel"]).staging(onto: "wheel", originalParents: parents, pending: moved))
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: ["wheel"]).staging(onto: "wheel", originalParents: parents, pending: moved))
        var tree = parents; tree["front"] = "wheel"
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: ["wheel"]).staging(onto: "front", originalParents: tree, pending: [:]))
    }
    func testReturnToOriginalParentRemovesOnlyThatPendingChange() throws {
        let pending = ["wheel":"propel", "chain":"propel"]
        let next = try GearTreeDrag(gearIDs: ["wheel"]).staging(onto: "tarmac", originalParents: parents, pending: pending)
        XCTAssertEqual(next, ["chain":"propel"])
        XCTAssertEqual(pending, ["wheel":"propel", "chain":"propel"])
        XCTAssertEqual(try GearTreeDrag(gearIDs: ["front"]).staging(onto: "tarmac", originalParents: parents, pending: next), next)
    }
    func testDetachToLibraryAndConsecutiveMoves() throws {
        let detached = try GearTreeDrag(gearIDs: ["wheel"]).staging(onto: "", originalParents: parents, pending: [:])
        XCTAssertEqual(detached, ["wheel":""])
        let next = try GearTreeDrag(gearIDs: ["front","rear"]).staging(onto: "wheel", originalParents: parents, pending: detached)
        XCTAssertEqual(next, ["wheel":"", "front":"wheel", "rear":"wheel"])
        XCTAssertEqual(try GearTreeDrag(gearIDs: ["propel"]).staging(onto: "", originalParents: parents, pending: next), next)
    }
    func testDeletedOrUnknownGearCannotBeDropped() throws {
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: ["missing"]).staging(onto: "wheel", originalParents: parents, pending: [:]))
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: ["wheel"]).staging(onto: "missing", originalParents: parents, pending: [:]))
        XCTAssertThrowsError(try GearTreeDrag(gearIDs: ["wheel","missing"]).staging(onto: "propel", originalParents: parents, pending: [:]))
    }
    func testMergedPendingLimitRejectsNewChangeButAllowsEditingAndReverting() throws {
        let ids = (0..<500).map { "gear-\($0)" }
        var tree = Dictionary(uniqueKeysWithValues: ids.map { ($0, "original") })
        for root in ["original", "first", "second"] { tree[root] = "" }
        let pending = try GearTreeDrag(gearIDs: Array(ids.prefix(499))).staging(onto: "first", originalParents: tree, pending: [:])
        XCTAssertEqual(pending.count, 499)

        let overflow = try GearTreeDrag(gearIDs: [ids[499]])
        XCTAssertThrowsError(try overflow.staging(onto: "first", originalParents: tree, pending: pending)) { error in
            let message = "每次最多调整 499 件装备，请先保存或撤销部分修改。"
            XCTAssertEqual((error as? DomainError)?.message, message)
            XCTAssertEqual(UserFacingError.message(error), message)
        }
        XCTAssertEqual(pending, Dictionary(uniqueKeysWithValues: ids.prefix(499).map { ($0, "first") }))

        let existing = try GearTreeDrag(gearIDs: [ids[0]])
        let changed = try existing.staging(onto: "second", originalParents: tree, pending: pending)
        XCTAssertEqual(changed.count, 499)
        XCTAssertEqual(changed[ids[0]], "second")
        let reduced = try existing.staging(onto: "original", originalParents: tree, pending: changed)
        XCTAssertEqual(reduced.count, 498)
        XCTAssertNil(reduced[ids[0]])
        let resumed = try overflow.staging(onto: "first", originalParents: tree, pending: reduced)
        XCTAssertEqual(resumed.count, 499)
        XCTAssertEqual(resumed[ids[499]], "first")
    }
    func testStagedBatchPublishesOneTimestampAndPreservesSavedActivityUsage() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = .array(parents.keys.sorted().map { ["id": .string($0), "name": .string($0), "type":"Equipment"] })
        state["events"] = .array(parents.filter { !$0.value.isEmpty }.map { ["id": .string("e-" + $0.key), "gearId": .string($0.key), "parentId": .string($0.value), "at":"2024-01-01T00:00:00"] })
        state["activities"] = [["id":"old", "at":"2025-01-01T00:00:00", "snapshot":[["id":"front", "parentId":"tarmac"], ["id":"rear", "parentId":"tarmac"]]]]
        let beforeActivities = state["activities"]
        let beforeEvents = state["events"]
        let pending = try GearTreeDrag(gearIDs: ["front","rear"]).staging(onto: "wheel", originalParents: parents, pending: [:])
        XCTAssertEqual(state["events"], beforeEvents)
        let changes: Value = .array(pending.map { ["gearId": .string($0.key), "parentId": .optional($0.value)] })
        let saved = try engine.execute(state: state, action: "moves", input: ["changes": changes, "at":"2026-10-01T10:30:00"])["state"]
        XCTAssertEqual(saved["gears"].array.count, parents.count)
        XCTAssertEqual(saved["events"].array.count, beforeEvents.array.count + 2)
        XCTAssertEqual(saved["activities"], beforeActivities)
        let installed = saved["events"].array.filter { $0["at"].text == "2026-10-01T00:00:00" }
        XCTAssertEqual(Set(installed.map { $0["gearId"].text }), Set(["front","rear"]))
        XCTAssertTrue(installed.allSatisfy { $0["parentId"].text == "wheel" })
    }
}
