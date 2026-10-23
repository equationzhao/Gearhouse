import XCTest
@testable import GearhouseCore

final class GearTimelineTests: XCTestCase {
    private var state: Value {
        ["gears": [["id":"b", "name":"Tarmac"], ["id":"c", "name":"Propel"], ["id":"w", "name":"CL II"], ["id":"t", "name":"IRC Front"]],
         "events": [
            ["id":"mount", "gearId":"w", "parentId":"b", "at":"2024-01-01T00:00:00"],
            ["id":"tyre", "gearId":"t", "parentId":"w", "at":"2024-01-02T00:00:00"],
            ["id":"remove", "gearId":"w", "parentId":.null, "at":"2025-01-01T00:00:00"],
            ["id":"move", "gearId":"w", "parentId":"c", "at":"2025-02-01T00:00:00"]
         ],
         "gearEvents": [
            ["id":"on-b", "gearId":"t", "kind":"inspection", "occurredDate":"2024-06-01"],
            ["id":"storage", "gearId":"t", "kind":"maintenance", "occurredDate":"2025-01-10"],
            ["id":"on-c", "gearId":"t", "kind":"maintenance", "occurredDate":"2025-02-02"]
         ], "activities":[["id":"ride", "at":"2024-06-01T10:00:00"]]]
    }
    func testHistoricalMembershipIncludesNestedComponentsAndDetachment() {
        let b = GearTimeline.buildRows(state: state, gearID: "b")
        XCTAssertEqual(Set(b.map(\.id)), ["mount", "tyre", "remove", "on-b"])
        XCTAssertEqual(b.first(where: { $0.id == "on-b" })?["subjectName"].text, "IRC Front")
        let c = GearTimeline.buildRows(state: state, gearID: "c")
        XCTAssertEqual(Set(c.map(\.id)), ["move", "on-c"])
        XCTAssertEqual(Set(GearTimeline.buildRows(state: state, gearID: "w").map(\.id)), ["mount", "tyre", "remove", "move", "on-b", "storage", "on-c"])
        XCTAssertFalse(b.contains { $0["entryType"].text == "activity" })
    }
    func testSameDayBatchTransferAttributesArrivalAndDepartureToBothBikes() {
        var s = state
        s["events"] = .array(s["events"].array.filter { $0.id != "remove" })
        let b = GearTimeline.buildRows(state: s, gearID: "b"), c = GearTimeline.buildRows(state: s, gearID: "c")
        XCTAssertTrue(b.contains { $0.id == "move" })
        XCTAssertTrue(c.contains { $0.id == "move" })
        XCTAssertFalse(b.contains { $0.id == "on-c" })
        XCTAssertEqual(b.first(where: { $0.id == "move" })?["fromParentId"].text, "b")
    }
    func testSnapshotTimelineDoesNotLeakFutureRecords() throws {
        let engine = try NativeDomain()
        let snapshot = try engine.execute(state: state, action: "view", input: ["date":"2024-12-31"])["result"]
        XCTAssertEqual(Set(GearTimeline.buildRows(state: snapshot, gearID: "b").map(\.id)), ["mount", "tyre", "on-b"])
    }
}
